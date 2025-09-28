class MatchResult {
  final String userId;
  final double score; // toplam eşleşme puanı
  final List<String> commonFilms;
  final List<String> commonDirectors;
  final List<String> commonActors;
  final List<String> commonGenres;
  final String? displayName;
  final String? letterboxdUsername;
  final String? photoURL;

  MatchResult({
    required this.userId,
    required this.score,
    required this.commonFilms,
    required this.commonDirectors,
    required this.commonActors,
    required this.commonGenres,
    this.displayName,
    this.letterboxdUsername,
    this.photoURL,
  });

  factory MatchResult.fromJson(Map<String, dynamic> json) {
    return MatchResult(
      userId: json['userId'] as String,
      score: (json['score'] as num).toDouble(),
      commonFilms: (json['commonFilms'] as List<dynamic>? ?? []).cast<String>(),
      commonDirectors: (json['commonDirectors'] as List<dynamic>? ?? [])
          .cast<String>(),
      commonActors: (json['commonActors'] as List<dynamic>? ?? [])
          .cast<String>(),
      commonGenres: (json['commonGenres'] as List<dynamic>? ?? [])
          .cast<String>(),
      displayName: json['displayName'] as String?,
      letterboxdUsername: json['letterboxdUsername'] as String?,
      photoURL: json['photoURL'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'score': score,
      'commonFilms': commonFilms,
      'commonDirectors': commonDirectors,
      'commonActors': commonActors,
      'commonGenres': commonGenres,
      'displayName': displayName,
      'letterboxdUsername': letterboxdUsername,
      'photoURL': photoURL,
    };
  }
}
