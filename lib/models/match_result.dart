class MatchResult {
  final String otherUid;
  final double score;
  final List<String> commonLoved;
  final List<String> commonDisliked;
  final List<String> posters;

  MatchResult({
    required this.otherUid,
    required this.score,
    required this.commonLoved,
    required this.commonDisliked,
    required this.posters,
  });

  Map<String, dynamic> toMap() {
    return {
      'otherUid': otherUid,
      'score': score,
      'commonLoved': commonLoved,
      'commonDisliked': commonDisliked,
      'posters': posters,
    };
  }

  factory MatchResult.fromMap(Map<String, dynamic> map) {
    return MatchResult(
      otherUid: map['otherUid'] ?? '',
      score: (map['score'] ?? 0).toDouble(),
      commonLoved: List<String>.from(map['commonLoved'] ?? []),
      commonDisliked: List<String>.from(map['commonDisliked'] ?? []),
      posters: List<String>.from(map['posters'] ?? []),
    );
  }
}
