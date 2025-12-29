import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


// Gerekli servis importları

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

class MatchResult {
  final String otherUid;
  final String? otherDisplayName;
  final List<String> commonKeys;
  final List<LetterboxdFilm> commonFilms;
  final int commonCount;

  MatchResult({
    required this.otherUid,
    required this.otherDisplayName,
    required this.commonKeys,
    required this.commonFilms,
  }) : commonCount = commonKeys.length;
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

  // --- Firestore Retry Helper ---
  static Future<T> _retryFirestore<T>(Future<T> Function() op) async {
    int attempts = 0;
    while (true) {
      try {
        return await op();
      } catch (e) {
        if (attempts >= 4) rethrow; 
        final err = e.toString().toLowerCase();
        if (err.contains('unavailable') || err.contains('network') || err.contains('offline')) {
          attempts++;
          await Future.delayed(Duration(milliseconds: 500 * attempts));
        } else {
          rethrow;
        }
      }
    }
  }

  // --- Core Parser Logic (Düzeltildi ve Merkezileştirildi) ---
  
  static Future<List<LetterboxdFilm>> _parseFilmsFromElements(List<dom.Element> elements) async {
    final items = <LetterboxdFilm>[];
    final seenHref = <String>{};

    for (final li in elements) {
      // Farklı element yapılarını kontrol et
      final a = li.querySelector('a.frame') ?? li.querySelector('a.frame.has-menu') ?? li.querySelector('a');
      final img = li.querySelector('img.image') ?? li.querySelector('img');
      final rc = li.querySelector('div.react-component');
      final divPoster = li.querySelector('div.poster'); // Bazı durumlarda div.poster ana taşıyıcıdır

      // En azından biri olmalı
      if (a == null && rc == null && img == null && divPoster == null) continue;

      // 1. Başlık Çıkarma
      String title = (a?.attributes['data-original-title'] ??
              img?.attributes['alt'] ??
              rc?.attributes['data-item-name'] ??
              rc?.attributes['data-item-full-display-name'] ??
              divPoster?.attributes['data-film-name'] ?? // Eklenen kontrol
              a?.querySelector('.frame-title')?.text ??
              '')
          .replaceAll(RegExp(r'^Poster for '), '')
          .trim();
          
      if (title.isEmpty) continue;

      // 2. Link (Href) Çıkarma
      String href = a?.attributes['href'] ??
          rc?.attributes['data-item-link'] ??
          rc?.attributes['data-target-link'] ??
          divPoster?.attributes['data-target-link'] ?? // Eklenen kontrol
          '';
          
      if (href.isEmpty) continue;
      if (href.startsWith('//')) href = 'https:$href';
      if (href.startsWith('/')) href = 'https://letterboxd.com$href';
      if (!seenHref.add(href)) continue;

      // 3. Poster URL Çıkarma
      String? poster = (img?.attributes['srcset'] ?? img?.attributes['data-srcset'])
          ?.split(',')
          .last
          .trim()
          .split(' ')
          .first;
      poster ??= img?.attributes['src'] ?? img?.attributes['data-src'];

      if (poster != null && poster.startsWith('//')) poster = 'https:$poster';
      if (poster != null && poster.startsWith('/')) poster = 'https://a.ltrbxd.com$poster';

      // 4. Poster Fallback ve İyileştirme
      final filmId = rc?.attributes['data-film-id'] ?? img?.attributes['data-film-id'] ?? divPoster?.attributes['data-film-id'] ?? li.attributes['data-film-id'];
      final slug = rc?.attributes['data-item-slug'] ?? img?.attributes['data-item-slug'] ?? divPoster?.attributes['data-film-slug'] ?? li.attributes['data-film-slug'];
      
      final isPlaceholder = poster != null && poster.contains('empty-poster');
      final looksImg = _looksLikeImageUrl(poster);

      // ID ve Slug varsa yüksek çözünürlüklü poster oluştur
      if (filmId != null && slug != null) {
        poster = _buildPosterFromIdSlug(filmId, slug, w: 300, h: 450);
      } else if (!looksImg || isPlaceholder) {
        // Detay sayfasından çekmeyi dene
        final details = rc?.attributes['data-details-endpoint'] ?? a?.attributes['data-details-endpoint'];
        if (details != null) {
          final via = await _resolvePosterFromDetails(details);
          if (via != null) poster = via;
        }
      }

      if ((poster == null || !_looksLikeImageUrl(poster)) && (rc != null || img != null)) {
        final viaAttrs = _posterFromDataAttrs(rc: rc, img: img, w: 300, h: 450);
        if (viaAttrs != null) poster = viaAttrs;
      }

      if (poster != null && poster.startsWith('//')) poster = 'https:$poster';
      // Hala geçerli bir poster yoksa atla (veya placeholder kullanabilirsin)
      if (poster == null || !_looksLikeImageUrl(poster)) continue;

      items.add(LetterboxdFilm(title: title, url: href, posterUrl: poster));
    }
    return items;
  }

  // --- Scrapers ---

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
    // Tüm olası film liste elemanlarını topla
    final candidates = <dom.Element>[
      ...doc.querySelectorAll('div.poster-grid ul.grid li.griditem'),
      ...doc.querySelectorAll('section.col-main .poster-grid ul.grid li.griditem'),
      ...doc.querySelectorAll('section.col-main ul.grid li.griditem'),
      ...doc.querySelectorAll('ul.grid.-p70 li.griditem'),
      ...doc.querySelectorAll('ul.grid li.griditem'),
      ...doc.querySelectorAll('li.poster-container'), // Bunları da ekledik
    ];

    final items = await _parseFilmsFromElements(candidates);

    if (items.isEmpty) {
      final cached = prefs.getString('${_cacheKeyFor(username)}$cacheSuffix');
      if (cached != null) {
        final list = (jsonDecode(cached) as List).map((e) => LetterboxdFilm.fromJson(e)).toList();
        if (list.isNotEmpty) return list;
      }
      throw Exception('$rating★ film bulunamadı');
    }

    final uniq = <String, LetterboxdFilm>{};
    for (final f in items) uniq[f.url] = f;
    final result = uniq.values.toList();

    try {
      await prefs.setString('${_cacheKeyFor(username)}$cacheSuffix', jsonEncode(result.map((e) => e.toJson()).toList()));
      await prefs.setInt('${_cacheKeyFor(username)}${cacheSuffix}_time', DateTime.now().millisecondsSinceEpoch);
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
    try { half = await fetchHalfStar(username); } catch (_) {}
    try { one = await fetchOneStar(username); } catch (_) {}
    final map = <String, LetterboxdFilm>{};
    for (final f in [...half, ...one]) map[f.url] = f;
    return map.values.toList();
  }

  static Future<List<LetterboxdFilm>> fetchFiveStar(String username) async {
    return _fetchRated(username, '5', cacheSuffix: '_rated5');
  }

  // --- DÜZELTİLEN METOD ---
  static Future<List<LetterboxdFilm>> fetchFavorites(String username) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final url = Uri.parse('https://letterboxd.com/$username/');
      final res = await _Http.get(url, headers: _Http.baseHeaders(referer: 'https://letterboxd.com/'));
      if (res == null || res.statusCode != 200) throw Exception('HTTP ${res?.statusCode}');
      
      final doc = html.parse(res.body);
      
      // Favoriler bölümünü bul
      final section = doc.querySelector('section#favourites');
      // Daha esnek bir seçim
      var ul = section?.querySelector('ul.poster-list'); 
      ul ??= doc.querySelector('ul.poster-list.-p150') ?? doc.querySelector('ul.poster-list');

      if (ul != null) {
        // li.posteritem YERİNE li.poster-container veya genel li kullanıyoruz
        final lis = ul.querySelectorAll('li.poster-container, li.posteritem, li');
        
        // Ortak parser'ı kullan
        final films = await _parseFilmsFromElements(lis);

        if (films.isNotEmpty) {
          final deduped = <LetterboxdFilm>[];
          final seen = <String>{};
          for (final f in films) {
            if (seen.add(f.url)) deduped.add(f);
          }
          final result = deduped.take(4).toList(); // Sadece ilk 4 favori
          
          await prefs.setString(_cacheKeyFor(username), jsonEncode(result.map((e) => e.toJson()).toList()));
          return result;
        }
      }

      throw Exception('Favori filmler bulunamadı');

    } catch (_) {
      final cached = prefs.getString(_cacheKeyFor(username));
      if (cached != null) {
        return (jsonDecode(cached) as List).map((e) => LetterboxdFilm.fromJson(e)).toList();
      }
      rethrow;
    }
  }

  // --- DÜZELTİLEN METOD ---
  static Future<List<LetterboxdFilm>> fetchWatchlist(String username) async {
    final prefs = await SharedPreferences.getInstance();
    final List<LetterboxdFilm> all = [];
    int page = 1;
    
    while (page <= 3) { // Maksimum 3 sayfa (yaklaşık 90-100 film)
      final uri = page == 1
          ? Uri.parse('https://letterboxd.com/$username/watchlist/')
          : Uri.parse('https://letterboxd.com/$username/watchlist/page/$page/');
      
      final res = await _Http.get(uri, headers: _reqHeaders);
      if (res == null || res.statusCode != 200) break;
      
      final doc = html.parse(res.body);
      
      // Watchlist genellikle grid yapısındadır
      final candidates = <dom.Element>[
         ...doc.querySelectorAll('ul.poster-list li.poster-container'),
         ...doc.querySelectorAll('ul.grid li.griditem'),
         ...doc.querySelectorAll('div.poster-grid li.griditem'),
      ];
      
      // Ortak güçlü parser kullanımı
      final items = await _parseFilmsFromElements(candidates);
      
      if(items.isEmpty) break;
      all.addAll(items);
      
      // Sayfalama kontrolü: Eğer "sonraki sayfa" butonu yoksa dur
      final next = doc.querySelector('.paginate-nextprev a.next');
      if (next == null) break;
      
      page++;
    }
    
    if(all.isEmpty) {
       final cached = prefs.getString('${_cacheKeyFor(username)}_watchlist');
       if(cached != null) return (jsonDecode(cached) as List).map((e)=>LetterboxdFilm.fromJson(e)).toList();
    } else {
       prefs.setString('${_cacheKeyFor(username)}_watchlist', jsonEncode(all.map((e)=>e.toJson()).toList()));
    }
    return all;
  }

  // --- Helpers ---
  
  static Future<String?> _resolvePosterFromDetails(String? detailsPath) async {
    if (detailsPath == null) return null;
    try {
      final res = await _Http.get(Uri.parse('https://letterboxd.com$detailsPath'));
      if(res?.statusCode != 200) return null;
      return _firstImageUrl(jsonDecode(res!.body));
    } catch (_) { return null; }
  }

  static String? _firstImageUrl(dynamic node) {
    if (node is String && (node.endsWith('.jpg') || node.endsWith('.png'))) return node;
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
    return u.endsWith('.jpg') || u.endsWith('.png') || u.endsWith('.webp');
  }

  static String _buildPosterFromIdSlug(String id, String slug, {int w=300, int h=450}) {
    final shard = id.split('').join('/');
    return 'https://a.ltrbxd.com/resized/film-poster/$shard/$id-$slug-0-$w-0-$h-crop.jpg';
  }

  static String? _posterFromDataAttrs({dom.Element? rc, dom.Element? img, int w=300, int h=450}) {
    final id = rc?.attributes['data-film-id'] ?? img?.attributes['data-film-id'];
    final slug = rc?.attributes['data-item-slug'] ?? img?.attributes['data-item-slug'];
    if(id != null && slug != null) return _buildPosterFromIdSlug(id, slug, w:w, h:h);
    return null;
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

  static Future<void> fullSyncOnboarding({
    required String uid,
    required String lbUsername,
  }) async {
    Future<List<LetterboxdFilm>> safeFetch(Future<List<LetterboxdFilm>> Function(String) f) async {
      try { return await f(lbUsername); } catch (_) { return []; }
    }

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

    final allFilms = [...favs, ...fiveStar, ...disliked, ...watchlist];
    for (int i = 0; i < allFilms.length; i += 50) {
      final end = (i + 50 < allFilms.length) ? i + 50 : allFilms.length;
      await _upsertCatalog(allFilms.sublist(i, end));
    }

    final db = FirebaseFirestore.instance;
    final userRef = db.collection('users').doc(uid);
    final tasteRef = db.collection('userTasteProfiles').doc(uid);

    final favKeys = LetterboxdFilm.keysOf(favs);
    final wlKeys = LetterboxdFilm.keysOf(watchlist);
    final fiveKeys = LetterboxdFilm.keysOf(fiveStar);
    final disKeys = LetterboxdFilm.keysOf(disliked);

    final favLite = favs.take(4).map((f) => {
      'title': f.title, 'url': f.url, 'posterUrl': f.posterUrl, 'key': f.key
    }).toList();
    
    final wLite = watchlist.take(30).map((f) => {
      'title': f.title, 'url': f.url, 'posterUrl': f.posterUrl, 'key': f.key
    }).toList();

    final postersMap = <String, String>{};
    for (var f in [...fiveStar, ...disliked]) {
      if (f.key.isNotEmpty && f.posterUrl.isNotEmpty) {
        postersMap[f.key] = f.posterUrl;
      }
    }

    await _retryFirestore(() async {
      final batch = db.batch();
      batch.set(userRef, {
        'lbUsername': lbUsername,
        'favoritesKeys': favKeys,
        'favorites': favLite,
        'watchlistKeys': wlKeys,
        'watchlist': wLite,
        'watchlistUpdatedAt': FieldValue.serverTimestamp(),
        'fiveStarKeys': fiveKeys,
        'dislikedKeys': disKeys,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastSyncedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(tasteRef, {
        'letterboxdUsername': lbUsername,
        'loved': fiveKeys,
        'disliked': disKeys,
        'posters': postersMap,
        'computedAtMs': DateTime.now().millisecondsSinceEpoch,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();
    });

    try {
      await _retryFirestore(() async {
        await MatchService.instance.autoCreateMatchesFiveOnly(uid, minCommonFive: 1);
      });
    } catch (_) {}
  }
}