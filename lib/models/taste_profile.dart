// ---------------- MATCHING ----------------
import 'package:cloud_firestore/cloud_firestore.dart';

/// Simple DTO to return a full, explainable match computation.
class MatchResult {
  final double score; // 0..100
  final int overlapCount;
  final bool dataInsufficient;

  /// Lists of minimal film maps: {id?, slug?, title?, posterUrl?}
  final List<Map<String, dynamic>> commonFiveStars;
  final List<Map<String, dynamic>> commonFavorites;
  final List<Map<String, dynamic>> commonDisliked;
  final List<Map<String, dynamic>> conflicts; // A like ∩ B dislike (two-way)
  final List<Map<String, dynamic>> commonWatchlist; // A∩B watchlist
  final List<Map<String, dynamic>>
  likeVsWatchlist; // (A like ∩ B watchlist) ∪ (B like ∩ A watchlist)

  const MatchResult({
    required this.score,
    required this.overlapCount,
    required this.dataInsufficient,
    required this.commonFiveStars,
    required this.commonFavorites,
    required this.commonDisliked,
    required this.conflicts,
    required this.commonWatchlist,
    required this.likeVsWatchlist,
  });

  Map<String, dynamic> toMap() => {
    'score': score,
    'overlapCount': overlapCount,
    'dataInsufficient': dataInsufficient,
    'commonFiveStars': commonFiveStars,
    'commonFavorites': commonFavorites,
    'commonDisliked': commonDisliked,
    'conflicts': conflicts,
    'commonWatchlist': commonWatchlist,
    'likeVsWatchlist': likeVsWatchlist,
    'updatedAt': FieldValue.serverTimestamp(),
    'version': 2,
  };

  static MatchResult fromMap(Map<String, dynamic> m) => MatchResult(
    score: (m['score'] ?? 0).toDouble(),
    overlapCount: (m['overlapCount'] ?? 0) as int,
    dataInsufficient: (m['dataInsufficient'] ?? false) as bool,
    commonFiveStars:
        (m['commonFiveStars'] as List?)?.cast<Map<String, dynamic>>() ??
        const [],
    commonFavorites:
        (m['commonFavorites'] as List?)?.cast<Map<String, dynamic>>() ??
        const [],
    commonDisliked:
        (m['commonDisliked'] as List?)?.cast<Map<String, dynamic>>() ??
        const [],
    conflicts:
        (m['conflicts'] as List?)?.cast<Map<String, dynamic>>() ?? const [],
    commonWatchlist:
        (m['commonWatchlist'] as List?)?.cast<Map<String, dynamic>>() ??
        const [],
    likeVsWatchlist:
        (m['likeVsWatchlist'] as List?)?.cast<Map<String, dynamic>>() ??
        const [],
  );
}

class MatchService {
  MatchService._();
  static final MatchService instance = MatchService._();

  final _db = FirebaseFirestore.instance;

  /// Compute or load cached match between two users.
  /// Reads tasteProfiles/{uid} documents created via TasteProfile.toMap()
  Future<MatchResult> computeForUsers(
    String uidA,
    String uidB, {
    Duration maxCacheAge = const Duration(hours: 24),
  }) async {
    final pairId = _pairId(uidA, uidB);
    final cacheRef = _db.collection('matches').doc(pairId);

    // 1) Try cache first
    final cacheSnap = await cacheRef.get();
    if (cacheSnap.exists) {
      final data = cacheSnap.data()!;
      final ts = (data['updatedAt'] as Timestamp?);
      final fresh =
          ts != null && DateTime.now().difference(ts.toDate()) < maxCacheAge;
      if (fresh) {
        return MatchResult.fromMap(data);
      }
    }

    // 2) Pull profile docs according to NEW schema (keys only)
    //    users/{uid}: favoritesKeys[], dislikedKeys[]
    //    userTasteProfiles/{uid}: fiveStars[]
    final usersA = await _db.collection('users').doc(uidA).get();
    final usersB = await _db.collection('users').doc(uidB).get();
    final tasteA = await _db.collection('userTasteProfiles').doc(uidA).get();
    final tasteB = await _db.collection('userTasteProfiles').doc(uidB).get();

    List<String> _keys(dynamic v) =>
        (v as List?)?.cast<String>() ?? const <String>[];

    final s5A = _keys((tasteA.data() ?? const {})['fiveStars']).toSet();
    final s5B = _keys((tasteB.data() ?? const {})['fiveStars']).toSet();

    final sfA = _keys((usersA.data() ?? const {})['favoritesKeys']).toSet();
    final sfB = _keys((usersB.data() ?? const {})['favoritesKeys']).toSet();

    final sdA = _keys((usersA.data() ?? const {})['dislikedKeys']).toSet();
    final sdB = _keys((usersB.data() ?? const {})['dislikedKeys']).toSet();

    final likeA = {...s5A, ...sfA};
    final likeB = {...s5B, ...sfB};

    Future<Set<String>> _watchlistKeys(String uid) async {
      final col = _db.collection('users').doc(uid).collection('watchlist');
      // Fetch first 500 items (can paginate later if needed)
      final qs = await col.limit(500).get();
      return qs.docs.map((d) => d.id).toSet();
    }

    final wA = await _watchlistKeys(uidA);
    final wB = await _watchlistKeys(uidB);

    Set<String> inter(Set<String> x, Set<String> y) => x.intersection(y);
    Set<String> uni(Set<String> x, Set<String> y) => x.union(y);

    final i5 = inter(s5A, s5B);
    final iF = inter(sfA, sfB);
    final iD = inter(sdA, sdB);

    final union5 = uni(s5A, s5B);
    final unionF = uni(sfA, sfB);
    final unionD = uni(sdA, sdB);

    double jacc(Set<String> i, Set<String> u) =>
        u.isEmpty ? 0 : i.length / u.length;

    // conflicts: A like ∩ B dislike and B like ∩ A dislike
    final c1 = inter(likeA, sdB);
    final c2 = inter(likeB, sdA);
    final conflictsKeys = {...c1, ...c2};

    final iW = inter(wA, wB);
    final likeVsWatch = inter(likeA, wB)..addAll(inter(likeB, wA));

    // overlap for data sufficiency (like-like intersection)
    final likeOverlap = inter(likeA, likeB).length;
    final dataInsufficient = likeOverlap < 5;

    // score (weights kept same)
    final s =
        100 *
            (0.55 * jacc(i5, union5) +
                0.30 * jacc(iF, unionF) +
                0.10 * jacc(iD, unionD)) -
        100 * (0.05 * conflictsKeys.length);

    // Resolve minimal film maps for UI using catalog_films/{filmKey}
    Future<Map<String, Map<String, dynamic>>> _resolve(Set<String> keys) async {
      final out = <String, Map<String, dynamic>>{};
      for (final k in keys) {
        final d = await _db.collection('catalog_films').doc(k).get();
        if (d.exists) {
          final m = d.data()!;
          out[k] = {
            'slug': k,
            'title': (m['title'] ?? '') as String,
            'posterUrl': (m['posterUrl'] ?? '') as String,
          };
        } else {
          out[k] = {'slug': k};
        }
      }
      return out;
    }

    final byKeyCommon5 = await _resolve(i5);
    final byKeyCommonF = await _resolve(iF);
    final byKeyCommonD = await _resolve(iD);
    final byKeyConf = await _resolve(conflictsKeys);
    final byKeyCommonW = await _resolve(iW);
    final byKeyLikeVsWatch = await _resolve(likeVsWatch);

    List<Map<String, dynamic>> _pick(
      Map<String, Map<String, dynamic>> m,
      Set<String> order,
    ) {
      final out = <Map<String, dynamic>>[];
      for (final k in order) {
        final v = m[k];
        if (v != null) out.add(v);
        if (out.length >= 50) break;
      }
      return out;
    }

    final commonFiveStars = _pick(byKeyCommon5, i5);
    final commonFavorites = _pick(byKeyCommonF, iF);
    final commonDisliked = _pick(byKeyCommonD, iD);
    final conflicts = _pick(byKeyConf, conflictsKeys);
    final commonWatchlist = _pick(byKeyCommonW, iW);
    final likeVsWatchlist = _pick(byKeyLikeVsWatch, likeVsWatch);

    final result = MatchResult(
      score: s.clamp(0, 100),
      overlapCount: likeOverlap,
      dataInsufficient: dataInsufficient,
      commonFiveStars: commonFiveStars,
      commonFavorites: commonFavorites,
      commonDisliked: commonDisliked,
      conflicts: conflicts,
      commonWatchlist: commonWatchlist,
      likeVsWatchlist: likeVsWatchlist,
    );

    // 3) Write cache
    await cacheRef.set(result.toMap(), SetOptions(merge: true));

    return result;
  }

  String _pairId(String a, String b) {
    if (a.compareTo(b) <= 0) return '${a}__${b}';
    return '${b}__${a}';
  }
}
