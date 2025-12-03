import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../secrets.dart';

/// Film Öneri Modeli
class MovieRecommendation {
  final int tmdbId;
  final String title;
  final String posterUrl;
  final String overview;
  final double voteAverage;
  final String releaseDate;
  final List<String> genres;
  double matchScore; // Artık değiştirilebilir (merge işlemi için)
  String matchReason; // Artık değiştirilebilir

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

  // Cache süresi (1 saat)
  static const Duration _cacheDuration = Duration(hours: 1);

  /// Ana öneri motoru - Kullanıcı için öneriler üretir
  Future<List<MovieRecommendation>> generateRecommendations(String uid) async {
    // 1. Kullanıcı profilini çek
    final profile = await _fetchUserProfile(uid);
    
    // Geçici ham liste
    final rawRecommendations = <MovieRecommendation>[];

    // 2. Paralel olarak farklı kaynaklardan öneriler topla (Havuzu genişletelim)
    await Future.wait([
      _getGenreBasedRecommendations(profile, rawRecommendations),
      _getDirectorBasedRecommendations(profile, rawRecommendations),
      _getActorBasedRecommendations(profile, rawRecommendations),
      _getSimilarMovieRecommendations(profile, rawRecommendations),
    ]);

    // 3. Tekilleştirme ve Puan Birleştirme (De-duplication)
    final uniqueMap = <int, MovieRecommendation>{};

    for (final rec in rawRecommendations) {
      if (uniqueMap.containsKey(rec.tmdbId)) {
        final existing = uniqueMap[rec.tmdbId]!;
        // Eğer zaten listede varsa:
        // 1. Puanını artır (Bonus puan)
        existing.matchScore = (existing.matchScore + 10).clamp(0.0, 100.0);
        
        // 2. Sebebi güncelle (Daha zengin açıklama)
        if (!existing.matchReason.contains(rec.matchReason)) {
           // Örnek: "Favori yönetmen" + ", Favori tür"
           // Çok uzun olmaması için basit bir check
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
    final filtered = _filterKnownMovies(mergedList, profile);

    // 5. Skorlarına göre sırala ve en iyi 30'u al
    filtered.sort((a, b) => b.matchScore.compareTo(a.matchScore));
    final top30 = filtered.take(30).toList();

    // 6. Firestore'a kaydet (cache)
    if (top30.isNotEmpty) {
      await _saveRecommendationsToCache(uid, top30);
    }

    return top30;
  }

  /// Cache'den önerileri getir
  Future<List<MovieRecommendation>?> getCachedRecommendations(String uid) async {
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

      return recommendationsData
          .map((e) => MovieRecommendation.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return null;
    }
  }

  // ... _fetchUserProfile ve _fetchTmdbIdsFromKeys metodları AYNI (değişiklik yok) ...
  Future<UserTasteProfile> _fetchUserProfile(String uid) async {
    final userDoc = await _db.collection('users').doc(uid).get();
    if (!userDoc.exists) return UserTasteProfile();

    final data = userDoc.data()!;
    final lovedIds = await _fetchTmdbIdsFromKeys(List<String>.from(data['fiveStarKeys'] ?? []));
    final dislikedIds = await _fetchTmdbIdsFromKeys(List<String>.from(data['dislikedKeys'] ?? []));

    // Ek olarak watchlist ve izlenenleri de "bilinen" olarak almalıyız ki tekrar önermeyelim
    // Ancak basitlik adına şimdilik mevcut yapıyı koruyoruz.
    
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

  /// Tür bazlı öneriler (Geliştirilmiş Puanlama)
  Future<void> _getGenreBasedRecommendations(
    UserTasteProfile profile,
    List<MovieRecommendation> recommendations,
  ) async {
    if (profile.favoriteGenres.isEmpty) return;

    final genreMap = await _getGenreIdMap();
    
    // İlk 5 favori türe bak (önceden 3'tü)
    for (final genreName in profile.favoriteGenres.take(5)) {
      final genreId = genreMap[genreName.toLowerCase()];
      if (genreId == null) continue;

      try {
        final uri = Uri.https('api.themoviedb.org', '/3/discover/movie', {
          'with_genres': genreId.toString(),
          'sort_by': 'vote_average.desc',
          'vote_count.gte': '300', // Filtreyi biraz gevşettik
          'language': 'tr-TR',
          'page': '1',
        });

        final resp = await http.get(uri, headers: {
          'Authorization': 'Bearer $_tmdbBearer',
          'Accept': 'application/json',
        });

        if (resp.statusCode == 200) {
          final data = json.decode(resp.body);
          final results = data['results'] as List;

          // Her türden en iyi 10 filmi al (önceden 5'ti)
          for (final movie in results.take(10)) {
            // Dinamik Skor: Baz (60) + (IMDB * 4) -> 7.0 ise 60 + 28 = 88 puan
            final vote = (movie['vote_average'] ?? 0.0).toDouble();
            final score = 50.0 + (vote * 5.0); // Max 100 civarı

            recommendations.add(_createRecommendation(
              movie,
              matchScore: score.clamp(0.0, 95.0),
              matchReason: 'Favori türün: $genreName',
            ));
          }
        }
      } catch (_) {}
    }
  }

  /// Yönetmen bazlı öneriler (Geliştirilmiş Arama)
  Future<void> _getDirectorBasedRecommendations(
    UserTasteProfile profile,
    List<MovieRecommendation> recommendations,
  ) async {
    if (profile.favoriteDirectors.isEmpty) return;

    for (final directorName in profile.favoriteDirectors.take(5)) {
      try {
        final searchUri = Uri.https('api.themoviedb.org', '/3/search/person', {
          'query': directorName,
          'language': 'tr-TR',
        });

        final searchResp = await http.get(searchUri, headers: {
          'Authorization': 'Bearer $_tmdbBearer',
          'Accept': 'application/json',
        });

        if (searchResp.statusCode != 200) continue;

        final searchData = json.decode(searchResp.body);
        final results = searchData['results'] as List;
        
        if (results.isEmpty) continue;
        
        // Doğru kişiyi bulma: Known for Directing?
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
          
          // Popülerliğe göre sırala ki en bilinenleri önersin
          directed.sort((a, b) => (b['popularity'] ?? 0).compareTo(a['popularity'] ?? 0));

          for (final movie in directed.take(5)) {
             final vote = (movie['vote_average'] ?? 0.0).toDouble();
             // Yönetmen filmleri genelde daha değerli (Baz 60)
             final score = 60.0 + (vote * 4.0); 

            recommendations.add(_createRecommendation(
              movie,
              matchScore: score.clamp(0.0, 98.0),
              matchReason: 'Favori yönetmen: $directorName',
            ));
          }
        }
      } catch (_) {}
    }
  }

  /// Oyuncu bazlı öneriler
  Future<void> _getActorBasedRecommendations(
    UserTasteProfile profile,
    List<MovieRecommendation> recommendations,
  ) async {
    if (profile.favoriteActors.isEmpty) return;

    for (final actorName in profile.favoriteActors.take(3)) {
      try {
        final searchUri = Uri.https('api.themoviedb.org', '/3/search/person', {
          'query': actorName,
          'language': 'tr-TR',
        });

        final searchResp = await http.get(searchUri, headers: {
          'Authorization': 'Bearer $_tmdbBearer',
          'Accept': 'application/json',
        });

        if (searchResp.statusCode != 200) continue;
        final searchData = json.decode(searchResp.body);
        final results = searchData['results'] as List;
        if (results.isEmpty) continue;

        // Oyunculuk kontrolü
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
          
          // Çok figüran olduğu filmleri elemek için 'order' kontrolü yapılabilir ama
          // şimdilik popülarite sıralaması yeterli
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
    }
  }

  /// Benzer filmler
  Future<void> _getSimilarMovieRecommendations(
    UserTasteProfile profile,
    List<MovieRecommendation> recommendations,
  ) async {
    if (profile.lovedMovieTmdbIds.isEmpty) return;

    // En son eklenen 5 sevilen filme bak
    for (final tmdbId in profile.lovedMovieTmdbIds.reversed.take(5)) {
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
              matchReason: 'Zevkine uygun', // Daha genel başlık
            ));
          }
        }
      } catch (_) {}
    }
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
    UserTasteProfile profile,
  ) {
    final knownIds = {
      ...profile.lovedMovieTmdbIds,
      ...profile.dislikedMovieTmdbIds,
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

  // _getGenreIdMap ve _genreIdToName aynı kalabilir...
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