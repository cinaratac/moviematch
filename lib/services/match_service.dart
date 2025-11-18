import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;

// Short‑term cache container for findMatches
class _FindCache {
  final List<MatchResult> results;
  final DateTime ts;
  const _FindCache(this.results, this.ts);
}

/// Tek bir eşleşmeyi temsil eder
class MatchResult {
  final String uid;
  final double score; // 0..100
  final List<String> commonFiveStars;
  final List<String> commonFavorites;
  final List<String> commonWatchlist;
  final List<String> commonDisliked;

  final String? displayName;
  final String? letterboxdUsername;
  final String? photoURL;

  final List<String> commonGenres;
  final List<String> commonDirectors;
  final List<String> commonActors;

  int get commonFiveCount => commonFiveStars.length;
  int get commonFavCount => commonFavorites.length;
  int get commonWatchCount => commonWatchlist.length;
  int get commonDisCount => commonDisliked.length;

  int get commonGenreCount => commonGenres.length;
  int get commonDirectorCount => commonDirectors.length;
  int get commonActorCount => commonActors.length;

  MatchResult({
    required this.uid,
    required this.score,
    required this.commonFiveStars,
    required this.commonFavorites,
    required this.commonWatchlist,
    required this.commonDisliked,
    required this.commonGenres,
    required this.commonDirectors,
    required this.commonActors,
    this.displayName,
    this.letterboxdUsername,
    this.photoURL,
  });
}

class MatchService {
  // --- Singleton Pattern ---
  MatchService._();
  static final MatchService instance = MatchService._();

  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _matches =>
      _db.collection('matches');

  // In-memory short-term cache
  final Map<String, _FindCache> _findCache = {};
  static const Duration _findCacheTtl = Duration(minutes: 5);

  void removeUserFromCache(String myUid, String otherUid) {
    final cached = _findCache[myUid];
    if (cached != null) {
      final newList = cached.results.where((m) => m.uid != otherUid).toList();
      _findCache[myUid] = _FindCache(newList, cached.ts);
    }
  }

  void clearCache(String myUid) {
    _findCache.remove(myUid);
  }

  Set<String> _lcSet(Map<String, dynamic> src, String key) {
    final raw = (src[key] ?? const []) as List;
    return raw
        .map((e) => e.toString().trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  Set<String> _extractSet(Map<String, dynamic>? data, List<String> keys) {
    if (data == null) return {};
    for (final key in keys) {
      final val = data[key];
      if (val is List) {
        final set = val
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toSet();
        if (set.isNotEmpty) return set;
      }
    }
    return {};
  }

  Map<String, dynamic> _profileSnippet(Map<String, dynamic> u, String uid) => {
    'uid': uid,
    'displayName': (u['displayName'] ?? '') as String,
    'lb': (u['letterboxdUsername'] ?? '') as String,
    'photoURL': (u['photoURL'] ?? '') as String,
  };

  String pairIdOf(String a, String b) =>
      (a.compareTo(b) < 0) ? '${a}_$b' : '${b}_$a';

  /* ---------------------------------------------------------------------- */
  /* 1) EŞLEŞME LİSTESİ HESAPLA                                           */
  /* ---------------------------------------------------------------------- */
  Future<List<MatchResult>> findMatches(String myUid) async {
    final meDoc = await _users.doc(myUid).get();
    if (!meDoc.exists) return [];

    final now = DateTime.now();
    final cached = _findCache[myUid];
    if (cached != null && now.difference(cached.ts) < _findCacheTtl) {
      if (cached.results.isNotEmpty) {
        return cached.results;
      }
    }

    final myData = meDoc.data();
    final myFive = _extractSet(myData, ['fiveStarKeys', 'fiveIds', 'fiveStars']);
    final myFavs = _extractSet(myData, ['favoritesKeys', 'favIds', 'favoriteFilmIds']);
    final myWatch = _extractSet(myData, ['watchlistKeys', 'watchIds', 'watchlistIds']);
    final myDis = _extractSet(myData, ['dislikedKeys', 'dislikes']);

    final myGenres = _lcSet(myData ?? {}, 'favGenres');
    final myDirectors = _lcSet(myData ?? {}, 'favDirectors');
    final myActors = _lcSet(myData ?? {}, 'favActors');

    if (myFive.isEmpty && myFavs.isEmpty && myWatch.isEmpty && myDis.isEmpty) {
      return [];
    }

    final hiddenUids = <String>{};
    try {
      final likesQs = await _db
          .collection('likes')
          .where('uids', arrayContains: myUid)
          .get();
      for (final doc in likesQs.docs) {
        final m = doc.data();
        final a = m['a'] as String?;
        final b = m['b'] as String?;
        if (a == null || b == null) continue;
        final meIsA = (myUid == a);
        final myLiked = (m[meIsA ? 'aLiked' : 'bLiked'] == true);
        final otherLiked = (m[meIsA ? 'bLiked' : 'aLiked'] == true);
        final myPass = (m[meIsA ? 'aPass' : 'bPass'] == true);
        final matched = myLiked && otherLiked;
        if (myPass || matched || myLiked) {
          hiddenUids.add(meIsA ? b : a);
        }
      }
    } catch (_) {}

    final all = await _users.get();
    final List<MatchResult> out = [];

    for (final d in all.docs) {
      final uid = d.id;
      if (uid == myUid) continue;
      if (hiddenUids.contains(uid)) continue;

      final data = d.data();
      final theirFive = _extractSet(data, ['fiveStarKeys', 'fiveIds']);
      final theirFavs = _extractSet(data, ['favoritesKeys', 'favIds']);
      final theirWatch = _extractSet(data, ['watchlistKeys', 'watchIds']);
      final theirDis = _extractSet(data, ['dislikedKeys', 'dislikes']);

      final theirGenres = _lcSet(data, 'favGenres');
      final theirDirectors = _lcSet(data, 'favDirectors');
      final theirActors = _lcSet(data, 'favActors');

      final common5 = myFive.intersection(theirFive).toList()..sort();
      final commonF = myFavs.intersection(theirFavs).toList()..sort();
      final commonW = myWatch.intersection(theirWatch).toList()..sort();
      final commonD = myDis.intersection(theirDis).toList()..sort();

      final commonG = myGenres.intersection(theirGenres).toList()..sort();
      final commonDir = myDirectors.intersection(theirDirectors).toList()..sort();
      final commonAct = myActors.intersection(theirActors).toList()..sort();

      if (common5.isEmpty && commonF.isEmpty && commonW.isEmpty &&
          commonD.isEmpty && commonG.isEmpty && commonDir.isEmpty && commonAct.isEmpty) {
        continue;
      }

      double part(double common, double w) {
        if (common <= 0) return 0.0;
        final denom = common * 2; 
        return w * (common / denom);
      }

      const w5 = 3.0, wFav = 4.0, wWatch = 1.6, wG = 1.5, wDir = 1.8, wAct = 1.2;
      final maxScoreUnit = w5 + wFav + wWatch + wG + wDir + wAct;
      final unitScore =
          part(common5.length.toDouble(), w5) +
          part(commonF.length.toDouble(), wFav) +
          part(commonW.length.toDouble(), wWatch) +
          part(commonG.length.toDouble(), wG) +
          part(commonDir.length.toDouble(), wDir) +
          part(commonAct.length.toDouble(), wAct);

      final raw = (unitScore / maxScoreUnit) * 100.0;
      const double gamma = 0.85;
      const double lift = 33.0; 
      final boosted = math.pow(raw / 100.0, gamma) * 100.0;
      final score = math.min(100.0, boosted + lift);

      out.add(
        MatchResult(
          uid: uid,
          score: score,
          commonFiveStars: common5,
          commonFavorites: commonF,
          commonWatchlist: commonW,
          commonDisliked: commonD,
          commonGenres: commonG,
          commonDirectors: commonDir,
          commonActors: commonAct,
          displayName: data['displayName'] as String?,
          letterboxdUsername: data['letterboxdUsername'] as String?,
          photoURL: data['photoURL'] as String?,
        ),
      );
    }

    out.sort((a, b) {
      final s = b.score.compareTo(a.score);
      if (s != 0) return s;
      return b.commonFiveCount.compareTo(a.commonFiveCount);
    });

    _findCache[myUid] = _FindCache(out, DateTime.now());
    return out;
  }

  /* ---------------------------------------------------------------------- */
  /* 2) OTOMATİK MATCH OLUŞTUR (Eksik olan metot buraya eklendi)            */
  /* ---------------------------------------------------------------------- */
  Future<int> autoCreateMatches(
    String myUid, {
    int minCommonFive = 1,
    int minCommonFav = 1,
    int minCommonDisliked = 1,
  }) async {
    final meDoc = await _users.doc(myUid).get();
    if (!meDoc.exists) return 0;

    final myFive = _extractSet(meDoc.data(), ['fiveStarKeys']);
    final myFavs = _extractSet(meDoc.data(), ['favoritesKeys']);
    final myWatch = _extractSet(meDoc.data(), ['watchlistKeys']);
    final myDis = _extractSet(meDoc.data(), ['dislikedKeys']);

    final all = await _users.get();
    int touched = 0;

    for (final d in all.docs) {
      final uid = d.id;
      if (uid == myUid) continue;

      final data = d.data();
      final theirFive = _extractSet(data, ['fiveStarKeys']);
      final theirFavs = _extractSet(data, ['favoritesKeys']);
      final theirWatch = _extractSet(data, ['watchlistKeys']);
      final theirDis = _extractSet(data, ['dislikedKeys']);

      final c5 = myFive.intersection(theirFive);
      final cf = myFavs.intersection(theirFavs);
      final cw = myWatch.intersection(theirWatch);
      final cd = myDis.intersection(theirDis);

      final meetsA = c5.length >= minCommonFive && cf.length >= minCommonFav;
      final meetsB = cd.length >= minCommonDisliked;
      const int minCommonWatchlist = 3;
      final meetsC = c5.length >= minCommonFive && cw.length >= minCommonWatchlist;
      
      if (!meetsA && !meetsB && !meetsC) continue;

      final pairId = pairIdOf(myUid, uid);
      final meIsA = myUid.compareTo(uid) < 0;
      final aProfile = _profileSnippet(
        meIsA ? (meDoc.data() ?? {}) : data,
        meIsA ? myUid : uid,
      );
      final bProfile = _profileSnippet(
        meIsA ? data : (meDoc.data() ?? {}),
        meIsA ? uid : myUid,
      );
      await _matches.doc(pairId).set({
        'uids': meIsA ? [myUid, uid] : [uid, myUid],
        'aProfile': aProfile,
        'bProfile': bProfile,
        'commonFiveStarsCount': c5.length,
        'commonFavoritesCount': cf.length,
        'commonWatchlistCount': cw.length,
        'commonDislikedCount': cd.length,
        'commonGenresCount': 0,
        'commonDirectorsCount': 0,
        'commonActorsCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'source': meetsB
            ? 'auto:disliked'
            : (meetsC ? 'auto:five+watch' : 'auto:five+fav'),
      }, SetOptions(merge: true));

      touched++;
    }
    return touched;
  }

  /* ---------------------------------------------------------------------- */
  /* 3) OTOMATİK MATCH (SADECE 5★)                                          */
  /* ---------------------------------------------------------------------- */
  Future<int> autoCreateMatchesFiveOnly(
    String myUid, {
    int minCommonFive = 1,
  }) async {
    final meDoc = await _users.doc(myUid).get();
    if (!meDoc.exists) return 0;
    
    final myFive = _extractSet(meDoc.data(), ['fiveStarKeys']);
    if (myFive.isEmpty) return 0;

    final all = await _users.get();
    int touched = 0;

    for (final d in all.docs) {
      final uid = d.id;
      if (uid == myUid) continue;
      final theirFive = _extractSet(d.data(), ['fiveStarKeys']);
      if (theirFive.isEmpty) continue;

      final commonFive = myFive.intersection(theirFive);
      if (commonFive.length < minCommonFive) continue;

      final pairId = pairIdOf(myUid, uid);
      final meIsA = myUid.compareTo(uid) < 0;
      final aProfile = _profileSnippet(
        meIsA ? (meDoc.data() ?? {}) : d.data(),
        meIsA ? myUid : uid,
      );
      final bProfile = _profileSnippet(
        meIsA ? d.data() : (meDoc.data() ?? {}),
        meIsA ? uid : myUid,
      );
      await _matches.doc(pairId).set({
        'uids': meIsA ? [myUid, uid] : [uid, myUid],
        'aProfile': aProfile,
        'bProfile': bProfile,
        'commonFiveStarsCount': commonFive.length,
        'commonFavoritesCount': 0,
        'commonDislikedCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'source': 'auto:fiveOnly',
      }, SetOptions(merge: true));

      touched++;
    }
    return touched;
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> matchesStream(String uid) {
    return _matches.where('uids', arrayContains: uid).limit(50).snapshots().map(
      (qs) {
        final docs = [...qs.docs];
        docs.sort((a, b) {
          final ta = a.data()['updatedAt'] as Timestamp?;
          final tb = b.data()['updatedAt'] as Timestamp?;
          final da = ta?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = tb?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da); 
        });
        return docs;
      },
    );
  }
}