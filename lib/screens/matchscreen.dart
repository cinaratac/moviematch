import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;
import 'package:fluttergirdi/services/match_service.dart'
    as global_match; // uses services/match_service.dart
import 'package:fluttergirdi/services/like_service.dart';

/// Lists other users ordered by computed match score using `MatchService().findMatches(...)`.
class MatchListScreen extends StatelessWidget {
  const MatchListScreen({super.key});

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
      body: FutureBuilder<List<global_match.MatchResult>>(
        future: global_match.MatchService().findMatches(me.uid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Hata: ${snap.error}'));
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return const Center(child: Text('Şu an eşleşme yok.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final m = items[i];
              final pct = m.score.clamp(0, 100).toStringAsFixed(1);
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage:
                      (m.photoURL != null && m.photoURL!.isNotEmpty)
                      ? NetworkImage(m.photoURL!)
                      : null,
                  child: (m.photoURL == null || m.photoURL!.isEmpty)
                      ? const Icon(Icons.person)
                      : null,
                ),
                title: Text(
                  (m.displayName != null && m.displayName!.isNotEmpty)
                      ? m.displayName!
                      : (m.letterboxdUsername != null &&
                                m.letterboxdUsername!.isNotEmpty
                            ? '@${m.letterboxdUsername}'
                            : m.uid),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '%$pct uyum • Ortak 5★: ${m.commonFiveCount} • Ortak fav: ${m.commonFavCount}',
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => MatchScreen(result: m)),
                  );
                },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Geç',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () async {
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
                    ),
                    IconButton(
                      tooltip: 'Beğen',
                      icon: const Icon(Icons.favorite_rounded),
                      onPressed: () async {
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
                    ),
                  ],
                ),
              );
            },
          );
        },
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

    Future<List<FilmItem>> _read(List<String> keys) async {
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

    final favs = await _read(m.commonFavorites);
    final fives = await _read(m.commonFiveStars);
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
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      film.posterUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        child: const Center(
                          child: Icon(Icons.image_not_supported),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  film.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
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
