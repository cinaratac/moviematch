import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// --- HTTP client & helpers ---------------------------------------------------
const _kDefaultUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36';
const _kAcceptLang = 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7';

class _Http {
  static final http.Client client = http.Client();

  static Map<String, String> baseHeaders({String? referer}) => {
    'User-Agent': _kDefaultUa,
    'Accept-Language': _kAcceptLang,
    if (referer != null) 'Referer': referer,
  };

  /// GET with timeout & simple retry (network hiccups)
  static Future<http.Response?> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
    int retries = 2,
  }) async {
    http.Response? res;
    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        final h = <String, String>{};
        if (headers != null) h.addAll(headers);
        res = await client.get(uri, headers: h).timeout(timeout);
        if (res.statusCode == 200) return res;
        // For 4xx/5xx, retry only once; otherwise break
        if (attempt == retries) return res;
      } on TimeoutException {
        if (attempt == retries) rethrow;
      } catch (_) {
        if (attempt == retries) rethrow;
      }
      // small backoff
      await Future.delayed(Duration(milliseconds: 200 * (attempt + 1)));
    }
    return res; // may be non-200
  }
}

class LetterboxdFilm {
  /// Display title (e.g., "The Matrix")
  final String title;

  /// Absolute Letterboxd film page url (e.g., https://letterboxd.com/film/the-matrix/)
  final String url;

  /// Absolute poster URL (preferably 300x450 crop from CDN)
  final String posterUrl;

  /// Stable key for matching across users (e.g., "film:the-matrix")
  /// Derived from `url` (preferred) or sanitized `title` as fallback.
  final String key;

  LetterboxdFilm({
    required this.title,
    required this.url,
    required this.posterUrl,
    String? key,
  }) : key = key ?? LetterboxdFilm._deriveKey(url, title);

  /// Map (for Firestore) — same shape as toJson
  Map<String, dynamic> toMap() => {
    'title': title,
    'url': url,
    'posterUrl': posterUrl,
    'key': key,
  };

  /// Alias for compatibility with older code
  Map<String, dynamic> toJson() => toMap();

  /// Create from map/json. If 'key' missing (old cache), derive it.
  static LetterboxdFilm fromMap(Map<String, dynamic> json) => LetterboxdFilm(
    title: json['title'] ?? '',
    url: json['url'] ?? '',
    posterUrl: json['posterUrl'] ?? '',
    key: json['key'],
  );

  /// Alias for compatibility with older code
  static LetterboxdFilm fromJson(Map<String, dynamic> json) => fromMap(json);

  /// Helper: produce only keys for matching
  static List<String> keysOf(List<LetterboxdFilm> films) =>
      films.map((f) => f.key).where((k) => k.isNotEmpty).toList();

  /// Public: extract canonical film key from an absolute Letterboxd href
  /// e.g., https://letterboxd.com/film/the-matrix/ -> film:the-matrix
  static String filmKeyFromHref(String href) => _deriveKey(href, '');

  /// --- internal ---------------------------------------------------------
  static String _deriveKey(String href, String titleFallback) {
    try {
      final u = Uri.parse(href);
      // Expect path like /film/<slug>/...
      final parts = u.path.split('/').where((e) => e.isNotEmpty).toList();
      final idx = parts.indexOf('film');
      if (idx != -1 && idx + 1 < parts.length) {
        final slug = parts[idx + 1].toLowerCase();
        if (slug.isNotEmpty) return 'film:$slug';
      }
    } catch (_) {
      // ignore
    }
    // Fallback to sanitized title
    final slug = titleFallback
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return slug.isNotEmpty ? 'film:$slug' : '';
  }
}

class MatchResult {
  final String otherUid;
  final String? otherDisplayName;
  final List<String> commonKeys; // e.g., ["film:the-matrix", ...]
  final List<LetterboxdFilm> commonFilms; // resolved for UI
  final int commonCount;

  MatchResult({
    required this.otherUid,
    required this.otherDisplayName,
    required this.commonKeys,
    required this.commonFilms,
  }) : commonCount = commonKeys.length;
}

class LetterboxdService {
  // Headers to load Letterboxd CDN images on mobile (used by Image.network headers)
  static const Map<String, String> imageHeaders = {
    'Referer': 'https://letterboxd.com/',
    'User-Agent': 'Mozilla/5.0',
  };
  static String _cacheKeyFor(String username) =>
      'lb_cache_${username.toLowerCase()}';
  // Default headers for HTML/JSON requests to Letterboxd
  static const Map<String, String> _reqHeaders = {
    'User-Agent': _kDefaultUa,
    'Accept-Language': _kAcceptLang,
    'Referer': 'https://letterboxd.com/',
  };
  // --- Generic rated-page fetcher (0.5★, 1★, 5★, etc.) ---------------------
  static Future<List<LetterboxdFilm>> _fetchRated(
    String username,
    String rating, {
    required String cacheSuffix,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    http.Response? res;
    final tries = [
      Uri.parse('https://letterboxd.com/$username/films/rated/$rating/'),
      Uri.parse('https://letterboxd.com/$username/films/ratings/$rating/'),
    ];

    for (final u in tries) {
      final r = await _Http.get(u, headers: _reqHeaders);
      if (r != null && r.statusCode == 200) {
        res = r;
        break;
      }
    }

    if (res == null) throw Exception('$rating★ sayfası alınamadı');

    final doc = html.parse(res.body);

    final candidates = <dom.Element>[
      ...doc.querySelectorAll('div.poster-grid ul.grid li.griditem'),
      ...doc.querySelectorAll(
        'section.col-main .poster-grid ul.grid li.griditem',
      ),
      ...doc.querySelectorAll('section.col-main ul.grid li.griditem'),
      ...doc.querySelectorAll('ul.grid.-p70 li.griditem'),
      ...doc.querySelectorAll('ul.grid li.griditem'),
    ];

    final items = <LetterboxdFilm>[];
    final seenHref = <String>{};

    for (final li in candidates) {
      final a =
          li.querySelector('a.frame') ?? li.querySelector('a.frame.has-menu');
      final img = li.querySelector('img.image') ?? li.querySelector('img');
      final rc = li.querySelector('div.react-component');
      if (a == null && rc == null && img == null) continue;

      String title =
          (a?.attributes['data-original-title'] ??
                  img?.attributes['alt'] ??
                  rc?.attributes['data-item-name'] ??
                  rc?.attributes['data-item-full-display-name'] ??
                  a?.querySelector('.frame-title')?.text ??
                  '')
              .replaceAll(RegExp(r'^Poster for '), '')
              .trim();
      if (title.isEmpty) continue;

      String href =
          a?.attributes['href'] ??
          rc?.attributes['data-item-link'] ??
          rc?.attributes['data-target-link'] ??
          '';
      if (href.isEmpty) continue;
      if (href.startsWith('//')) href = 'https:$href';
      if (href.startsWith('/')) href = 'https://letterboxd.com$href';
      if (!seenHref.add(href)) continue;

      String? poster =
          (img?.attributes['srcset'] ?? img?.attributes['data-srcset'])
              ?.split(',')
              .last
              .trim()
              .split(' ')
              .first;
      poster ??= img?.attributes['src'] ?? img?.attributes['data-src'];

      if (poster != null && poster.startsWith('//')) poster = 'https:$poster';
      if (poster != null && poster.startsWith('/')) {
        poster = 'https://a.ltrbxd.com$poster';
      }

      final filmId =
          rc?.attributes['data-film-id'] ?? img?.attributes['data-film-id'];
      final slug =
          rc?.attributes['data-item-slug'] ?? img?.attributes['data-item-slug'];
      final isPlaceholder = poster != null && poster.contains('empty-poster');
      final looksImg = _looksLikeImageUrl(poster);

      if (filmId != null && slug != null) {
        poster = _buildPosterFromIdSlug(filmId, slug, w: 300, h: 450);
      } else if (!looksImg || isPlaceholder) {
        final details =
            rc?.attributes['data-details-endpoint'] ??
            a?.attributes['data-details-endpoint'];
        final via = await _resolvePosterFromDetails(details);
        if (via != null) poster = via;
      }

      if ((poster == null || !_looksLikeImageUrl(poster)) &&
          (rc != null || img != null)) {
        final viaAttrs = _posterFromDataAttrs(rc: rc, img: img, w: 300, h: 450);
        if (viaAttrs != null) poster = viaAttrs;
      }

      if (poster != null && poster.startsWith('//')) poster = 'https:' + poster;
      if (poster == null || !_looksLikeImageUrl(poster)) continue;

      items.add(LetterboxdFilm(title: title, url: href, posterUrl: poster));
    }

    if (items.isEmpty) {
      final cached = prefs.getString('${_cacheKeyFor(username)}$cacheSuffix');
      if (cached != null) {
        final list = (jsonDecode(cached) as List)
            .map((e) => LetterboxdFilm.fromJson(e))
            .toList();
        if (list.isNotEmpty) return list;
      }
      throw Exception('$rating★ film bulunamadı (selector uyumsuz)');
    }

    // Tekrarları temizle
    final uniq = <String, LetterboxdFilm>{};
    for (final f in items) {
      uniq[f.url] = f;
    }
    final result = uniq.values.toList();

    try {
      await prefs.setString(
        '${_cacheKeyFor(username)}$cacheSuffix',
        jsonEncode(result.map((e) => e.toJson()).toList()),
      );
      await prefs.setInt(
        '${_cacheKeyFor(username)}${cacheSuffix}_time',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}

    return result;
  }

  /// 0.5★ verilen filmleri getirir
  static Future<List<LetterboxdFilm>> fetchHalfStar(String username) {
    // For 0.5, the Letterboxd URL is .../films/rated/.5/
    return _fetchRated(username, '.5', cacheSuffix: '_rated05');
  }

  /// 1★ verilen filmleri getirir
  static Future<List<LetterboxdFilm>> fetchOneStar(String username) {
    return _fetchRated(username, '1', cacheSuffix: '_rated1');
  }

  /// "Sevmediği Filmler": 0.5★ ve 1★
  static Future<List<LetterboxdFilm>> fetchDisliked(String username) async {
    List<LetterboxdFilm> half = const [];
    List<LetterboxdFilm> one = const [];
    try {
      half = await fetchHalfStar(username);
    } catch (_) {}
    try {
      one = await fetchOneStar(username);
    } catch (_) {}

    final map = <String, LetterboxdFilm>{};
    for (final f in [...half, ...one]) {
      map[f.url] = f;
    }
    return map.values.toList();
  }

  static Future<String?> _resolvePosterFromDetails(String? detailsPath) async {
    if (detailsPath == null || detailsPath.isEmpty) return null;
    final uri = detailsPath.startsWith('http')
        ? Uri.parse(detailsPath)
        : Uri.parse('https://letterboxd.com$detailsPath');
    try {
      final res = await _Http.get(
        uri,
        headers: _Http.baseHeaders(referer: 'https://letterboxd.com/'),
      );
      if (res == null || res.statusCode != 200) return null;
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

    // Letterboxd placeholder'ı dışla
    if (path.contains('empty-poster')) return false;

    // Sadece gerçek görsel uzantılarını kabul et (query string'i path'e dahil olmadığı için sorun yok)
    return path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.png') ||
        path.endsWith('.webp') ||
        path.endsWith('.avif');
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

  static String? _posterFromDataAttrs({
    dom.Element? rc,
    dom.Element? img,
    int w = 300,
    int h = 450,
  }) {
    final filmId =
        rc?.attributes['data-film-id'] ?? img?.attributes['data-film-id'];
    final slug =
        rc?.attributes['data-item-slug'] ?? img?.attributes['data-item-slug'];

    // 1) Varsa filmId+slug ile doğrudan 300x450 üret
    if (filmId != null && slug != null) {
      return _buildPosterFromIdSlug(filmId, slug, w: w, h: h);
    }

    // 2) data-poster-url: /film/<slug>/image-150/ -> gerçek görsel değil; yükseltmeyi deneyelim
    final dataPosterUrl =
        rc?.attributes['data-poster-url'] ?? img?.attributes['data-poster-url'];
    if (dataPosterUrl != null && dataPosterUrl.isNotEmpty) {
      // /film/<slug>/image-150/ biçiminde olur. ID yoksa güvenilir büyük görsel üretemeyiz.
      // Bu durumda null döndürüp çağıranın detay endpoint fallback'ine düşmesini sağlayalım.
      return null;
    }

    return null;
  }

  static Future<List<LetterboxdFilm>> fetchFavorites(String username) async {
    final prefs = await SharedPreferences.getInstance();

    try {
      final url = Uri.parse('https://letterboxd.com/$username/');
      final res = await _Http.get(
        url,
        headers: _Http.baseHeaders(referer: 'https://letterboxd.com/'),
      );
      if (res == null || res.statusCode != 200)
        throw Exception('HTTP ${res?.statusCode}');
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
              posterUrl = 'https:$posterUrl';
            } else if (posterUrl.startsWith('/')) {
              // Eğer TMDB path'i gibi değilse ltrbxd CDN'e yönlendir
              posterUrl = 'https://a.ltrbxd.com$posterUrl';
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
            final rc2 = li.querySelector('div.react-component');
            final filmId =
                rc2?.attributes['data-film-id'] ??
                img?.attributes['data-film-id'];
            final slug =
                rc2?.attributes['data-item-slug'] ??
                img?.attributes['data-item-slug'];
            if (filmId != null && slug != null) {
              posterUrl = _buildPosterFromIdSlug(filmId, slug, w: 300, h: 450);
            }
          }

          if (href != null && title != null && posterUrl != null) {
            final absHref = href.startsWith('http')
                ? href
                : 'https://letterboxd.com$href';
            String absPoster = posterUrl;
            if (!absPoster.startsWith('http')) {
              absPoster = 'https://letterboxd.com$absPoster';
            }
            // DEBUG: Çıkan URL'leri konsola yazalım
            // Örn: LB fav: 12 Angry Men (1957) | https://a.ltrbxd.com/resized/...jpg?v=...
            // ignore: avoid_print
            print('LB fav: $title | $absPoster');

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
                src = 'https:$src';
              } else if (src.startsWith('/')) {
                src = 'https://a.ltrbxd.com$src';
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

      // De-duplicate by URL (same film can appear twice in some layouts)
      final seen = <String>{};
      final deduped = <LetterboxdFilm>[];
      for (final f in films) {
        if (seen.add(f.url)) deduped.add(f);
      }

      // Keep at most 4 for favorites widget (if more exist)
      final result = deduped.length > 4 ? deduped.take(4).toList() : deduped;

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

  static Future<List<LetterboxdFilm>> fetchFiveStar(String username) async {
    final prefs = await SharedPreferences.getInstance();

    final tries = [
      Uri.parse('https://letterboxd.com/$username/films/rated/5/'),
      Uri.parse('https://letterboxd.com/$username/films/ratings/5/'),
    ];

    http.Response? res;
    for (final u in tries) {
      final r = await _Http.get(u, headers: _reqHeaders);
      if (r != null && r.statusCode == 200) {
        res = r;
        break;
      }
    }
    if (res == null) throw Exception('5★ sayfası alınamadı');

    final doc = html.parse(res.body);

    // Birden fazla varyant: (poster-grid) V1, (section .grid) V2, genel yedek V3 + ek varyantlar
    final candidates = <dom.Element>[
      ...doc.querySelectorAll('div.poster-grid ul.grid li.griditem'),
      ...doc.querySelectorAll(
        'section.col-main .poster-grid ul.grid li.griditem',
      ),
      ...doc.querySelectorAll('section.col-main ul.grid li.griditem'),
      ...doc.querySelectorAll('ul.grid.-p70 li.griditem'),
      ...doc.querySelectorAll('ul.grid li.griditem'),
    ];
    // DEBUG: Kaç aday bulundu?
    // ignore: avoid_print
    print('[LB][5★] candidate count: ${candidates.length}');

    final items = <LetterboxdFilm>[];
    final seenHref = <String>{};

    for (final li in candidates) {
      final a =
          li.querySelector('a.frame') ?? li.querySelector('a.frame.has-menu');
      final img = li.querySelector('img.image') ?? li.querySelector('img');
      final rc = li.querySelector('div.react-component');

      // Bazı varyantlarda <a.frame> veya <img> olmayabilir; rc ve data-* ile çözeriz
      if (a == null && rc == null && img == null) continue;

      // Title
      String title =
          (a?.attributes['data-original-title'] ??
                  img?.attributes['alt'] ??
                  rc?.attributes['data-item-name'] ??
                  rc?.attributes['data-item-full-display-name'] ??
                  a?.querySelector('.frame-title')?.text ??
                  '')
              .replaceAll(RegExp(r'^Poster for '), '')
              .trim();
      if (title.isEmpty) continue;

      // Href (absolute)
      String href =
          a?.attributes['href'] ??
          rc?.attributes['data-item-link'] ??
          rc?.attributes['data-target-link'] ??
          '';
      if (href.isEmpty) continue;
      if (href.startsWith('//')) href = 'https:$href';
      if (href.startsWith('/')) href = 'https://letterboxd.com$href';
      if (!seenHref.add(href)) continue;

      // Poster URL — srcset > data-srcset > src > data-src
      String? poster =
          (img?.attributes['srcset'] ?? img?.attributes['data-srcset'])
              ?.split(',')
              .last
              .trim()
              .split(' ')
              .first;
      poster ??= img?.attributes['src'] ?? img?.attributes['data-src'];

      // Normalizasyon
      if (poster != null && poster.startsWith('//')) poster = 'https:$poster';
      if (poster != null && poster.startsWith('/'))
        poster = 'https://a.ltrbxd.com$poster';

      // Placeholder ise/uzantı yoksa filmId+slug’tan üret
      final filmId =
          rc?.attributes['data-film-id'] ?? img?.attributes['data-film-id'];
      final slug =
          rc?.attributes['data-item-slug'] ?? img?.attributes['data-item-slug'];

      final isPlaceholder = poster != null && poster.contains('empty-poster');
      final looksImg = _looksLikeImageUrl(poster);
      if (filmId != null && slug != null) {
        // 70px küçük görsel gelse bile 300x450’e yükselt
        poster = _buildPosterFromIdSlug(filmId, slug, w: 300, h: 450);
      } else if (!looksImg || isPlaceholder) {
        // Son çare: detay endpoint’ten dene
        final details =
            rc?.attributes['data-details-endpoint'] ??
            a?.attributes['data-details-endpoint'];
        final via = await _resolvePosterFromDetails(details);
        if (via != null) poster = via;
      }

      // Ek fallback: data-* attribute'larından üret (tercihen id+slug -> 300x450)
      if ((poster == null || !_looksLikeImageUrl(poster)) &&
          (rc != null || img != null)) {
        final viaAttrs = _posterFromDataAttrs(rc: rc, img: img, w: 300, h: 450);
        if (viaAttrs != null) poster = viaAttrs;
      }

      if (poster != null && poster.startsWith('//')) {
        poster = 'https:$poster';
      }
      if (poster == null || !_looksLikeImageUrl(poster)) continue;

      // ignore: avoid_print
      if (items.length < 5) {
        print('[LB][5★] $title | $poster');
      }

      items.add(LetterboxdFilm(title: title, url: href, posterUrl: poster));
    }

    if (items.isEmpty) {
      // Cache’e düş
      final cached = prefs.getString('${_cacheKeyFor(username)}_rated5');
      if (cached != null) {
        final list = (jsonDecode(cached) as List)
            .map((e) => LetterboxdFilm.fromJson(e))
            .toList();
        if (list.isNotEmpty) return list;
      }
      throw Exception('5★ film bulunamadı (selector uyumsuz)');
    }

    // Tekrarları temizle
    final uniq = <String, LetterboxdFilm>{};
    for (final f in items) {
      uniq[f.url] = f;
    }
    final result = uniq.values.toList();

    // Cache yaz
    try {
      await prefs.setString(
        '${_cacheKeyFor(username)}_rated5',
        jsonEncode(result.map((e) => e.toJson()).toList()),
      );
      await prefs.setInt(
        '${_cacheKeyFor(username)}_rated5_time',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}

    return result;
  }

  /// Writes a canonical catalog doc for each film so we can resolve keys to title/poster later
  static Future<void> _upsertCatalog(List<LetterboxdFilm> films) async {
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    for (final f in films) {
      if (f.key.isEmpty) continue;
      final doc = db
          .collection('catalog_films')
          .doc(f.key); // docId example: film:the-matrix
      batch.set(doc, {
        'title': f.title,
        'url': f.url,
        'posterUrl': f.posterUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  /// Fetches user's favorites from Letterboxd and persists them under users/{uid}
  /// The document keeps: lbUsername, favoritesKeys (array of keys), favorites (first 4 with title/url/poster), updatedAt
  static Future<List<LetterboxdFilm>> syncFavoritesToFirestore({
    String? uid,
    String? lbUsername,
  }) async {
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;
    final effectiveUid = uid ?? user?.uid;
    if (effectiveUid == null) {
      throw StateError('No Firebase user. Call FirebaseAuth.signIn first.');
    }
    if (lbUsername == null || lbUsername.isEmpty) {
      throw ArgumentError('lbUsername is required to sync favorites');
    }

    // 1) Scrape favorites
    final favs = await fetchFavorites(lbUsername);

    // 2) Upsert film catalog for resolving common films later
    await _upsertCatalog(favs);

    // 3) Persist on user profile doc
    final db = FirebaseFirestore.instance;
    final doc = db.collection('users').doc(effectiveUid);

    final favKeys = LetterboxdFilm.keysOf(favs);
    final favLite = favs
        .take(4)
        .map(
          (f) => {
            'title': f.title,
            'url': f.url,
            'posterUrl': f.posterUrl,
            'key': f.key,
          },
        )
        .toList();

    await doc.set({
      // You said you prefer to keep only displayName in Auth; we keep lbUsername here for scraping linkage.
      'lbUsername': lbUsername,
      'favoritesKeys': favKeys,
      'favorites': favLite,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return favs;
  }

  /// Fetch user's WATCHLIST films from Letterboxd (with pagination) and return full film objects
  static Future<List<LetterboxdFilm>> fetchWatchlist(String username) async {
    final prefs = await SharedPreferences.getInstance();

    final List<LetterboxdFilm> all = [];
    final seenHref = <String>{};
    int page = 1;

    while (true) {
      final uri = page == 1
          ? Uri.parse('https://letterboxd.com/$username/watchlist/')
          : Uri.parse('https://letterboxd.com/$username/watchlist/page/$page/');

      http.Response? res;
      final r = await _Http.get(uri, headers: _reqHeaders);
      if (r != null && r.statusCode == 200) {
        res = r;
      }

      if (res == null) break; // further pages likely don't exist

      final doc = html.parse(res.body);

      // Use the same robust selectors used elsewhere to handle layout variants
      final candidates = <dom.Element>[
        ...doc.querySelectorAll('div.poster-grid ul.grid li.griditem'),
        ...doc.querySelectorAll(
          'section.col-main .poster-grid ul.grid li.griditem',
        ),
        ...doc.querySelectorAll('section.col-main ul.grid li.griditem'),
        ...doc.querySelectorAll('ul.grid.-p70 li.griditem'),
        ...doc.querySelectorAll('ul.grid li.griditem'),
      ];

      final pageItems = <LetterboxdFilm>[];

      for (final li in candidates) {
        final a =
            li.querySelector('a.frame') ?? li.querySelector('a.frame.has-menu');
        final img = li.querySelector('img.image') ?? li.querySelector('img');
        final rc = li.querySelector('div.react-component');
        if (a == null && rc == null && img == null) continue;

        String title =
            (a?.attributes['data-original-title'] ??
                    img?.attributes['alt'] ??
                    rc?.attributes['data-item-name'] ??
                    rc?.attributes['data-item-full-display-name'] ??
                    a?.querySelector('.frame-title')?.text ??
                    '')
                .replaceAll(RegExp(r'^Poster for '), '')
                .trim();
        if (title.isEmpty) continue;

        String href =
            a?.attributes['href'] ??
            rc?.attributes['data-item-link'] ??
            rc?.attributes['data-target-link'] ??
            '';
        if (href.isEmpty) continue;
        if (href.startsWith('//')) href = 'https:$href';
        if (href.startsWith('/')) href = 'https://letterboxd.com$href';
        if (!seenHref.add(href)) continue;

        String? poster =
            (img?.attributes['srcset'] ?? img?.attributes['data-srcset'])
                ?.split(',')
                .last
                .trim()
                .split(' ')
                .first;
        poster ??= img?.attributes['src'] ?? img?.attributes['data-src'];

        if (poster != null && poster.startsWith('//')) poster = 'https:$poster';
        if (poster != null && poster.startsWith('/')) {
          poster = 'https://a.ltrbxd.com$poster';
        }

        final filmId =
            rc?.attributes['data-film-id'] ?? img?.attributes['data-film-id'];
        final slug =
            rc?.attributes['data-item-slug'] ??
            img?.attributes['data-item-slug'];
        final isPlaceholder = poster != null && poster.contains('empty-poster');
        final looksImg = _looksLikeImageUrl(poster);

        if (filmId != null && slug != null) {
          poster = _buildPosterFromIdSlug(filmId, slug, w: 300, h: 450);
        } else if (!looksImg || isPlaceholder) {
          final details =
              rc?.attributes['data-details-endpoint'] ??
              a?.attributes['data-details-endpoint'];
          final via = await _resolvePosterFromDetails(details);
          if (via != null) poster = via;
        }

        if ((poster == null || !_looksLikeImageUrl(poster)) &&
            (rc != null || img != null)) {
          final viaAttrs = _posterFromDataAttrs(
            rc: rc,
            img: img,
            w: 300,
            h: 450,
          );
          if (viaAttrs != null) poster = viaAttrs;
        }

        if (poster != null && poster.startsWith('//'))
          poster = 'https:' + poster;
        if (poster == null || !_looksLikeImageUrl(poster)) continue;

        pageItems.add(
          LetterboxdFilm(title: title, url: href, posterUrl: poster),
        );
      }

      if (pageItems.isEmpty) break;

      // De-duplicate by absolute URL within this page (global dedup is already handled by seenHref)
      final uniq = <String, LetterboxdFilm>{};
      for (final f in pageItems) {
        uniq[f.url] = f;
      }
      all.addAll(uniq.values);

      page++;
      if (page > 50) break; // hard stop to avoid infinite loops
    }

    if (all.isEmpty) {
      // fallback to cache if exists
      final cached = prefs.getString('${_cacheKeyFor(username)}_watchlist');
      if (cached != null) {
        final list = (jsonDecode(cached) as List)
            .map((e) => LetterboxdFilm.fromJson(e))
            .toList();
        if (list.isNotEmpty) return list;
      }
      throw Exception('Watchlist boş veya seçiciler uyumsuz');
    }

    try {
      await prefs.setString(
        '${_cacheKeyFor(username)}_watchlist',
        jsonEncode(all.map((e) => e.toJson()).toList()),
      );
      await prefs.setInt(
        '${_cacheKeyFor(username)}_watchlist_time',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}

    return all;
  }

  /// Sync Letterboxd WATCHLIST into Firestore under users/{uid}
  /// Writes: users/{uid}.watchlistKeys (all keys), users/{uid}.watchlist (first N lite items), and upserts catalog_films
  static Future<void> syncWatchlistToFirestore({
    String? uid,
    required String lbUsername,
    int liteLimit = 30,
  }) async {
    final auth = FirebaseAuth.instance;
    final me = uid ?? auth.currentUser?.uid;
    if (me == null) {
      throw StateError('No Firebase user. Call FirebaseAuth.signIn first.');
    }

    // 1) Scrape watchlist
    final films = await fetchWatchlist(lbUsername);

    // 2) Upsert catalog in chunks
    const int batchSize =
        50; // reuse catalog helper signature (List<LetterboxdFilm>)
    for (int i = 0; i < films.length; i += batchSize) {
      final end = (i + batchSize < films.length) ? i + batchSize : films.length;
      await _upsertCatalog(films.sublist(i, end));
    }

    // 3) Persist on user profile
    final db = FirebaseFirestore.instance;
    final doc = db.collection('users').doc(me);

    final keys = LetterboxdFilm.keysOf(films);
    final lite = films
        .take(liteLimit)
        .map(
          (f) => {
            'title': f.title,
            'url': f.url,
            'posterUrl': f.posterUrl,
            'key': f.key,
          },
        )
        .toList();

    await doc.set({
      'lbUsername': lbUsername,
      'watchlistKeys': keys,
      'watchlist': lite,
      'watchlistUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Utility: chunks a list into parts of size [n]
  static List<List<T>> _chunk<T>(List<T> list, int n) {
    final chunks = <List<T>>[];
    for (var i = 0; i < list.length; i += n) {
      final end = (i + n < list.length) ? i + n : list.length;
      chunks.add(list.sublist(i, end));
    }
    return chunks;
  }

  /// Finds other users who share at least [minCommon] favorites with the current user.
  /// Strategy: 1) read my favoritesKeys; 2) query candidates with array-contains-any in 10-key chunks; 3) compute exact intersections client-side; 4) resolve common films via catalog
  static Future<List<MatchResult>> findMatchesForCurrentUser({
    int minCommon = 1,
    int limit = 50,
  }) async {
    final auth = FirebaseAuth.instance;
    final me = auth.currentUser;
    if (me == null) throw StateError('No Firebase user');

    final db = FirebaseFirestore.instance;

    // 1) get my keys
    final myDoc = await db.collection('users').doc(me.uid).get();
    final myKeys = List<String>.from(
      (myDoc.data() ?? const {})['favoritesKeys'] ?? const [],
    );
    if (myKeys.isEmpty) return const [];

    // 2) get candidate docs using array-contains-any (max 10 terms per query)
    final candidates = <String, Map<String, dynamic>>{}; // uid -> data
    for (final part in _chunk(myKeys, 10)) {
      final snap = await db
          .collection('users')
          .where('favoritesKeys', arrayContainsAny: part)
          .limit(limit)
          .get();
      for (final d in snap.docs) {
        if (d.id == me.uid) continue; // skip self
        candidates[d.id] = d.data();
      }
    }

    // 3) compute intersections
    final mySet = myKeys.toSet();
    final results = <MatchResult>[];
    for (final entry in candidates.entries) {
      final uid = entry.key;
      final data = entry.value;
      final theirKeys = List<String>.from(data['favoritesKeys'] ?? const []);
      if (theirKeys.isEmpty) continue;
      final inter = mySet.intersection(theirKeys.toSet()).toList();
      if (inter.length < minCommon) continue;

      // 4) resolve film docs from catalog for UI
      final commonFilmDocs = await Future.wait(
        inter.map((k) async {
          final doc = await db.collection('catalog_films').doc(k).get();
          if (!doc.exists) return null;
          final m = doc.data()!;
          return LetterboxdFilm(
            title: (m['title'] ?? '') as String,
            url: (m['url'] ?? '') as String,
            posterUrl: (m['posterUrl'] ?? '') as String,
            key: k,
          );
        }),
      );

      results.add(
        MatchResult(
          otherUid: uid,
          otherDisplayName: data['displayName'] as String?,
          commonKeys: inter,
          commonFilms: commonFilmDocs.whereType<LetterboxdFilm>().toList(),
        ),
      );
    }

    // 5) sort by most in common
    results.sort((a, b) => b.commonCount.compareTo(a.commonCount));
    return results;
  }

  /// Optional: also sync low ratings as `dislikedKeys` if you want to avoid pairing on hated films
  static Future<void> syncDislikedToFirestore({
    String? uid,
    required String lbUsername,
  }) async {
    final auth = FirebaseAuth.instance;
    final me = uid ?? auth.currentUser?.uid;
    if (me == null) throw StateError('No Firebase user');
    final disliked = await fetchDisliked(lbUsername);
    await _upsertCatalog(disliked);
    final db = FirebaseFirestore.instance;
    await db.collection('users').doc(me).set({
      'dislikedKeys': LetterboxdFilm.keysOf(disliked),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Call from app shutdown if needed
  static void disposeHttp() {
    try {
      _Http.client.close();
    } catch (_) {}
  }
}
