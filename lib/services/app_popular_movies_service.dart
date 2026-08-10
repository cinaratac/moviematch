import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class AppPopularMoviesService {
  AppPopularMoviesService._();
  static final AppPopularMoviesService instance = AppPopularMoviesService._();

  Future<List<AppPopularMovie>> loadWeeklyPopularMovies({
    int resultLimit = 10,
    int maxWeeks = 3,
  }) async {
    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('getWeeklyPopularMovies')
          .call({'resultLimit': resultLimit, 'maxWeeks': maxWeeks});
      final data = Map<String, dynamic>.from(response.data as Map);
      final movies = data['movies'] is List ? data['movies'] as List : const [];
      return movies
          .map((raw) => AppPopularMovie.fromMap(Map<String, dynamic>.from(raw)))
          .where((movie) => movie.id.isNotEmpty && movie.title.isNotEmpty)
          .take(resultLimit)
          .toList(growable: false);
    } catch (e) {
      debugPrint('AppPopularMoviesService callable error: $e');
      return const [];
    }
  }
}

class AppPopularMovie {
  final String id;
  final int? tmdbId;
  final String title;
  final int? year;
  final String posterUrl;
  final int additions;

  const AppPopularMovie({
    required this.id,
    required this.tmdbId,
    required this.title,
    required this.year,
    required this.posterUrl,
    required this.additions,
  });

  factory AppPopularMovie.fromMap(Map<String, dynamic> map) {
    return AppPopularMovie(
      id: (map['id'] ?? '').toString(),
      tmdbId: _positiveInt(map['tmdbId']),
      title: (map['title'] ?? '').toString(),
      year: _positiveInt(map['year']),
      posterUrl: (map['posterUrl'] ?? '').toString(),
      additions: _positiveInt(map['additions']) ?? 0,
    );
  }

  static int? _positiveInt(Object? value) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return parsed != null && parsed > 0 ? parsed : null;
  }
}
