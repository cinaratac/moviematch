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

  // NEW: profile snippet (already existed)
  final String? displayName;
  final String? letterboxdUsername;
  final String? photoURL;

  // NEW: semantic overlaps
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
  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _matches =>
      _db.collection('matches');

  // In-memory short-term cache for findMatches results per user
  final Map<String, _FindCache> _findCache = {};
  static const Duration _findCacheTtl = Duration(seconds: 60);

  Set<String> _lcSet(Map<String, dynamic> src, String key) {
    final raw = (src[key] ?? const []) as List;
    return raw
        .map((e) => e.toString().trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  Map<String, dynamic> _profileSnippet(Map<String, dynamic> u, String uid) => {
    'uid': uid,
    'displayName': (u['displayName'] ?? '') as String,
    'lb': (u['letterboxdUsername'] ?? '') as String,
    'photoURL': (u['photoURL'] ?? '') as String,
  };

  /// İki uid’den deterministik pairId üret
  String pairIdOf(String a, String b) =>
      (a.compareTo(b) < 0) ? '${a}_$b' : '${b}_$a';

  /* ---------------------------------------------------------------------- */
  /* 1) EŞLEŞME LİSTESİ HESAPLA (YAZMADAN, SADECE HESAP)                     */
  /* ---------------------------------------------------------------------- */
  Future<List<MatchResult>> findMatches(String myUid) async {
    final meDoc = await _users.doc(myUid).get();
    if (!meDoc.exists) return [];

    // Short-term cache: avoid recomputing within TTL for the same user
    final now = DateTime.now();
    final cached = _findCache[myUid];
    if (cached != null && now.difference(cached.ts) < _findCacheTtl) {
      return cached.results;
    }

    final myFive = Set<String>.from(
      (meDoc.data()?['fiveStarKeys'] ?? const []) as List,
    );
    final myFavs = Set<String>.from(
      (meDoc.data()?['favoritesKeys'] ?? const []) as List,
    );
    final myWatch = Set<String>.from(
      (meDoc.data()?['watchlistKeys'] ?? const []) as List,
    );
    final myDis = Set<String>.from(
      (meDoc.data()?['dislikedKeys'] ?? const []) as List,
    );

    // NEW: profile vectors (lowercased)
    final meMap = meDoc.data() ?? {};
    final myGenres = _lcSet(meMap, 'favGenres');
    final myDirectors = _lcSet(meMap, 'favDirectors');
    final myActors = _lcSet(meMap, 'favActors');

    if (myFive.isEmpty &&
        myFavs.isEmpty &&
        myWatch.isEmpty &&
        myDis.isEmpty &&
        myGenres.isEmpty &&
        myDirectors.isEmpty &&
        myActors.isEmpty) {
      return [];
    }

    // Tüm kullanıcıları oku (geliştirme için uygun; üretimde pagination düşünebilirsin)
    final all = await _users.get();

    final List<MatchResult> out = [];
    for (final d in all.docs) {
      final uid = d.id;
      if (uid == myUid) continue;

      final data = d.data();

      // ratings-based keys
      final theirFive = Set<String>.from(
        (data['fiveStarKeys'] ?? const []) as List,
      );
      final theirFavs = Set<String>.from(
        (data['favoritesKeys'] ?? const []) as List,
      );
      final theirWatch = Set<String>.from(
        (data['watchlistKeys'] ?? const []) as List,
      );
      final theirDis = Set<String>.from(
        (data['dislikedKeys'] ?? const []) as List,
      );

      // semantic vectors (lowercased)
      final theirGenres = _lcSet(data, 'favGenres');
      final theirDirectors = _lcSet(data, 'favDirectors');
      final theirActors = _lcSet(data, 'favActors');

      // intersections
      final common5 = myFive.intersection(theirFive).toList()..sort();
      final commonF = myFavs.intersection(theirFavs).toList()..sort();
      final commonW = myWatch.intersection(theirWatch).toList()..sort();
      final commonD = myDis.intersection(theirDis).toList()..sort();

      final commonG = myGenres.intersection(theirGenres).toList()..sort();
      final commonDir = myDirectors.intersection(theirDirectors).toList()
        ..sort();
      final commonAct = myActors.intersection(theirActors).toList()..sort();

      if (common5.isEmpty &&
          commonF.isEmpty &&
          commonW.isEmpty &&
          commonD.isEmpty &&
          commonG.isEmpty &&
          commonDir.isEmpty &&
          commonAct.isEmpty) {
        continue;
      }

      // Weighted score: 5★ (w=3), favorites (w=2), watchlist (w=1.6), genres (w=1.5), directors (w=1.8), actors (w=1.2)
      // New denominator: double the intersection count
      double part(double common, double total, double w) {
        if (common <= 0) return 0.0;
        final denom = common * 2; // ortak kümenin iki katı
        return w * (common / denom);
      }

      // weights (favoriler boosted)
      const w5 = 3.0,
          wFav = 4.0,
          wWatch = 1.6,
          wG = 1.5,
          wDir = 0.0,
          wAct = 0.0;

      final maxScoreUnit = w5 + wFav + wWatch + wG + wDir + wAct;
      final unitScore =
          part(common5.length.toDouble(), 0, w5) +
          part(commonF.length.toDouble(), 0, wFav) +
          part(commonW.length.toDouble(), 0, wWatch) +
          part(commonG.length.toDouble(), 0, wG) +
          part(commonDir.length.toDouble(), 0, wDir) +
          part(commonAct.length.toDouble(), 0, wAct);

      // --- Calibration for a slightly higher, friendlier score distribution ---
      // raw in [0,100]
      final raw = (unitScore / maxScoreUnit) * 100.0;
      const double gamma = 0.85; // <1.0 → boosts mid/low scores gently
      const double lift = 33.0; // constant lift, capped later
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

    // Skor > ortak 5★ > ortak favori > ortak watchlist > ortak genre > ortak director > ortak actor sayısına göre sırala
    out.sort((a, b) {
      final s = b.score.compareTo(a.score);
      if (s != 0) return s;
      final f5 = b.commonFiveCount.compareTo(a.commonFiveCount);
      if (f5 != 0) return f5;
      final fav = b.commonFavCount.compareTo(a.commonFavCount);
      if (fav != 0) return fav;
      final w = b.commonWatchCount.compareTo(a.commonWatchCount);
      if (w != 0) return w;
      final g = b.commonGenreCount.compareTo(a.commonGenreCount);
      if (g != 0) return g;
      final d0 = b.commonDirectorCount.compareTo(a.commonDirectorCount);
      if (d0 != 0) return d0;
      return b.commonActorCount.compareTo(a.commonActorCount);
    });

    // Store in short-term cache
    _findCache[myUid] = _FindCache(out, DateTime.now());
    return out;
  }

  /* ---------------------------------------------------------------------- */
  /* 2) OTOMATİK MATCH OLUŞTUR (matches/{pairId})                           */
  /* ---------------------------------------------------------------------- */
  /// Şartı sağlayan adaylar için `matches/{pairId}` belgesini set/merge eder.
  /// Varsayılan eşik: en az 1 ortak 5★ VE 1 ortak favori **VEYA** en az 1 ortak disliked.
  Future<int> autoCreateMatches(
    String myUid, {
    int minCommonFive = 1,
    int minCommonFav = 1,
    int minCommonDisliked = 1,
  }) async {
    final meDoc = await _users.doc(myUid).get();
    if (!meDoc.exists) return 0;

    final myFive = Set<String>.from(
      (meDoc.data()?['fiveStarKeys'] ?? const []) as List,
    );
    final myFavs = Set<String>.from(
      (meDoc.data()?['favoritesKeys'] ?? const []) as List,
    );
    final myWatch = Set<String>.from(
      (meDoc.data()?['watchlistKeys'] ?? const []) as List,
    );
    final myDis = Set<String>.from(
      (meDoc.data()?['dislikedKeys'] ?? const []) as List,
    );

    final all = await _users.get();

    int touched = 0;
    for (final d in all.docs) {
      final uid = d.id;
      if (uid == myUid) continue;

      final data = d.data();
      final theirFive = Set<String>.from(
        (data['fiveStarKeys'] ?? const []) as List,
      );
      final theirFavs = Set<String>.from(
        (data['favoritesKeys'] ?? const []) as List,
      );
      final theirWatch = Set<String>.from(
        (data['watchlistKeys'] ?? const []) as List,
      );
      final theirDis = Set<String>.from(
        (data['dislikedKeys'] ?? const []) as List,
      );

      final c5 = myFive.intersection(theirFive);
      final cf = myFavs.intersection(theirFavs);
      final cw = myWatch.intersection(theirWatch);
      final cd = myDis.intersection(theirDis);

      // NEW: semantic overlaps
      final myGenres = _lcSet(meDoc.data() ?? {}, 'favGenres');
      final myDirectors = _lcSet(meDoc.data() ?? {}, 'favDirectors');
      final myActors = _lcSet(meDoc.data() ?? {}, 'favActors');

      final theirGenres = _lcSet(data, 'favGenres');
      final theirDirectors = _lcSet(data, 'favDirectors');
      final theirActors = _lcSet(data, 'favActors');

      final cG = myGenres.intersection(theirGenres);
      final cDir = myDirectors.intersection(theirDirectors);
      final cAct = myActors.intersection(theirActors);

      final meetsA = c5.length >= minCommonFive && cf.length >= minCommonFav;
      final meetsB = cd.length >= minCommonDisliked;
      // NEW: allow watchlist synergy as an alternative path
      const int minCommonWatchlist = 3; // tweakable threshold
      final meetsC =
          c5.length >= minCommonFive && cw.length >= minCommonWatchlist;
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
        'commonGenresCount': cG.length,
        'commonDirectorsCount': cDir.length,
        'commonActorsCount': cAct.length,
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
  /* 2.1) OTOMATİK MATCH (SADECE ORTAK 5★)                                 */
  /* ---------------------------------------------------------------------- */
  /// Yalnızca ortak 5★'ı baz alan otomatik eşleştirme.
  /// En az [minCommonFive] adet ortak 5★ varsa matches/{pairId} set/merge eder.
  Future<int> autoCreateMatchesFiveOnly(
    String myUid, {
    int minCommonFive = 1,
  }) async {
    final meDoc = await _users.doc(myUid).get();
    if (!meDoc.exists) return 0;

    final myFive = Set<String>.from(
      (meDoc.data()?['fiveStarKeys'] ?? const []) as List,
    );

    if (myFive.isEmpty) return 0;

    final all = await _users.get();
    int touched = 0;

    for (final d in all.docs) {
      final uid = d.id;
      if (uid == myUid) continue;

      final data = d.data();
      final theirFive = Set<String>.from(
        (data['fiveStarKeys'] ?? const []) as List,
      );
      if (theirFive.isEmpty) continue;

      final commonFive = myFive.intersection(theirFive);
      if (commonFive.length < minCommonFive) continue;

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

  /* ---------------------------------------------------------------------- */
  /* 3) MATCHES LİSTESİ STREAM (ekrana göstermek için)                      */
  /* ---------------------------------------------------------------------- */
  /// Not: orderBy kullanmıyoruz; indeks gerekmesin diye client-side sıralıyoruz.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> matchesStream(
    String uid,
  ) {
    return _matches.where('uids', arrayContains: uid).limit(50).snapshots().map(
      (qs) {
        final docs = [...qs.docs];
        docs.sort((a, b) {
          final ta = a.data()['updatedAt'] as Timestamp?;
          final tb = b.data()['updatedAt'] as Timestamp?;
          final da = ta?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = tb?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da); // desc
        });
        return docs;
      },
    );
  }
}
