import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluttergirdi/services/blocking_service.dart';

class _FindCache {
  final List<MatchResult> results;
  final DateTime ts;
  const _FindCache(this.results, this.ts);
}

class _SeenMatch {
  final int count;
  final DateTime? lastSeenAt;

  const _SeenMatch({required this.count, required this.lastSeenAt});

  factory _SeenMatch.fromJson(Map<String, dynamic> json) {
    return _SeenMatch(
      count: (json['count'] as num?)?.toInt() ?? 1,
      lastSeenAt: DateTime.tryParse((json['lastSeenAt'] ?? '').toString()),
    );
  }

  Map<String, dynamic> toJson() => {
    'count': count,
    if (lastSeenAt != null) 'lastSeenAt': lastSeenAt!.toIso8601String(),
  };
}

class MatchResult {
  final String uid;
  final double score; // UI'da gösterilen SAF uyumluluk yüzdesi (Asla düşmez)
  final double
  sortScore; // Arka planda sıralama yapmak için kullanılan görünmez puan

  final List<String> commonFiveStars;
  final List<String> commonFavorites;
  final List<String> commonWatchlist;
  final List<String> commonDisliked;

  final List<String> commonGenres;
  final List<String> commonDirectors;
  final List<String> commonActors;

  final String? displayName;
  final String? letterboxdUsername;
  final String? username;
  final String? photoURL;

  MatchResult({
    required this.uid,
    this.username,
    required this.score,
    required this.sortScore,
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

  // HATA VEREN YERLER BURAYDI (GERİ EKLENDİ)
  int get commonFiveCount => commonFiveStars.length;
  int get commonFavCount => commonFavorites.length;
  int get commonWatchCount => commonWatchlist.length;
  int get commonDisCount => commonDisliked.length;
  int get commonGenreCount => commonGenres.length;
  int get commonDirectorCount => commonDirectors.length;
  int get commonActorCount => commonActors.length;
}

class MatchService {
  MatchService._();
  static final MatchService instance = MatchService._();

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _matches =>
      _db.collection('matches');

  final Map<String, _FindCache> _findCache = {};
  static const Duration _findCacheTtl = Duration(minutes: 5);
  static const int _maxSeenMatches = 500;
  static const Duration _seenCountCooldown = Duration(hours: 6);

  void clearCache() => _findCache.clear();

  String _seenMetaKey(String uid) => 'match_seen_meta_$uid';
  String _legacySeenKey(String uid) => 'seen_uids_$uid';

  Future<Map<String, _SeenMatch>> _loadSeenMatches(String myUid) async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, _SeenMatch>{};

    final raw = prefs.getString(_seenMetaKey(myUid));
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          if (entry.value is Map) {
            out[entry.key] = _SeenMatch.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
            );
          }
        }
      } catch (_) {}
    }

    final legacySeen = prefs.getStringList(_legacySeenKey(myUid)) ?? const [];
    for (final uid in legacySeen) {
      out.putIfAbsent(uid, () => const _SeenMatch(count: 1, lastSeenAt: null));
    }

    return out;
  }

  Future<void> _saveSeenMatches(
    String myUid,
    Map<String, _SeenMatch> seen,
  ) async {
    final entries = seen.entries.toList()
      ..sort((a, b) {
        final ad = a.value.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = b.value.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });

    final limited = Map<String, _SeenMatch>.fromEntries(
      entries.take(_maxSeenMatches),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _seenMetaKey(myUid),
      jsonEncode(limited.map((key, value) => MapEntry(key, value.toJson()))),
    );
    await prefs.setStringList(_legacySeenKey(myUid), limited.keys.toList());
  }

  Future<void> markAsSeen(String myUid, String targetUid) async {
    if (myUid.isEmpty || targetUid.isEmpty || myUid == targetUid) return;

    final now = DateTime.now();
    final seen = await _loadSeenMatches(myUid);
    final previous = seen[targetUid];
    final shouldIncrement =
        previous == null ||
        previous.lastSeenAt == null ||
        now.difference(previous.lastSeenAt!) > _seenCountCooldown;

    seen[targetUid] = _SeenMatch(
      count: (previous?.count ?? 0) + (shouldIncrement ? 1 : 0),
      lastSeenAt: now,
    );

    await _saveSeenMatches(myUid, seen);
    _findCache.remove(myUid);
  }

  double _seenPenalty(_SeenMatch? seen) {
    if (seen == null) return 0.0;

    final age = seen.lastSeenAt == null
        ? Duration.zero
        : DateTime.now().difference(seen.lastSeenAt!);

    double recencyPenalty;
    if (age < const Duration(hours: 6)) {
      recencyPenalty = 700.0;
    } else if (age < const Duration(days: 1)) {
      recencyPenalty = 550.0;
    } else if (age < const Duration(days: 3)) {
      recencyPenalty = 420.0;
    } else if (age < const Duration(days: 7)) {
      recencyPenalty = 280.0;
    } else if (age < const Duration(days: 21)) {
      recencyPenalty = 150.0;
    } else {
      recencyPenalty = 60.0;
    }

    final repeatPenalty = math.min(260.0, math.max(1, seen.count) * 55.0);
    return recencyPenalty + repeatPenalty;
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

  MatchResult _computeMatch(
    String myUid,
    String otherUid,
    Map<String, dynamic> myData,
    Map<String, dynamic> theirData,
    _SeenMatch? seen,
  ) {
    final myFive = _extractSet(myData, [
      'fiveStarKeys',
      'fiveIds',
      'fiveStars',
    ]);
    final myFavs = _extractSet(myData, [
      'favoritesKeys',
      'favIds',
      'favoriteFilmIds',
    ]);
    final myWatch = _extractSet(myData, [
      'watchlistKeys',
      'watchIds',
      'watchlistIds',
    ]);
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

    final common5 = myFive.intersection(theirFive).toList()..sort();
    final commonF = myFavs.intersection(theirFavs).toList()..sort();
    final commonW = myWatch.intersection(theirWatch).toList()..sort();
    final commonD = myDis.intersection(theirDis).toList()..sort();

    final commonG = myGenres.intersection(theirGenres).toList()..sort();
    final commonDir = myDirectors.intersection(theirDirectors).toList()..sort();
    final commonAct = myActors.intersection(theirActors).toList()..sort();

    double baseCompatibility = 0.0;

    baseCompatibility += commonF.length * 15.0;
    baseCompatibility += common5.length * 8.0;
    baseCompatibility += commonDir.length * 5.0;
    baseCompatibility += commonW.length * 3.0;
    baseCompatibility += commonG.length * 2.0;
    baseCompatibility += commonAct.length * 2.0;
    baseCompatibility += commonD.length * 2.0;

    if (baseCompatibility > 0) {
      baseCompatibility += 20.0;
    } else {
      baseCompatibility = 5.0;
    }

    final displayScore = math.min(100.0, baseCompatibility);
    double sortingScore = displayScore - _seenPenalty(seen);

    sortingScore += math.Random().nextDouble() * 18.0;

    return MatchResult(
      uid: otherUid,
      score: displayScore,
      sortScore: sortingScore,
      commonFiveStars: common5,
      username: (theirData['username'] ?? '').toString(),
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

  Future<List<MatchResult>> findMatches(
    String myUid, {
    int candidateLimit = 1000,
  }) async {
    final now = DateTime.now();
    final cached = _findCache[myUid];
    if (cached != null && now.difference(cached.ts) < _findCacheTtl) {
      if (cached.results.isNotEmpty) return cached.results;
    }

    final meDoc = await _users.doc(myUid).get();
    if (!meDoc.exists) return [];
    final myData = meDoc.data() ?? {};

    final hiddenUids = <String>{myUid};
    try {
      final followingSnap = await _users
          .doc(myUid)
          .collection('following')
          .get();
      for (final doc in followingSnap.docs) {
        hiddenUids.add(doc.id);
      }
    } catch (_) {}
    try {
      final blockedIds = await BlockingService.instance.getBlockedAndBlockerIds(
        myUid,
      );
      hiddenUids.addAll(blockedIds);
    } catch (_) {}

    final seenMatches = await _loadSeenMatches(myUid);

    List<MatchResult> out = [];

    // --- OPTİMİZASYON: PARALEL İŞLEM BAŞLANGICI ---
    // Cloud Function ve Firestore sorgularını aynı anda başlatıyoruz.
    // Böylece biri diğerini bekleyip (30 saniye vs.) sistemi kilitlemeyecek.

    // 1. İŞLEM: Cloud Function'ı arka planda başlat
    Future<List<MatchResult>> fetchFromCloudFunction() async {
      List<MatchResult> cloudResults = [];
      try {
        final callable = FirebaseFunctions.instance.httpsCallable(
          'findMatchesCallable',
        );
        final resp = await callable.call();
        final rawList = resp.data['results'] as List<dynamic>;

        for (final item in rawList) {
          final map = Map<String, dynamic>.from(item as Map);
          final uid = map['uid'] as String;

          if (hiddenUids.contains(uid)) continue;

          final result = _computeMatch(
            myUid,
            uid,
            myData,
            map,
            seenMatches[uid],
          );
          cloudResults.add(result);
        }
      } catch (e) {
        // Sessizce yut, normal akış devam etsin.
      }
      return cloudResults;
    }

    // 2. İŞLEM: Firestore'dan normal kullanıcıları çekme
    Future<List<MatchResult>> fetchFromFirestore() async {
      List<MatchResult> firestoreResults = [];
      DocumentSnapshot? lastDoc;
      bool keepFetching = true;
      int fetchCycles = 0;
      const int maxCycles = 10; // Daha hızlı dönmesi için limiti 10'a çektim

      while (keepFetching &&
          firestoreResults.length < candidateLimit &&
          fetchCycles < maxCycles) {
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
          final data = d.data() as Map<String, dynamic>;

          final username = data['username'] as String?;
          if (username == null || username.trim().isEmpty) continue;
          if (hiddenUids.contains(uid)) continue;

          final result = _computeMatch(
            myUid,
            uid,
            myData,
            data,
            seenMatches[uid],
          );
          firestoreResults.add(result);
        }
      }
      return firestoreResults;
    }

    // İki işlemi aynı anda (paralel) çalıştır ve hangisi önce biterse bitmesini bekle
    // Not: Cloud Function uzun sürse bile (Cold Start), Firestore hızlıca biteceği için
    // uygulama Firestore verileriyle anında devam edebilir (Eğer timeout eklersek).
    // Ancak burada iki işlemin de sonucunu sağlıklı birleştirmek için Future.wait kullanıyoruz.
    final results = await Future.wait([
      fetchFromCloudFunction(),
      fetchFromFirestore(),
    ]);

    // Sonuçları birleştir (Cloud Function'dan gelenler ve Firestore'dan gelenler)
    final cloudMatches = results[0];
    final dbMatches = results[1];

    // Tekilleştirme: Aynı kullanıcı her iki listede de varsa sadece birini al
    final Set<String> processedUids = {};

    for (var match in cloudMatches) {
      if (!processedUids.contains(match.uid)) {
        out.add(match);
        processedUids.add(match.uid);
      }
    }

    for (var match in dbMatches) {
      if (!processedUids.contains(match.uid)) {
        out.add(match);
        processedUids.add(match.uid);
      }
    }

    // --- AŞAMA 3: LİSTEYİ PUANA GÖRE SIRALA VE CACHE'E YAZ ---
    out.sort((a, b) {
      final s = b.sortScore.compareTo(a.sortScore);
      if (s != 0) return s;
      return b.commonFiveCount.compareTo(a.commonFiveCount);
    });

    _findCache[myUid] = _FindCache(out, DateTime.now());
    return out;
  }

  // YENİ: AŞAMALI YÜKLEME AKIŞI (STREAM)
  Stream<List<MatchResult>> findMatchesStream(
    String myUid, {
    int candidateLimit = 160,
  }) async* {
    final now = DateTime.now();
    final cached = _findCache[myUid];
    if (cached != null && now.difference(cached.ts) < _findCacheTtl) {
      if (cached.results.isNotEmpty) {
        yield cached.results;
        return;
      }
    }

    final meDoc = await _users.doc(myUid).get();
    if (!meDoc.exists) {
      yield [];
      return;
    }
    final myData = meDoc.data() ?? {};

    final hiddenUids = <String>{myUid};
    try {
      final followingSnap = await _users
          .doc(myUid)
          .collection('following')
          .get();
      for (final doc in followingSnap.docs) {
        hiddenUids.add(doc.id);
      }
    } catch (_) {}
    try {
      final blockedIds = await BlockingService.instance.getBlockedAndBlockerIds(
        myUid,
      );
      hiddenUids.addAll(blockedIds);
    } catch (_) {}

    final seenMatches = await _loadSeenMatches(myUid);

    List<MatchResult> out = [];
    final Set<String> processedUids = {};

    // Ekranda kaymayı engellemek için yeni gelenleri kendi içinde sıralayıp SONA ekliyoruz
    void appendResults(List<MatchResult> newItems) {
      for (var item in newItems) {
        if (!processedUids.contains(item.uid)) {
          out.add(item);
          processedUids.add(item.uid);
          hiddenUids.add(item.uid);
        }
      }
      out.sort((a, b) {
        final s = b.sortScore.compareTo(a.sortScore);
        if (s != 0) return s;
        return b.commonFiveCount.compareTo(a.commonFiveCount);
      });
    }

    // 1. CLOUD FUNCTION'I BEKLEMEDEN ARKA PLANDA BAŞLAT
    final cloudFuture = FirebaseFunctions.instance
        .httpsCallable('findMatchesCallable')
        .call()
        .then((resp) {
          final rawList = resp.data['results'] as List<dynamic>;
          List<MatchResult> cloudRes = [];
          for (final item in rawList) {
            final map = Map<String, dynamic>.from(item as Map);
            final uid = map['uid'] as String;
            if (hiddenUids.contains(uid)) continue;
            cloudRes.add(
              _computeMatch(myUid, uid, myData, map, seenMatches[uid]),
            );
          }
          return cloudRes;
        })
        .catchError((_) => <MatchResult>[]);

    // 2. VERİTABANINDAN 10'ARLI GRUPLAR HALİNDE KARTLARI ÇEK VE ANINDA GÖSTER
    DocumentSnapshot? lastDoc;
    bool keepFetching = true;
    int fetchCycles = 0;
    const int pageSize = 20;
    const int initialFetchCycles = 2;
    bool yieldedInitialBatch = false;
    const int maxCycles = 8; // Maksimum 160 kişi

    while (keepFetching &&
        out.length < candidateLimit &&
        fetchCycles < maxCycles) {
      fetchCycles++;
      // İLK 10 KİŞİ ÇEKİLDİĞİ AN EKRANA GİDER!
      Query query = _users.orderBy(FieldPath.documentId).limit(pageSize);

      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) {
        keepFetching = false;
        break;
      }
      lastDoc = snapshot.docs.last;

      List<MatchResult> chunkResults = [];
      for (final d in snapshot.docs) {
        final uid = d.id;
        final data = d.data() as Map<String, dynamic>;

        final username = data['username'] as String?;
        if (username == null || username.trim().isEmpty) continue;
        if (hiddenUids.contains(uid)) continue;

        chunkResults.add(
          _computeMatch(myUid, uid, myData, data, seenMatches[uid]),
        );
      }

      appendResults(chunkResults);

      // İlk 10 veri geldiği an (ve her yeni pakette) arayüzü güncelle
      final initialBatchReady =
          fetchCycles >= initialFetchCycles || !keepFetching;
      if (out.isNotEmpty && (yieldedInitialBatch || initialBatchReady)) {
        yieldedInitialBatch = true;
        yield List.from(out);
      }
    }

    // 3. EN SON CLOUD FUNCTION BİTİNCE ONLARI DA DESTENİN ALTINA GİZLİCE EKLE
    final cloudMatches = await cloudFuture;
    if (cloudMatches.isNotEmpty) {
      appendResults(cloudMatches);
      yield List.from(out);
    }

    _findCache[myUid] = _FindCache(out, DateTime.now());
  }

  // PUBLIC PROFILE EKRANININ HATA VERDİĞİ YER (GERİ EKLENDİ)
  Future<int> calculateMatchScore(String myUid, String otherUid) async {
    try {
      final meDoc = await _users.doc(myUid).get();
      final otherDoc = await _users.doc(otherUid).get();

      if (!meDoc.exists || !otherDoc.exists) return 0;

      // Sadece hesaplama yaptığı için "isSeen" değerini false geçiyoruz
      final result = _computeMatch(
        myUid,
        otherUid,
        meDoc.data()!,
        otherDoc.data()!,
        null,
      );
      return result.score.round();
    } catch (e) {
      return 0;
    }
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> matchesStream(
    String uid,
  ) {
    // YENİ: Artık users altından değil, ana ROOT matches havuzundan çekiyoruz
    return _matches
        .where('users', arrayContains: uid)
        .orderBy('matchedAt', descending: true)
        .limit(50)
        .snapshots()
        .map((qs) => qs.docs);
  }
}
