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
  static const Duration _findCacheTtl = Duration(seconds: 120);
  // Cache: my taste profile + hidden uids (likes/passes/matches)
  final Map<String, Map<String, dynamic>> _myTasteCache = {};
  final Map<String, DateTime> _myTasteCacheTs = {};
  final Map<String, Set<String>> _hiddenCache = {};
  final Map<String, DateTime> _hiddenCacheTs = {};
  static const Duration _cacheTtl = Duration(minutes: 5);

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
  Future<List<MatchResult>> findMatches(
    String myUid, {
    int limit = 200,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    // 0) short-term result cache (UI tekrar çağırırsa)
    final now = DateTime.now();
    final cached = _findCache[myUid];
    if (cached != null && now.difference(cached.ts) < _findCacheTtl) {
      return cached.results;
    }

    // 1) OWN PROFILE (read once, then cache 5 dk)
    Map<String, dynamic>? meMap = _myTasteCache[myUid];
    final meTs = _myTasteCacheTs[myUid];
    final meFresh = meTs != null && now.difference(meTs) < _cacheTtl;

    if (meMap == null || !meFresh) {
      // prefer lighter userTasteProfiles/{uid}, fallback to users/{uid}
      final tasteDoc = await _db
          .collection('userTasteProfiles')
          .doc(myUid)
          .get();
      if (tasteDoc.exists) {
        meMap = tasteDoc.data();
      } else {
        final meDoc = await _users.doc(myUid).get();
        if (!meDoc.exists) return [];
        meMap = meDoc.data();
      }
      _myTasteCache[myUid] = meMap ?? {};
      _myTasteCacheTs[myUid] = now;
    }

    final myFive = Set<String>.from(
      (meMap?['fiveStarKeys'] ?? const []) as List,
    );
    final myFavs = Set<String>.from(
      (meMap?['favoritesKeys'] ?? const []) as List,
    );
    final myWatch = Set<String>.from(
      (meMap?['watchlistKeys'] ?? const []) as List,
    );
    final myDis = Set<String>.from(
      (meMap?['dislikedKeys'] ?? const []) as List,
    );

    final myGenres = _lcSet(meMap ?? const {}, 'favGenres');
    final myDirectors = _lcSet(meMap ?? const {}, 'favDirectors');
    final myActors = _lcSet(meMap ?? const {}, 'favActors');

    if (myFive.isEmpty &&
        myFavs.isEmpty &&
        myWatch.isEmpty &&
        myDis.isEmpty &&
        myGenres.isEmpty &&
        myDirectors.isEmpty &&
        myActors.isEmpty) {
      return [];
    }

    // 2) HIDDEN (likes/passes/matched) — read once per 5 dk
    Set<String> hiddenUids = _hiddenCache[myUid] ?? {};
    final hidTs = _hiddenCacheTs[myUid];
    final hidFresh = hidTs != null && now.difference(hidTs) < _cacheTtl;

    if (!hidFresh) {
      hiddenUids = <String>{};
      try {
        // keep it cheap; read only docs where I am in uids and within a reasonable cap
        final likesQs = await _db
            .collection('likes')
            .where('uids', arrayContains: myUid)
            .limit(400)
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
          if (myPass || matched || (myLiked && !matched)) {
            hiddenUids.add(meIsA ? b : a);
          }
        }
      } catch (_) {
        // swallow
      }
      _hiddenCache[myUid] = hiddenUids;
      _hiddenCacheTs[myUid] = now;
    }

    // 3) PAGE THROUGH userTasteProfiles to minimize reads
    final profiles = _db.collection('userTasteProfiles');

    // Target number of candidates to RETURN (hard cap to avoid huge CPU work)
    const int targetCount = 40;

    List<MatchResult> results = [];
    DocumentSnapshot<Map<String, dynamic>>? cursor = startAfter;
    bool more = true;

    while (results.length < targetCount && more) {
      Query<Map<String, dynamic>> q = profiles.limit(limit);
      // If you have an index on updatedAt, uncomment next line to prefer fresher profiles.
      // q = q.orderBy('updatedAt', descending: true);

      final page = cursor == null
          ? await q.get()
          : await q.startAfterDocument(cursor).get();
      if (page.docs.isEmpty) {
        more = false;
        break;
      }
      cursor = page.docs.last;

      for (final d in page.docs) {
        final uid = d.id;
        if (uid == myUid) continue;
        if (hiddenUids.contains(uid)) continue;

        final data = d.data();

        // ratings-based sets
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

        // semantic vectors
        final theirGenres = _lcSet(data, 'favGenres');
        final theirDirectors = _lcSet(data, 'favDirectors');
        final theirActors = _lcSet(data, 'favActors');

        final common5 = myFive.intersection(theirFive);
        final commonF = myFavs.intersection(theirFavs);
        final commonW = myWatch.intersection(theirWatch);
        final commonD = myDis.intersection(theirDis);
        final commonG = myGenres.intersection(theirGenres);
        final commonDir = myDirectors.intersection(theirDirectors);
        final commonAct = myActors.intersection(theirActors);

        if (common5.isEmpty &&
            commonF.isEmpty &&
            commonW.isEmpty &&
            commonD.isEmpty &&
            commonG.isEmpty &&
            commonDir.isEmpty &&
            commonAct.isEmpty) {
          continue;
        }

        // score (lightweight)
        double part(int common, double w) {
          if (common <= 0) return 0.0;
          final denom = common * 2.0;
          return w * (common / denom);
        }

        const w5 = 3.0,
            wFav = 4.0,
            wWatch = 1.6,
            wG = 1.5,
            wDir = 0.0,
            wAct = 0.0;
        final maxScoreUnit = w5 + wFav + wWatch + wG + wDir + wAct;
        final unitScore =
            part(common5.length, w5) +
            part(commonF.length, wFav) +
            part(commonW.length, wWatch) +
            part(commonG.length, wG) +
            part(commonDir.length, wDir) +
            part(commonAct.length, wAct);

        final raw = (unitScore / maxScoreUnit) * 100.0;
        const double gamma = 0.85;
        const double lift = 33.0;
        final boosted =
            (math.pow(raw / 100.0, gamma) as num).toDouble() * 100.0;
        final score = math.min(100.0, boosted + lift);

        results.add(
          MatchResult(
            uid: uid,
            score: score,
            commonFiveStars: common5.toList(),
            commonFavorites: commonF.toList(),
            commonWatchlist: commonW.toList(),
            commonDisliked: commonD.toList(),
            commonGenres: commonG.toList(),
            commonDirectors: commonDir.toList(),
            commonActors: commonAct.toList(),
            displayName: data['displayName'] as String?,
            letterboxdUsername: data['letterboxdUsername'] as String?,
            photoURL: data['photoURL'] as String?,
          ),
        );

        if (results.length >= targetCount) break;
      }
    }

    // stable sort
    results.sort((a, b) {
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

    _findCache[myUid] = _FindCache(results, DateTime.now());
    return results;
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

    final all = await _db.collection('userTasteProfiles').get();

    WriteBatch? batch;
    int batchCount = 0;
    Future<void> commitIfNeeded() async {
      if (batch != null && batchCount >= 400) {
        await batch!.commit();
        batch = null;
        batchCount = 0;
      }
    }

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
      batch ??= _db.batch();
      final docRef = _matches.doc(pairId);
      batch!.set(docRef, {
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
      batchCount++;
      await commitIfNeeded();
      touched++;
    }
    if (batch != null && batchCount > 0) {
      await batch!.commit();
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

    final all = await _db.collection('userTasteProfiles').get();
    WriteBatch? batch;
    int batchCount = 0;
    Future<void> commitIfNeeded() async {
      if (batch != null && batchCount >= 400) {
        await batch!.commit();
        batch = null;
        batchCount = 0;
      }
    }

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
      batch ??= _db.batch();
      final docRef = _matches.doc(pairId);
      batch!.set(docRef, {
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
      batchCount++;
      await commitIfNeeded();
      touched++;
    }
    if (batch != null && batchCount > 0) {
      await batch!.commit();
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
