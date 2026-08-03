import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:developer';

class CatalogService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

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

  Future<String?> upsertFromTmdb(
    Map<String, dynamic> movie, {
    String? catalogKey,
  }) async {
    final int? tmdbId = movie['id'] is int
        ? movie['id']
        : int.tryParse('${movie['id'] ?? ''}');
    if (tmdbId == null) return null;

    // Belirli bir eski katalog kaydı zenginleştiriliyorsa genel TMDB cache'i
    // o kaydın sunucuda eşleştirilmesini atlamamalı.
    if (catalogKey != null && catalogKey.trim().isNotEmpty) {
      return _doUpsert(movie, tmdbId, catalogKey: catalogKey);
    }

    // 1. Bellekte varsa anında dön — Firestore'a gitme
    if (_upsertCache.containsKey(tmdbId)) {
      return _upsertCache[tmdbId];
    }

    // 2. Aynı film için zaten devam eden bir işlem varsa ona katıl
    if (_upsertInFlight.containsKey(tmdbId)) {
      return _upsertInFlight[tmdbId];
    }

    // 3. Yoksa gerçek işlemi başlat ve kaydet
    final future = _doUpsert(movie, tmdbId, catalogKey: catalogKey);
    _upsertInFlight[tmdbId] = future;

    try {
      final result = await future;
      if (result != null) _upsertCache[tmdbId] = result;
      return result;
    } finally {
      _upsertInFlight.remove(tmdbId);
    }
  }

  Future<String?> _doUpsert(
    Map<String, dynamic> movie,
    int tmdbId, {
    String? catalogKey,
  }) async {
    try {
      final title = (movie['title'] ?? movie['original_title'])?.toString();
      final releaseDate = movie['release_date']?.toString();
      final year = releaseDate != null && releaseDate.length >= 4
          ? int.tryParse(releaseDate.substring(0, 4))
          : null;
      final result = await resolveAndUpsert(
        tmdbId: tmdbId,
        title: title,
        year: year,
        catalogKey: catalogKey,
      );
      return result?['docId']?.toString();
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
      final title = lbFilm['title']?.toString().trim() ?? '';
      final rawKey = lbFilm['key'] ?? lbFilm['lbSlug'];
      final key = rawKey == null
          ? ''
          : rawKey.toString().startsWith('film:')
          ? rawKey.toString()
          : 'film:${rawKey.toString()}';
      if (title.isEmpty || key == 'film:') return;
      if (tmdbId != null && tmdbId > 0) {
        await resolveAndUpsert(
          tmdbId: tmdbId,
          title: title,
          year: _coercePositiveInt(lbFilm['year']),
          catalogKey: key,
        );
      } else {
        await importLetterboxdFilms([
          {...lbFilm, 'key': key, 'title': title},
        ]);
      }
    } catch (e, st) {
      log('Error in upsertFromLetterboxd: $e', stackTrace: st);
    }
  }

  Future<Map<String, dynamic>?> resolveAndUpsert({
    int? tmdbId,
    String? title,
    int? year,
    String? catalogKey,
  }) async {
    final callable = _functions.httpsCallable('resolveCatalogMovie');
    final response = await callable.call({
      if (tmdbId != null && tmdbId > 0) 'tmdbId': tmdbId,
      if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      if (year != null && year > 0) 'year': year,
      if (catalogKey != null && catalogKey.trim().isNotEmpty)
        'catalogKey': catalogKey.trim(),
    });
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['ok'] != true) return null;
    final docId = data['docId']?.toString();
    if (docId != null && docId.isNotEmpty) {
      _filmCache[docId] = {...data, 'docId': docId};
      final resolvedTmdbId = _coercePositiveInt(data['tmdbId']);
      if (resolvedTmdbId != null) _upsertCache[resolvedTmdbId] = docId;
    }
    return data;
  }

  Future<void> importLetterboxdFilms(List<Map<String, dynamic>> films) async {
    if (films.isEmpty) return;
    const batchSize = 50;
    for (var i = 0; i < films.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, films.length);
      final chunk = films.sublist(i, end).map((film) {
        return {
          'key': film['key']?.toString() ?? '',
          'title': film['title']?.toString() ?? '',
          if (_coercePositiveInt(film['year']) != null)
            'year': _coercePositiveInt(film['year']),
        };
      }).toList();
      await _functions.httpsCallable('importLetterboxdCatalog').call({
        'films': chunk,
      });
    }
  }

  static int? _coercePositiveInt(dynamic value) {
    if (value is int && value > 0) return value;
    if (value is num && value > 0) return value.toInt();
    final parsed = int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed > 0 ? parsed : null;
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
    final orderedKeys = keys
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .toList();
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
          .where(
            (k) => !_filmCache.containsKey(k) && !_missingFilmKeys.contains(k),
          )
          .toList();
      if (stillMissing.isNotEmpty) {
        await _loadFilmChunks(stillMissing, Source.server);
      }
    }

    return [
      for (final key in orderedKeys)
        if (_filmCache[key] != null)
          Map<String, dynamic>.from(_filmCache[key]!),
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
