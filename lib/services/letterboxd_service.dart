import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'package:fluttergirdi/services/catalog_service.dart';

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
  final int? year;

  LetterboxdFilm({
    required this.title,
    required this.url,
    required this.posterUrl,
    String? key,
    this.year,
  }) : key = key ?? LetterboxdFilm._deriveKey(url, title);

  Map<String, dynamic> toMap() => {
    'title': title,
    'url': url,
    'posterUrl': posterUrl,
    'key': key,
    if (year != null) 'year': year,
  };

  Map<String, dynamic> toJson() => toMap();

  static LetterboxdFilm fromMap(Map<String, dynamic> json) => LetterboxdFilm(
    title: json['title'] ?? '',
    url: json['url'] ?? '',
    // Eski cihaz cache'lerinde Letterboxd CDN URL'leri bulunabilir. Bu URL'ler
    // hotlink koruması nedeniyle yeniden kullanılmaz; TMDB fallback çözer.
    posterUrl: '',
    key: json['key'],
    year: int.tryParse('${json['year'] ?? ''}'),
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

class LetterboxdSyncException implements Exception {
  final String code;
  final String message;

  const LetterboxdSyncException(this.code, this.message);

  @override
  String toString() => message;
}

class LetterboxdService {
  static final Map<String, Future<void>> _activeSyncs = {};

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

      final rawYear =
          divPoster?.attributes['data-film-release-year'] ??
          divPoster?.attributes['data-release-year'] ??
          rc?.attributes['data-item-year'] ??
          li.attributes['data-film-release-year'];
      final year = int.tryParse(rawYear ?? '');

      items.add(
        LetterboxdFilm(title: title, url: href, posterUrl: '', year: year),
      );
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
    // Bu iki sayfa tek bir "beğenmediklerim" kategorisini oluşturuyor. Birisi
    // alınamazsa kısmi sonucu başarılı saymak eski Letterboxd verisini silebilir.
    final results = await Future.wait([
      fetchHalfStar(username),
      fetchOneStar(username),
    ]);
    final half = results[0];
    final one = results[1];
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
      if (e.toString().contains('HTTP 404')) {
        throw LetterboxdSyncException(
          'profile-not-found',
          'Letterboxd kullanıcısı bulunamadı: $username',
        );
      }
      rethrow;
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
      if (res == null || res.statusCode != 200) {
        if (page == 1 && all.isEmpty) {
          final cached = prefs.getString('${_cacheKeyFor(username)}_watchlist');
          if (cached != null) {
            return (jsonDecode(cached) as List)
                .map((e) => LetterboxdFilm.fromJson(e))
                .toList();
          }
          throw LetterboxdSyncException(
            'watchlist-unavailable',
            'Letterboxd izleme listesi şu anda alınamıyor.',
          );
        }
        break;
      }

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

  static Future<void> _upsertCatalog(List<LetterboxdFilm> films) async {
    await CatalogService().importLetterboxdFilms(
      films
          .where((film) => film.key.isNotEmpty && film.title.isNotEmpty)
          .map(
            (film) => {
              'key': film.key,
              'title': film.title,
              if (film.year != null) 'year': film.year,
            },
          )
          .toList(),
    );
  }

  // =========================================================================
  // KRİTİK GÜNCELLEME: Delta Sync Fonksiyonu
  // MANUEL FİLMLERİ SİLMEZ, SADECE YENİLERİ EKLER VE KORUR.
  // =========================================================================
  static Future<void> fullSyncOnboarding({
    required String uid,
    required String lbUsername,
    String source = 'manual',
  }) {
    final normalizedUsername = lbUsername.trim();
    final syncKey = '$uid:${normalizedUsername.toLowerCase()}';
    final running = _activeSyncs[syncKey];
    if (running != null) return running;

    final sync = _runTrackedSync(
      uid: uid,
      lbUsername: normalizedUsername,
      source: source,
    );
    _activeSyncs[syncKey] = sync;
    return sync.whenComplete(() {
      if (identical(_activeSyncs[syncKey], sync)) {
        _activeSyncs.remove(syncKey);
      }
    });
  }

  static Future<void> _runTrackedSync({
    required String uid,
    required String lbUsername,
    required String source,
  }) async {
    final statusRef = FirebaseFirestore.instance
        .collection('userTasteProfiles')
        .doc(uid);
    await _writeSyncStatus(statusRef, {
      'status': 'running',
      'username': lbUsername,
      'source': source,
      'startedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    try {
      await _performFullSync(uid: uid, lbUsername: lbUsername);
      await _writeSyncStatus(statusRef, {
        'status': 'success',
        'username': lbUsername,
        'source': source,
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error, stackTrace) {
      final failure = _normalizeSyncError(error);
      await _writeSyncStatus(statusRef, {
        'status': 'failed',
        'username': lbUsername,
        'source': source,
        'errorCode': failure.code,
        'message': failure.message,
        'failedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      Error.throwWithStackTrace(failure, stackTrace);
    }
  }

  static Future<void> _writeSyncStatus(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> status,
  ) async {
    try {
      await ref.set({'letterboxdSync': status}, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Letterboxd senkronizasyon durumu yazılamadı: $error');
    }
  }

  static LetterboxdSyncException _normalizeSyncError(Object error) {
    if (error is LetterboxdSyncException) return error;
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'unauthenticated':
          return const LetterboxdSyncException(
            'unauthenticated',
            'Oturumun sona ermiş. Lütfen yeniden giriş yap.',
          );
        case 'unavailable':
        case 'deadline-exceeded':
          return const LetterboxdSyncException(
            'unavailable',
            'Senkronizasyon servisine şu anda ulaşılamıyor. Tekrar dene.',
          );
        case 'resource-exhausted':
          return const LetterboxdSyncException(
            'rate-limited',
            'Çok fazla senkronizasyon isteği gönderildi. Biraz sonra tekrar dene.',
          );
        default:
          return const LetterboxdSyncException(
            'catalog-import-failed',
            'Film kataloğu güncellenemedi. Lütfen tekrar dene.',
          );
      }
    }
    final text = error.toString().toLowerCase();
    if (text.contains('404') || text.contains('kullanıcısı bulunamadı')) {
      return const LetterboxdSyncException(
        'profile-not-found',
        'Letterboxd kullanıcısı bulunamadı. Kullanıcı adını kontrol et.',
      );
    }
    if (text.contains('timeout') ||
        text.contains('socket') ||
        text.contains('network')) {
      return const LetterboxdSyncException(
        'network',
        'Letterboxd bağlantısı kurulamadı. İnternetini kontrol edip tekrar dene.',
      );
    }
    return const LetterboxdSyncException(
      'unknown',
      'Letterboxd verileri güncellenemedi. Lütfen tekrar dene.',
    );
  }

  static Future<void> _performFullSync({
    required String uid,
    required String lbUsername,
  }) async {
    // Tüm bölümler yazma başlamadan önce alınır. Herhangi biri başarısızsa
    // mevcut Letterboxd verileri korunur ve senkronizasyon tekrar denenebilir.
    final favs = await fetchFavorites(lbUsername);

    final results = await Future.wait([
      fetchFiveStar(lbUsername),
      fetchDisliked(lbUsername),
      fetchWatchlist(lbUsername),
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
    final letterboxdWatchedKeys = {
      ...newFavKeys,
      ...newFiveKeys,
      ...newDisKeys,
    }.toList();

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
          .map((item) {
            final sanitized = Map<String, dynamic>.from(item);
            for (final field in ['poster', 'posterUrl', 'image']) {
              if ((sanitized[field] ?? '').toString().contains('ltrbxd.com')) {
                sanitized[field] = '';
              }
            }
            return sanitized;
          })
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

    final watchedRef = userRef.collection('watched').doc('history');
    final relatedSnapshots = await Future.wait([
      tasteRef.get(),
      watchedRef.get(),
    ]);
    final tasteSnap = relatedSnapshots[0];
    final watchedSnap = relatedSnapshots[1];
    final dynamic rawPosters = (tasteSnap.data() ?? {})['posters'];
    final Map<String, String> existingPosters = rawPosters is Map
        ? Map<String, String>.from(rawPosters)
        : {};
    existingPosters.removeWhere((_, url) => url.contains('ltrbxd.com'));

    final postersMap = <String, String>{}..addAll(existingPosters);
    for (var f in [...fiveStar, ...disliked]) {
      if (f.key.isNotEmpty && f.posterUrl.isNotEmpty) {
        postersMap[f.key] = f.posterUrl;
      }
    }

    final rawWatchedIds = (watchedSnap.data() ?? {})['ids'];
    final watchedIds = rawWatchedIds is Map
        ? Map<String, dynamic>.from(rawWatchedIds)
        : <String, dynamic>{};
    final rawRecentIds = (watchedSnap.data() ?? {})['recentIds'];
    final recentIds = rawRecentIds is List
        ? rawRecentIds.map((item) => item.toString()).toList()
        : <String>[];
    final newlyWatchedKeys = letterboxdWatchedKeys
        .where((key) => watchedIds[key] != true)
        .toList();
    for (final key in newlyWatchedKeys) {
      watchedIds[key] = true;
    }
    for (final key in newlyWatchedKeys.reversed) {
      recentIds.removeWhere((item) => item == key);
      recentIds.insert(0, key);
    }
    if (recentIds.length > 20) {
      recentIds.removeRange(20, recentIds.length);
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
        if (newlyWatchedKeys.isNotEmpty) ...{
          'recentWatchedIds': recentIds,
          'recentWatchedUpdatedAt': FieldValue.serverTimestamp(),
        },
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

      if (newlyWatchedKeys.isNotEmpty) {
        batch.set(watchedRef, {
          'ids': watchedIds,
          'recentIds': recentIds,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      await batch.commit();
    });
  }
}
