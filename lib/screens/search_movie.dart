import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

import '../models/shelf_target.dart';
import '../secrets.dart';

// Local fallback extension in case the model extension isn't present in build scope
extension ShelfTargetXLocal on ShelfTarget {
  String get userArrayField {
    switch (this) {
      case ShelfTarget.fiveStar:
        return 'fiveStarKeys';
      case ShelfTarget.disliked:
        return 'dislikedKeys';
      case ShelfTarget.favorites:
        return 'favoritesKeys';
      case ShelfTarget.watchlist:
        return 'watchlistKeys';
    }
  }
}

Future<List<dynamic>> _tmdbSearchMovies(String query) async {
  final q = query.trim();
  if (q.isEmpty) return [];
  final bearer = Secrets.tmdbAccessToken;
  if (bearer.isEmpty) {
    throw Exception(
      'TMDB Bearer token bulunamadı. Lütfen lib/secrets.dart içindeki tmdbAccessToken değerini doldurun.',
    );
  }
  final uri = Uri.https('api.themoviedb.org', '/3/search/movie', {
    'query': q,
    'include_adult': 'false',
    'language': 'en-US',
    'page': '1',
  });
  final resp = await http.get(
    uri,
    headers: {'Authorization': 'Bearer $bearer', 'Accept': 'application/json'},
  );
  if (resp.statusCode != 200) {
    throw Exception('TMDB error ${resp.statusCode}');
  }
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  final results = (data['results'] as List?) ?? const [];
  return results;
}

class SearchMoviePage extends StatefulWidget {
  final ShelfTarget target;
  const SearchMoviePage({super.key, required this.target});

  @override
  State<SearchMoviePage> createState() => _SearchMoviePageState();
}

class _SearchMoviePageState extends State<SearchMoviePage> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _movies = [];
  bool _isLoading = false;
  String? _error;

  String _titleFor(ShelfTarget t) {
    switch (t) {
      case ShelfTarget.fiveStar:
        return 'Sevdiği Film Ekle';
      case ShelfTarget.disliked:
        return 'Sevmediği Film Ekle';
      case ShelfTarget.favorites:
        return 'Favori Film Ekle';
      case ShelfTarget.watchlist:
        return 'Watchlist\'e Ekle';
    }
  }

  String _hintFor(ShelfTarget t) {
    switch (t) {
      case ShelfTarget.fiveStar:
        return 'Sevdiğin film ara...';
      case ShelfTarget.disliked:
        return 'Sevmediğin film ara...';
      case ShelfTarget.favorites:
        return 'Favori film ara...';
      case ShelfTarget.watchlist:
        return 'Watchlist için film ara...';
    }
  }

  Future<void> _searchMovies(String query) async {
    if (query.isEmpty) {
      setState(() {
        _movies = [];
        _error = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await _tmdbSearchMovies(query);
      setState(() {
        _movies = results;
      });
    } catch (e) {
      setState(() {
        _error = 'Arama sırasında bir hata oluştu: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showMovieDetails(dynamic movie) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              children: [
                Text(
                  movie['title'] ?? 'Başlık yok',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),

                const SizedBox(height: 12),
                Text(
                  movie['overview'] ?? 'Açıklama yok',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () async {
                      try {
                        final uid = FirebaseAuth.instance.currentUser?.uid;
                        if (uid == null) {
                          if (mounted) Navigator.of(context).pop();
                          return;
                        }

                        // TMDB raw fields
                        final int tmdbId = (movie['id'] as num).toInt();
                        final String title = (movie['title'] ?? '').toString();
                        final String release = (movie['release_date'] ?? '')
                            .toString(); // "YYYY-MM-DD"
                        final int year = release.isNotEmpty
                            ? int.tryParse(release.substring(0, 4)) ?? 0
                            : 0;

                        // Normalization helpers
                        String _slugify(String s) {
                          var t = s.toLowerCase();
                          t = t
                              .replaceAll(RegExp(r'[çÇ]'), 'c')
                              .replaceAll(RegExp(r'[ğĞ]'), 'g')
                              .replaceAll(RegExp(r'[ıİ]'), 'i')
                              .replaceAll(RegExp(r'[öÖ]'), 'o')
                              .replaceAll(RegExp(r'[şŞ]'), 's')
                              .replaceAll(RegExp(r'[üÜ]'), 'u');
                          // keep letters, digits and spaces; collapse whitespace; hyphenate
                          t = t.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
                          t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
                          t = t.replaceAll(' ', '-');
                          return t;
                        }

                        String _normTitle(String s) {
                          var t = s.toLowerCase();
                          t = t
                              .replaceAll(RegExp(r'[çÇ]'), 'c')
                              .replaceAll(RegExp(r'[ğĞ]'), 'g')
                              .replaceAll(RegExp(r'[ıİ]'), 'i')
                              .replaceAll(RegExp(r'[öÖ]'), 'o')
                              .replaceAll(RegExp(r'[şŞ]'), 's')
                              .replaceAll(RegExp(r'[üÜ]'), 'u');
                          t = t.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
                          t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
                          return t;
                        }

                        final String titleLc = _normTitle(title);
                        final String guessLbSlug = _slugify(
                          title,
                        ); // best-effort guess

                        // Poster URL
                        final String posterUrl =
                            (movie['poster_path'] is String &&
                                (movie['poster_path'] as String).isNotEmpty)
                            ? 'https://image.tmdb.org/t/p/w500${movie['poster_path']}'
                            : '';

                        final db = FirebaseFirestore.instance;

                        // 1) Try to find an existing catalog entry by tmdbId (works if previously mapped)
                        String? primaryKey;
                        final byTmdb = await db
                            .collection('catalog_films')
                            .where('tmdbId', isEqualTo: tmdbId)
                            .limit(1)
                            .get();

                        if (byTmdb.docs.isNotEmpty) {
                          final foundId = byTmdb.docs.first.id;
                          if (foundId.startsWith('tmdb:')) {
                            // Legacy doc id style. Create/merge a Letterboxd-style doc and prefer it as canonical.
                            final slugId = 'film:$guessLbSlug';
                            final slugRef = db
                                .collection('catalog_films')
                                .doc(slugId);
                            await slugRef.set({
                              'title': title.isNotEmpty ? title : 'Başlık yok',
                              'posterUrl': posterUrl,
                              'tmdbId': tmdbId,
                              'year': year,
                              'titleLc': titleLc,
                              'lbSlugGuess': guessLbSlug,
                              'aliases': FieldValue.arrayUnion([
                                'tmdb:$tmdbId',
                              ]),
                              'source': 'tmdb',
                              'updatedAt': FieldValue.serverTimestamp(),
                            }, SetOptions(merge: true));
                            primaryKey = slugId; // ALWAYS prefer film:<slug>
                          } else {
                            primaryKey =
                                foundId; // already a film:<slug> (or other canonical id)
                          }
                        } else {
                          // 1.1) Try direct LB-style key by slug: catalog_films/film:<slug>
                          final slugId = 'film:$guessLbSlug';
                          final slugDoc = await db
                              .collection('catalog_films')
                              .doc(slugId)
                              .get();
                          if (slugDoc.exists) {
                            primaryKey = slugId;
                          } else {
                            // 2) Try to match by normalized title + year (to hit Letterboxd-imported docs)
                            // Note: this may require a composite index on (titleLc, year) on first run.
                            final byTitleYear = await db
                                .collection('catalog_films')
                                .where('titleLc', isEqualTo: titleLc)
                                .where('year', isEqualTo: year)
                                .limit(1)
                                .get();

                            if (byTitleYear.docs.isNotEmpty) {
                              primaryKey = byTitleYear
                                  .docs
                                  .first
                                  .id; // likely "film:<slug>"
                            }
                          }
                        }

                        // 3) Choose key. If still no match, **create as Letterboxd-style** key
                        primaryKey ??= 'film:$guessLbSlug';

                        // 4) Upsert catalog with normalized helpers and alias info
                        final docRef = db
                            .collection('catalog_films')
                            .doc(primaryKey);
                        await docRef.set({
                          'title': title.isNotEmpty ? title : 'Başlık yok',
                          'posterUrl': posterUrl,
                          'tmdbId': tmdbId,
                          'year': year,
                          'titleLc': titleLc,
                          'lbSlugGuess':
                              guessLbSlug, // hint for future mapping/search
                          // Always keep tmdb alias so future lookups hit the same doc
                          'aliases': FieldValue.arrayUnion(['tmdb:$tmdbId']),
                          'source': 'tmdb',
                          'updatedAt': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));

                        // 5) Determine user field by target (via model extension)
                        final String userArrayField =
                            widget.target.userArrayField;

                        // 6) Update users/{uid} with the chosen primary key
                        await db.collection('users').doc(uid).set({
                          userArrayField: FieldValue.arrayUnion([primaryKey]),
                          'updatedAt': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));

                        // 7) Mirror taste profile if applicable
                        if (widget.target == ShelfTarget.fiveStar) {
                          await db.collection('userTasteProfiles').doc(uid).set(
                            {
                              'fiveStars': FieldValue.arrayUnion([primaryKey]),
                              'updatedAt': FieldValue.serverTimestamp(),
                            },
                            SetOptions(merge: true),
                          );
                        } else if (widget.target == ShelfTarget.disliked) {
                          await db.collection('userTasteProfiles').doc(uid).set(
                            {
                              'lowRatings': FieldValue.arrayUnion([primaryKey]),
                              'updatedAt': FieldValue.serverTimestamp(),
                            },
                            SetOptions(merge: true),
                          );
                        }

                        if (mounted) {
                          Navigator.of(context).pop(); // Close bottom sheet
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Hata: $e')));
                        }
                      }
                    },
                    child: const Text('Ekle'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildGridItem(dynamic movie) {
    final posterPath = movie['poster_path'];
    return InkWell(
      onTap: () => _showMovieDetails(movie),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: posterPath != null && posterPath != ''
                  ? Image.network(
                      'https://image.tmdb.org/t/p/w500$posterPath',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.broken_image),
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        );
                      },
                    )
                  : Container(
                      color: Colors.grey[300],
                      child: const Icon(Icons.movie, size: 48),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                movie['title'] ?? 'Başlık yok',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_movies.isEmpty) {
      return const Center(child: Text('Film aramak için yukarıya yazınız.'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.7,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _movies.length,
      itemBuilder: (context, index) {
        final movie = _movies[index];
        return _buildGridItem(movie);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: _hintFor(widget.target),
            border: InputBorder.none,
            hintStyle: const TextStyle(color: Colors.white54),
          ),
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white,
          onChanged: (value) {
            _searchMovies(value);
          },
          autofocus: true,
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _buildBody(),
    );
  }
}
