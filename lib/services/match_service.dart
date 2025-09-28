import 'package:cloud_firestore/cloud_firestore.dart';

/// Tek bir eşleşmeyi temsil eder
class MatchResult {
  final String uid;
  final double score; // 0..100
  final List<String> commonFiveStars;
  final List<String> commonFavorites;
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
  int get commonDisCount => commonDisliked.length;

  int get commonGenreCount => commonGenres.length;
  int get commonDirectorCount => commonDirectors.length;
  int get commonActorCount => commonActors.length;

  MatchResult({
    required this.uid,
    required this.score,
    required this.commonFiveStars,
    required this.commonFavorites,
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

    final myFive = Set<String>.from(
      (meDoc.data()?['fiveStarKeys'] ?? const []) as List,
    );
    final myFavs = Set<String>.from(
      (meDoc.data()?['favoritesKeys'] ?? const []) as List,
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
      final commonD = myDis.intersection(theirDis).toList()..sort();

      final commonG = myGenres.intersection(theirGenres).toList()..sort();
      final commonDir = myDirectors.intersection(theirDirectors).toList()
        ..sort();
      final commonAct = myActors.intersection(theirActors).toList()..sort();

      if (common5.isEmpty &&
          commonF.isEmpty &&
          commonD.isEmpty &&
          commonG.isEmpty &&
          commonDir.isEmpty &&
          commonAct.isEmpty) {
        continue;
      }

      // Weighted score: 5★ (w=3), favorites (w=2), genres (w=1.5), directors (w=1.8), actors (w=1.2)
      // Denominators use sum of both sides for each vector, to keep score in 0..100.
      double part(double common, double total, double w) =>
          total == 0 ? 0.0 : w * (common / total);

      final totalFive = (myFive.length + theirFive.length).toDouble();
      final totalFavs = (myFavs.length + theirFavs.length).toDouble();
      final totalG = (myGenres.length + theirGenres.length).toDouble();
      final totalDir = (myDirectors.length + theirDirectors.length).toDouble();
      final totalAct = (myActors.length + theirActors.length).toDouble();

      // weights
      const w5 = 3.0, wFav = 2.0, wG = 1.5, wDir = 1.8, wAct = 1.2;

      final maxScoreUnit = w5 + wFav + wG + wDir + wAct;
      final unitScore =
          part(common5.length.toDouble(), totalFive, w5) +
          part(commonF.length.toDouble(), totalFavs, wFav) +
          part(commonG.length.toDouble(), totalG, wG) +
          part(commonDir.length.toDouble(), totalDir, wDir) +
          part(commonAct.length.toDouble(), totalAct, wAct);

      final score = (unitScore / maxScoreUnit) * 100.0;

      out.add(
        MatchResult(
          uid: uid,
          score: score,
          commonFiveStars: common5,
          commonFavorites: commonF,
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

    // Skor > ortak 5★ > ortak favori > ortak genre > ortak director > ortak actor sayısına göre sırala
    out.sort((a, b) {
      final s = b.score.compareTo(a.score);
      if (s != 0) return s;
      final f5 = b.commonFiveCount.compareTo(a.commonFiveCount);
      if (f5 != 0) return f5;
      final fav = b.commonFavCount.compareTo(a.commonFavCount);
      if (fav != 0) return fav;
      final g = b.commonGenreCount.compareTo(a.commonGenreCount);
      if (g != 0) return g;
      final d0 = b.commonDirectorCount.compareTo(a.commonDirectorCount);
      if (d0 != 0) return d0;
      return b.commonActorCount.compareTo(a.commonActorCount);
    });

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
      final theirDis = Set<String>.from(
        (data['dislikedKeys'] ?? const []) as List,
      );

      final c5 = myFive.intersection(theirFive);
      final cf = myFavs.intersection(theirFavs);
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
      if (!meetsA && !meetsB) continue;

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
        'commonDislikedCount': cd.length,
        'commonGenresCount': cG.length,
        'commonDirectorsCount': cDir.length,
        'commonActorsCount': cAct.length,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'source': meetsB ? 'auto:disliked' : 'auto:five+fav',
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
