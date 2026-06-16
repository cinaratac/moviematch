import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer';

class CatalogService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Film verisi cache'i (docId → data)
  static final Map<String, Map<String, dynamic>> _filmCache = {};
  static final Set<String> _missingFilmKeys = {};

  // upsertFromTmdb için cache: tmdbId → catalogDocId
  // Film ekleme butonu defalarca basılsa bile Firestore'a sadece 1 kez gidilir.
  static final Map<int, String> _upsertCache = {};

  // upsertFromTmdb için devam eden işlemler: tmdbId → Future
  // Aynı film için eş zamanlı 2 çağrı yapılırsa ikincisi bekler, tekrar sorgu atmaz.
  static final Map<int, Future<String?>> _upsertInFlight = {};

  static String canonicalKeyFromTmdb(int tmdbId) => 'tmdb:$tmdbId';

  static String _slugify(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'[\s_]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  static String _normTitle(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
  }

  Future<String?> upsertFromTmdb(Map<String, dynamic> movie) async {
    final int? tmdbId = movie['id'] is int
        ? movie['id']
        : int.tryParse('${movie['id'] ?? ''}');
    if (tmdbId == null) return null;

    // 1. Bellekte varsa anında dön — Firestore'a gitme
    if (_upsertCache.containsKey(tmdbId)) {
      return _upsertCache[tmdbId];
    }

    // 2. Aynı film için zaten devam eden bir işlem varsa ona katıl
    if (_upsertInFlight.containsKey(tmdbId)) {
      return _upsertInFlight[tmdbId];
    }

    // 3. Yoksa gerçek işlemi başlat ve kaydet
    final future = _doUpsert(movie, tmdbId);
    _upsertInFlight[tmdbId] = future;

    try {
      final result = await future;
      if (result != null) _upsertCache[tmdbId] = result;
      return result;
    } finally {
      _upsertInFlight.remove(tmdbId);
    }
  }

  Future<String?> _doUpsert(Map<String, dynamic> movie, int tmdbId) async {
    try {
      final String? imdbId = movie['imdb_id'];
      final String? title = movie['title'];
      final String? posterPath = movie['poster_path'];
      final String? releaseDate = movie['release_date'];
      final int? year = releaseDate != null && releaseDate.length >= 4
          ? int.tryParse(releaseDate.substring(0, 4))
          : null;
      final String? posterUrl =
          posterPath != null ? 'https://image.tmdb.org/t/p/w500$posterPath' : null;
      final String? titleLc = title != null ? _normTitle(title) : null;

      String? primaryId;
      DocumentSnapshot? foundDoc;

      // a) tmdbId ile ara
      final q1 = await _db
          .collection('catalog_films')
          .where('tmdbId', isEqualTo: tmdbId)
          .limit(1)
          .get();
      if (q1.docs.isNotEmpty) foundDoc = q1.docs.first;

      // b) imdbId ile ara (sadece bulunamadıysa)
      if (foundDoc == null && imdbId != null) {
        final q2 = await _db
            .collection('catalog_films')
            .where('imdbId', isEqualTo: imdbId)
            .limit(1)
            .get();
        if (q2.docs.isNotEmpty) foundDoc = q2.docs.first;
      }

      // c) titleLc + year ile ara (sadece bulunamadıysa)
      if (foundDoc == null && titleLc != null && year != null) {
        final q3 = await _db
            .collection('catalog_films')
            .where('titleLc', isEqualTo: titleLc)
            .where('year', isEqualTo: year)
            .limit(1)
            .get();
        if (q3.docs.isNotEmpty) foundDoc = q3.docs.first;
      }

      if (foundDoc != null) {
        primaryId = foundDoc.id;
        // Zaten var — cache'e al ve sadece gerekli alanları güncelle
        _filmCache[primaryId] = {
          ...Map<String, dynamic>.from(foundDoc.data() as Map),
          'docId': primaryId,
        };

        // Sadece eksik alanlar varsa yaz (tmdbId yoksa ekle)
        final existingData = foundDoc.data() as Map<String, dynamic>;
        if (existingData['tmdbId'] == null || existingData['posterUrl'] == null) {
          _db.collection('catalog_films').doc(primaryId).set({
            'tmdbId': tmdbId,
            if (posterUrl != null) 'posterUrl': posterUrl,
            'aliases': FieldValue.arrayUnion(['tmdb:$tmdbId']),
          }, SetOptions(merge: true));
        }

        return primaryId;
      }

      // Bulunamadı — yeni doc oluştur
      if (title != null) {
        String slug = _slugify(title);
        String candidateId = 'film:$slug';
        final docSnap = await _db.collection('catalog_films').doc(candidateId).get();
        if (docSnap.exists) {
          final data = docSnap.data();
          bool conflict = false;
          if (data != null) {
            if ((data['tmdbId'] != null && data['tmdbId'] != tmdbId) ||
                (imdbId != null && data['imdbId'] != null && data['imdbId'] != imdbId) ||
                (year != null && data['year'] != null && data['year'] != year)) {
              conflict = true;
            }
          }
          if (conflict && year != null && year > 0) {
            candidateId = 'film:$slug-$year';
          }
        }
        primaryId = candidateId;
      } else {
        primaryId = canonicalKeyFromTmdb(tmdbId);
      }

      final Map<String, dynamic> data = {
        if (title != null) 'title': title,
        if (year != null) 'year': year,
        if (posterUrl != null) 'posterUrl': posterUrl,
        'tmdbId': tmdbId,
        if (imdbId != null) 'imdbId': imdbId,
        if (titleLc != null) 'titleLc': titleLc,
        'canonicalKey': primaryId,
        'source': 'tmdb',
        'aliases': FieldValue.arrayUnion([
          'tmdb:$tmdbId',
          if (imdbId != null) 'imdb:$imdbId',
        ]),
      };

      await _db.collection('catalog_films').doc(primaryId).set(data, SetOptions(merge: true));

      // Yeni oluşturulan dokümanı da cache'e al
      _filmCache[primaryId!] = {...data, 'docId': primaryId};

      return primaryId;
    } catch (e, st) {
      log('Error in upsertFromTmdb: $e', stackTrace: st);
      return null;
    }
  }

  Future<void> upsertFromLetterboxd(
    Map<String, dynamic> lbFilm, {
    int? tmdbId,
  }) async {
    try {
      String? primaryId;
      String? lbSlug = lbFilm['lbSlug'];
      String? title = lbFilm['title'];
      int? year = lbFilm['year'];
      String? imdbId = lbFilm['imdbId'];
      String? posterUrl = lbFilm['posterUrl'];
      String? titleLc = title != null ? _normTitle(title) : null;

      if (lbSlug != null && lbSlug.toString().isNotEmpty) {
        primaryId = 'film:$lbSlug';
      } else if (title != null) {
        primaryId = 'film:${_slugify(title)}';
      } else {
        log('Cannot upsert Letterboxd film without slug or title');
        return;
      }

      final aliases = <String>[
        if (tmdbId != null) 'tmdb:$tmdbId',
        if (imdbId != null) 'imdb:$imdbId',
      ];

      final data = <String, dynamic>{
        if (tmdbId != null) 'tmdbId': tmdbId,
        if (imdbId != null) 'imdbId': imdbId,
        if (title != null) 'title': title,
        if (year != null) 'year': year,
        if (posterUrl != null) 'posterUrl': posterUrl,
        if (titleLc != null) 'titleLc': titleLc,
        'canonicalKey': primaryId,
        'source': 'letterboxd',
        'aliases': FieldValue.arrayUnion(aliases),
      };

      await _db.collection('catalog_films').doc(primaryId).set(data, SetOptions(merge: true));
    } catch (e, st) {
      log('Error in upsertFromLetterboxd: $e', stackTrace: st);
    }
  }

  Future<Map<String, dynamic>?> getFilmByCanonical(String canonicalKey) async {
    if (_filmCache.containsKey(canonicalKey)) return _filmCache[canonicalKey];
    try {
      final doc = await _db.collection('catalog_films').doc(canonicalKey).get();
      if (doc.exists) {
        final data = {...doc.data()!, 'docId': doc.id};
        _filmCache[canonicalKey] = data;
        return data;
      }
      return null;
    } catch (e, st) {
      log('Error in getFilmByCanonical: $e', stackTrace: st);
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getFilmsByKeys(List<String> keys) async {
    final orderedKeys = keys.map((k) => k.trim()).where((k) => k.isNotEmpty).toList();
    if (orderedKeys.isEmpty) return [];

    final keysToLoad = <String>[];
    for (final key in orderedKeys.toSet()) {
      if (!_filmCache.containsKey(key) && !_missingFilmKeys.contains(key)) {
        keysToLoad.add(key);
      }
    }

    if (keysToLoad.isNotEmpty) {
      await _loadFilmChunks(keysToLoad, Source.cache);
      final stillMissing = keysToLoad
          .where((k) => !_filmCache.containsKey(k) && !_missingFilmKeys.contains(k))
          .toList();
      if (stillMissing.isNotEmpty) {
        await _loadFilmChunks(stillMissing, Source.server);
      }
    }

    return [
      for (final key in orderedKeys)
        if (_filmCache[key] != null) Map<String, dynamic>.from(_filmCache[key]!),
    ];
  }

  Future<void> _loadFilmChunks(List<String> keys, Source source) async {
    const batchSize = 10;
    final futures = <Future<void>>[];
    for (var i = 0; i < keys.length; i += batchSize) {
      final chunk = keys.sublist(i, (i + batchSize).clamp(0, keys.length));
      futures.add(_loadFilmChunk(chunk, source));
    }
    await Future.wait(futures);
  }

  Future<void> _loadFilmChunk(List<String> chunk, Source source) async {
    if (chunk.isEmpty) return;
    try {
      final snapshot = await _db
          .collection('catalog_films')
          .where(FieldPath.documentId, whereIn: chunk)
          .get(GetOptions(source: source));

      final foundIds = <String>{};
      for (final doc in snapshot.docs) {
        foundIds.add(doc.id);
        final data = Map<String, dynamic>.from(doc.data());
        data['docId'] = doc.id;
        data['canonicalKey'] ??= doc.id;
        _filmCache[doc.id] = data;
      }

      if (source == Source.server) {
        for (final key in chunk) {
          if (!foundIds.contains(key)) _missingFilmKeys.add(key);
        }
      }
    } catch (e, st) {
      if (source == Source.server) {
        log('Error in getFilmsByKeys chunk: $e', stackTrace: st);
      }
    }
  }

  /// Cache'i temizle (test veya logout için)
  static void clearCache() {
    _filmCache.clear();
    _missingFilmKeys.clear();
    _upsertCache.clear();
  }
}