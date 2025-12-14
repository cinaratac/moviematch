import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;

// --- Cache Yardımcı Sınıfı ---
class _FindCache {
  final List<MatchResult> results;
  final DateTime ts;
  const _FindCache(this.results, this.ts);
}

// --- Eşleşme Sonuç Modeli ---
class MatchResult {
  final String uid;
  final double score; // 0..100
  
  // Ortak nokta detayları
  final List<String> commonFiveStars;
  final List<String> commonFavorites;
  final List<String> commonWatchlist;
  final List<String> commonDisliked;

  final List<String> commonGenres;
  final List<String> commonDirectors;
  final List<String> commonActors;

  // UI için gerekli profil bilgileri
  final String? displayName;
  final String? letterboxdUsername;
  final String? photoURL;

  // Helper getters
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
  
  // Koleksiyon Referansları
  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _matches => _db.collection('matches');
  CollectionReference<Map<String, dynamic>> get _likes => _db.collection('likes');

  // In-memory short-term cache
  final Map<String, _FindCache> _findCache = {};


  void clearCache() => _findCache.clear();

  void removeUserFromCache(String myUid, String otherUid) {
    final cached = _findCache[myUid];
    if (cached != null) {
      final newList = cached.results.where((m) => m.uid != otherUid).toList();
      _findCache[myUid] = _FindCache(newList, cached.ts);
    }
  }

  // --- Yardımcı Metotlar ---

  String pairIdOf(String a, String b) => (a.compareTo(b) < 0) ? '${a}_$b' : '${b}_$a';

  Set<String> _lcSet(Map<String, dynamic> src, String key) {
    final raw = (src[key] ?? const []) as List;
    return raw.map((e) => e.toString().trim().toLowerCase()).where((e) => e.isNotEmpty).toSet();
  }

  Set<String> _extractSet(Map<String, dynamic>? data, List<String> keys) {
    if (data == null) return {};
    for (final key in keys) {
      final val = data[key];
      if (val is List) {
        final set = val.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toSet();
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

  // ---------------------------------------------------------------------------
  // YENİ: MERKEZİ HESAPLAMA MOTORU (Daha Cömert Algoritma)
  // Bu fonksiyon hem findMatches hem de calculateMatchScore tarafından kullanılır.
  // ---------------------------------------------------------------------------
  MatchResult? _computeMatch(String myUid, String otherUid, Map<String, dynamic> myData, Map<String, dynamic> theirData) {
    // 1. Verileri Hazırla
    final myFive = _extractSet(myData, ['fiveStarKeys', 'fiveIds', 'fiveStars']);
    final myFavs = _extractSet(myData, ['favoritesKeys', 'favIds', 'favoriteFilmIds']);
    final myWatch = _extractSet(myData, ['watchlistKeys', 'watchIds', 'watchlistIds']);
    final myDis = _extractSet(myData, ['dislikedKeys', 'dislikes']);
    
    final myGenres = _lcSet(myData, 'favGenres');
    final myDirectors = _lcSet(myData, 'favDirectors');
    final myActors = _lcSet(myData, 'favActors');

    final theirFive = _extractSet(theirData, ['fiveStarKeys', 'fiveIds']);
    final theirFavs = _extractSet(theirData, ['favoritesKeys', 'favIds']);
    final theirWatch = _extractSet(theirData, ['watchlistKeys', 'watchIds']);
    final theirDis = _extractSet(theirData, ['dislikedKeys', 'dislikes']);
    
    final theirGenres = _lcSet(theirData, 'favGenres');
    final theirDirectors = _lcSet(theirData, 'favDirectors');
    final theirActors = _lcSet(theirData, 'favActors');

    // 2. Kesişimleri Bul
    final common5 = myFive.intersection(theirFive).toList()..sort();
    final commonF = myFavs.intersection(theirFavs).toList()..sort();
    final commonW = myWatch.intersection(theirWatch).toList()..sort();
    final commonD = myDis.intersection(theirDis).toList()..sort();
    
    final commonG = myGenres.intersection(theirGenres).toList()..sort();
    final commonDir = myDirectors.intersection(theirDirectors).toList()..sort();
    final commonAct = myActors.intersection(theirActors).toList()..sort();

    // Hiçbir ortak nokta yoksa null dön (Listede hiç çıkmasın)
    if (common5.isEmpty && commonF.isEmpty && commonW.isEmpty &&
        commonD.isEmpty && commonG.isEmpty && commonDir.isEmpty && commonAct.isEmpty) {
      return null;
    }

    // 3. PUANLAMA ALGORİTMASI (Daha Cömert Versiyon)
    
    // Yardımcı: Doygunluk Fonksiyonu
    // count: Ortak sayı
    // weight: Bu kategorinin maksimum puanı
    // k (saturation): Kaç tane ortak olunca puanın yarısını alsın? (Düşük k = Hızlı Puan)
    double calcPart(int count, double weight, double k) {
      if (count <= 0) return 0.0;
      // Formül: weight * (count / (count + k))
      return weight * (count / (count + k));
    }

    // Ağırlıklar (Toplamı ~100)
    const w5 = 30.0;     
    const wFav = 40.0;   
    const wWatch = 10.0; 
    const wG = 5.0;      
    const wDir = 10.0;   
    const wAct = 5.0;    

    // --- CÖMERT AYARLAR ---
    final score5 = calcPart(common5.length, w5, 2.0);      
    final scoreFav = calcPart(commonF.length, wFav, 1.0);  // 1 ortak favori = 20 puan!
    final scoreWatch = calcPart(commonW.length, wWatch, 3.0); 
    
    final scoreG = calcPart(commonG.length, wG, 1.0);
    final scoreDir = calcPart(commonDir.length, wDir, 1.0);
    final scoreAct = calcPart(commonAct.length, wAct, 1.0);

    // Ham Toplam
    double totalScore = score5 + scoreFav + scoreWatch + scoreG + scoreDir + scoreAct;

    // Beğenilmeyenler Bonusu
    if (commonD.isNotEmpty) totalScore += 3.0;

    // --- BOOST (YÜKSELTME) ---
    if (totalScore > 0) {
      // 1. Taban puan ekle (Herhangi bir ortaklık varsa en az 15 puan cebe girsin)
      totalScore += 15.0; 
      
      // 2. Düşük puanları yukarı çeken eğri uygula
      totalScore = math.sqrt(totalScore) * 10.0;
    }

    // Son limit
    final finalScore = math.min(100.0, totalScore);

    return MatchResult(
      uid: otherUid,
      score: finalScore,
      commonFiveStars: common5,
      commonFavorites: commonF,
      commonWatchlist: commonW,
      commonDisliked: commonD,
      commonGenres: commonG,
      commonDirectors: commonDir,
      commonActors: commonAct,
      displayName: theirData['displayName'] as String?,
      letterboxdUsername: theirData['letterboxdUsername'] as String?,
      photoURL: theirData['photoURL'] as String?,
    );
  }

  /* ---------------------------------------------------------------------- */
  /* 1) EŞLEŞME LİSTESİ HESAPLA (findMatches)                               */
  /* ---------------------------------------------------------------------- */

Future<List<MatchResult>> findMatches(String myUid, {int candidateLimit = 100}) async {
  // 1. Kendi verini çek
  final meDoc = await _users.doc(myUid).get();
  if (!meDoc.exists) return [];
  final myData = meDoc.data() ?? {};

  // --- İMLEÇ MANTIĞI BAŞLANGICI ---
  // Kullanıcının en son hangi tarihteki kullanıcıyı çektiğini alıyoruz.
  final lastCursorTs = myData['lastFetchCursor'] as Timestamp?;
  // --- İMLEÇ MANTIĞI BİTİŞİ ---

  // 2. Etkileşime geçilenleri filtrele (Cache ve Likes tablosundan)
  final hiddenUids = <String>{myUid};
  
  // Cache'teki sonuçları da hidden listesine ekle ki tekrar hesaplamasın
  final cachedResults = _findCache[myUid]?.results;
  if (cachedResults != null) {
    hiddenUids.addAll(cachedResults.map((e) => e.uid));
  }

  try {
    // Beğendiklerini ve geçtiklerini al
    final likesQs = await _likes.where('uids', arrayContains: myUid).get();
    for (final doc in likesQs.docs) {
      final m = doc.data();
      final a = m['a'] as String?;
      final b = m['b'] as String?;
      if (a == null || b == null) continue;
      // Karşı tarafın ID'sini bul ve gizlenenlere ekle
      hiddenUids.add(myUid == a ? b : a);
    }
  } catch (_) {}

  // 3. Adayları Getir (İyileştirilmiş Sorgu)
  // 'createdAt' alanına göre sırala. En yeniler veya en eskiler fark etmez,
  // önemli olan sıranın sabit olmasıdır. (Burada 'descending: true' = En yeniler önce)
  Query<Map<String, dynamic>> query = _users.orderBy('createdAt', descending: true);

  // Eğer daha önce bir yerde kaldıysak, oradan sonrasını getir
  if (lastCursorTs != null) {
    query = query.startAfter([lastCursorTs]);
  }

  // LIMIT: hiddenUids kontrolünü hesaba katarak biraz fazla çekiyoruz
  // çünkü çektiğimiz 100 kişinin 50'si zaten beğenilmiş olabilir.
  final allCandidates = await query.limit(candidateLimit + hiddenUids.length).get();
  
  // Eğer hiç aday kalmadıysa ve cursor varsa (yani sona geldiysek),
  // belki cursor'ı sıfırlayıp başa dönmek isteyebilirsiniz (opsiyonel).
  if (allCandidates.docs.isEmpty) {
     // Kullanıcı bitti.
     return [];
  }

  final List<MatchResult> out = [];
  Timestamp? newLastCursor; // Bu batch'teki son kişinin tarihi

  // 4. Her aday için hesapla
  for (final d in allCandidates.docs) {
    final uid = d.id;
    final docData = d.data();
    
    // İşlenen son dokümanın tarihini takip et
    if (docData['createdAt'] is Timestamp) {
      newLastCursor = docData['createdAt'] as Timestamp;
    }

    if (hiddenUids.contains(uid)) continue;

    // Hesaplama Motoru
    final result = _computeMatch(myUid, uid, myData, docData);
    if (result != null) {
      out.add(result);
    }
  }

  // --- İMLECİ GÜNCELLE ---
  // Çekilen son kişinin tarihini kullanıcının profiline kaydet.
  // Böylece bir sonraki sefer aynı kişileri çekmeyiz.
  if (newLastCursor != null) {
    await _users.doc(myUid).update({
      'lastFetchCursor': newLastCursor
    });
  }

  // 5. Sırala
  out.sort((a, b) {
    final s = b.score.compareTo(a.score);
    if (s != 0) return s;
    return b.commonFiveCount.compareTo(a.commonFiveCount);
  });

  // Cache'i güncelle
  _findCache[myUid] = _FindCache(out, DateTime.now());
  
  return out;
}

  /* ---------------------------------------------------------------------- */
  /* 2) TEKİL KULLANICI UYUMU HESAPLA (Profil Ekranı İçin)                  */
  /* ---------------------------------------------------------------------- */
  Future<int> calculateMatchScore(String myUid, String otherUid) async {
    try {
      final meDoc = await _users.doc(myUid).get();
      final otherDoc = await _users.doc(otherUid).get();

      if (!meDoc.exists || !otherDoc.exists) return 0;

      final result = _computeMatch(myUid, otherUid, meDoc.data()!, otherDoc.data()!);
      
      return result != null ? result.score.round() : 0;
    } catch (e) {
      return 0;
    }
  }

  /* ---------------------------------------------------------------------- */
  /* 3) AUTO MATCH                                                          */
  /* ---------------------------------------------------------------------- */
  Future<int> autoCreateMatches(
    String myUid, {
    int minCommonFive = 1,
    int minCommonFav = 1,
    int minCommonDisliked = 1,
    int limitCandidates = 50,
  }) async {
    final meDoc = await _users.doc(myUid).get();
    if (!meDoc.exists) return 0;
    final myData = meDoc.data() ?? {};

    final myFive = _extractSet(myData, ['fiveStarKeys']);
    final myFavs = _extractSet(myData, ['favoritesKeys']);
    final myWatch = _extractSet(myData, ['watchlistKeys']);
    final myDis = _extractSet(myData, ['dislikedKeys']);

    final all = await _users.limit(limitCandidates).get();
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
      
      final aProfile = _profileSnippet(meIsA ? myData : data, meIsA ? myUid : uid);
      final bProfile = _profileSnippet(meIsA ? data : myData, meIsA ? uid : myUid);
      
      await _matches.doc(pairId).set({
        'uids': meIsA ? [myUid, uid] : [uid, myUid],
        'aProfile': aProfile,
        'bProfile': bProfile,
        'commonFiveStarsCount': c5.length,
        'commonFavoritesCount': cf.length,
        'commonWatchlistCount': cw.length,
        'commonDislikedCount': cd.length,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'source': meetsB ? 'auto:disliked' : (meetsC ? 'auto:five+watch' : 'auto:five+fav'),
      }, SetOptions(merge: true));

      touched++;
    }
    return touched;
  }

  /* ---------------------------------------------------------------------- */
  /* 4) AUTO MATCH FIVE ONLY                                                */
  /* ---------------------------------------------------------------------- */
  Future<int> autoCreateMatchesFiveOnly(
    String myUid, {
    int minCommonFive = 1,
    int candidateLimit = 50, 
  }) async {
    final meDoc = await _users.doc(myUid).get();
    if (!meDoc.exists) return 0;
    
    final myFive = _extractSet(meDoc.data(), ['fiveStarKeys']);
    if (myFive.isEmpty) return 0;

    final all = await _users.limit(candidateLimit).get();
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
      
      final aProfile = _profileSnippet(meIsA ? (meDoc.data() ?? {}) : d.data(), meIsA ? myUid : uid);
      final bProfile = _profileSnippet(meIsA ? d.data() : (meDoc.data() ?? {}), meIsA ? uid : myUid);

      await _matches.doc(pairId).set({
        'uids': meIsA ? [myUid, uid] : [uid, myUid],
        'aProfile': aProfile,
        'bProfile': bProfile,
        'commonFiveStarsCount': commonFive.length,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'source': 'auto:fiveOnly',
      }, SetOptions(merge: true));

      touched++;
    }
    return touched;
  }

  /* ---------------------------------------------------------------------- */
  /* 5) MATCHES STREAM                                                      */
  /* ---------------------------------------------------------------------- */
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