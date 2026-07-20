import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class PosterFallbackService {
  PosterFallbackService._();
  static final PosterFallbackService instance = PosterFallbackService._();

  // RAM Önbelleği
  final Map<String, String> _resolvedCache = {};

  // URL format kontrolü
  bool _looksValid(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final u = url.trim();
    if (!(u.startsWith('http://') || u.startsWith('https://'))) return false;
    if (u.contains('empty-poster') || u.contains('null')) return false; 
    if (u.contains('ltrbxd.com')) return false; 
    return true;
  }

  // Ana Fonksiyon
  Future<String?> resolvePosterUrl({
    String? existing,
    int? tmdbId,
    String? imdbId, 
    String? title,
    int? year,
    bool writeBackToCatalog = true,
    bool ignoreExisting = false,
  }) async {
    
    // CACHE KONTROLÜ
    final cacheKey = tmdbId?.toString() ?? title?.toLowerCase().trim() ?? existing ?? '';
    if (cacheKey.isNotEmpty && _resolvedCache.containsKey(cacheKey)) {
      return _resolvedCache[cacheKey];
    }

    // HTTP isteği yapmadan sadece geçerli mi diye bakıyoruz. Ağı boğmasını engeller.
    if (!ignoreExisting && _looksValid(existing)) {
      if (cacheKey.isNotEmpty) _resolvedCache[cacheKey] = existing!;
      return existing; 
    }

    String? found;

    if (tmdbId != null && tmdbId > 0) {
      found = await _byTmdbId(tmdbId);
    }
    
    if (found == null && imdbId != null && imdbId.isNotEmpty) {
      found = await _byImdbId(imdbId);
    }

    if (found == null && (title != null && title.trim().isNotEmpty)) {
      found = await _bySearch(title: title.trim(), year: year);
    }

    if (writeBackToCatalog && found != null && found != existing) {
      _updateCatalog(found, tmdbId, imdbId, title, year);
    }

    if (found != null && cacheKey.isNotEmpty) {
       _resolvedCache[cacheKey] = found;
    }

    return found;
  }

  Future<void> _updateCatalog(String newUrl, int? tmdbId, String? imdbId, String? title, int? year) async {
     try {
        final db = FirebaseFirestore.instance;
        QuerySnapshot? q;

        if (tmdbId != null && tmdbId > 0) {
          q = await db.collection('catalog_films').where('tmdbId', isEqualTo: tmdbId).limit(1).get();
        } else if (title != null) {
           q = await db.collection('catalog_films')
              .where('titleLc', isEqualTo: title.toLowerCase())
              .where('year', isEqualTo: year).limit(1).get();
        }

        if (q != null && q.docs.isNotEmpty) {
          await q.docs.first.reference.set({'posterUrl': newUrl}, SetOptions(merge: true));
        }
      } catch (e) {}
  }

  // --- CLOUD FUNCTIONS KISMI (w200 olarak optimize edildi) ---

  Future<String?> _byTmdbId(int tmdbId) async {
    try {
      final result = await FirebaseFunctions.instance.httpsCallable('callTMDB').call({
        'endpoint': '/3/movie/$tmdbId',
        'params': {'language': 'tr-TR'}
      });
      final map = Map<String, dynamic>.from(result.data as Map);
      final p = (map['poster_path'] ?? '') as String;
      
      if (p.isEmpty) return null;
      return 'https://image.tmdb.org/t/p/w200$p';
    } catch (e) {
      return null;
    }
  }

  Future<String?> _byImdbId(String imdbId) async {
    try {
      final result = await FirebaseFunctions.instance.httpsCallable('callTMDB').call({
        'endpoint': '/3/find/$imdbId',
        'params': {
          'external_source': 'imdb_id',
          'language': 'en-US',
        }
      });
      final map = Map<String, dynamic>.from(result.data as Map);
      final List results = (map['movie_results'] ?? []) as List;
      if (results.isEmpty) return null;
      
      final first = Map<String, dynamic>.from(results.first as Map);
      final p = (first['poster_path'] ?? '') as String;
      if (p.isEmpty) return null;
      
      return 'https://image.tmdb.org/t/p/w200$p';
    } catch (e) {
      return null;
    }
  }

  Future<String?> _bySearch({required String title, int? year}) async {
    try {
      final params = <String, dynamic>{
        'query': title,
        'include_adult': 'false',
        'language': 'en-US',
        'page': '1',
      };
      if (year != null && year > 0) {
        params['primary_release_year'] = year.toString();
      }
      
      final result = await FirebaseFunctions.instance.httpsCallable('callTMDB').call({
        'endpoint': '/3/search/movie',
        'params': params
      });
      
      final map = Map<String, dynamic>.from(result.data as Map);
      final List results = (map['results'] ?? []) as List;
      if (results.isEmpty) return null;
      
      final first = Map<String, dynamic>.from(results.first as Map);
      final p = (first['poster_path'] ?? '') as String;
      if (p.isEmpty) return null;
      
      return 'https://image.tmdb.org/t/p/w200$p';
    } catch (e) {
      return null;
    }
  }
}