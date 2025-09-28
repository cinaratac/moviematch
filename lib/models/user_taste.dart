class UserTaste {
  final int? age;
  final List<String> favGenres;
  final List<String> favDirectors;
  final List<String> favActors;

  UserTaste({
    this.age,
    this.favGenres = const [],
    this.favDirectors = const [],
    this.favActors = const [],
  });

  factory UserTaste.fromMap(Map<String, dynamic>? data) {
    if (data == null) return UserTaste();
    return UserTaste(
      age: data['age'] as int?,
      favGenres: List<String>.from(data['favGenres'] ?? []),
      favDirectors: List<String>.from(data['favDirectors'] ?? []),
      favActors: List<String>.from(data['favActors'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'age': age,
      'favGenres': favGenres,
      'favDirectors': favDirectors,
      'favActors': favActors,
    };
  }
}
