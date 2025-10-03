import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/services/letterboxd_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/services/chat_service.dart';
import 'package:fluttergirdi/screens/chat_room_screen.dart';
import 'dart:ui' as ui;

const Map<String, String> _lbImageHeaders = {
  'Referer': 'https://letterboxd.com',
  'User-Agent':
      'Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/117.0',
};

class PublicProfileScreen extends StatefulWidget {
  final String uid;
  const PublicProfileScreen({super.key, required this.uid});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  /// Blurred full-screen backdrop from the first favorite poster
  Widget _blurBackdrop() {
    if (_futureFavs == null) return const SizedBox.shrink();
    return FutureBuilder<List<LetterboxdFilm>>(
      future: _futureFavs,
      builder: (context, snap) {
        final list = snap.data ?? const <LetterboxdFilm>[];
        final hasPoster = list.isNotEmpty && list.first.posterUrl.isNotEmpty;
        if (!hasPoster) return const SizedBox.shrink();
        final url = list.first.posterUrl;
        return Positioned.fill(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  headers: _lbImageHeaders,
                  errorBuilder: (_, __, ___) => Container(color: Colors.black),
                ),
              ),
              // Koyu bir scrim ile kontrast arttır
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xCC000000),
                      Color(0x99000000),
                      Color(0x66000000),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<List<LetterboxdFilm>>? _futureFavs;
  Future<List<LetterboxdFilm>>? _futureFiveStars;
  Future<List<LetterboxdFilm>>? _futureDisliked;
  String? _lastLb;
  // Cache for watchlist catalog fetches to avoid repeated refetch on doc updates
  final Map<String, Future<List<Map<String, dynamic>?>>> _watchlistFutureCache =
      {};

  Future<List<Map<String, dynamic>?>> _fetchCatalogForKeys(
    List<String> keys,
  ) async {
    final fs = FirebaseFirestore.instance;

    // Preserve original order and exact casing of IDs
    final ordered = <String>[];
    final clean = <String>[];
    for (final raw in keys) {
      final s = raw.trim();
      if (s.isEmpty) continue;
      ordered.add(s);
      clean.add(s);
    }

    final found = <String, Map<String, dynamic>>{};
    const int chunk = 10; // Firestore whereIn limit

    // 1) Batch fetch with whereIn
    for (int i = 0; i < clean.length; i += chunk) {
      final part = clean.sublist(
        i,
        i + chunk > clean.length ? clean.length : i + chunk,
      );
      if (part.isEmpty) continue;
      final qs = await fs
          .collection('catalog_films')
          .where(FieldPath.documentId, whereIn: part)
          .get();
      for (final d in qs.docs) {
        found[d.id] = d.data();
      }
    }

    // 2) Fallback for any missing IDs — fetch individually to handle case/whitespace mismatches
    final missing = ordered.where((id) => !found.containsKey(id)).toList();
    for (final id in missing) {
      try {
        final snap = await fs.collection('catalog_films').doc(id).get();
        if (snap.exists) {
          found[id] = snap.data()!;
        }
      } catch (_) {
        // ignore individual failures
      }
    }

    // 3) Build result preserving original order, allow nulls for not-found
    final out = <Map<String, dynamic>?>[];
    for (final id in ordered) {
      out.add(found[id]);
    }
    return out;
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final doc = FirebaseFirestore.instance.collection('users').doc(widget.uid);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        backgroundColor: Colors.black.withValues(
          alpha: 0.20,
        ), // semi‑transparent
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: doc.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text('Kullanıcı bulunamadı'));
          }
          final data = snap.data!.data()!;
          final displayName = (data['displayName'] ?? '') as String;
          final lb = (data['letterboxdUsername'] ?? '') as String;
          final photoURL = (data['photoURL'] ?? '') as String;
          final appUsername = (data['username'] ?? '') as String; // NEW

          // Title fallback: username → displayName → @letterboxd → (İsimsiz)
          final titleText = appUsername.isNotEmpty
              ? appUsername
              : (displayName.isNotEmpty
                    ? displayName
                    : (lb.isNotEmpty ? '@$lb' : '(İsimsiz)'));

          // Favori/5★/dislike verilerini sadece Letterboxd kullanıcı adı değiştiğinde yeniden hazırla
          if (_lastLb != lb) {
            _lastLb = lb;
            if (lb.isNotEmpty) {
              _futureFavs = LetterboxdService.fetchFavorites(lb);
              _futureFiveStars = LetterboxdService.fetchFiveStar(lb);
              _futureDisliked = LetterboxdService.fetchDisliked(lb);
            } else {
              _futureFavs = null;
              _futureFiveStars = null;
              _futureDisliked = null;
            }
          }

          return Stack(
            children: [
              _blurBackdrop(),
              ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  MediaQuery.of(context).padding.top + kToolbarHeight + 12,
                  16,
                  16,
                ),
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundImage: photoURL.isNotEmpty
                            ? NetworkImage(photoURL)
                            : null,
                        child: photoURL.isEmpty
                            ? Text(
                                displayName.isNotEmpty
                                    ? displayName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(fontSize: 24),
                              )
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              titleText,
                              style: Theme.of(context).textTheme.titleLarge,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (displayName.isNotEmpty &&
                                titleText != displayName)
                              Text(
                                displayName,
                                style: Theme.of(context).textTheme.bodySmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (lb.isNotEmpty)
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      runAlignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Text(
                          'Letterboxd: @$lb',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton.icon(
                              onPressed: () =>
                                  _openUrl('https://letterboxd.com/$lb/'),
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('Profili aç'),
                            ),
                            const SizedBox(width: 6),
                            TextButton.icon(
                              onPressed: () async {
                                final myUid =
                                    FirebaseAuth.instance.currentUser!.uid;
                                final chatId = await ChatService.instance
                                    .getOrCreateChat(myUid, widget.uid);
                                if (!context.mounted) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatRoomScreen(
                                      chatId: chatId,
                                      otherUid: widget.uid,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.message),
                              label: const Text('Mesaj gönder'),
                            ),
                          ],
                        ),
                      ],
                    )
                  else
                    const Text('Letterboxd bağlı değil'),

                  const SizedBox(height: 12),
                  // — Kullanıcı tercihleri (yaş, türler, yönetmenler, oyuncular) — (tek stream'den render)
                  () {
                    final age = data['age'];
                    final genres = List<String>.from(
                      data['favGenres'] ?? const [],
                    );
                    final directors = List<String>.from(
                      data['favDirectors'] ?? const [],
                    );
                    final actors = List<String>.from(
                      data['favActors'] ?? const [],
                    );

                    if ((age == null || (age is int && age <= 0)) &&
                        genres.isEmpty &&
                        directors.isEmpty &&
                        actors.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    Widget chipWrap(String title, List<String> items) {
                      if (items.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: items
                                  .map((e) => Chip(label: Text(e)))
                                  .toList(),
                            ),
                          ],
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (age is int && age > 0) const SizedBox(height: 8),
                        if (age is int && age > 0)
                          Row(
                            children: [
                              const Icon(Icons.cake, size: 18),
                              const SizedBox(width: 6),
                              Text('Yaş: $age'),
                            ],
                          ),
                        chipWrap('Sevdiği türler', genres),
                        chipWrap('Sevdiği yönetmenler', directors),
                        chipWrap('Sevdiği oyuncular', actors),
                        const SizedBox(height: 12),
                      ],
                    );
                  }(),
                  if (lb.isNotEmpty)
                    Text(
                      'Favori Filmler',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  if (lb.isNotEmpty) const SizedBox(height: 8),
                  if (lb.isNotEmpty)
                    FutureBuilder<List<LetterboxdFilm>>(
                      future: _futureFavs,
                      builder: (context, s) {
                        if (s.connectionState == ConnectionState.waiting) {
                          return const SizedBox(
                            height: 180,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (s.hasError) {
                          return Text('Favoriler alınamadı: ${s.error}');
                        }
                        final items = s.data ?? [];
                        if (items.isEmpty) {
                          return const Text('Favori film bulunamadı.');
                        }
                        return SizedBox(
                          height: 180,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (_, i) {
                              final f = items[i];
                              return AspectRatio(
                                aspectRatio: 2 / 3,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.network(
                                        f.posterUrl,
                                        headers: _lbImageHeaders,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: Colors.black26,
                                          alignment: Alignment.center,
                                          child: const Icon(
                                            Icons.image_not_supported,
                                          ),
                                        ),
                                      ),
                                      Align(
                                        alignment: Alignment.bottomCenter,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 4,
                                          ),
                                          color: Colors.black54,
                                          child: Text(
                                            f.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.white,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  if (lb.isNotEmpty) const SizedBox(height: 16),
                  if (lb.isNotEmpty)
                    Text(
                      'Sevdiği Filmler',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  if (lb.isNotEmpty)
                    FutureBuilder<List<LetterboxdFilm>>(
                      future: _futureFiveStars,
                      builder: (context, s) {
                        if (s.connectionState == ConnectionState.waiting) {
                          return const SizedBox(
                            height: 180,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (s.hasError) {
                          return const Text('5★ film bulunamadı.');
                        }
                        final items = s.data ?? [];
                        if (items.isEmpty) {
                          return const Text('5★ film bulunamadı.');
                        }
                        return SizedBox(
                          height: 180,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (_, i) {
                              final f = items[i];
                              return AspectRatio(
                                aspectRatio: 2 / 3,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.network(
                                        f.posterUrl,
                                        headers: _lbImageHeaders,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: Colors.black26,
                                          alignment: Alignment.center,
                                          child: const Icon(
                                            Icons.image_not_supported,
                                          ),
                                        ),
                                      ),
                                      Align(
                                        alignment: Alignment.bottomCenter,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 4,
                                          ),
                                          color: Colors.black54,
                                          child: Text(
                                            f.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.white,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  if (lb.isNotEmpty) const SizedBox(height: 16),
                  if (lb.isNotEmpty)
                    Text(
                      'Sevmediği Filmler',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  if (lb.isNotEmpty)
                    FutureBuilder<List<LetterboxdFilm>>(
                      future: _futureDisliked,
                      builder: (context, s) {
                        if (s.connectionState == ConnectionState.waiting) {
                          return const SizedBox(
                            height: 180,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (s.hasError) {
                          return Text(
                            'Sevmediği filmler alınamadı: ${s.error}',
                          );
                        }
                        final items = s.data ?? [];
                        if (items.isEmpty) {
                          return const Text('Sevmediği film bulunamadı.');
                        }
                        return SizedBox(
                          height: 180,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (_, i) {
                              final f = items[i];
                              return AspectRatio(
                                aspectRatio: 2 / 3,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.network(
                                        f.posterUrl,
                                        headers: _lbImageHeaders,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: Colors.black26,
                                          alignment: Alignment.center,
                                          child: const Icon(
                                            Icons.image_not_supported,
                                          ),
                                        ),
                                      ),
                                      Align(
                                        alignment: Alignment.bottomCenter,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 4,
                                          ),
                                          color: Colors.black54,
                                          child: Text(
                                            f.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.white,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  // --- WATCHLIST SECTION ---
                  const SizedBox(height: 16),
                  Text(
                    'Watchlist',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      // Accept multiple shapes: keys array OR inline film maps
                      final List<dynamic> keysDyn =
                          (data['watchlistKeys'] ??
                                  data['watchlistIds'] ??
                                  data['watchlist_keys'] ??
                                  [])
                              as List<dynamic>;
                      final keys = keysDyn
                          .map((e) => e.toString())
                          .where((e) => e.isNotEmpty)
                          .toList();

                      // Inline film fallback (if user doc stores film maps instead of keys)
                      final List<dynamic> inlineDyn =
                          (data['watchlistFilms'] ?? data['watchlist'] ?? [])
                              as List<dynamic>;
                      final List<Map<String, dynamic>> inlineFilms = inlineDyn
                          .whereType<Map<String, dynamic>>()
                          .toList();

                      // If both empty
                      if (keys.isEmpty && inlineFilms.isEmpty) {
                        return const Text('Watchlist boş.');
                      }

                      final limited = keys.take(30).toList();

                      // Build a stable cache key and reuse future to prevent duplicate loads
                      final hash = limited.join('|');

                      return FutureBuilder<List<Map<String, dynamic>?>>(
                        future: limited.isEmpty
                            ? Future.value(const <Map<String, dynamic>?>[])
                            : (_watchlistFutureCache[hash] ??=
                                  _fetchCatalogForKeys(limited)),
                        builder: (context, fsnap) {
                          List<Map<String, dynamic>> films = const [];

                          if (fsnap.connectionState ==
                                  ConnectionState.waiting &&
                              inlineFilms.isEmpty) {
                            return const SizedBox(
                              height: 180,
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }

                          if (fsnap.hasData && fsnap.data != null) {
                            films = fsnap.data!
                                .where((m) => m != null)
                                .map((m) => m!)
                                .toList();
                          }

                          // If catalog fetch yielded nothing but inline films exist, use inline
                          if (films.isEmpty && inlineFilms.isNotEmpty) {
                            films = inlineFilms;
                          }

                          if (films.isEmpty) {
                            return const Text('Watchlist boş.');
                          }

                          return SizedBox(
                            height: 180,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: films.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (_, i) {
                                final film = films[i];
                                final poster =
                                    (film['poster'] ??
                                            film['posterUrl'] ??
                                            film['image'] ??
                                            '')
                                        as String;
                                final title =
                                    (film['title'] ??
                                            film['name'] ??
                                            film['t'] ??
                                            '')
                                        as String;
                                return AspectRatio(
                                  aspectRatio: 2 / 3,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        poster.isNotEmpty
                                            ? Image.network(
                                                poster,
                                                headers: _lbImageHeaders,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    Container(
                                                      color: Colors.black26,
                                                      alignment:
                                                          Alignment.center,
                                                      child: const Icon(
                                                        Icons
                                                            .image_not_supported,
                                                      ),
                                                    ),
                                              )
                                            : Container(color: Colors.black26),
                                        if (title.isNotEmpty)
                                          Align(
                                            alignment: Alignment.bottomCenter,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 4,
                                                  ),
                                              color: Colors.black54,
                                              child: Text(
                                                title,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.white,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
