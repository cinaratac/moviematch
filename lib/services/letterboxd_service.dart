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
    if (node is String) {
      final s = node;
      if (s.startsWith('http') &&
          (s.contains('.jpg') || s.contains('.png') || s.contains('.jpeg'))) {
        return s;
      }
      return null;
    }
    if (node is Map) {
      for (final v in node.values) {
        final r = _firstImageUrl(v);
        if (r != null) return r;
      }
      return null;
    }
    if (node is List) {
      for (final v in node) {
        final r = _firstImageUrl(v);
        if (r != null) return r;
      }
      return null;
    }
    return null;
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

      // 1) İlk olarak, kullanıcı örneğinde verilen liste yapısını hedefle
      final ul = doc.querySelector('ul.poster-list.-p150.-horizontal');
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
          // 1) srcset varsa ilk URL'yi çek
          final srcset = img?.attributes['srcset'];
          if (srcset != null && srcset.isNotEmpty) {
            final first = srcset.split(',').first.trim();
            final part = first.split(' ').first.trim();
            if (part.isNotEmpty) posterUrl = part;
          }
          // 2) yoksa src / data-src
          posterUrl ??= img?.attributes['src'];
          posterUrl ??= img?.attributes['data-src'];

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
          // 3) Hâlâ gerçek görsel URL değilse details endpoint üzerinden çöz
          if (posterUrl == null ||
              (!posterUrl.startsWith('http') &&
                  !posterUrl.endsWith('.jpg') &&
                  !posterUrl.endsWith('.png') &&
                  !posterUrl.endsWith('.jpeg'))) {
            final detailsPath = rc?.attributes['data-details-endpoint'];
            final viaDetails = await _resolvePosterFromDetails(detailsPath);
            if (viaDetails != null) posterUrl = viaDetails;
          }

          if (href != null && title != null && posterUrl != null) {
            final absHref = href.startsWith('http')
                ? href
                : 'https://letterboxd.com' + href;
            String absPoster = posterUrl;
            if (!absPoster.startsWith('http')) {
              absPoster = 'https://letterboxd.com' + absPoster;
            }
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
              films.add(
                LetterboxdFilm(
                  title: img.attributes['alt'] ?? link.text.trim(),
                  url: href.startsWith('http')
                      ? href
                      : 'https://letterboxd.com$href',
                  posterUrl:
                      img.attributes['src'] ?? img.attributes['data-src'] ?? '',
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
