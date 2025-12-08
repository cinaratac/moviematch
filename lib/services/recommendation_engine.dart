import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart'; // debugPrint için
import '../secrets.dart';
import 'dart:math';

/// Film Öneri Modeli
class MovieRecommendation {
  final int tmdbId;
  final String title;
  final String posterUrl;
  final String overview;
  final double voteAverage;
  final String releaseDate;
  final List<String> genres;
  double matchScore; 
  String matchReason; 

  MovieRecommendation({
    required this.tmdbId,
    required this.title,
    required this.posterUrl,
    required this.overview,
    required this.voteAverage,
    required this.releaseDate,
    required this.genres,
    required this.matchScore,
    required this.matchReason,
  });

  Map<String, dynamic> toMap() => {
    'tmdbId': tmdbId,
    'title': title,
    'posterUrl': posterUrl,
    'overview': overview,
    'voteAverage': voteAverage,
    'releaseDate': releaseDate,
    'genres': genres,
    'matchScore': matchScore,
    'matchReason': matchReason,
    'recommendedAt': FieldValue.serverTimestamp(),
  };

  factory MovieRecommendation.fromMap(Map<String, dynamic> map) {
    return MovieRecommendation(
      tmdbId: map['tmdbId'] ?? 0,
      title: map['title'] ?? '',
      posterUrl: map['posterUrl'] ?? '',
      overview: map['overview'] ?? '',
      voteAverage: (map['voteAverage'] ?? 0.0).toDouble(),
      releaseDate: map['releaseDate'] ?? '',
      genres: List<String>.from(map['genres'] ?? []),
      matchScore: (map['matchScore'] ?? 0.0).toDouble(),
      matchReason: map['matchReason'] ?? '',
    );
  }
}

/// Kullanıcı Zevk Profili
class UserTasteProfile {
  final List<String> favoriteGenres;
  final List<String> favoriteDirectors;
  final List<String> favoriteActors;
  final List<int> lovedMovieTmdbIds;
  final List<String> lovedMovieTitles; // ID yoksa isimle aramak için
  final List<int> dislikedMovieTmdbIds;
  final int? age;

  UserTasteProfile({
    this.favoriteGenres = const [],
    this.favoriteDirectors = const [],
    this.favoriteActors = const [],
    this.lovedMovieTmdbIds = const [],
    this.lovedMovieTitles = const [],
    this.dislikedMovieTmdbIds = const [],
    this.age,
  });
}

class RecommendationEngine {
  RecommendationEngine._();
  static final RecommendationEngine instance = RecommendationEngine._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _tmdbBearer = Secrets.tmdbAccessToken;

  // Cache süresi (7 Gün)
  static const Duration _cacheDuration = Duration(days: 7);
  List<MovieRecommendation>? _memoryCache;
  DateTime? _lastFetchTime;

  /// ÖNERİLERİ KAYDETTİĞİMİZ YENİ GÜVENLİ YOL
  /// users -> {uid} -> recommendations -> feed
  DocumentReference _getRecRef(String uid) {
    return _db.collection('users').doc(uid).collection('recommendations').doc('feed');
  }

  Future<List<MovieRecommendation>> generateRecommendations(String uid, {bool forceRefresh = false}) async {
    // 1. RAM Cache Kontrolü
    if (!forceRefresh && _memoryCache != null && _memoryCache!.isNotEmpty && _lastFetchTime != null) {
      if (DateTime.now().difference(_lastFetchTime!) < _cacheDuration) {
        return _memoryCache!;
      }
    }

    final Set<int> ignoreIds = {};
    
    // 2. Firebase Cache Kontrolü (YENİ ADRES)
    try {
      final docRef = _getRecRef(uid);
      final snapshot = await docRef.get();

      if (!forceRefresh && snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        final cachedAt = (data['cachedAt'] as Timestamp?)?.toDate();
        
        if (cachedAt != null && DateTime.now().difference(cachedAt) < _cacheDuration) {
           final recsData = data['recommendations'] as List?;
           if (recsData != null && recsData.isNotEmpty) {
             final list = recsData.map((e) => MovieRecommendation.fromMap(e)).toList();
             _memoryCache = list;
             _lastFetchTime = cachedAt;
             return list;
           }
        }
        // Veri eskiyse ID'leri al (tekrar önermemek için)
        final recs = data['recommendations'] as List?;
        if (recs != null) {
          for (var r in recs) ignoreIds.add(r['tmdbId']);
        }
      }
    } catch (e) {
      debugPrint("Cache okuma hatası: $e");
    }

    // 3. Profil Analizi
    final profile = await _fetchUserProfile(uid);
    final rawRecommendations = <MovieRecommendation>[];

    // 4. API İstekleri (Hataları Yutmadan)
    await Future.wait([
      _getGenreBasedRecommendations(profile, rawRecommendations),
      _getDirectorBasedRecommendations(profile, rawRecommendations),
      _getActorBasedRecommendations(profile, rawRecommendations),
      _getSimilarMovieRecommendations(profile, rawRecommendations),
    ]);

    // 5. Birleştirme & Puanlama
    final uniqueMap = <int, MovieRecommendation>{};
    for (final rec in rawRecommendations) {
      if (uniqueMap.containsKey(rec.tmdbId)) {
        final existing = uniqueMap[rec.tmdbId]!;
        existing.matchScore = (existing.matchScore + 10).clamp(0.0, 100.0);
        if (!existing.matchReason.contains(rec.matchReason)) {
           if (existing.matchReason.length < 50) {
             existing.matchReason = '${existing.matchReason}, ${rec.matchReason.split(':').last}';
           }
        }
      } else {
        uniqueMap[rec.tmdbId] = rec;
      }
    }

    // 6. YEDEK PLAN: Liste boşsa Trendleri Çek
    if (uniqueMap.length < 10) {
      final trending = <MovieRecommendation>[];
      await _getTrendingRecommendations(trending);
      for (final tr in trending) {
        if (!uniqueMap.containsKey(tr.tmdbId) && !ignoreIds.contains(tr.tmdbId)) {
           uniqueMap[tr.tmdbId] = tr;
        }
      }
    }

    var mergedList = uniqueMap.values.toList();
    final filtered = _filterKnownMovies(mergedList, profile, ignoreIds: ignoreIds);
    filtered.sort((a, b) => b.matchScore.compareTo(a.matchScore));
    final top30 = filtered.take(30).toList();

    // 7. Firebase'e Yazma (YENİ ADRES)
    if (top30.isNotEmpty) {
      try {
        await _getRecRef(uid).set({
          'recommendations': top30.map((r) => r.toMap()).toList(),
          'cachedAt': FieldValue.serverTimestamp(),
          'count': top30.length,
        });
        _memoryCache = top30;
        _lastFetchTime = DateTime.now();
      } catch (e) {
        debugPrint("Yazma hatası: $e");
      }
    }

    return top30;
  }

  // --- Yardımcı Fonksiyonlar ---

  void clearMemoryCache() {
    _memoryCache = null;
    _lastFetchTime = null;
  }

  Future<List<MovieRecommendation>?> getCachedRecommendations(String uid) async {
    if (_memoryCache != null && _memoryCache!.isNotEmpty) return _memoryCache;
    try {
      final snapshot = await _getRecRef(uid).get();
      if (!snapshot.exists) return null;

      final data = snapshot.data() as Map<String, dynamic>;
      final cachedAt = (data['cachedAt'] as Timestamp?)?.toDate();
      
      if (cachedAt != null && DateTime.now().difference(cachedAt) > _cacheDuration) return null;

      final recommendationsData = data['recommendations'] as List?;
      if (recommendationsData == null) return null;

      final list = recommendationsData.map((e) => MovieRecommendation.fromMap(e)).toList();
      _memoryCache = list;
      _lastFetchTime = cachedAt ?? DateTime.now();
      return list;
    } catch (e) {
      return null;
    }
  }

  Future<UserTasteProfile> _fetchUserProfile(String uid) async {
    try {
      final userDoc = await _db.collection('users').doc(uid).get();
      if (!userDoc.exists) return UserTasteProfile();

      final data = userDoc.data()!;
      final keys = <String>{...List<String>.from(data['fiveStarKeys'] ?? []), ...List<String>.from(data['favoritesKeys'] ?? [])};
      
      final resolvedIds = <int>[];
      final resolvedTitles = <String>[];

      if (keys.isNotEmpty) {
        final keyList = keys.toList();
        for (var i = 0; i < keyList.length; i += 10) {
          final chunk = keyList.sublist(i, i + 10 > keyList.length ? keyList.length : i + 10);
          final qs = await _db.collection('catalog_films').where(FieldPath.documentId, whereIn: chunk).get();
          for (final doc in qs.docs) {
            final d = doc.data();
            final tmdbId = d['tmdbId'];
            if (tmdbId is int && tmdbId > 0) {
              resolvedIds.add(tmdbId);
            } else {
              final title = d['title'] as String?;
              if (title != null && title.isNotEmpty) resolvedTitles.add(title);
            }
          }
        }
      }

      return UserTasteProfile(
        favoriteGenres: List<String>.from(data['favGenres'] ?? []),
        favoriteDirectors: List<String>.from(data['favDirectors'] ?? []),
        favoriteActors: List<String>.from(data['favActors'] ?? []),
        lovedMovieTmdbIds: resolvedIds,
        lovedMovieTitles: resolvedTitles,
        age: data['age'] as int?,
      );
    } catch (e) {
      return UserTasteProfile();
    }
  }

  // --- API Fetcher Helper ---
  
  Map<String, String> get _headers => {
    'Authorization': 'Bearer $_tmdbBearer',
    'Accept': 'application/json',
  };

  Future<void> _fetchAndAddRecommendations(String path, List<MovieRecommendation> list, String reason) async {
    try {
      final uri = Uri.https('api.themoviedb.org', path, {'language': 'tr-TR', 'page': '1'});
      final resp = await http.get(uri, headers: _headers);
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        final results = data['results'] as List;
        for (final movie in results.take(5)) {
          final vote = (movie['vote_average'] ?? 0.0).toDouble();
          final score = 50.0 + (vote * 4.5);
          list.add(_createRecommendation(
            movie,
            matchScore: score.clamp(0.0, 92.0),
            matchReason: reason,
          ));
        }
      }
    } catch (e) {
      debugPrint("API Error: $e");
    }
  }

  // --- Kaynak Fonksiyonları ---

  Future<void> _getGenreBasedRecommendations(UserTasteProfile profile, List<MovieRecommendation> recommendations) async {
    if (profile.favoriteGenres.isEmpty) return;
    final genreMap = await _getGenreIdMap();
    for (var g in profile.favoriteGenres.take(3)) {
      final id = genreMap[g.toLowerCase().trim()];
      if (id != null) {
        try {
          final uri = Uri.https('api.themoviedb.org', '/3/discover/movie', {
            'with_genres': id.toString(), 'sort_by': 'popularity.desc', 'language': 'tr-TR'
          });
          final resp = await http.get(uri, headers: _headers);
          if(resp.statusCode==200) {
             final res = json.decode(resp.body)['results'] as List;
             for(var m in res.take(5)) {
               final vote = (m['vote_average'] ?? 0.0).toDouble();
               recommendations.add(_createRecommendation(m, matchScore: (50.0 + (vote * 5.0)).clamp(0.0, 95.0), matchReason: 'Tür: $g'));
             }
          }
        } catch(_){}
      }
    }
  }

  Future<void> _getDirectorBasedRecommendations(UserTasteProfile profile, List<MovieRecommendation> recommendations) async {
    for (var name in profile.favoriteDirectors.take(2)) {
      await _fetchPersonCredits(name, 'Directing', recommendations, 'Yönetmen');
    }
  }

  Future<void> _getActorBasedRecommendations(UserTasteProfile profile, List<MovieRecommendation> recommendations) async {
    for (var name in profile.favoriteActors.take(2)) {
      await _fetchPersonCredits(name, 'Acting', recommendations, 'Oyuncu');
    }
  }

  Future<void> _fetchPersonCredits(String name, String dept, List<MovieRecommendation> list, String roleLabel) async {
    try {
      final sUri = Uri.https('api.themoviedb.org', '/3/search/person', {'query': name, 'language': 'tr-TR'});
      final sResp = await http.get(sUri, headers: _headers);
      if (sResp.statusCode != 200) return;
      final sRes = json.decode(sResp.body)['results'] as List;
      if (sRes.isEmpty) return;
      final personId = sRes.first['id'];
      final cUri = Uri.https('api.themoviedb.org', '/3/person/$personId/movie_credits', {'language': 'tr-TR'});
      final cResp = await http.get(cUri, headers: _headers);
      if (cResp.statusCode == 200) {
        final cData = json.decode(cResp.body);
        var credits = (dept == 'Directing' ? cData['crew'] : cData['cast']) as List;
        if (dept == 'Directing') {
          credits = credits.where((c) => c['job'] == 'Director').toList();
        }
        credits.sort((a, b) => (b['popularity'] ?? 0).compareTo(a['popularity'] ?? 0));
        for (final movie in credits.take(4)) {
           final vote = (movie['vote_average'] ?? 0.0).toDouble();
           list.add(_createRecommendation(
             movie,
             matchScore: (55.0 + (vote * 4.0)).clamp(0.0, 90.0),
             matchReason: '$roleLabel: $name',
           ));
        }
      }
    } catch (_) {}
  }

  Future<void> _getSimilarMovieRecommendations(UserTasteProfile profile, List<MovieRecommendation> recommendations) async {
    // ID ile
    for (var id in profile.lovedMovieTmdbIds.take(3)) {
      await _fetchAndAddRecommendations('/3/movie/$id/recommendations', recommendations, 'Benzer');
    }
    // İsim ile (ID Bulup)
    for (var title in profile.lovedMovieTitles.take(3)) {
      try {
        final sUri = Uri.https('api.themoviedb.org', '/3/search/movie', {'query': title, 'language': 'tr-TR'});
        final sResp = await http.get(sUri, headers: _headers);
        if (sResp.statusCode == 200) {
          final res = json.decode(sResp.body)['results'] as List;
          if (res.isNotEmpty) {
            final id = res.first['id'];
            await _fetchAndAddRecommendations('/3/movie/$id/recommendations', recommendations, 'Benzer: $title');
          }
        }
      } catch(_){}
    }
  }

  Future<void> _getTrendingRecommendations(List<MovieRecommendation> recommendations) async {
    await _fetchAndAddRecommendations('/3/trending/movie/week', recommendations, 'Popüler');
  }

  MovieRecommendation _createRecommendation(Map<String, dynamic> movie, {required double matchScore, required String matchReason}) {
    final posterPath = movie['poster_path'] as String?;
    final genreIds = List<int>.from(movie['genre_ids'] ?? []);
    return MovieRecommendation(
      tmdbId: movie['id'] as int,
      title: movie['title'] ?? '',
      posterUrl: posterPath != null ? 'https://image.tmdb.org/t/p/w500$posterPath' : '',
      overview: movie['overview'] ?? '',
      voteAverage: (movie['vote_average'] ?? 0.0).toDouble(),
      releaseDate: movie['release_date'] ?? '',
      genres: genreIds.map((id) => _genreIdToName(id)).toList(),
      matchScore: matchScore,
      matchReason: matchReason,
    );
  }

  List<MovieRecommendation> _filterKnownMovies(List<MovieRecommendation> list, UserTasteProfile profile, {Set<int>? ignoreIds}) {
    final knownIds = {...profile.lovedMovieTmdbIds, ...?ignoreIds};
    final knownTitles = profile.lovedMovieTitles.map((t) => t.toLowerCase()).toSet();
    return list.where((rec) {
      if (knownIds.contains(rec.tmdbId)) return false;
      if (knownTitles.contains(rec.title.toLowerCase())) return false;
      return true;
    }).toList();
  }

  Future<Map<String, int>> _getGenreIdMap() async {
    return {
      'aksiyon': 28, 'macera': 12, 'animasyon': 16, 'komedi': 35, 'suç': 80, 
      'belgesel': 99, 'dram': 18, 'drama': 18, 'aile': 10751, 'fantastik': 14, 
      'tarih': 36, 'korku': 27, 'müzik': 10402, 'gizem': 9648, 'romantik': 10749,
      'bilimkurgu': 878, 'bilim kurgu': 878, 'gerilim': 53, 'savaş': 10752, 
      'western': 37, 'klasikler': 18
    };
  }

  String _genreIdToName(int id) {
    final map = {
      28: 'Aksiyon', 12: 'Macera', 16: 'Animasyon', 35: 'Komedi', 80: 'Suç',
      99: 'Belgesel', 18: 'Dram', 10751: 'Aile', 14: 'Fantastik', 36: 'Tarih',
      27: 'Korku', 10402: 'Müzik', 9648: 'Gizem', 10749: 'Romantik',
      878: 'Bilim Kurgu', 53: 'Gerilim', 10752: 'Savaş', 37: 'Western',
    };
    return map[id] ?? 'Diğer';
  }
}