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
        if (err.contains('unavailable') || err.contains('network') || err.contains('offline')) {
          attempts++;
          await Future.delayed(Duration(milliseconds: 500 * attempts));
        } else {
          rethrow;
        }
      }
    }
  }

  // --- KUSURSUZ PARSER (Ekran görüntüsündeki yapıya özel revize edildi) ---
  static Future<List<LetterboxdFilm>> _parseFilmsFromElements(List<dom.Element> elements) async {
    final items = <LetterboxdFilm>[];
    final seenHref = <String>{};

    for (final li in elements) {
      final a = li.querySelector('a.frame') ?? li.querySelector('a');
      final img = li.querySelector('img.image') ?? li.querySelector('img');
      final rc = li.querySelector('div.react-component');
      // GÖRÜNTÜDEKİ ASIL KUTU: div.film-poster
      final divPoster = li.querySelector('div.film-poster') ?? li.querySelector('div.poster'); 

      if (a == null && rc == null && img == null && divPoster == null) continue;

      // 1. BAŞLIK: Önceliği doğrudan data-film-name attributuna veriyoruz.
      String title = (divPoster?.attributes['data-film-name'] ??
              a?.attributes['data-original-title'] ??
              img?.attributes['alt'] ??
              rc?.attributes['data-item-name'] ??
              rc?.attributes['data-item-full-display-name'] ??
              a?.querySelector('.frame-title')?.text ??
              '')
          .replaceAll(RegExp(r'^Poster for '), '')
          .trim();
          
      if (title.isEmpty) continue;

      // 2. LİNK (HREF): Önceliği doğrudan data-film-link attributuna veriyoruz.
      String href = divPoster?.attributes['data-film-link'] ??
          rc?.attributes['data-item-link'] ??
          rc?.attributes['data-target-link'] ??
          a?.attributes['href'] ??
          '';
          
      if (href.isEmpty) continue;
      if (href.startsWith('//')) href = 'https:$href';
      if (href.startsWith('/')) href = 'https://letterboxd.com$href';
      if (!seenHref.add(href)) continue;

      // 3. FİLM ID VE SLUG
      final filmId = divPoster?.attributes['data-film-id'] ?? rc?.attributes['data-film-id'] ?? img?.attributes['data-film-id'] ?? li.attributes['data-film-id'];
      String? slug = divPoster?.attributes['data-film-slug'] ?? rc?.attributes['data-item-slug'] ?? img?.attributes['data-item-slug'] ?? li.attributes['data-film-slug'];
      
      // Eğer slug html'de açıkça yoksa (favorilerde genelde olmaz), linkin içinden söküp çıkarıyoruz.
      if (slug == null && href.contains('/film/')) {
         final parts = Uri.parse(href).pathSegments;
         final idx = parts.indexOf('film');
         if (idx != -1 && idx + 1 < parts.length) {
           slug = parts[idx + 1];
         }
      }

      String? poster;

      // 4. POSTER OLUŞTURMA: ID ve Slug elimizdeyse, Letterboxd'ın resimlerini (lazy load kaynaklı bulanıklıkları) beklemeden KENDİMİZ yüksek çözünürlüklü üretiyoruz.
      if (filmId != null && slug != null && slug.isNotEmpty) {
        poster = _buildPosterFromIdSlug(filmId, slug, w: 300, h: 450);
      } else {
        // Fallback
        poster = (img?.attributes['srcset'] ?? img?.attributes['data-srcset'])?.split(',').last.trim().split(' ').first;
        poster ??= img?.attributes['src'] ?? img?.attributes['data-src'];
      }

      if (poster != null && poster.startsWith('//')) poster = 'https:$poster';
      if (poster != null && poster.startsWith('/')) poster = 'https://a.ltrbxd.com$poster';
      
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
    final candidates = <dom.Element>[
      ...doc.querySelectorAll('div.poster-grid ul.grid li.griditem'),
      ...doc.querySelectorAll('section.col-main .poster-grid ul.grid li.griditem'),
      ...doc.querySelectorAll('section.col-main ul.grid li.griditem'),
      ...doc.querySelectorAll('ul.grid.-p70 li.griditem'),
      ...doc.querySelectorAll('ul.grid li.griditem'),
      ...doc.querySelectorAll('li.poster-container'),
    ];

    final items = await _parseFilmsFromElements(candidates);

    if (items.isEmpty) {
      final cached = prefs.getString('${_cacheKeyFor(username)}$cacheSuffix');
      if (cached != null) {
        final list = (jsonDecode(cached) as List).map((e) => LetterboxdFilm.fromJson(e)).toList();
        if (list.isNotEmpty) return list;
      }
      return []; // Hata fırlatma, boş liste dön
    }

    final uniq = <String, LetterboxdFilm>{};
    for (final f in items) uniq[f.url] = f;
    final result = uniq.values.toList();

    try {
      await prefs.setString('${_cacheKeyFor(username)}$cacheSuffix', jsonEncode(result.map((e) => e.toJson()).toList()));
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

  // --- GARANTİLİ FAVORİ ÇEKİCİ ---
  static Future<List<LetterboxdFilm>> fetchFavorites(String username) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final url = Uri.parse('https://letterboxd.com/$username/');
      final res = await _Http.get(url, headers: _Http.baseHeaders(referer: 'https://letterboxd.com/'));
      if (res == null || res.statusCode != 200) throw Exception('HTTP ${res?.statusCode}');
      
      final doc = html.parse(res.body);
      
      // Görüntüdeki gibi tam id='#favourites'
      final section = doc.querySelector('#favourites');
      if (section != null) {
        final lis = section.querySelectorAll('li'); // ul altındaki tüm li'leri al
        final films = await _parseFilmsFromElements(lis);

        if (films.isNotEmpty) {
          final deduped = <LetterboxdFilm>[];
          final seen = <String>{};
          for (final f in films) {
            if (seen.add(f.url)) deduped.add(f);
          }
          final result = deduped.take(4).toList(); 
          
          await prefs.setString(_cacheKeyFor(username), jsonEncode(result.map((e) => e.toJson()).toList()));
          return result;
        }
      }
      return []; // Hata fırlatmak yerine boş liste dönüyoruz ki sistem çökmesin
    } catch (_) {
      final cached = prefs.getString(_cacheKeyFor(username));
      if (cached != null) {
        return (jsonDecode(cached) as List).map((e) => LetterboxdFilm.fromJson(e)).toList();
      }
      return [];
    }
  }

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
      
      final candidates = <dom.Element>[
         ...doc.querySelectorAll('ul.poster-list li.poster-container'),
         ...doc.querySelectorAll('ul.grid li.griditem'),
         ...doc.querySelectorAll('div.poster-grid li.griditem'),
      ];
      
      final items = await _parseFilmsFromElements(candidates);
      
      if(items.isEmpty) break;
      all.addAll(items);
      
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
  }
}