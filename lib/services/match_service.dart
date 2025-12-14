import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart'; // YENİ EKLENDİ
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
  static const Duration _findCacheTtl = Duration(minutes: 5);

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
  // MERKEZİ HESAPLAMA MOTORU
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

    // Hiçbir ortak nokta yoksa null dön
    if (common5.isEmpty && commonF.isEmpty && commonW.isEmpty &&
        commonD.isEmpty && commonG.isEmpty && commonDir.isEmpty && commonAct.isEmpty) {
      return null;
    }

    // 3. PUANLAMA ALGORİTMASI
    double calcPart(int count, double weight, double k) {
      if (count <= 0) return 0.0;
      return weight * (count / (count + k));
    }

    const w5 = 30.0;     
    const wFav = 40.0;   
    const wWatch = 10.0; 
    const wG = 5.0;      
    const wDir = 10.0;   
    const wAct = 5.0;    

    final score5 = calcPart(common5.length, w5, 2.0);      
    final scoreFav = calcPart(commonF.length, wFav, 1.0);
    final scoreWatch = calcPart(commonW.length, wWatch, 3.0); 
    
    final scoreG = calcPart(commonG.length, wG, 1.0);
    final scoreDir = calcPart(commonDir.length, wDir, 1.0);
    final scoreAct = calcPart(commonAct.length, wAct, 1.0);

    double totalScore = score5 + scoreFav + scoreWatch + scoreG + scoreDir + scoreAct;

    if (commonD.isNotEmpty) totalScore += 3.0;

    if (totalScore > 0) {
      totalScore += 15.0; 
      totalScore = math.sqrt(totalScore) * 10.0;
    }

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
      displayName: (theirData['displayName'] ?? '').toString(),
      letterboxdUsername: (theirData['letterboxdUsername'] ?? '').toString(),
      photoURL: (theirData['photoURL'] ?? '').toString(),
    );
  }

  /* ---------------------------------------------------------------------- */
  /* 1) EŞLEŞME LİSTESİ HESAPLA (findMatches) - HİBRİT VERSİYON             */
  /* Cloud Function'ı dener, hata verirse yerel sorguya düşer.           */
  /* ---------------------------------------------------------------------- */
  Future<List<MatchResult>> findMatches(String myUid, {int candidateLimit = 100}) async {
    // 1. Cache Kontrolü
    final now = DateTime.now();
    final cached = _findCache[myUid];
    if (cached != null && now.difference(cached.ts) < _findCacheTtl) {
      if (cached.results.isNotEmpty) return cached.results;
    }

    // 2. Kendi verini çek
    final meDoc = await _users.doc(myUid).get();
    if (!meDoc.exists) return [];
    final myData = meDoc.data() ?? {};

    // 3. Etkileşime geçilenleri filtrele
    final hiddenUids = <String>{myUid};
    try {
      final likesQs = await _likes.where('uids', arrayContains: myUid).get();
      for (final doc in likesQs.docs) {
        final m = doc.data();
        final a = m['a'] as String?;
        final b = m['b'] as String?;
        if (a == null || b == null) continue;
        final meIsA = (myUid == a);
        final myLiked = (m[meIsA ? 'aLiked' : 'bLiked'] == true);
        final myPass = (m[meIsA ? 'aPass' : 'bPass'] == true);
        final otherLiked = (m[meIsA ? 'bLiked' : 'aLiked'] == true);
        
        if (myLiked || myPass || (myLiked && otherLiked)) {
          hiddenUids.add(meIsA ? b : a);
        }
      }
    } catch (_) {}

    List<MatchResult> out = [];
    bool cloudFailed = false;

    // --- YÖNTEM A: CLOUD FUNCTION DENEMESİ ---
    try {
      print("🔍 Cloud Function ile eşleşme aranıyor...");
      final callable = FirebaseFunctions.instance.httpsCallable('findMatchesCallable');
      final resp = await callable.call();
      
      final rawList = resp.data['results'] as List<dynamic>;
      
      for (final item in rawList) {
        final map = Map<String, dynamic>.from(item as Map);
        final uid = map['uid'] as String;

        if (hiddenUids.contains(uid)) continue;

        final result = _computeMatch(myUid, uid, myData, map);
        if (result != null) {
          out.add(result);
        }
      }

      // Eğer Cloud sonuç döndürdüyse işlem tamam
      if (out.isNotEmpty) {
        out.sort((a, b) => b.score.compareTo(a.score));
        _findCache[myUid] = _FindCache(out, DateTime.now());
        print("✅ Cloud Function ${out.length} eşleşme buldu.");
        return out;
      } else {
         print("⚠️ Cloud Function boş döndü, yerel sorguya geçiliyor.");
         cloudFailed = true;
      }

    } catch (e) {
      print("❌ Cloud Function hatası: $e");
      print("⚠️ Yerel sorguya (eski yönteme) geçiliyor...");
      cloudFailed = true;
    }

    // --- YÖNTEM B: YEREL SORGU (FALLBACK / YEDEK PLAN) ---
    // Eğer Cloud hata verdiyse veya sonuç bulamadıysa burası çalışır.
    if (cloudFailed || out.isEmpty) {
      DocumentSnapshot? lastDoc;
      bool keepFetching = true;
      int fetchCycles = 0;
      const int maxCycles = 10; 

      while (keepFetching && out.length < candidateLimit && fetchCycles < maxCycles) {
        fetchCycles++;
        Query query = _users.orderBy(FieldPath.documentId).limit(50);
        
        if (lastDoc != null) {
          query = query.startAfterDocument(lastDoc);
        }

        final snapshot = await query.get();

        if (snapshot.docs.isEmpty) {
          keepFetching = false;
          break;
        }

        lastDoc = snapshot.docs.last;

        for (final d in snapshot.docs) {
          final uid = d.id;
          if (hiddenUids.contains(uid)) continue;

          final result = _computeMatch(myUid, uid, myData, d.data() as Map<String, dynamic>);
          if (result != null) {
            out.add(result);
          }
        }
      }
      
      // Sırala
      out.sort((a, b) {
        final s = b.score.compareTo(a.score);
        if (s != 0) return s;
        return b.commonFiveCount.compareTo(a.commonFiveCount);
      });
    }

    // Cache'i güncelle
    _findCache[myUid] = _FindCache(out, DateTime.now());
    return out;
  }

  /* ---------------------------------------------------------------------- */
  /* 2) TEKİL KULLANICI UYUMU HESAPLA                                       */
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