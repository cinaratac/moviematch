import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';

class RecentWatchedMovies extends StatefulWidget {
  final String uid;
  final List<String> fallbackMovieKeys;

  const RecentWatchedMovies({
    super.key,
    required this.uid,
    this.fallbackMovieKeys = const [],
  });

  @override
  State<RecentWatchedMovies> createState() => _RecentWatchedMoviesState();
}

class _RecentWatchedMoviesState extends State<RecentWatchedMovies> {
  static final Map<String, List<_RecentWatchedMovie>> _resultCache = {};
  static final Map<String, Future<List<_RecentWatchedMovie>>> _pendingLoads =
      {};

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _historySub;
  List<_RecentWatchedMovie>? _movies;
  String? _activeLoadKey;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _refresh(null, notify: false);
    _listenHistory();
  }

  @override
  void didUpdateWidget(covariant RecentWatchedMovies oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid ||
        _fallbackKey(oldWidget.fallbackMovieKeys) !=
            _fallbackKey(widget.fallbackMovieKeys)) {
      _historySub?.cancel();
      _movies = null;
      _activeLoadKey = null;
      _isLoading = false;
      _refresh(null, notify: false);
      _listenHistory();
    }
  }

  @override
  void dispose() {
    _historySub?.cancel();
    super.dispose();
  }

  void _listenHistory() {
    if (widget.uid.isEmpty) return;
    _historySub = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .collection('watched')
        .doc('history')
        .snapshots()
        .listen((snapshot) {
          _refresh(snapshot.data());
        });
  }

  void _refresh(Map<String, dynamic>? historyData, {bool notify = true}) {
    if (widget.uid.isEmpty) return;

    final loadKey = _cacheKey(
      widget.uid,
      historyData,
      widget.fallbackMovieKeys,
    );
    if (_activeLoadKey == loadKey && (_isLoading || _movies != null)) return;

    _activeLoadKey = loadKey;
    final cached = _resultCache[loadKey];
    if (cached != null) {
      if (notify && mounted) {
        setState(() {
          _movies = cached;
          _isLoading = false;
        });
      } else {
        _movies = cached;
        _isLoading = false;
      }
      return;
    }

    if (notify && mounted) {
      setState(() => _isLoading = true);
    } else {
      _isLoading = true;
    }

    final future = _pendingLoads.putIfAbsent(
      loadKey,
      () => _loadRecentMovies(historyData, widget.fallbackMovieKeys),
    );

    future
        .then((loaded) {
          _pendingLoads.remove(loadKey);
          _remember(loadKey, loaded);
          if (!mounted || _activeLoadKey != loadKey) return;
          setState(() {
            _movies = loaded;
            _isLoading = false;
          });
        })
        .catchError((_) {
          _pendingLoads.remove(loadKey);
          if (!mounted || _activeLoadKey != loadKey) return;
          setState(() {
            _movies = const [];
            _isLoading = false;
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.uid.isEmpty) return const SizedBox.shrink();

    final movies = _movies ?? const <_RecentWatchedMovie>[];
    if (movies.isEmpty && !_isLoading) return const SizedBox.shrink();

    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black87;
    final placeholderCount = math.min(
      5,
      math.max(3, widget.fallbackMovieKeys.length),
    );
    final itemCount = movies.isNotEmpty ? movies.length : placeholderCount;

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
              itemCount: itemCount,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                if (movies.isEmpty) {
                  return _RecentWatchedPlaceholder(textColor: textColor);
                }
                return _RecentWatchedPoster(movie: movies[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  static void _remember(String key, List<_RecentWatchedMovie> movies) {
    _resultCache[key] = movies;
    if (_resultCache.length <= 80) return;
    _resultCache.remove(_resultCache.keys.first);
  }
}

class _RecentWatchedPoster extends StatelessWidget {
  final _RecentWatchedMovie movie;

  const _RecentWatchedPoster({required this.movie});

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black87;

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
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: textColor.withValues(alpha: 0.72),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentWatchedPlaceholder extends StatelessWidget {
  final Color textColor;

  const _RecentWatchedPlaceholder({required this.textColor});

  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return SizedBox(
      width: 76,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ColoredBox(color: fill, child: const SizedBox.expand()),
            ),
          ),
          const SizedBox(height: 5),
          Container(
            height: 9,
            width: 58,
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
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
  Map<String, dynamic>? historyData,
  List<String> fallbackMovieKeys,
) async {
  final db = FirebaseFirestore.instance;
  final orderedKeys = <String>[];

  final recentIds = historyData?['recentIds'];
  if (recentIds is List) {
    orderedKeys.addAll(recentIds.map((id) => id.toString()));
  }

  if (orderedKeys.isEmpty) {
    final ids = historyData?['ids'];
    if (ids is Map) {
      orderedKeys.addAll(ids.keys.map((id) => id.toString()).toList().reversed);
    }
  }

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

String _cacheKey(
  String uid,
  Map<String, dynamic>? historyData,
  List<String> fallbackMovieKeys,
) {
  final historyKeys = <String>[];
  final recentIds = historyData?['recentIds'];
  final ids = historyData?['ids'];
  if (recentIds is List) {
    historyKeys.addAll(recentIds.map((id) => id.toString()));
  } else if (ids is Map) {
    historyKeys.addAll(ids.keys.map((id) => id.toString()));
  }
  return '$uid|${_fallbackKey(historyKeys)}|${_fallbackKey(fallbackMovieKeys)}';
}

String _fallbackKey(List<String> keys) {
  return _dedupeKeys(keys).join(',');
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
