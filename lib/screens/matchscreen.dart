import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;
import 'package:fluttergirdi/services/match_service.dart'
    as global_match; // uses services/match_service.dart
import 'package:fluttergirdi/services/like_service.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';

/// Lists other users ordered by computed match score using `MatchService().findMatches(...)`.
class MatchListScreen extends StatefulWidget {
  const MatchListScreen({super.key});

  @override
  State<MatchListScreen> createState() => _MatchListScreenState();
}

class _MatchListScreenState extends State<MatchListScreen> {
  final _scrollController = ScrollController();
  final _pageSize = 12; // how many cards per "page"
  List<global_match.MatchResult> _all = const [];
  int _visibleCount = 0;
  bool _initialLoading = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      setState(() {
        _initialLoading = false;
        _all = const [];
      });
      return;
    }
    try {
      // NOTE: We fetch once, then reveal incrementally for quick first paint.
      final results = await global_match.MatchService().findMatches(me.uid);
      if (!mounted) return;
      setState(() {
        _all = results;
        _visibleCount = results.isEmpty
            ? 0
            : (_pageSize).clamp(0, results.length);
        _initialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // propagate via Scaffold below
      setState(() {
        _all = const [];
        _initialLoading = false;
      });
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Eşleşmeler alınamadı: $e')));
    }
  }

  void _onScroll() {
    if (_loadingMore || _initialLoading) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // When user is within 400px of bottom, reveal next page
    if (position.pixels > position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_visibleCount >= _all.length) return;
    setState(() => _loadingMore = true);
    await Future<void>.delayed(
      const Duration(milliseconds: 50),
    ); // allow a frame
    if (!mounted) return;
    final next = (_visibleCount + _pageSize).clamp(0, _all.length);
    setState(() {
      _visibleCount = next;
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      return const Scaffold(
        body: Center(child: Text('Oturum açmanız gerekiyor')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Eşleşmeler')),
      body: _initialLoading
          ? const Center(child: CircularProgressIndicator())
          : (_all.isEmpty
                ? const Center(child: Text('Şu an eşleşme yok.'))
                : RefreshIndicator(
                    onRefresh: _loadInitial,
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: _visibleCount + 1, // +1 for loader at the end
                      itemBuilder: (context, i) {
                        if (i >= _visibleCount) {
                          final hasMore = _visibleCount < _all.length;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: hasMore
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Hepsi bu kadar 👋'),
                            ),
                          );
                        }
                        final m = _all[i];
                        return _MatchCard(
                          result: m,
                          onOpen: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => MatchScreen(result: m),
                              ),
                            );
                          },
                          onLike: () async {
                            try {
                              await LikeService.instance.likeUser(
                                m.uid,
                                commonFavoritesCount: m.commonFavCount,
                                commonFiveStarsCount: m.commonFiveCount,
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Beğenildi')),
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Beğenme hatası: $e')),
                              );
                            }
                          },
                          onPass: () async {
                            try {
                              await LikeService.instance.passUser(m.uid);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Geçildi')),
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Geç hatası: $e')),
                              );
                            }
                          },
                        );
                      },
                    ),
                  )),
    );
  }
}

class _MatchCard extends StatelessWidget {
  final global_match.MatchResult result;
  final VoidCallback onOpen;
  final VoidCallback onLike;
  final VoidCallback onPass;
  const _MatchCard({
    required this.result,
    required this.onOpen,
    required this.onLike,
    required this.onPass,
  });

  @override
  Widget build(BuildContext context) {
    final m = result;
    final theme = Theme.of(context);
    final pct = m.score.clamp(0, 100).toStringAsFixed(1);
    final title = (m.displayName != null && m.displayName!.isNotEmpty)
        ? m.displayName!
        : (m.letterboxdUsername != null && m.letterboxdUsername!.isNotEmpty
              ? '@${m.letterboxdUsername}'
              : m.uid);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          final m = result;
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: m.uid)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: FutureBuilder<_CardData>(
            future: _loadCardData(m),
            builder: (context, snap) {
              final cd = snap.data;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundImage:
                            (m.photoURL != null && m.photoURL!.isNotEmpty)
                            ? NetworkImage(m.photoURL!)
                            : null,
                        child: (m.photoURL == null || m.photoURL!.isEmpty)
                            ? const Icon(Icons.person, size: 40)
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _Pill(icon: Icons.percent, text: '%$pct uyum'),
                                _Pill(
                                  icon: Icons.star_rate_rounded,
                                  text: 'Ortak 5★: ${m.commonFiveCount}',
                                ),
                                _Pill(
                                  icon: Icons.favorite_outline,
                                  text: 'Ortak fav: ${m.commonFavCount}',
                                ),
                                if (cd?.age != null)
                                  _Pill(
                                    icon: Icons.cake_outlined,
                                    text: 'Yaş: ${cd!.age}',
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Favorite genres / directors / actors chips (limited)
                  if (cd != null) ...[
                    if (cd.genres.isNotEmpty)
                      _ChipsRow(
                        label: 'Sevdiği Türler',
                        values: cd.genres.take(6).toList(),
                      ),
                    if (cd.directors.isNotEmpty)
                      _ChipsRow(
                        label: 'Sevdiği Yönetmenler',
                        values: cd.directors.take(4).toList(),
                      ),
                    if (cd.actors.isNotEmpty)
                      _ChipsRow(
                        label: 'Sevdiği Oyuncular',
                        values: cd.actors.take(4).toList(),
                      ),
                    const SizedBox(height: 8),
                  ] else ...[
                    const _SkeletonLine(),
                    const SizedBox(height: 8),
                  ],

                  // Common film posters preview (favorites & 5★)
                  if (cd != null &&
                      (cd.favPosters.isNotEmpty ||
                          cd.fivePosters.isNotEmpty)) ...[
                    if (cd.fivePosters.isNotEmpty) ...[
                      const _SectionLabel(text: 'Ortak 5★ Filmler'),
                      const SizedBox(height: 8),
                      _PosterStrip(urls: cd.fivePosters),
                      const SizedBox(height: 12),
                    ],
                    if (cd.favPosters.isNotEmpty) ...[
                      const _SectionLabel(text: 'Ortak Favoriler'),
                      const SizedBox(height: 8),
                      _PosterStrip(urls: cd.favPosters),
                      const SizedBox(height: 12),
                    ],
                  ] else ...[
                    if (snap.connectionState == ConnectionState.waiting)
                      const _SkeletonPosters(),
                  ],

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onPass,
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('Geç'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onLike,
                          icon: const Icon(Icons.favorite_rounded),
                          label: const Text('Beğen'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Pill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(text, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class FilmItem {
  final String title;
  final String posterUrl;
  const FilmItem({required this.title, required this.posterUrl});
}

/// Shows details for a single match, resolving posters/titles from `catalog_films/{filmKey}`.
class MatchScreen extends StatelessWidget {
  final global_match.MatchResult result;
  const MatchScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    // Normalize possible nulls from MatchResult for new common fields
    final commonGenres = result.commonGenres ?? const <String>[];
    final commonDirectors = result.commonDirectors ?? const <String>[];
    final commonActors = result.commonActors ?? const <String>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          (result.displayName != null && result.displayName!.isNotEmpty)
              ? result.displayName!
              : (result.letterboxdUsername != null &&
                        result.letterboxdUsername!.isNotEmpty
                    ? '@${result.letterboxdUsername}'
                    : result.uid),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        actions: [
          IconButton(
            tooltip: 'Geç',
            icon: const Icon(Icons.close_rounded),
            onPressed: () async {
              try {
                await LikeService.instance.passUser(result.uid);
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Geçildi')));
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Geç hatası: $e')));
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<_Resolved>(
        future: _resolveCommonFilms(result),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Detay yüklenemedi: ${snap.error}'));
          }
          final data = snap.data ?? const _Resolved();
          final pct = result.score.clamp(0, 100).toStringAsFixed(1);

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '%$pct uyum',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _StatChip(
                            label: 'Ortak 5★',
                            value: data.fiveStars.length,
                          ),
                          _StatChip(
                            label: 'Ortak favori',
                            value: data.favorites.length,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (commonGenres.isNotEmpty)
                        _ChipsRow(
                          label: 'Ortak Türler',
                          values: commonGenres.take(8).toList(),
                        ),
                      if (commonDirectors.isNotEmpty)
                        _ChipsRow(
                          label: 'Ortak Yönetmenler',
                          values: commonDirectors.take(6).toList(),
                        ),
                      if (commonActors.isNotEmpty)
                        _ChipsRow(
                          label: 'Ortak Oyuncular',
                          values: commonActors.take(6).toList(),
                        ),
                    ],
                  ),
                ),
              ),
              _SectionGrid(title: 'Ortak 5★', films: data.fiveStars),
              _SectionGrid(title: 'Ortak Favoriler', films: data.favorites),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          try {
            await LikeService.instance.likeUser(
              result.uid,
              commonFavoritesCount: result.commonFavCount,
              commonFiveStarsCount: result.commonFiveCount,
            );
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Beğenildi')));
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Beğenme hatası: $e')));
          }
        },
        icon: const Icon(Icons.favorite_rounded),
        label: const Text('Beğen'),
      ),
    );
  }

  Future<_Resolved> _resolveCommonFilms(global_match.MatchResult m) async {
    final db = FirebaseFirestore.instance;

    Future<List<FilmItem>> readChunk(List<String> keys) async {
      if (keys.isEmpty) return const [];
      final items = <FilmItem>[];
      const chunkSize = 10; // Firestore whereIn max 10

      for (var i = 0; i < keys.length; i += chunkSize) {
        final chunk = keys.sublist(i, math.min(i + chunkSize, keys.length));
        final qs = await db
            .collection('catalog_films')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in qs.docs) {
          final d = doc.data();
          items.add(
            FilmItem(
              title: (d['title'] ?? '') as String,
              posterUrl: (d['posterUrl'] ?? '') as String,
            ),
          );
        }
      }
      return items;
    }

    final favs = await readChunk(m.commonFavorites);
    final fives = await readChunk(m.commonFiveStars);
    return _Resolved(favorites: favs, fiveStars: fives);
  }
}

class _Resolved {
  final List<FilmItem> favorites;
  final List<FilmItem> fiveStars;
  const _Resolved({this.favorites = const [], this.fiveStars = const []});
}

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  const _StatChip({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Chip(avatar: const Icon(Icons.movie), label: Text('$label: $value'));
  }
}

class _SectionGrid extends StatelessWidget {
  final String title;
  final List<FilmItem> films;
  const _SectionGrid({required this.title, required this.films});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (films.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(width: 8),
              Text('—', style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            _Grid(films: films),
          ],
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  final List<FilmItem> films;
  const _Grid({required this.films});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 110).floor().clamp(3, 6);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: films.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2 / 3,
          ),
          itemBuilder: (context, index) {
            final film = films[index];
            return AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      film.posterUrl,
                      fit: BoxFit.cover,
                      cacheWidth:
                          300, // ~2x of 150px width; lets engine request smaller bitmaps
                      filterQuality: FilterQuality.low,
                      errorBuilder: (_, __, ___) => Container(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        child: const Center(
                          child: Icon(Icons.image_not_supported),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                        ),
                        child: Text(
                          film.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: Colors.white, height: 1.1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Convenience entry screen
class MatchesEntry extends StatelessWidget {
  const MatchesEntry({super.key});
  @override
  Widget build(BuildContext context) => const MatchListScreen();
}

// --- CardData and helpers for match card preview ---

class _CardData {
  final int? age;
  final List<String> genres;
  final List<String> directors;
  final List<String> actors;
  final List<String> favPosters; // from commonFavorites
  final List<String> fivePosters; // from commonFiveStars
  const _CardData({
    this.age,
    this.genres = const [],
    this.directors = const [],
    this.actors = const [],
    this.favPosters = const [],
    this.fivePosters = const [],
  });
}

Future<_CardData> _loadCardData(global_match.MatchResult m) async {
  final db = FirebaseFirestore.instance;

  // 1) Read profile prefs from users/{uid}
  final u = await db.collection('users').doc(m.uid).get();
  int? age;
  List<String> genres = const [];
  List<String> directors = const [];
  List<String> actors = const [];
  if (u.exists) {
    final d = u.data() ?? {};
    final a = d['age'];
    if (a is int) age = a; // nullable
    genres = List<String>.from(d['favGenres'] ?? const []);
    directors = List<String>.from(d['favDirectors'] ?? const []);
    actors = List<String>.from(d['favActors'] ?? const []);
  }

  // 2) Resolve a few poster URLs from catalog for common films
  Future<List<String>> readPosters(List<String> keys, {int limit = 8}) async {
    if (keys.isEmpty) return const [];
    final pick = keys.take(limit).toList();
    final posters = <String>[];
    const chunk = 10;
    for (var i = 0; i < pick.length; i += chunk) {
      final sub = pick.sublist(i, math.min(i + chunk, pick.length));
      final qs = await db
          .collection('catalog_films')
          .where(FieldPath.documentId, whereIn: sub)
          .get();
      for (final doc in qs.docs) {
        final d = doc.data();
        final p = (d['posterUrl'] ?? '') as String;
        if (p.isNotEmpty) posters.add(p);
      }
    }
    return posters;
  }

  final favPosters = await readPosters(m.commonFavorites, limit: 8);
  final fivePosters = await readPosters(m.commonFiveStars, limit: 8);

  return _CardData(
    age: age,
    genres: genres,
    directors: directors,
    actors: actors,
    favPosters: favPosters,
    fivePosters: fivePosters,
  );
}

class _ChipsRow extends StatelessWidget {
  final String label;
  final List<String> values;
  const _ChipsRow({required this.label, required this.values});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in values)
                  Chip(label: Text(v, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});
  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.bodyLarge);
  }
}

class _PosterStrip extends StatelessWidget {
  final List<String> urls;
  const _PosterStrip({required this.urls});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final u = urls[i];
          return AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                u,
                fit: BoxFit.cover,
                cacheWidth: 240, // ~120px * 2 devicePixelRatio
                filterQuality: FilterQuality.low,
                errorBuilder: (_, __, ___) => Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Center(child: Icon(Icons.image_not_supported)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 16,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _SkeletonPosters extends StatelessWidget {
  const _SkeletonPosters();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: Row(
        children: List.generate(
          4,
          (i) => Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == 3 ? 0 : 8),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
