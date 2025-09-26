import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';

/// Tek bir eşleşmeyi temsil eder.
class MatchResult {
  final String uid;
  final double score; // 0..100
  final String? displayName;
  final String? username;
  final String? avatarUrl;

  /// Ortak favori ve ortak 5 yıldız anahtarları (film:<slug>)
  final List<String> commonFavorites;
  final List<String> commonFiveStars;

  int get commonFavoritesCount => commonFavorites.length;
  int get commonFiveStarsCount => commonFiveStars.length;

  MatchResult({
    required this.uid,
    required this.score,
    this.displayName,
    this.username,
    this.avatarUrl,
    required this.commonFavorites,
    required this.commonFiveStars,
  });
}

/// Eşleşme hesaplama servisi.
/// Kullandığı kaynaklar:
///  - users/{uid}.favoritesKeys : List<String>
///  - userTasteProfiles/{uid}.fiveStars : List<String>
///  - userTasteProfiles/{uid}.profile : { displayName?, letterboxdUsername?, avatarUrl? }
class MatchService {
  final _usersCol = FirebaseFirestore.instance.collection('users');
  final _tasteCol = FirebaseFirestore.instance.collection('userTasteProfiles');

  final _matchesCol = FirebaseFirestore.instance.collection('matches');

  String _pairIdOf(String u1, String u2) =>
      (u1.compareTo(u2) < 0) ? '${u1}_$u2' : '${u2}_$u1';

  /// [myUid] kullanıcısı için diğer kullanıcılarla eşleşme skorlarını döndürür.
  /// Skor: ortak 5 yıldızlara daha fazla ağırlık verilir.
  /// Formül (0..100):
  ///   score = 100 * ( 2*|F★∩G★| + |F∩G| ) / ( 2*(|F★|+|G★|) + (|F|+|G|) )
  /// Burada F=benim favorites, F★=benim fiveStars; G=karşı taraf favorites, G★=karşı taraf fiveStars.
  Future<List<MatchResult>> findMatches(String myUid) async {
    // 1) Benim dokümanlarım
    final meUsersSnap = await _usersCol.doc(myUid).get();
    final meTasteSnap = await _tasteCol.doc(myUid).get();

    final Set<String> myFavorites = Set<String>.from(
      (meUsersSnap.data()?['favoritesKeys'] ?? const []) as List,
    );
    final Set<String> myFiveStars = Set<String>.from(
      (meTasteSnap.data()?['fiveStars'] ?? const []) as List,
    );

    if (myFavorites.isEmpty && myFiveStars.isEmpty) {
      return [];
    }

    // 2) Diğer kullanıcıların toplu okunması
    final usersSnap = await _usersCol.get();
    final tasteSnap = await _tasteCol.get();

    // Haritalar: uid -> list
    final Map<String, Set<String>> favoritesByUid = {
      for (final d in usersSnap.docs)
        d.id: Set<String>.from((d.data()['favoritesKeys'] ?? const []) as List),
    };
    final Map<String, Set<String>> fiveStarsByUid = {
      for (final d in tasteSnap.docs)
        d.id: Set<String>.from((d.data()['fiveStars'] ?? const []) as List),
    };

    // Profil alanları (displayName / username / avatar)
    final Map<String, Map<String, dynamic>> profileByUid = {
      for (final d in tasteSnap.docs)
        d.id: (d.data()['profile'] ?? const {}) as Map<String, dynamic>,
    };

    // 3) Her aday için skor hesapla
    final List<MatchResult> out = [];

    final allUids = <String>{}
      ..addAll(favoritesByUid.keys)
      ..addAll(fiveStarsByUid.keys);

    for (final uid in allUids) {
      if (uid == myUid) continue;

      final theirFavs = favoritesByUid[uid] ?? const <String>{};
      final their5 = fiveStarsByUid[uid] ?? const <String>{};

      if (theirFavs.isEmpty && their5.isEmpty) continue;

      final commonFavs = myFavorites.intersection(theirFavs).toList()..sort();
      final common5 = myFiveStars.intersection(their5).toList()..sort();

      // Ağırlıklı skor
      final favDen = myFavorites.length + theirFavs.length;
      final fiveDen = myFiveStars.length + their5.length;
      final denom = 2 * fiveDen + favDen; // iki kat ağırlık 5 yıldıza

      double score = 0;
      if (denom > 0) {
        score = 100.0 * ((2 * common5.length + commonFavs.length) / denom);
      }

      // Profil bilgisi
      final p = profileByUid[uid] ?? const {};

      // En azından bir ortaklık olmalı
      if (commonFavs.isEmpty && common5.isEmpty) continue;

      out.add(
        MatchResult(
          uid: uid,
          score: score,
          displayName: p['displayName'] as String?,
          username: p['letterboxdUsername'] as String?,
          avatarUrl: p['avatarUrl'] as String?,
          commonFavorites: commonFavs,
          commonFiveStars: common5,
        ),
      );
    }

    // 4) Skora ve sonra ortak 5 yıldız sayısına göre sırala
    out.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final by5 = b.commonFiveStarsCount.compareTo(a.commonFiveStarsCount);
      if (by5 != 0) return by5;
      return b.commonFavoritesCount.compareTo(a.commonFavoritesCount);
    });

    return out;
  }

  /// Otomatik eşleştirme:
  /// - Koşul A: en az [minCommonFive] ortak 5★ VE en az [minCommonFav] ortak favori
  /// - Veya Koşul B: en az [minCommonDisliked] ortak beğenilmeyen (disliked)
  /// Şartı sağlayan adaylar için `matches/{pairId}` belgesi oluşturulur/güncellenir.
  Future<int> autoCreateMatches(
    String myUid, {
    int minCommonFive = 1,
    int minCommonFav = 1,
    int minCommonDisliked = 1,
  }) async {
    // 1) Benim profillerim
    final meUsersSnap = await _usersCol.doc(myUid).get();
    final meTasteSnap = await _tasteCol.doc(myUid).get();

    final Set<String> myFavorites = Set<String>.from(
      (meUsersSnap.data()?['favoritesKeys'] ?? const []) as List,
    );
    final Set<String> myFiveStars = Set<String>.from(
      (meTasteSnap.data()?['fiveStars'] ?? const []) as List,
    );
    final Set<String> myDisliked = Set<String>.from(
      (meUsersSnap.data()?['dislikedKeys'] ?? const []) as List,
    );

    if (myFavorites.isEmpty && myFiveStars.isEmpty && myDisliked.isEmpty) {
      return 0;
    }

    // 2) Tüm kullanıcı ve tat profilleri
    final usersSnap = await _usersCol.get();
    final tasteSnap = await _tasteCol.get();

    final Map<String, Set<String>> favoritesByUid = {
      for (final d in usersSnap.docs)
        d.id: Set<String>.from((d.data()['favoritesKeys'] ?? const []) as List),
    };
    final Map<String, Set<String>> dislikedByUid = {
      for (final d in usersSnap.docs)
        d.id: Set<String>.from((d.data()['dislikedKeys'] ?? const []) as List),
    };
    final Map<String, Set<String>> fiveStarsByUid = {
      for (final d in tasteSnap.docs)
        d.id: Set<String>.from((d.data()['fiveStars'] ?? const []) as List),
    };

    // 3) Adayları değerlendir, koşulu sağlayanlara match yaz
    int createdOrUpdated = 0;
    for (final uid in {
      ...favoritesByUid.keys,
      ...fiveStarsByUid.keys,
      ...dislikedByUid.keys,
    }) {
      if (uid == myUid) continue;

      final theirFavs = favoritesByUid[uid] ?? const <String>{};
      final their5 = fiveStarsByUid[uid] ?? const <String>{};
      final theirDis = dislikedByUid[uid] ?? const <String>{};

      final commonFavs = myFavorites.intersection(theirFavs);
      final common5 = myFiveStars.intersection(their5);
      final commonDis = myDisliked.intersection(theirDis);

      final meetsA =
          common5.length >= minCommonFive && commonFavs.length >= minCommonFav;
      final meetsB = commonDis.length >= minCommonDisliked;
      if (!meetsA && !meetsB) continue;

      final pairId = _pairIdOf(myUid, uid);
      final docRef = _matchesCol.doc(pairId);

      // createdAt sadece yoksa set edilir; updatedAt her seferinde güncellenir
      await docRef.set({
        'uids': (myUid.compareTo(uid) < 0) ? [myUid, uid] : [uid, myUid],
        'commonFavoritesCount': commonFavs.length,
        'commonFiveStarsCount': common5.length,
        'commonDislikedCount': commonDis.length,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'source': meetsB ? 'auto:disliked' : 'auto:five+fav',
      }, SetOptions(merge: true));

      createdOrUpdated += 1;
    }

    return createdOrUpdated;
  }
}
