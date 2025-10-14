// lib/services/poster_fallback_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

import '../secrets.dart';

/// Tek noktadan poster çözümü.
/// 1) existing valid ise onu döner
/// 2) tmdbId varsa /movie/{id} ile poster_path alır
/// 3) imdbId varsa /find/{imdb_id}
/// 4) title(+year) ile /search/movie
/// Bulduğu posterı full URL (https://image.tmdb.org/...) olarak döner.
/// İstersen Firestore `catalog_films` içine posterUrl alanını da yazar.
class PosterFallbackService {
  PosterFallbackService._();
  static final PosterFallbackService instance = PosterFallbackService._();

  // Basit validasyon: boş olmayan, http(s) ile başlayan ve bilinen hatalı/placeholder içermeyen URL
  bool _looksValid(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final u = url.trim();
    if (!(u.startsWith('http://') || u.startsWith('https://'))) return false;
    // Letterboxd placeholder veya sorunlu varyantlar:
    if (u.contains('empty-poster')) return false;
    // İstekte belirtmiştin: /sm/upload varyantı bazen patlıyor; gerekirse blokla:
    if (u.contains('/sm/upload')) return false;
    return true;
  }

  Future<bool> _isReachable(String url) async {
    try {
      final uri = Uri.parse(url);
      // 1) Try HEAD first (cheapest)
      final head = await http
          .head(uri, headers: {'Accept': 'image/*,*/*'})
          .timeout(const Duration(seconds: 5));
      if (head.statusCode >= 200 && head.statusCode < 300) {
        // If content-type hints image, accept
        final ct = head.headers['content-type'] ?? '';
        if (ct.contains('image')) return true;
        // Some CDNs don’t return content-type on HEAD; treat 2xx as OK
        return true;
      }
      // 405/403 etc. → retry with tiny GET (range: 0-0)
      final get = await http
          .get(uri, headers: {'Accept': 'image/*,*/*', 'Range': 'bytes=0-0'})
          .timeout(const Duration(seconds: 6));
      return get.statusCode >= 200 && get.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<String?> resolvePosterUrl({
    String? existing,
    int? tmdbId,
    String? imdbId, // "tt" ile başlayan form
    String? title,
    int? year,
    bool writeBackToCatalog = true,
  }) async {
    // 0) Varsa, gerçekten çalışıyor mu kontrol et (404/timeouts vs.)
    if (_looksValid(existing)) {
      final ok = await _isReachable(existing!.trim());
      if (ok) {
        return existing;
      }
      // değilse TMDB fallback akışına devam et
    }

    String? found;

    // 1) TMDB by id
    if (found == null && tmdbId != null && tmdbId > 0) {
      found = await _byTmdbId(tmdbId);
    }

    // 2) TMDB by imdb id
    if (found == null && imdbId != null && imdbId.isNotEmpty) {
      found = await _byImdbId(imdbId);
    }

    // 3) TMDB search by title(+year)
    if (found == null && (title != null && title.trim().isNotEmpty)) {
      found = await _bySearch(title: title.trim(), year: year);
    }

    // Geri yaz (id mevcutsa doğru belgeye yazmak daha sağlıklı)
    if (writeBackToCatalog && found != null) {
      try {
        final db = FirebaseFirestore.instance;
        // En iyi anahtarın tmdbId olduğu varsayımı:
        if (tmdbId != null && tmdbId > 0) {
          final docId = 'tmdb:$tmdbId';
          await db.collection('catalog_films').doc(docId).set({
            'posterUrl': found,
          }, SetOptions(merge: true));
        } else if (imdbId != null && imdbId.isNotEmpty) {
          // imdb tabanlı belge bulmaya çalış (canonicalKey veya alias)
          final q = await db
              .collection('catalog_films')
              .where('imdbId', isEqualTo: imdbId)
              .limit(1)
              .get();
          if (q.docs.isNotEmpty) {
            await q.docs.first.reference.set({
              'posterUrl': found,
            }, SetOptions(merge: true));
          }
        } else if (title != null && title.isNotEmpty && year != null) {
          // title+year eşleşmesi (düşük kesinlikli ama iş görür)
          final q = await db
              .collection('catalog_films')
              .where('titleLc', isEqualTo: title.toLowerCase())
              .where('year', isEqualTo: year)
              .limit(1)
              .get();
          if (q.docs.isNotEmpty) {
            await q.docs.first.reference.set({
              'posterUrl': found,
            }, SetOptions(merge: true));
          }
        }
      } catch (_) {
        // sessiz geç
      }
    }

    return found;
  }

  // --- TMDB helpers ----------------------------------------------------------

  Future<String?> _byTmdbId(int tmdbId) async {
    final bearer = Secrets.tmdbAccessToken;
    if (bearer.isEmpty) return null;
    final uri = Uri.https('api.themoviedb.org', '/3/movie/$tmdbId', {
      'language': 'en-US',
    });
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
  }

  Future<String?> _byImdbId(String imdbId) async {
    final bearer = Secrets.tmdbAccessToken;
    if (bearer.isEmpty) return null;
    final uri = Uri.https('api.themoviedb.org', '/3/find/$imdbId', {
      'external_source': 'imdb_id',
      'language': 'en-US',
    });
    final resp = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $bearer',
        'Accept': 'application/json',
      },
    );
    if (resp.statusCode != 200) return null;
    final map = json.decode(resp.body) as Map<String, dynamic>;
    final List results = (map['movie_results'] ?? []) as List;
    if (results.isEmpty) return null;
    final first = results.first as Map<String, dynamic>;
    final p = (first['poster_path'] ?? '') as String;
    if (p.isEmpty) return null;
    return 'https://image.tmdb.org/t/p/w500$p';
  }

  Future<String?> _bySearch({required String title, int? year}) async {
    final bearer = Secrets.tmdbAccessToken;
    if (bearer.isEmpty) return null;
    final qp = <String, String>{
      'query': title,
      'include_adult': 'false',
      'language': 'en-US',
      'page': '1',
    };
    if (year != null && year > 0) {
      qp['year'] = year.toString();
      qp['primary_release_year'] = year.toString();
    }
    final uri = Uri.https('api.themoviedb.org', '/3/search/movie', qp);
    final resp = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer $bearer',
        'Accept': 'application/json',
      },
    );
    if (resp.statusCode != 200) return null;
    final map = json.decode(resp.body) as Map<String, dynamic>;
    final List results = (map['results'] ?? []) as List;
    if (results.isEmpty) return null;
    final first = results.first as Map<String, dynamic>;
    final p = (first['poster_path'] ?? '') as String;
    if (p.isEmpty) return null;
    return 'https://image.tmdb.org/t/p/w500$p';
  }
}
