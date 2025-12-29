import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class PosterFallbackService {
  PosterFallbackService._();
  static final PosterFallbackService instance = PosterFallbackService._();

  // URL format kontrolü
  bool _looksValid(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final u = url.trim();
    if (!(u.startsWith('http://') || u.startsWith('https://'))) return false;
    if (u.contains('empty-poster') || u.contains('null')) return false; 
    return true;
  }

  // URL erişilebilirlik kontrolü
  Future<bool> _isReachable(String url) async {
    try {
      final uri = Uri.parse(url);
      final head = await http
          .head(uri, headers: {'Accept': 'image/*'})
          .timeout(const Duration(seconds: 3));
      
      // İçerik tipi resim değilse başarısız say
      if (head.headers['content-type'] != null && 
          !head.headers['content-type']!.contains('image')) {
        return false;
      }

      if (head.statusCode == 200) return true;
      
      if (head.statusCode == 403 || head.statusCode == 404 || head.statusCode == 405) {
        final get = await http
            .get(uri, headers: {'Range': 'bytes=0-10'}) 
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
    
    // 1. Mevcut URL kontrolü
    if (!ignoreExisting && _looksValid(existing)) {
      final works = await _isReachable(existing!.trim());
      if (works) {
        return existing; 
      }
    }

    // Konsola bilgi bas (Debug için)
  
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

    return found;
  }

  Future<void> _updateCatalog(String newUrl, int? tmdbId, String? imdbId, String? title, int? year) async {
     try {
        final db = FirebaseFirestore.instance;
        QuerySnapshot? q;

        if (tmdbId != null && tmdbId > 0) {
          // ID ile bul ve güncelle
          q = await db.collection('catalog_films').where('tmdbId', isEqualTo: tmdbId).limit(1).get();
        } else if (title != null) {
          // İsim ve yıla göre bul
           q = await db.collection('catalog_films')
              .where('titleLc', isEqualTo: title.toLowerCase())
              .where('year', isEqualTo: year).limit(1).get();
        }

        if (q != null && q.docs.isNotEmpty) {
          await q.docs.first.reference.set({'posterUrl': newUrl}, SetOptions(merge: true));
        
        }
      } catch (e) {
      
      }
  }

  // --- CLOUD FUNCTIONS ---

  Future<String?> _byTmdbId(int tmdbId) async {
    try {
      final result = await FirebaseFunctions.instance.httpsCallable('callTMDB').call({
        'endpoint': '/3/movie/$tmdbId',
        'params': {'language': 'tr-TR'}
      });
      
      // DÜZELTME: Güvenli tip dönüşümü
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
      
      // DÜZELTME: Güvenli tip dönüşümü
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
      
      // DÜZELTME: Güvenli tip dönüşümü (Map<Object?, Object?> -> Map<String, dynamic>)
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