import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
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
  final List<int> dislikedMovieTmdbIds;
  final int? age;

  UserTasteProfile({
    this.favoriteGenres = const [],
    this.favoriteDirectors = const [],
    this.favoriteActors = const [],
    this.lovedMovieTmdbIds = const [],
    this.dislikedMovieTmdbIds = const [],
    this.age,
  });

  factory UserTasteProfile.fromFirestore(Map<String, dynamic> data) {
    return UserTasteProfile(
      favoriteGenres: List<String>.from(data['favGenres'] ?? []),
      favoriteDirectors: List<String>.from(data['favDirectors'] ?? []),
      favoriteActors: List<String>.from(data['favActors'] ?? []),
      age: data['age'] as int?,
    );
  }
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

  /// Ana öneri motoru - Kullanıcı için öneriler üretir
  Future<List<MovieRecommendation>> generateRecommendations(String uid) async {
    // 1. Kullanıcı profilini çek
    if (_memoryCache != null && _memoryCache!.isNotEmpty && _lastFetchTime != null) {
      if (DateTime.now().difference(_lastFetchTime!) < _cacheDuration) {
        return _memoryCache!;
      }
    }
    final Set<int> ignoreIds = {};
    try {
      // Sadece kullanıcının en son kaydedilen öneri dökümanını çekiyoruz
      final lastRecDoc = await _db.collection('userRecommendations').doc(uid).get();
      
      if (lastRecDoc.exists) {
        final data = lastRecDoc.data();
        // 'recommendations' listesindeki filmleri al
        final recs = data?['recommendations'] as List?;
        if (recs != null) {
          for (var r in recs) {
            // Sadece geçen sefer önerilenleri engelle
            ignoreIds.add(r['tmdbId']); 
          }
        }
      }
    } catch (_) {}
    final profile = await _fetchUserProfile(uid);
    
    // Geçici ham liste
    final rawRecommendations = <MovieRecommendation>[];

    // 2. Paralel olarak farklı kaynaklardan öneriler topla
    await Future.wait([
      _getGenreBasedRecommendations(profile, rawRecommendations),
      _getDirectorBasedRecommendations(profile, rawRecommendations),
      _getActorBasedRecommendations(profile, rawRecommendations),
      _getSimilarMovieRecommendations(profile, rawRecommendations),
    ]);

    // 3. Tekilleştirme ve Puan Birleştirme
    final uniqueMap = <int, MovieRecommendation>{};

    for (final rec in rawRecommendations) {
      if (uniqueMap.containsKey(rec.tmdbId)) {
        final existing = uniqueMap[rec.tmdbId]!;
        // Eğer zaten listede varsa:
        // 1. Puanını artır
        existing.matchScore = (existing.matchScore + 10).clamp(0.0, 100.0);
        
        // 2. Sebebi güncelle
        if (!existing.matchReason.contains(rec.matchReason)) {
           if (existing.matchReason.length < 50) {
             existing.matchReason = '${existing.matchReason}, ${rec.matchReason.split(':').last}';
           }
        }
      } else {
        uniqueMap[rec.tmdbId] = rec;
      }
    }

    var mergedList = uniqueMap.values.toList();

    // 4. Zaten bilinen filmleri filtrele
    final filtered = _filterKnownMovies(mergedList, profile, ignoreIds: ignoreIds);

    // 5. Skorlarına göre sırala ve en iyi 30'u al
    filtered.sort((a, b) => b.matchScore.compareTo(a.matchScore));
    final top30 = filtered.take(30).toList();

    // 6. Firestore'a kaydet (cache)
    if (top30.isNotEmpty) {
      await _saveRecommendationsToCache(uid, top30);
      _memoryCache = top30;
      _lastFetchTime = DateTime.now();
    }

    return top30;
  }

  void clearMemoryCache() {
    _memoryCache = null;
    _lastFetchTime = null;
  }

  /// Cache'den önerileri getir (DÜZELTİLEN FONKSİYON)
  Future<List<MovieRecommendation>?> getCachedRecommendations(String uid) async {
    if (_memoryCache != null && _memoryCache!.isNotEmpty) {
       return _memoryCache;
    }
    try {
      final doc = await _db.collection('userRecommendations').doc(uid).get();
      if (!doc.exists) return null;

      final data = doc.data()!;
      final cachedAt = (data['cachedAt'] as Timestamp?)?.toDate();
      
      if (cachedAt != null && DateTime.now().difference(cachedAt) > _cacheDuration) {
        return null;
      }

      final recommendationsData = data['recommendations'] as List?;
      if (recommendationsData == null) return null;

      final list = recommendationsData
          .map((e) => MovieRecommendation.fromMap(e as Map<String, dynamic>))
          .toList();
      
      // --- EKLENEN KISIM: Profil verisine göre filtreleme ---
      // Cache'ten gelse bile, kullanıcı bu sürede izlemiş olabilir diye tekrar filtreliyoruz
      final profile = await _fetchUserProfile(uid);
      final filteredList = _filterKnownMovies(list, profile); 
      // -----------------------------------------------------

      _memoryCache = filteredList;
      _lastFetchTime = cachedAt ?? DateTime.now();
      return filteredList;
    } catch (e) {
      return null; // <-- BU SATIR EKSİKTİ, EKLENDİ
    }
  }

  Future<UserTasteProfile> _fetchUserProfile(String uid) async {
    final userDoc = await _db.collection('users').doc(uid).get();
    if (!userDoc.exists) return UserTasteProfile();

    final data = userDoc.data()!;
    final lovedIds = await _fetchTmdbIdsFromKeys(List<String>.from(data['fiveStarKeys'] ?? []));
    final dislikedIds = await _fetchTmdbIdsFromKeys(List<String>.from(data['dislikedKeys'] ?? []));
    
    return UserTasteProfile(
      favoriteGenres: List<String>.from(data['favGenres'] ?? []),
      favoriteDirectors: List<String>.from(data['favDirectors'] ?? []),
      favoriteActors: List<String>.from(data['favActors'] ?? []),
      lovedMovieTmdbIds: lovedIds,
      dislikedMovieTmdbIds: dislikedIds,
      age: data['age'] as int?,
    );
  }

  Future<List<int>> _fetchTmdbIdsFromKeys(List<String> keys) async {
    if (keys.isEmpty) return [];
    final ids = <int>[];
    for (var i = 0; i < keys.length; i += 10) {
      final chunk = keys.sublist(i, i + 10 > keys.length ? keys.length : i + 10);
      try {
        final qs = await _db.collection('catalog_films').where(FieldPath.documentId, whereIn: chunk).get();
        for (final doc in qs.docs) {
          final tmdbId = doc.data()['tmdbId'];
          if (tmdbId is int && tmdbId > 0) ids.add(tmdbId);
        }
      } catch (_) {}
    }
    return ids;
  }

  // Paralel istekler için güncellenmiş yardımcı fonksiyonlar
  Future<void> _getGenreBasedRecommendations(
    UserTasteProfile profile,
    List<MovieRecommendation> recommendations,
  ) async {
    if (profile.favoriteGenres.isEmpty) return;
    final genreMap = await _getGenreIdMap();
    
    // Future.wait ile paralel çalıştır
    await Future.wait(profile.favoriteGenres.take(5).map((genreName) async {
      final genreId = genreMap[genreName.toLowerCase()];
      if (genreId == null) return;

      try {
        final randomPage = Random().nextInt(3) + 1;
        final uri = Uri.https('api.themoviedb.org', '/3/discover/movie', {
          'with_genres': genreId.toString(),
          'sort_by': 'vote_average.desc',
          'vote_count.gte': '300',
          'language': 'tr-TR',
          'page': randomPage.toString(),
        });

        final resp = await http.get(uri, headers: {
          'Authorization': 'Bearer $_tmdbBearer',
          'Accept': 'application/json',
        });

        if (resp.statusCode == 200) {
          final data = json.decode(resp.body);
          final results = data['results'] as List;

          for (final movie in results.take(10)) {
            final vote = (movie['vote_average'] ?? 0.0).toDouble();
            final score = 50.0 + (vote * 5.0);

            recommendations.add(_createRecommendation(
              movie,
              matchScore: score.clamp(0.0, 95.0),
              matchReason: 'Favori türün: $genreName',
            ));
          }
        }
      } catch (_) {}
    }));
  }

  Future<void> _getDirectorBasedRecommendations(
    UserTasteProfile profile,
    List<MovieRecommendation> recommendations,
  ) async {
    if (profile.favoriteDirectors.isEmpty) return;

    // Paralel çalıştır
    await Future.wait(profile.favoriteDirectors.take(5).map((directorName) async {
      try {
        final searchUri = Uri.https('api.themoviedb.org', '/3/search/person', {
          'query': directorName,
          'language': 'tr-TR',
        });

        final searchResp = await http.get(searchUri, headers: {
          'Authorization': 'Bearer $_tmdbBearer',
          'Accept': 'application/json',
        });

        if (searchResp.statusCode != 200) return;

        final searchData = json.decode(searchResp.body);
        final results = searchData['results'] as List;
        
        if (results.isEmpty) return;
        
        var person = results.first;
        if (results.length > 1) {
           final directorPerson = results.firstWhere(
             (p) => (p['known_for_department'] == 'Directing'), 
             orElse: () => results.first
           );
           person = directorPerson;
        }
        
        final directorId = person['id'];

        final moviesUri = Uri.https(
          'api.themoviedb.org',
          '/3/person/$directorId/movie_credits',
          {'language': 'tr-TR'},
        );

        final moviesResp = await http.get(moviesUri, headers: {
          'Authorization': 'Bearer $_tmdbBearer',
          'Accept': 'application/json',
        });

        if (moviesResp.statusCode == 200) {
          final moviesData = json.decode(moviesResp.body);
          final crew = moviesData['crew'] as List;
          final directed = crew.where((c) => c['job'] == 'Director').toList();
          
          directed.sort((a, b) => (b['popularity'] ?? 0).compareTo(a['popularity'] ?? 0));

          for (final movie in directed.take(5)) {
             final vote = (movie['vote_average'] ?? 0.0).toDouble();
             final score = 60.0 + (vote * 4.0); 

            recommendations.add(_createRecommendation(
              movie,
              matchScore: score.clamp(0.0, 98.0),
              matchReason: 'Favori yönetmen: $directorName',
            ));
          }
        }
      } catch (_) {}
    }));
  }

  Future<void> _getActorBasedRecommendations(
    UserTasteProfile profile,
    List<MovieRecommendation> recommendations,
  ) async {
    if (profile.favoriteActors.isEmpty) return;

    // Paralel çalıştır
    await Future.wait(profile.favoriteActors.take(3).map((actorName) async {
      try {
        final searchUri = Uri.https('api.themoviedb.org', '/3/search/person', {
          'query': actorName,
          'language': 'tr-TR',
        });

        final searchResp = await http.get(searchUri, headers: {
          'Authorization': 'Bearer $_tmdbBearer',
          'Accept': 'application/json',
        });

        if (searchResp.statusCode != 200) return;
        final searchData = json.decode(searchResp.body);
        final results = searchData['results'] as List;
        if (results.isEmpty) return;

        var person = results.first;
         if (results.length > 1) {
           person = results.firstWhere(
             (p) => (p['known_for_department'] == 'Acting'), 
             orElse: () => results.first
           );
        }
        final actorId = person['id'];

        final moviesUri = Uri.https(
          'api.themoviedb.org',
          '/3/person/$actorId/movie_credits',
          {'language': 'tr-TR'},
        );

        final moviesResp = await http.get(moviesUri, headers: {
          'Authorization': 'Bearer $_tmdbBearer',
          'Accept': 'application/json',
        });

        if (moviesResp.statusCode == 200) {
          final moviesData = json.decode(moviesResp.body);
          final cast = moviesData['cast'] as List;
          
          cast.sort((a, b) => (b['popularity'] ?? 0).compareTo(a['popularity'] ?? 0));

          for (final movie in cast.take(5)) {
            final vote = (movie['vote_average'] ?? 0.0).toDouble();
            final score = 55.0 + (vote * 4.0);

            recommendations.add(_createRecommendation(
              movie,
              matchScore: score.clamp(0.0, 90.0),
              matchReason: 'Favori oyuncun: $actorName',
            ));
          }
        }
      } catch (_) {}
    }));
  }

  Future<void> _getSimilarMovieRecommendations(
    UserTasteProfile profile,
    List<MovieRecommendation> recommendations,
  ) async {
    if (profile.lovedMovieTmdbIds.isEmpty) return;

    // Paralel çalıştır
    await Future.wait(profile.lovedMovieTmdbIds.reversed.take(5).map((tmdbId) async {
      try {
        final uri = Uri.https(
          'api.themoviedb.org',
          '/3/movie/$tmdbId/recommendations',
          {'language': 'tr-TR', 'page': '1'},
        );

        final resp = await http.get(uri, headers: {
          'Authorization': 'Bearer $_tmdbBearer',
          'Accept': 'application/json',
        });

        if (resp.statusCode == 200) {
          final data = json.decode(resp.body);
          final results = data['results'] as List;

          for (final movie in results.take(5)) {
            final vote = (movie['vote_average'] ?? 0.0).toDouble();
            final score = 50.0 + (vote * 4.5);

            recommendations.add(_createRecommendation(
              movie,
              matchScore: score.clamp(0.0, 92.0),
              matchReason: 'Zevkine uygun',
            ));
          }
        }
      } catch (_) {}
    }));
  }

  MovieRecommendation _createRecommendation(
    Map<String, dynamic> movie, {
    required double matchScore,
    required String matchReason,
  }) {
    final posterPath = movie['poster_path'] as String?;
    final genreIds = List<int>.from(movie['genre_ids'] ?? []);

    return MovieRecommendation(
      tmdbId: movie['id'] as int,
      title: movie['title'] ?? '',
      posterUrl: posterPath != null 
          ? 'https://image.tmdb.org/t/p/w500$posterPath'
          : '',
      overview: movie['overview'] ?? '',
      voteAverage: (movie['vote_average'] ?? 0.0).toDouble(),
      releaseDate: movie['release_date'] ?? '',
      genres: genreIds.map((id) => _genreIdToName(id)).toList(),
      matchScore: matchScore,
      matchReason: matchReason,
    );
  }

  List<MovieRecommendation> _filterKnownMovies(
    List<MovieRecommendation> recommendations,
    UserTasteProfile profile, {
    Set<int>? ignoreIds,
  }) {
    final knownIds = {
      ...profile.lovedMovieTmdbIds,
      ...profile.dislikedMovieTmdbIds,
      ...?ignoreIds, 
    };
    return recommendations.where((rec) => !knownIds.contains(rec.tmdbId)).toList();
  }

  Future<void> _saveRecommendationsToCache(
    String uid,
    List<MovieRecommendation> recommendations,
  ) async {
    try {
      await _db.collection('userRecommendations').doc(uid).set({
        'recommendations': recommendations.map((r) => r.toMap()).toList(),
        'cachedAt': FieldValue.serverTimestamp(),
        'count': recommendations.length,
      });
    } catch (_) {}
  }

  Future<Map<String, int>> _getGenreIdMap() async {
    return {
      'aksiyon': 28, 'macera': 12, 'animasyon': 16, 'komedi': 35, 'suç': 80,
      'belgesel': 99, 'drama': 18, 'aile': 10751, 'fantastik': 14, 'tarih': 36,
      'korku': 27, 'müzik': 10402, 'gizem': 9648, 'romantik': 10749,
      'bilim kurgu': 878, 'gerilim': 53, 'savaş': 10752, 'western': 37,
    };
  }

  String _genreIdToName(int id) {
    final map = {
      28: 'Aksiyon', 12: 'Macera', 16: 'Animasyon', 35: 'Komedi', 80: 'Suç',
      99: 'Belgesel', 18: 'Drama', 10751: 'Aile', 14: 'Fantastik', 36: 'Tarih',
      27: 'Korku', 10402: 'Müzik', 9648: 'Gizem', 10749: 'Romantik',
      878: 'Bilim Kurgu', 53: 'Gerilim', 10752: 'Savaş', 37: 'Western',
    };
    return map[id] ?? 'Diğer';
  }
}