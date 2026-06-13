import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class PosterFallbackService {
  PosterFallbackService._();
  static final PosterFallbackService instance = PosterFallbackService._();

  // --- 1. EKLENEN KISIM: RAM ÖNBELLEĞİ ---
  // Çözümlenen URL'leri hafızada tutarak aynı filmi tekrar aratmayı engeller
  final Map<String, String> _resolvedCache = {};

  // URL format kontrolü
  bool _looksValid(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final u = url.trim();
    if (!(u.startsWith('http://') || u.startsWith('https://'))) return false;
    if (u.contains('empty-poster') || u.contains('null')) return false; 
    
    // --- 2. EKLENEN KISIM: Letterboxd linklerini baştan reddet ---
    // Böylece vakit kaybetmeden direkt TMDB aramasına geçer
    if (u.contains('ltrbxd.com')) return false; 

    return true;
  }

  // URL erişilebilirlik kontrolü
  Future<bool> _isReachable(String url) async {
    try {
      final uri = Uri.parse(url);
      final headers = {
        'Accept': 'image/*',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
      };
      final head = await http
          .head(uri, headers: headers)
          .timeout(const Duration(seconds: 3));
      
      if (head.headers['content-type'] != null && 
          !head.headers['content-type']!.contains('image')) {
        return false;
      }

      if (head.statusCode == 200) return true;
      
      if (head.statusCode == 403 || head.statusCode == 404 || head.statusCode == 405) {
        final get = await http
            .get(uri, headers: headers) 
            .timeout(const Duration(seconds: 4));
            
        if (get.headers['content-type'] != null && 
            !get.headers['content-type']!.contains('image')) {
          return false;
        }
        return get.statusCode >= 200 && get.statusCode < 300;
      }
      return false;
    } catch (_) {
      return false;
    }
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
    
    // --- 3. EKLENEN KISIM: CACHE KONTROLÜ ---
    final cacheKey = tmdbId?.toString() ?? title?.toLowerCase().trim() ?? existing ?? '';
    if (cacheKey.isNotEmpty && _resolvedCache.containsKey(cacheKey)) {
      return _resolvedCache[cacheKey]; // İnternete hiç gitmeden saniyesinde hafızadan döndür
    }

    // 1. Mevcut URL kontrolü
    if (!ignoreExisting && _looksValid(existing)) {
      final works = await _isReachable(existing!.trim());
      if (works) {
        if (cacheKey.isNotEmpty) _resolvedCache[cacheKey] = existing;
        return existing; 
      }
    }

    String? found;

    // 2. TMDB ID ile çağır
    if (tmdbId != null && tmdbId > 0) {
      found = await _byTmdbId(tmdbId);
    }
    
    // 3. IMDb ID ile çağır
    if (found == null && imdbId != null && imdbId.isNotEmpty) {
      found = await _byImdbId(imdbId);
    }

    // 4. İsim ve Yıl ile çağır
    if (found == null && (title != null && title.trim().isNotEmpty)) {
      found = await _bySearch(title: title.trim(), year: year);
    }

    // 5. Kataloğu güncelle
    if (writeBackToCatalog && found != null && found != existing) {
      _updateCatalog(found, tmdbId, imdbId, title, year);
    }

    // BULUNAN TEMİZ LİNKİ HAFIZAYA KAYDET
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

  // --- CLOUD FUNCTIONS ---

  Future<String?> _byTmdbId(int tmdbId) async {
    try {
      final result = await FirebaseFunctions.instance.httpsCallable('callTMDB').call({
        'endpoint': '/3/movie/$tmdbId',
        'params': {'language': 'tr-TR'}
      });
      final map = Map<String, dynamic>.from(result.data as Map);
      final p = (map['poster_path'] ?? '') as String;
      
      if (p.isEmpty) return null;
      return 'https://image.tmdb.org/t/p/w500$p';
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
      
      return 'https://image.tmdb.org/t/p/w500$p';
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
      
      return 'https://image.tmdb.org/t/p/w500$p';
    } catch (e) {
      return null;
    }
  }
}