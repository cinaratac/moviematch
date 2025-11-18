import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

import '../secrets.dart';

/// Tek noktadan poster çözümü.
/// 1) existing valid ise ve erişilebiliyorsa onu döner.
/// 2) Değilse ve tmdbId varsa /movie/{id} ile poster_path alır.
/// 3) imdbId varsa /find/{imdb_id}
/// 4) title(+year) ile /search/movie
class PosterFallbackService {
  PosterFallbackService._();
  static final PosterFallbackService instance = PosterFallbackService._();

  // Boş veya hatalı olduğu bilinen URL'leri filtrele
  bool _looksValid(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final u = url.trim();
    if (!(u.startsWith('http://') || u.startsWith('https://'))) return false;
    if (u.contains('empty-poster')) return false;
    if (u.contains('null')) return false; // Bazen string olarak 'null' gelebilir
    return true;
  }

  /// URL'in gerçekten resim döndürüp döndürmediğini kontrol eder.
  Future<bool> _isReachable(String url) async {
    try {
      final uri = Uri.parse(url);
      // Önce HEAD isteği ile hızlı kontrol (Timeout kısa tutuldu: 3sn)
      final head = await http
          .head(uri, headers: {'Accept': 'image/*'})
          .timeout(const Duration(seconds: 3));
      
      if (head.statusCode == 200) {
        return true;
      }
      
      // Bazı CDN'ler HEAD'e izin vermez, 403/405 dönerse küçük bir GET dene
      if (head.statusCode == 403 || head.statusCode == 404 || head.statusCode == 405) {
        final get = await http
            .get(uri, headers: {'Range': 'bytes=0-10'}) // Sadece ilk byte'ları iste
            .timeout(const Duration(seconds: 4));
        return get.statusCode >= 200 && get.statusCode < 300;
      }
      
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<String?> resolvePosterUrl({
    String? existing,
    int? tmdbId,
    String? imdbId, 
    String? title,
    int? year,
    bool writeBackToCatalog = true,
  }) async {
    // 1. Adım: Mevcut URL sağlam mı?
    if (_looksValid(existing)) {
      final works = await _isReachable(existing!.trim());
      if (works) {
        return existing; // Sağlamsa maceraya gerek yok, kullan.
      }
      // Değilse aşağı devam et (Fallback mekanizması)
    }

    String? found;

    // 2. Adım: En güvenilir kaynak TMDB ID'dir.
    if (found == null && tmdbId != null && tmdbId > 0) {
      found = await _byTmdbId(tmdbId);
    }

    // 3. Adım: IMDb ID ile bulmaya çalış.
    if (found == null && imdbId != null && imdbId.isNotEmpty) {
      found = await _byImdbId(imdbId);
    }

    // 4. Adım: İsim ve Yıl ile arama yap (En son çare).
    if (found == null && (title != null && title.trim().isNotEmpty)) {
      found = await _bySearch(title: title.trim(), year: year);
    }

    // 5. Adım: Eğer yeni bir poster bulunduysa, kataloğa geri yaz (Tamir et).
    if (writeBackToCatalog && found != null && found != existing) {
      _updateCatalog(found, tmdbId, imdbId, title, year);
    }

    return found;
  }

  // --- Firestore Güncelleme ---
  Future<void> _updateCatalog(String newUrl, int? tmdbId, String? imdbId, String? title, int? year) async {
     try {
        final db = FirebaseFirestore.instance;
        QuerySnapshot? q;

        // Belgeyi bulmaya çalış
        if (tmdbId != null && tmdbId > 0) {
          // Önce doc ID olarak dene, yoksa sorgula
          final docId = 'tmdb:$tmdbId';
          final docCheck = await db.collection('catalog_films').doc(docId).get();
          if (docCheck.exists) {
            await docCheck.reference.update({'posterUrl': newUrl});
            return;
          } else {
             q = await db.collection('catalog_films').where('tmdbId', isEqualTo: tmdbId).limit(1).get();
          }
        } else if (imdbId != null) {
           q = await db.collection('catalog_films').where('imdbId', isEqualTo: imdbId).limit(1).get();
        } else if (title != null) {
           q = await db.collection('catalog_films')
              .where('titleLc', isEqualTo: title.toLowerCase())
              .where('year', isEqualTo: year).limit(1).get();
        }

        if (q != null && q.docs.isNotEmpty) {
          await q.docs.first.reference.set({'posterUrl': newUrl}, SetOptions(merge: true));
        }
      } catch (_) {
        // Log hatası (sessizce geç)
      }
  }

  // --- TMDB API Yardımcıları ---

  Future<String?> _byTmdbId(int tmdbId) async {
    final bearer = Secrets.tmdbAccessToken;
    if (bearer.isEmpty) return null;
    
    try {
      final uri = Uri.parse('https://api.themoviedb.org/3/movie/$tmdbId?language=tr-TR'); 
      // Not: Dil tercihi posterde çok fark etmez ama metadata için tr-TR denenebilir, 
      // poster yoksa en-US fallback yapılabilir ama basitleştirmek için varsayılanı kullanıyoruz.
      
      final resp = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $bearer',
          'Accept': 'application/json',
        },
      );

      if (resp.statusCode != 200) return null;
      
      final map = json.decode(resp.body) as Map<String, dynamic>;
      final p = (map['poster_path'] ?? '') as String;
      
      if (p.isEmpty) return null;
      return 'https://image.tmdb.org/t/p/w500$p';
    } catch (_) {
      return null;
    }
  }

  Future<String?> _byImdbId(String imdbId) async {
    final bearer = Secrets.tmdbAccessToken;
    if (bearer.isEmpty) return null;
    try {
      final uri = Uri.https('api.themoviedb.org', '/3/find/$imdbId', {
        'external_source': 'imdb_id',
        'language': 'en-US',
      });
      final resp = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $bearer', 'Accept': 'application/json'},
      );
      if (resp.statusCode != 200) return null;
      
      final map = json.decode(resp.body) as Map<String, dynamic>;
      final List results = (map['movie_results'] ?? []) as List;
      if (results.isEmpty) return null;
      
      final first = results.first as Map<String, dynamic>;
      final p = (first['poster_path'] ?? '') as String;
      if (p.isEmpty) return null;
      
      return 'https://image.tmdb.org/t/p/w500$p';
    } catch (_) {
      return null;
    }
  }

  Future<String?> _bySearch({required String title, int? year}) async {
    final bearer = Secrets.tmdbAccessToken;
    if (bearer.isEmpty) return null;
    try {
      final qp = <String, String>{
        'query': title,
        'include_adult': 'false',
        'language': 'en-US', // Poster için global arama daha güvenli
        'page': '1',
      };
      if (year != null && year > 0) {
        qp['primary_release_year'] = year.toString();
      }
      
      final uri = Uri.https('api.themoviedb.org', '/3/search/movie', qp);
      final resp = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $bearer', 'Accept': 'application/json'},
      );
      
      if (resp.statusCode != 200) return null;
      final map = json.decode(resp.body) as Map<String, dynamic>;
      final List results = (map['results'] ?? []) as List;
      if (results.isEmpty) return null;
      
      final first = results.first as Map<String, dynamic>;
      final p = (first['poster_path'] ?? '') as String;
      if (p.isEmpty) return null;
      
      return 'https://image.tmdb.org/t/p/w500$p';
    } catch (_) {
      return null;
    }
  }
}