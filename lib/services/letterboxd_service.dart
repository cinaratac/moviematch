import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fluttergirdi/services/match_service.dart';

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

  /// GET with timeout & retry
  static Future<http.Response?> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 30),
    int retries = 2,
  }) async {
    http.Response? res;
    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        final h = <String, String>{};
        if (headers != null) h.addAll(headers);
        res = await client.get(uri, headers: h).timeout(timeout);
        if (res.statusCode == 200) return res;
        if (attempt == retries) return res;
      } on TimeoutException {
        if (attempt == retries) rethrow;
      } catch (_) {
        if (attempt == retries) rethrow;
      }
      await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
    }
    return res;
  }
}

class LetterboxdFilm {
  final String title;
  final String url;
  final String posterUrl;
  final String key;

  LetterboxdFilm({
    required this.title,
    required this.url,
    required this.posterUrl,
    String? key,
  }) : key = key ?? LetterboxdFilm._deriveKey(url, title);

  Map<String, dynamic> toMap() => {
    'title': title,
    'url': url,
    'posterUrl': posterUrl,
    'key': key,
  };

  Map<String, dynamic> toJson() => toMap();

  static LetterboxdFilm fromMap(Map<String, dynamic> json) => LetterboxdFilm(
    title: json['title'] ?? '',
    url: json['url'] ?? '',
    posterUrl: json['posterUrl'] ?? '',
    key: json['key'],
  );

  static LetterboxdFilm fromJson(Map<String, dynamic> json) => fromMap(json);

  static List<String> keysOf(List<LetterboxdFilm> films) =>
      films.map((f) => f.key).where((k) => k.isNotEmpty).toList();

  static String filmKeyFromHref(String href) => _deriveKey(href, '');

  static String _deriveKey(String href, String titleFallback) {
    try {
      final u = Uri.parse(href);
      final parts = u.path.split('/').where((e) => e.isNotEmpty).toList();
      final idx = parts.indexOf('film');
      if (idx != -1 && idx + 1 < parts.length) {
        final slug = parts[idx + 1].toLowerCase();
        if (slug.isNotEmpty) return 'film:$slug';
      }
    } catch (_) {}
    final slug = titleFallback
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return slug.isNotEmpty ? 'film:$slug' : '';
  }
}

class LetterboxdService {
  static const Map<String, String> imageHeaders = {
    'Referer': 'https://letterboxd.com/',
    'User-Agent': 'Mozilla/5.0',
  };
  static String _cacheKeyFor(String username) =>
      'lb_cache_${username.toLowerCase()}';

  static const Map<String, String> _reqHeaders = {
    'User-Agent': _kDefaultUa,
    'Accept-Language': _kAcceptLang,
    'Referer': 'https://letterboxd.com/',
  };

  static Future<T> _retryFirestore<T>(Future<T> Function() op) async {
    int attempts = 0;
    while (true) {
      try {
        return await op();
      } catch (e) {
        if (attempts >= 4) rethrow;
        final err = e.toString().toLowerCase();
        if (err.contains('unavailable') ||
            err.contains('network') ||
            err.contains('offline')) {
          attempts++;
          await Future.delayed(Duration(milliseconds: 500 * attempts));
        } else {
          rethrow;
        }
      }
    }
  }

  static Future<List<LetterboxdFilm>> _parseFilmsFromElements(
    List<dom.Element> elements,
  ) async {
    final items = <LetterboxdFilm>[];
    final seenHref = <String>{};

    for (final li in elements) {
      final a = li.querySelector('a.frame') ?? li.querySelector('a');
      final img = li.querySelector('img.image') ?? li.querySelector('img');
      final rc = li.querySelector('div.react-component');
      final divPoster =
          li.querySelector('div.film-poster') ?? li.querySelector('div.poster');

      if (a == null && rc == null && img == null && divPoster == null) continue;

      String title =
          (divPoster?.attributes['data-film-name'] ??
                  a?.attributes['data-original-title'] ??
                  img?.attributes['alt'] ??
                  rc?.attributes['data-item-name'] ??
                  rc?.attributes['data-item-full-display-name'] ??
                  a?.querySelector('.frame-title')?.text ??
                  '')
              .replaceAll(RegExp(r'^Poster for '), '')
              .trim();

      if (title.isEmpty) continue;

      String href =
          divPoster?.attributes['data-film-link'] ??
          rc?.attributes['data-item-link'] ??
          rc?.attributes['data-target-link'] ??
          a?.attributes['href'] ??
          '';

      if (href.isEmpty) continue;
      if (href.startsWith('//')) href = 'https:$href';
      if (href.startsWith('/')) href = 'https://letterboxd.com$href';
      if (!seenHref.add(href)) continue;

      String? filmId =
          divPoster?.attributes['data-film-id'] ??
          rc?.attributes['data-film-id'] ??
          img?.attributes['data-film-id'] ??
          li.attributes['data-film-id'];

      if (filmId == null) {
        final pId = rc?.attributes['data-postered-identifier'];
        if (pId != null) {
          final match = RegExp(r'"uid":"film:(\d+)"').firstMatch(pId);
          if (match != null) filmId = match.group(1);
        }
      }

      String? slug =
          divPoster?.attributes['data-film-slug'] ??
          rc?.attributes['data-item-slug'] ??
          img?.attributes['data-item-slug'] ??
          li.attributes['data-film-slug'];

      if (slug == null && href.contains('/film/')) {
        final parts = Uri.parse(href).pathSegments;
        final idx = parts.indexOf('film');
        if (idx != -1 && idx + 1 < parts.length) slug = parts[idx + 1];
      }

      String? poster;

      if (filmId != null && slug != null && slug.isNotEmpty) {
        poster = _buildPosterFromIdSlug(filmId, slug, w: 300, h: 450);
      } else {
        poster = (img?.attributes['srcset'] ?? img?.attributes['data-srcset'])
            ?.split(',')
            .last
            .trim()
            .split(' ')
            .first;
        poster ??= img?.attributes['src'] ?? img?.attributes['data-src'];
      }

      if (poster != null && poster.startsWith('//')) poster = 'https:$poster';
      if (poster != null && poster.startsWith('/'))
        poster = 'https://a.ltrbxd.com$poster';

      if (poster != null &&
          (poster.contains('empty-poster') || !_looksLikeImageUrl(poster))) {
        poster = '';
      }
      poster ??= '';

      items.add(LetterboxdFilm(title: title, url: href, posterUrl: poster));
    }
    return items;
  }

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
      ...doc.querySelectorAll('li.poster-container'),
    ];

    final items = await _parseFilmsFromElements(candidates);

    if (items.isEmpty) {
      final cached = prefs.getString('${_cacheKeyFor(username)}$cacheSuffix');
      if (cached != null) {
        final list = (jsonDecode(cached) as List)
            .map((e) => LetterboxdFilm.fromJson(e))
            .toList();
        if (list.isNotEmpty) return list;
      }
      return [];
    }

    final uniq = <String, LetterboxdFilm>{};
    for (final f in items) uniq[f.url] = f;
    final result = uniq.values.toList();

    try {
      await prefs.setString(
        '${_cacheKeyFor(username)}$cacheSuffix',
        jsonEncode(result.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}

    return result;
  }

  static Future<List<LetterboxdFilm>> fetchHalfStar(String username) {
    return _fetchRated(username, '.5', cacheSuffix: '_rated05');
  }

  static Future<List<LetterboxdFilm>> fetchOneStar(String username) {
    return _fetchRated(username, '1', cacheSuffix: '_rated1');
  }

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
    for (final f in [...half, ...one]) map[f.url] = f;
    return map.values.toList();
  }

  static Future<List<LetterboxdFilm>> fetchFiveStar(String username) async {
    return _fetchRated(username, '5', cacheSuffix: '_rated5');
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

      final section = doc.querySelector('#favourites');
      if (section != null) {
        final lis = section.querySelectorAll('li');
        final films = await _parseFilmsFromElements(lis);

        if (films.isNotEmpty) {
          final deduped = <LetterboxdFilm>[];
          final seen = <String>{};
          for (final f in films) {
            if (seen.add(f.url)) deduped.add(f);
          }
          final result = deduped.take(4).toList();

          await prefs.setString(
            _cacheKeyFor(username),
            jsonEncode(result.map((e) => e.toJson()).toList()),
          );
          return result;
        }
      }
      return [];
    } catch (e) {
      final cached = prefs.getString(_cacheKeyFor(username));
      if (cached != null) {
        return (jsonDecode(cached) as List)
            .map((e) => LetterboxdFilm.fromJson(e))
            .toList();
      }
      return [];
    }
  }

  static Future<List<LetterboxdFilm>> fetchWatchlist(String username) async {
    final prefs = await SharedPreferences.getInstance();
    final List<LetterboxdFilm> all = [];
    int page = 1;

    while (page <= 3) {
      final uri = page == 1
          ? Uri.parse('https://letterboxd.com/$username/watchlist/')
          : Uri.parse('https://letterboxd.com/$username/watchlist/page/$page/');

      final res = await _Http.get(uri, headers: _reqHeaders);
      if (res == null || res.statusCode != 200) break;

      final doc = html.parse(res.body);

      final candidates = <dom.Element>[
        ...doc.querySelectorAll('ul.poster-list li.poster-container'),
        ...doc.querySelectorAll('ul.grid li.griditem'),
        ...doc.querySelectorAll('div.poster-grid li.griditem'),
      ];

      final items = await _parseFilmsFromElements(candidates);

      if (items.isEmpty) break;
      all.addAll(items);

      final next = doc.querySelector('.paginate-nextprev a.next');
      if (next == null) break;

      page++;
    }

    if (all.isEmpty) {
      final cached = prefs.getString('${_cacheKeyFor(username)}_watchlist');
      if (cached != null)
        return (jsonDecode(cached) as List)
            .map((e) => LetterboxdFilm.fromJson(e))
            .toList();
    } else {
      prefs.setString(
        '${_cacheKeyFor(username)}_watchlist',
        jsonEncode(all.map((e) => e.toJson()).toList()),
      );
    }
    return all;
  }

  static String? _firstImageUrl(dynamic node) {
    if (node is String && (node.endsWith('.jpg') || node.endsWith('.png')))
      return node;
    if (node is Map) {
      for (final v in node.values) {
        final r = _firstImageUrl(v);
        if (r != null) return r;
      }
    }
    return null;
  }

  static bool _looksLikeImageUrl(String? u) {
    if (u == null) return false;
    if (u.contains('empty-poster')) return false;
    final cleanUrl = u.split('?').first.toLowerCase();
    return cleanUrl.endsWith('.jpg') ||
        cleanUrl.endsWith('.png') ||
        cleanUrl.endsWith('.webp');
  }

  static String _buildPosterFromIdSlug(
    String id,
    String slug, {
    int w = 300,
    int h = 450,
  }) {
    final shard = id.split('').join('/');
    return 'https://a.ltrbxd.com/resized/film-poster/$shard/$id-$slug-0-$w-0-$h-crop.jpg';
  }

  static Future<void> _upsertCatalog(List<LetterboxdFilm> films) async {
    final db = FirebaseFirestore.instance;
    await _retryFirestore(() async {
      final batch = db.batch();
      for (final f in films) {
        if (f.key.isEmpty) continue;
        final doc = db.collection('catalog_films').doc(f.key);
        batch.set(doc, {
          'title': f.title,
          'url': f.url,
          'posterUrl': f.posterUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    });
  }

  // =========================================================================
  // KRİTİK GÜNCELLEME: Delta Sync Fonksiyonu
  // MANUEL FİLMLERİ SİLMEZ, SADECE YENİLERİ EKLER VE KORUR.
  // =========================================================================
  static Future<void> fullSyncOnboarding({
    required String uid,
    required String lbUsername,
  }) async {
    Future<List<LetterboxdFilm>> safeFetch(
      Future<List<LetterboxdFilm>> Function(String) f,
    ) async {
      try {
        return await f(lbUsername);
      } catch (_) {
        return [];
      }
    }

    // 1. Verileri Çek
    List<LetterboxdFilm> favs = [];
    try {
      favs = await fetchFavorites(lbUsername);
    } catch (e) {
      if (e.toString().contains('HTTP 404')) {
        throw Exception('Letterboxd kullanıcısı bulunamadı: $lbUsername');
      }
    }

    final results = await Future.wait([
      safeFetch(fetchFiveStar),
      safeFetch(fetchDisliked),
      safeFetch(fetchWatchlist),
    ]);

    final fiveStar = results[0];
    final disliked = results[1];
    final watchlist = results[2];

    final db = FirebaseFirestore.instance;
    final userRef = db.collection('users').doc(uid);
    final tasteRef = db.collection('userTasteProfiles').doc(uid);

    // 2. Kullanıcının MEVCUT (manuel) verilerini Firestore'dan Oku
    final userSnap = await userRef.get();
    final Map<String, dynamic> currentData = userSnap.data() ?? {};

    final Map<String, String> filmSources = Map<String, String>.from(
      currentData['filmSources'] ?? {},
    );

    final existingFavKeys = List<String>.from(
      currentData['favoritesKeys'] ?? [],
    );
    final existingWlKeys = List<String>.from(
      currentData['watchlistKeys'] ?? [],
    );
    final existingFiveKeys = List<String>.from(
      currentData['fiveStarKeys'] ?? [],
    );
    final existingDisKeys = List<String>.from(
      currentData['dislikedKeys'] ?? [],
    );

    final existingFavLite = List<Map<String, dynamic>>.from(
      currentData['favorites'] ?? [],
    );
    final existingWlite = List<Map<String, dynamic>>.from(
      currentData['watchlist'] ?? [],
    );

    final Set<String> allExistingKeys = {
      ...existingFavKeys,
      ...existingWlKeys,
      ...existingFiveKeys,
      ...existingDisKeys,
    };

    // 3. Optimizasyon: Sadece veritabanında daha önce OLMAYAN yepyeni filmleri kataloğa yaz.
    final allScrapedFilms = [...favs, ...fiveStar, ...disliked, ...watchlist];
    final List<LetterboxdFilm> brandNewFilms = [];
    final Set<String> processedKeys = {};

    for (final f in allScrapedFilms) {
      if (f.key.isNotEmpty &&
          !allExistingKeys.contains(f.key) &&
          processedKeys.add(f.key)) {
        brandNewFilms.add(f);
      }
    }

    for (int i = 0; i < brandNewFilms.length; i += 50) {
      final end = (i + 50 < brandNewFilms.length)
          ? i + 50
          : brandNewFilms.length;
      await _upsertCatalog(brandNewFilms.sublist(i, end));
    }

    // 4. Listeleri Harmanlama (Merge) - Manuel olanları koru
    final newFavKeys = LetterboxdFilm.keysOf(favs);
    final newWlKeys = LetterboxdFilm.keysOf(watchlist);
    final newFiveKeys = LetterboxdFilm.keysOf(fiveStar);
    final newDisKeys = LetterboxdFilm.keysOf(disliked);

    List<String> mergeKeyList({
      required List<String> existingKeys,
      required List<String> newLbKeys,
      required Map<String, String> sources,
    }) {
      // sources map'inde 'manual' olarak işaretlenmemiş veya kaynak bilgisi olmayan (eski veri) her şeyi manuel kabul et (esnek koruma)
      final manualKeys = existingKeys
          .where((k) => sources[k] == 'manual' || !sources.containsKey(k))
          .toList();

      for (final k in existingKeys) {
        if (sources[k] == 'letterboxd') {
          sources.remove(k);
        }
      }

      for (final k in newLbKeys) {
        if (sources[k] != 'manual') {
          sources[k] = 'letterboxd';
        }
      }
      return {...manualKeys, ...newLbKeys}.toList();
    }

    final finalFavKeys = mergeKeyList(
      existingKeys: existingFavKeys,
      newLbKeys: newFavKeys,
      sources: filmSources,
    );
    final finalWlKeys = mergeKeyList(
      existingKeys: existingWlKeys,
      newLbKeys: newWlKeys,
      sources: filmSources,
    );
    final finalFiveKeys = mergeKeyList(
      existingKeys: existingFiveKeys,
      newLbKeys: newFiveKeys,
      sources: filmSources,
    );
    final finalDisKeys = mergeKeyList(
      existingKeys: existingDisKeys,
      newLbKeys: newDisKeys,
      sources: filmSources,
    );

    final newFavLite = favs
        .take(4)
        .map(
          (f) => {
            'title': f.title,
            'url': f.url,
            'posterUrl': f.posterUrl,
            'key': f.key,
            'source': 'letterboxd',
          },
        )
        .toList();

    final newWLite = watchlist
        .take(30)
        .map(
          (f) => {
            'title': f.title,
            'url': f.url,
            'posterUrl': f.posterUrl,
            'key': f.key,
            'source': 'letterboxd',
          },
        )
        .toList();

    List<Map<String, dynamic>> mergeLiteList({
      required List<Map<String, dynamic>> existingLite,
      required List<Map<String, dynamic>> newLbLite,
    }) {
      // Manuel işaretlileri veya source etiketi olmayan (eski kayıtları) koru
      final manualLite = existingLite
          .where(
            (item) => item['source'] == 'manual' || !item.containsKey('source'),
          )
          .toList();

      final Map<String, Map<String, dynamic>> uniqMap = {};
      for (final item in manualLite) {
        final k = (item['key'] ?? '').toString();
        if (k.isNotEmpty) uniqMap[k] = item;
      }
      for (final item in newLbLite) {
        final k = (item['key'] ?? '').toString();
        if (k.isNotEmpty && !uniqMap.containsKey(k)) {
          uniqMap[k] = item;
        }
      }
      return uniqMap.values.toList();
    }

    final finalFavLite = mergeLiteList(
      existingLite: existingFavLite,
      newLbLite: newFavLite,
    );
    final finalWlite = mergeLiteList(
      existingLite: existingWlite,
      newLbLite: newWLite,
    );

    final tasteSnap = await tasteRef.get();
    final dynamic rawPosters = (tasteSnap.data() ?? {})['posters'];
    final Map<String, String> existingPosters = rawPosters is Map
        ? Map<String, String>.from(rawPosters)
        : {};

    final postersMap = <String, String>{}..addAll(existingPosters);
    for (var f in [...fiveStar, ...disliked]) {
      if (f.key.isNotEmpty && f.posterUrl.isNotEmpty) {
        postersMap[f.key] = f.posterUrl;
      }
    }

    // 5. Veritabanına Güvenli Batch Yazma
    await _retryFirestore(() async {
      final batch = db.batch();

      batch.set(userRef, {
        'lbUsername': lbUsername,
        'filmSources': filmSources,
        'favoritesKeys': finalFavKeys,
        'favorites': finalFavLite,
        'watchlistKeys': finalWlKeys,
        'watchlist': finalWlite,
        'watchlistUpdatedAt': FieldValue.serverTimestamp(),
        'fiveStarKeys': finalFiveKeys,
        'dislikedKeys': finalDisKeys,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastSyncedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(tasteRef, {
        'letterboxdUsername': lbUsername,
        'loved': finalFiveKeys,
        'disliked': finalDisKeys,
        'posters': postersMap,
        'computedAtMs': DateTime.now().millisecondsSinceEpoch,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();
    });
  }
}
