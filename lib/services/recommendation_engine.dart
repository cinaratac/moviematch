import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart'; 
import 'dart:math';

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
    'recommendedAt': Timestamp.now(),
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

class UserTasteProfile {
  final List<String> favoriteGenres;
  final List<String> favoriteDirectors;
  final List<String> favoriteActors;
  final List<int> lovedMovieTmdbIds;
  final List<String> lovedMovieTitles; 
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
  final Random _rng = Random(); 

  // Cache süresi (7 Gün)
  static const Duration _cacheDuration = Duration(days: 7);
  
  List<MovieRecommendation>? _memoryCache;
  String? _cachedUid; 
  DateTime? _lastFetchTime;

  DocumentReference _getRecRef(String uid) {
    return _db.collection('users').doc(uid).collection('recommendations').doc('feed');
  }

  Future<List<MovieRecommendation>> generateRecommendations(String uid, {bool forceRefresh = false}) async {
    if (!forceRefresh && 
        _memoryCache != null && 
        _memoryCache!.isNotEmpty && 
        _cachedUid == uid && 
        _lastFetchTime != null) {
      
      if (DateTime.now().difference(_lastFetchTime!) < _cacheDuration) {
        return _memoryCache!;
      }
    }

    final Set<int> ignoreIds = {};
    
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
             
             if (list.length >= 10) {
               _memoryCache = list;
               _cachedUid = uid; 
               _lastFetchTime = cachedAt;
               return list;
             }
           }
        }
        
        final recs = data['recommendations'] as List?;
        if (recs != null) {
          for (var r in recs) ignoreIds.add(r['tmdbId']);
        }
      }
    } catch (e) {
      debugPrint("Cache check error: $e");
    }

    // 3. Profil Analizi
    final profile = await _fetchUserProfile(uid);
    final rawRecommendations = <MovieRecommendation>[];

    // 4. API İstekleri
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
        existing.matchScore = (existing.matchScore + 10).clamp(0.0, 100.0).toDouble();
        if (!existing.matchReason.contains(rec.matchReason)) {
           if (existing.matchReason.length < 50) {
             existing.matchReason = '${existing.matchReason}, ${rec.matchReason.split(':').last}';
           }
        }
      } else {
        uniqueMap[rec.tmdbId] = rec;
      }
    }

    // 6. YEDEK PLAN (Trendler - Profil tamamen boşsa)
    if (uniqueMap.length < 15) {
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

    // 7. Firebase'e Yazma
    if (top30.isNotEmpty) {
      try {
        await _getRecRef(uid).set({
          'recommendations': top30.map((r) => r.toMap()).toList(),
          'cachedAt': FieldValue.serverTimestamp(),
          'count': top30.length,
        });
        _memoryCache = top30;
        _cachedUid = uid; 
        _lastFetchTime = DateTime.now();
      } catch (e) {
        debugPrint("Firebase write error: $e");
      }
    }

    return top30;
  }

  void clearMemoryCache() {
    _memoryCache = null;
    _cachedUid = null;
    _lastFetchTime = null;
  }

  Future<List<MovieRecommendation>?> getCachedRecommendations(String uid) async {
    if (_memoryCache != null && _memoryCache!.isNotEmpty && _cachedUid == uid) return _memoryCache;
    
    try {
      final snapshot = await _getRecRef(uid).get();
      if (!snapshot.exists) return null;

      final data = snapshot.data() as Map<String, dynamic>;
      final cachedAt = (data['cachedAt'] as Timestamp?)?.toDate();
      
      if (cachedAt != null && DateTime.now().difference(cachedAt) > _cacheDuration) return null;

      final recommendationsData = data['recommendations'] as List?;
      if (recommendationsData == null) return null;

      final list = recommendationsData.map((e) => MovieRecommendation.fromMap(e)).toList();
      
      if (list.length < 10) return null;

      _memoryCache = list;
      _cachedUid = uid; 
      _lastFetchTime = cachedAt ?? DateTime.now();
      return list;
    } catch (e) {
      return null;
    }
  }

  // GİZLİ ÇÖKME HATASINI DÜZELTEN YARDIMCI FONKSİYON
  List<String> _extractNames(dynamic listData) {
    if (listData is! List) return [];
    return listData.map((e) {
      if (e is Map) return (e['name'] ?? '').toString();
      return e.toString();
    }).where((s) => s.trim().isNotEmpty).toList();
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

      // KESİN ÇÖZÜM: _extractNames kullanarak Map'lerden sadece isimleri çıkarıyoruz.
      return UserTasteProfile(
        favoriteGenres: _extractNames(data['favGenres']),
        favoriteDirectors: _extractNames(data['favDirectors']),
        favoriteActors: _extractNames(data['favActors']),
        lovedMovieTmdbIds: resolvedIds,
        lovedMovieTitles: resolvedTitles,
        dislikedMovieTmdbIds: List<int>.from(data['dislikedMovieIds'] ?? []), 
        age: data['age'] as int?,
      );
    } catch (e) {
      debugPrint('Profile Fetch Error: $e');
      return UserTasteProfile();
    }
  }
  
  Future<void> _fetchAndAddRecommendations(String path, List<MovieRecommendation> list, String reason) async {
    try {
      final int randomPage = _rng.nextInt(3) + 1;

      final result = await FirebaseFunctions.instance.httpsCallable('callTMDB').call({
        'endpoint': path,
        'params': {'language': 'tr-TR', 'page': '$randomPage'}
      });

      final data = Map<String, dynamic>.from(result.data as Map); 
      final results = data['results'] as List;
      
      for (final rawMovie in results.take(15)) {
        final movie = Map<String, dynamic>.from(rawMovie as Map);
        final vote = (movie['vote_average'] ?? 0.0).toDouble();
        final score = 50.0 + (vote * 4.5);
        list.add(_createRecommendation(
          movie,
          matchScore: score.clamp(0.0, 92.0).toDouble(),
          matchReason: reason,
        ));
      }
    } catch (e) {
      debugPrint("API Error ($path): $e");
    }
  }

  Future<void> _getGenreBasedRecommendations(UserTasteProfile profile, List<MovieRecommendation> recommendations) async {
    if (profile.favoriteGenres.isEmpty) return;
    final genreMap = await _getGenreIdMap();
    for (var g in profile.favoriteGenres.take(3)) {
      final id = genreMap[g.toLowerCase().trim()];
      if (id != null) {
        try {
          final int randomPage = _rng.nextInt(10) + 1;

          final result = await FirebaseFunctions.instance.httpsCallable('callTMDB').call({
            'endpoint': '/3/discover/movie',
            'params': {
              'with_genres': id.toString(), 
              'sort_by': 'popularity.desc', 
              'page': '$randomPage',
              'language': 'tr-TR'
            }
          });
          
          final data = Map<String, dynamic>.from(result.data as Map);
          final res = data['results'] as List;
          
          for(var rawM in res.take(10)) {
            final m = Map<String, dynamic>.from(rawM as Map);
            final vote = (m['vote_average'] ?? 0.0).toDouble();
            recommendations.add(_createRecommendation(
              m, 
              matchScore: (50.0 + (vote * 5.0)).clamp(0.0, 95.0).toDouble(), 
              matchReason: 'Tür: $g'
            ));
          }
        } catch(_){}
      }
    }
  }

  Future<void> _getDirectorBasedRecommendations(UserTasteProfile profile, List<MovieRecommendation> recommendations) async {
    // Limit artırıldı: 3 Yönetmen
    for (var name in profile.favoriteDirectors.take(3)) {
      await _fetchPersonCredits(name, 'Directing', recommendations, 'Yönetmen');
    }
  }

  Future<void> _getActorBasedRecommendations(UserTasteProfile profile, List<MovieRecommendation> recommendations) async {
    // Limit artırıldı: 4 Oyuncu
    for (var name in profile.favoriteActors.take(4)) {
      await _fetchPersonCredits(name, 'Acting', recommendations, 'Oyuncu');
    }
  }

  Future<void> _fetchPersonCredits(String name, String dept, List<MovieRecommendation> list, String roleLabel) async {
    try {
      final sResult = await FirebaseFunctions.instance.httpsCallable('callTMDB').call({
        'endpoint': '/3/search/person',
        'params': {'query': name, 'language': 'tr-TR'}
      });
      
      final sData = Map<String, dynamic>.from(sResult.data as Map);
      final sRes = sData['results'] as List;

      if (sRes.isEmpty) return;
      
      final personId = sRes.first['id'];

      final cResult = await FirebaseFunctions.instance.httpsCallable('callTMDB').call({
        'endpoint': '/3/person/$personId/movie_credits',
        'params': {'language': 'tr-TR'}
      });

      final cData = Map<String, dynamic>.from(cResult.data as Map);
      var credits = (dept == 'Directing' ? cData['crew'] : cData['cast']) as List;
      
      if (dept == 'Directing') {
        credits = credits.where((c) => c['job'] == 'Director').toList();
      }
      
      credits.sort((a, b) => (b['popularity'] ?? 0).compareTo(a['popularity'] ?? 0));
      
      var topCandidates = credits.take(20).toList();
      topCandidates.shuffle(_rng);

      // Daha fazla film getirmesi sağlandı (max 6)
      for (final rawMovie in topCandidates.take(6)) {
         final movie = Map<String, dynamic>.from(rawMovie as Map);
         final vote = (movie['vote_average'] ?? 0.0).toDouble();
         list.add(_createRecommendation(
           movie,
           matchScore: (55.0 + (vote * 4.0)).clamp(0.0, 90.0).toDouble(),
           matchReason: '$roleLabel: $name',
         ));
      }
    } catch (_) {}
  }

  Future<void> _getSimilarMovieRecommendations(UserTasteProfile profile, List<MovieRecommendation> recommendations) async {
    for (var id in profile.lovedMovieTmdbIds.take(3)) {
      await _fetchAndAddRecommendations('/3/movie/$id/recommendations', recommendations, 'Benzer');
    }
    for (var title in profile.lovedMovieTitles.take(3)) {
      try {
        final sResult = await FirebaseFunctions.instance.httpsCallable('callTMDB').call({
          'endpoint': '/3/search/movie',
          'params': {'query': title, 'language': 'tr-TR'}
        });
        
        final data = Map<String, dynamic>.from(sResult.data as Map);
        final res = data['results'] as List;

        if (res.isNotEmpty) {
          final id = res.first['id'];
          await _fetchAndAddRecommendations('/3/movie/$id/recommendations', recommendations, 'Benzer: $title');
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
      if (profile.dislikedMovieTmdbIds.contains(rec.tmdbId)) return false;
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