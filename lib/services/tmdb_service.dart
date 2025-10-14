import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/models/shelf_target.dart';

class SearchMovieScreen extends StatefulWidget {
  final ShelfTarget target;

  const SearchMovieScreen({Key? key, required this.target}) : super(key: key);

  @override
  _SearchMovieScreenState createState() => _SearchMovieScreenState();
}

class _SearchMovieScreenState extends State<SearchMovieScreen> {
  // ... other code ...

  @override
  Widget build(BuildContext context) {
    // Placeholder minimal UI to satisfy build; keep your actual UI if it exists elsewhere.
    return Scaffold(
      appBar: AppBar(title: const Text('Film Ara')),
      body: const SizedBox.shrink(),
    );
  }

  void _showMovieDetails(Map<String, dynamic> movie) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(movie['title'] ?? ''),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ... other widgets ...
              ElevatedButton(
                onPressed: () async {
                  try {
                    final uid = FirebaseAuth.instance.currentUser?.uid;
                    if (uid == null) {
                      if (mounted) Navigator.of(context).pop();
                      return;
                    }

                    final db = FirebaseFirestore.instance;

                    // TMDB base fields
                    final int tmdbId = (movie['id'] as num).toInt();
                    final String rawTitle = (movie['title'] ?? '').toString();
                    final String release = (movie['release_date'] ?? '')
                        .toString();
                    final int year = release.isNotEmpty
                        ? int.tryParse(release.substring(0, 4)) ?? 0
                        : 0;

                    // IMDb ayrıntılarını çekmeden devam ediyoruz (opsiyonel)
                    const String imdbId = '';

                    String _norm(String s) {
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

                    String _slug(String s) {
                      final n = _norm(s);
                      return n.replaceAll(' ', '-');
                    }

                    final String title = rawTitle;
                    final String titleLc = _norm(title);
                    final String slug = _slug(title);

                    final String posterUrl =
                        (movie['poster_path'] is String &&
                            (movie['poster_path'] as String).isNotEmpty)
                        ? 'https://image.tmdb.org/t/p/w500${movie['poster_path']}'
                        : '';

                    // 1) Try to find existing doc by tmdbId
                    String? primaryKey;
                    final byTmdb = await db
                        .collection('catalog_films')
                        .where('tmdbId', isEqualTo: tmdbId)
                        .limit(1)
                        .get();
                    if (byTmdb.docs.isNotEmpty) {
                      primaryKey = byTmdb
                          .docs
                          .first
                          .id; // often film:<slug> if already mapped
                    }

                    // 2) Try by imdbId (strongest cross-source key)
                    if (primaryKey == null && imdbId.isNotEmpty) {
                      final byImdb = await db
                          .collection('catalog_films')
                          .where('imdbId', isEqualTo: imdbId)
                          .limit(1)
                          .get();
                      if (byImdb.docs.isNotEmpty) {
                        primaryKey =
                            byImdb.docs.first.id; // should be film:<slug>
                      }
                    }

                    // 3) Try by normalized title + year (needs composite index on titleLc/year)
                    if (primaryKey == null) {
                      final byTy = await db
                          .collection('catalog_films')
                          .where('titleLc', isEqualTo: titleLc)
                          .where('year', isEqualTo: year)
                          .limit(1)
                          .get();
                      if (byTy.docs.isNotEmpty) {
                        primaryKey = byTy.docs.first.id;
                      }
                    }

                    // 4) Fallback: prefer film:<slug> (and if exists, add -year suffix)
                    if (primaryKey == null) {
                      String candidate = 'film:$slug';
                      final exists = await db
                          .collection('catalog_films')
                          .doc(candidate)
                          .get();
                      if (exists.exists && year > 0) {
                        candidate = 'film:$slug-$year';
                      }
                      primaryKey =
                          candidate; // ✅ no tmdb: id unless already present
                    }

                    // 5) Upsert chosen document with aliases
                    final docRef = db
                        .collection('catalog_films')
                        .doc(primaryKey);
                    await docRef.set({
                      'title': title.isNotEmpty ? title : 'Başlık yok',
                      'titleLc': titleLc,
                      'year': year,
                      'posterUrl': posterUrl,
                      'tmdbId': tmdbId,
                      if (imdbId.isNotEmpty) 'imdbId': imdbId,
                      'source': 'tmdb',
                      'aliases': FieldValue.arrayUnion([
                        'tmdb:$tmdbId',
                        if (imdbId.isNotEmpty) 'imdb:$imdbId',
                      ]),
                      'updatedAt': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));

                    // 6) Decide user field by target
                    String userArrayField =
                        'favoritesKeys'; // will be overwritten by switch
                    switch (widget.target) {
                      case ShelfTarget.fiveStar:
                        userArrayField = 'fiveStarKeys';
                        break;
                      case ShelfTarget.disliked:
                        userArrayField = 'dislikedKeys';
                        break;
                      case ShelfTarget.favorites:
                        userArrayField = 'favoritesKeys';
                        break;
                      case ShelfTarget.watchlist:
                        userArrayField = 'watchlistKeys';
                        break;
                    }

                    await db.collection('users').doc(uid).set({
                      userArrayField: FieldValue.arrayUnion([primaryKey]),
                      'updatedAt': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));

                    if (widget.target == ShelfTarget.fiveStar) {
                      await db.collection('userTasteProfiles').doc(uid).set({
                        'fiveStars': FieldValue.arrayUnion([primaryKey]),
                        'updatedAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));
                    } else if (widget.target == ShelfTarget.disliked) {
                      await db.collection('userTasteProfiles').doc(uid).set({
                        'lowRatings': FieldValue.arrayUnion([primaryKey]),
                        'updatedAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));
                    }

                    if (mounted) {
                      Navigator.of(context).pop();
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
                    }
                  }
                },
                child: const Text('Add'),
              ),
            ],
          ),
        );
      },
    );
  }

  // ... other code ...
}
