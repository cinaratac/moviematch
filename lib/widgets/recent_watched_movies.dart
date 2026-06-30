import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';

class RecentWatchedMovies extends StatelessWidget {
  final String uid;
  final List<String> fallbackMovieKeys;

  const RecentWatchedMovies({
    super.key,
    required this.uid,
    this.fallbackMovieKeys = const [],
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_RecentWatchedMovie>>(
      future: _loadRecentMovies(uid, fallbackMovieKeys),
      builder: (context, snapshot) {
        final movies = snapshot.data ?? const <_RecentWatchedMovie>[];
        if (movies.isEmpty) return const SizedBox.shrink();

        final textColor = Theme.of(context).brightness == Brightness.dark
            ? Colors.white
            : Colors.black87;

        return Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 18,
                    color: textColor.withValues(alpha: 0.82),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'Son İzlenenler',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 116,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: movies.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final movie = movies[index];
                    return GestureDetector(
                      onTap: movie.tmdbId == null
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MovieDetailScreen(
                                    tmdbId: movie.tmdbId!,
                                    title: movie.title,
                                    posterUrl: movie.posterUrl,
                                  ),
                                ),
                              );
                            },
                      child: SizedBox(
                        width: 76,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: AspectRatio(
                                  aspectRatio: 2 / 3,
                                  child: PosterImage(
                                    posterUrl: movie.posterUrl,
                                    title: movie.title,
                                    tmdbId: movie.tmdbId,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              movie.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: textColor.withValues(alpha: 0.72),
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RecentWatchedMovie {
  final String key;
  final String title;
  final String posterUrl;
  final int? tmdbId;

  const _RecentWatchedMovie({
    required this.key,
    required this.title,
    required this.posterUrl,
    this.tmdbId,
  });
}

Future<List<_RecentWatchedMovie>> _loadRecentMovies(
  String uid,
  List<String> fallbackMovieKeys,
) async {
  if (uid.isEmpty) return const [];

  final db = FirebaseFirestore.instance;
  final orderedKeys = <String>[];

  try {
    final historyDoc = await db
        .collection('users')
        .doc(uid)
        .collection('watched')
        .doc('history')
        .get(const GetOptions(source: Source.serverAndCache));
    final data = historyDoc.data() ?? const <String, dynamic>{};

    final recentIds = data['recentIds'];
    if (recentIds is List) {
      orderedKeys.addAll(recentIds.map((id) => id.toString()));
    }

    if (orderedKeys.isEmpty) {
      final ids = data['ids'];
      if (ids is Map) {
        orderedKeys.addAll(
          ids.keys.map((id) => id.toString()).toList().reversed,
        );
      }
    }
  } catch (_) {}

  if (orderedKeys.isEmpty) {
    orderedKeys.addAll(fallbackMovieKeys);
  }

  final cleanKeys = _dedupeKeys(orderedKeys).take(18).toList();
  if (cleanKeys.isEmpty) return const [];

  final byKey = <String, _RecentWatchedMovie>{};

  for (var i = 0; i < cleanKeys.length; i += 10) {
    final chunk = cleanKeys.sublist(i, math.min(i + 10, cleanKeys.length));
    try {
      final qs = await db
          .collection('catalog_films')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in qs.docs) {
        final movie = _movieFromDoc(doc);
        byKey[doc.id] = movie;
        if (movie.tmdbId != null) {
          byKey[movie.tmdbId.toString()] = movie;
        }
      }
    } catch (_) {}

    final numericIds = chunk
        .map((key) => int.tryParse(key))
        .whereType<int>()
        .toSet()
        .toList();
    if (numericIds.isEmpty) continue;

    try {
      final qs = await db
          .collection('catalog_films')
          .where('tmdbId', whereIn: numericIds.take(10).toList())
          .get();
      for (final doc in qs.docs) {
        final movie = _movieFromDoc(doc);
        byKey[doc.id] = movie;
        if (movie.tmdbId != null) {
          byKey[movie.tmdbId.toString()] = movie;
        }
      }
    } catch (_) {}
  }

  return [
    for (final key in cleanKeys)
      if (byKey[key] != null) byKey[key]!,
  ].take(5).toList();
}

List<String> _dedupeKeys(Iterable<String> keys) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in keys) {
    final key = raw.trim().toLowerCase();
    if (key.isEmpty) continue;
    if (seen.add(key)) out.add(key);
  }
  return out;
}

_RecentWatchedMovie _movieFromDoc(
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
) {
  final data = doc.data();
  final rawTmdbId = data['tmdbId'];
  return _RecentWatchedMovie(
    key: doc.id,
    title:
        (data['title'] ??
                data['titleTr'] ??
                data['originalTitle'] ??
                data['name'] ??
                'Film')
            .toString(),
    posterUrl: (data['posterUrl'] ?? data['poster'] ?? data['image'] ?? '')
        .toString(),
    tmdbId: rawTmdbId is num
        ? rawTmdbId.toInt()
        : int.tryParse(rawTmdbId?.toString() ?? ''),
  );
}
