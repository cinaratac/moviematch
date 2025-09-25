import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;
import 'package:shared_preferences/shared_preferences.dart';

class LetterboxdFilm {
  final String title;
  final String url;
  final String posterUrl;

  LetterboxdFilm({
    required this.title,
    required this.url,
    required this.posterUrl,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'posterUrl': posterUrl,
  };

  static LetterboxdFilm fromJson(Map<String, dynamic> json) => LetterboxdFilm(
    title: json['title'] ?? '',
    url: json['url'] ?? '',
    posterUrl: json['posterUrl'] ?? '',
  );
}

class LetterboxdService {
  static String _cacheKeyFor(String username) =>
      'lb_cache_' + username.toLowerCase();
  static const _cacheTtl = Duration(hours: 12);

  static Future<String?> _resolvePosterFromDetails(String? detailsPath) async {
    if (detailsPath == null || detailsPath.isEmpty) return null;
    final uri = detailsPath.startsWith('http')
        ? Uri.parse(detailsPath)
        : Uri.parse('https://letterboxd.com$detailsPath');
    try {
      final res = await http.get(
        uri,
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122 Safari/537.36',
          'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
        },
      );
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      return _firstImageUrl(data);
    } catch (_) {
      return null;
    }
  }

  static String? _firstImageUrl(dynamic node) {
    String? pick(String s) {
      // Normalize protocol-relative
      if (s.startsWith('//')) s = 'https:$s';
      // Only trust when path ends with an image extension (ignore query)
      final uri = Uri.tryParse(s);
      if (uri == null) return null;
      final p = uri.path.toLowerCase();
      final looksImage =
          p.endsWith('.jpg') || p.endsWith('.jpeg') || p.endsWith('.png');
      if (!looksImage) return null;
      return s;
    }

    // 1) Direct string
    if (node is String) {
      final s = node;
      // Prefer TMDB if present
      if (s.contains('image.tmdb.org')) {
        final chosen = pick(s);
        if (chosen != null) return chosen;
      }
      // Then Letterboxd CDN
      if (s.contains('a.ltrbxd.com')) {
        final chosen = pick(s);
        if (chosen != null) return chosen;
      }
      // Otherwise any image-looking URL
      return pick(s);
    }

    // 2) Maps: DFS
    if (node is Map) {
      for (final v in node.values) {
        final r = _firstImageUrl(v);
        if (r != null) return r;
      }
      return null;
    }

    // 3) Lists: DFS
    if (node is List) {
      for (final v in node) {
        final r = _firstImageUrl(v);
        if (r != null) return r;
      }
      return null;
    }

    return null;
  }

  static bool _looksLikeImageUrl(String? u) {
    if (u == null || u.isEmpty) return false;
    final s = u.startsWith('//') ? 'https:$u' : u;
    final uri = Uri.tryParse(s);
    if (uri == null) return false;
    final path = uri.path.toLowerCase();
    // Letterboxd boş poster görselini reddet
    if (path.contains('empty-poster')) return false;
    return path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png');
  }

  static String _buildPosterFromIdSlug(
    String filmId,
    String slug, {
    int w = 300,
    int h = 450,
  }) {
    // Letterboxd poster path sharding: each digit becomes a directory level
    final shard = filmId.split('').join('/');
    return 'https://a.ltrbxd.com/resized/film-poster/$shard/$filmId-$slug-0-$w-0-$h-crop.jpg';
  }

  static Future<List<LetterboxdFilm>> fetchFavorites(String username) async {
    final prefs = await SharedPreferences.getInstance();

    try {
      final url = Uri.parse('https://letterboxd.com/$username/');
      final res = await http.get(
        url,
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122 Safari/537.36',
          'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
        },
      );
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');

      final doc = html.parse(res.body);

      final films = <LetterboxdFilm>[];

      // 1) Önce #favourites bölümündeki listeyi hedefle, bulamazsa genel arama yap
      final section = doc.querySelector('section#favourites');
      final ul =
          section?.querySelector('ul.poster-list.-p150.-horizontal') ??
          doc.querySelector('ul.poster-list.-p150.-horizontal');

      if (ul != null) {
        // Sadece gerçek favori öğelerini dolaş (placeholder'ları atla)
        for (final li in ul.querySelectorAll(
          'li.posteritem.favourite-production-poster-container',
        )) {
          // Öncelik: doğrudan görünen poster <img>
          final img =
              li.querySelector('div.poster.film-poster img.image') ??
              li.querySelector('div.poster.film-poster img');
          final a = li.querySelector('a.frame.has-menu');

          String? posterUrl;
          // 1) srcset varsa EN YÜKSEK çözünürlüğü (son giriş) al
          final srcset = img?.attributes['srcset'];
          if (srcset != null && srcset.isNotEmpty) {
            final parts = srcset.split(',');
            final last = parts.last.trim();
            final urlPart = last.split(' ').first.trim();
            if (urlPart.isNotEmpty)
              posterUrl =
                  urlPart; // örn: https://a.ltrbxd.com/resized/...-0-300-0-450-crop.jpg?v=...
          }
          // 1.5) yoksa data-srcset (lazy)
          if ((posterUrl == null || posterUrl.isEmpty)) {
            final dataSrcset = img?.attributes['data-srcset'];
            if (dataSrcset != null && dataSrcset.isNotEmpty) {
              final parts2 = dataSrcset.split(',');
              final last2 = parts2.last.trim();
              final urlPart2 = last2.split(' ').first.trim();
              if (urlPart2.isNotEmpty) posterUrl = urlPart2;
            }
          }
          // 2) yoksa src / data-src
          posterUrl ??= img?.attributes['src'];
          posterUrl ??= img?.attributes['data-src'];

          // Eğer boş poster (placeholder) geldiyse, geçersiz say ve alternatiflere düş
          if (posterUrl != null && posterUrl.isNotEmpty) {
            final test = posterUrl.startsWith('//')
                ? 'https:' + posterUrl
                : posterUrl;
            final up = Uri.tryParse(test);
            if (up != null && up.path.toLowerCase().contains('empty-poster')) {
              posterUrl = null;
            }
          }

          String? title = img?.attributes['alt']?.trim();
          String? href = a?.attributes['href'];
          if ((title == null || title.isEmpty) && a != null) {
            title = a.attributes['data-original-title'] ?? a.text.trim();
          }

          // Yedek: react-component üzerindeki data-*
          final rc = li.querySelector('div.react-component');
          title ??=
              rc?.attributes['data-item-name'] ??
              rc?.attributes['data-item-full-display-name'];
          href ??=
              rc?.attributes['data-item-link'] ??
              rc?.attributes['data-target-link'];
          if (posterUrl == null || posterUrl.isEmpty) {
            posterUrl = rc?.attributes['data-poster-url'];
          }

          // Poster URL normalizasyonu: CDN/TMDB ve relatif yollar
          if (posterUrl != null && posterUrl.isNotEmpty) {
            if (posterUrl.startsWith('//')) {
              posterUrl = 'https:' + posterUrl;
            } else if (posterUrl.startsWith('/')) {
              // Eğer TMDB path'i gibi değilse ltrbxd CDN'e yönlendir
              posterUrl = 'https://a.ltrbxd.com' + posterUrl;
            }
          }

          // 3) Hâlâ gerçek görsel URL değilse (sonek değil, PATH uzantısına bak)
          if (!_looksLikeImageUrl(posterUrl)) {
            final detailsPath = rc?.attributes['data-details-endpoint'];
            final viaDetails = await _resolvePosterFromDetails(detailsPath);
            if (viaDetails != null) posterUrl = viaDetails;
          }

          // Son çare: film-id + slug'tan poster üret (Letterboxd şeması)
          if (!_looksLikeImageUrl(posterUrl)) {
            final rc = li.querySelector('div.react-component');
            final filmId =
                rc?.attributes['data-film-id'] ??
                img?.attributes['data-film-id'];
            final slug =
                rc?.attributes['data-item-slug'] ??
                img?.attributes['data-item-slug'];
            if (filmId != null && slug != null) {
              posterUrl = _buildPosterFromIdSlug(filmId, slug, w: 300, h: 450);
            }
          }

          if (href != null && title != null && posterUrl != null) {
            final absHref = href.startsWith('http')
                ? href
                : 'https://letterboxd.com' + href;
            String absPoster = posterUrl;
            if (!absPoster.startsWith('http')) {
              absPoster = 'https://letterboxd.com' + absPoster;
            }
            // DEBUG: Çıkan URL'leri konsola yazalım
            // Örn: LB fav: 12 Angry Men (1957) | https://a.ltrbxd.com/resized/...jpg?v=...
            // ignore: avoid_print
            print('LB fav: ' + (title ?? '') + ' | ' + absPoster);

            films.add(
              LetterboxdFilm(title: title, url: absHref, posterUrl: absPoster),
            );
          }
        }
      }

      // 2) Eğer hala boşsa, eski favoriler seçicisine dön
      if (films.isEmpty) {
        final favSection =
            doc.querySelector('.favorites') ?? doc.querySelector('#favorites');
        if (favSection != null) {
          for (var link in favSection.querySelectorAll('a[href*="/film/"]')) {
            final href = link.attributes['href'];
            final img = link.querySelector('img');
            if (href != null && img != null) {
              var src =
                  img.attributes['src'] ?? img.attributes['data-src'] ?? '';
              if (src.startsWith('//')) {
                src = 'https:' + src;
              } else if (src.startsWith('/')) {
                src = 'https://a.ltrbxd.com' + src;
              }
              // Placeholder ise ekleme
              final up2 = Uri.tryParse(src);
              if (up2 != null &&
                  up2.path.toLowerCase().contains('empty-poster')) {
                continue;
              }
              films.add(
                LetterboxdFilm(
                  title: img.attributes['alt'] ?? link.text.trim(),
                  url: href.startsWith('http')
                      ? href
                      : 'https://letterboxd.com$href',
                  posterUrl: src,
                ),
              );
            }
          }
        }
      }

      if (films.isEmpty) {
        throw Exception('Favori filmler bulunamadı');
      }

      // keep only first 4
      final result = films.take(4).toList();

      // Save to cache
      await prefs.setString(
        _cacheKeyFor(username),
        jsonEncode(result.map((e) => e.toJson()).toList()),
      );
      await prefs.setInt(
        '${_cacheKeyFor(username)}_time',
        DateTime.now().millisecondsSinceEpoch,
      );

      return result;
    } catch (_) {
      // On error, fallback to cache
      final cached = prefs.getString(_cacheKeyFor(username));
      if (cached != null) {
        final list = (jsonDecode(cached) as List)
            .map((e) => LetterboxdFilm.fromJson(e))
            .toList();
        return list;
      }
      rethrow;
    }
  }
}
