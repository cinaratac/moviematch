import 'package:cloud_firestore/cloud_firestore.dart';

/// Tek bir eşleşmeyi temsil eder
class MatchResult {
  final String uid;
  final double score; // 0..100
  final List<String> commonFiveStars;
  final List<String> commonFavorites;
  final List<String> commonDisliked;
  final String? displayName;
  final String? letterboxdUsername;
  final String? photoURL;

  int get commonFiveCount => commonFiveStars.length;
  int get commonFavCount => commonFavorites.length;
  int get commonDisCount => commonDisliked.length;

  MatchResult({
    required this.uid,
    required this.score,
    required this.commonFiveStars,
    required this.commonFavorites,
    required this.commonDisliked,
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

    final Set<String> myFive = Set<String>.from(
      (meDoc.data()?['fiveStarKeys'] ?? const []) as List,
    );
    final Set<String> myFavs = Set<String>.from(
      (meDoc.data()?['favoritesKeys'] ?? const []) as List,
    );
    final Set<String> myDis = Set<String>.from(
      (meDoc.data()?['dislikedKeys'] ?? const []) as List,
    );

    if (myFive.isEmpty && myFavs.isEmpty && myDis.isEmpty) return [];

    // Tüm kullanıcıları oku (geliştirme için uygun; üretimde pagination düşünebilirsin)
    final all = await _users.get();

    final List<MatchResult> out = [];
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

      if (theirFive.isEmpty && theirFavs.isEmpty && theirDis.isEmpty) continue;

      final common5 = myFive.intersection(theirFive).toList()..sort();
      final commonF = myFavs.intersection(theirFavs).toList()..sort();
      final commonD = myDis.intersection(theirDis).toList()..sort();

      // En az bir ortaklık olmalı
      if (common5.isEmpty && commonF.isEmpty && commonD.isEmpty) continue;

      // Skor: 5★ iki kat ağırlık
      final denom =
          2 * (myFive.length + theirFive.length) +
          (myFavs.length + theirFavs.length);
      final score = denom == 0
          ? 0.0
          : (100.0 * ((2 * common5.length + commonF.length) / denom))
                .toDouble();

      out.add(
        MatchResult(
          uid: uid,
          score: score,
          commonFiveStars: common5,
          commonFavorites: commonF,
          commonDisliked: commonD,
          displayName: data['displayName'] as String?,
          letterboxdUsername: data['letterboxdUsername'] as String?,
          photoURL: data['photoURL'] as String?,
        ),
      );
    }

    // Skor > ortak 5★ > ortak favori sayısına göre sırala
    out.sort((a, b) {
      final s = b.score.compareTo(a.score);
      if (s != 0) return s;
      final f5 = b.commonFiveCount.compareTo(a.commonFiveCount);
      if (f5 != 0) return f5;
      return b.commonFavCount.compareTo(a.commonFavCount);
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
