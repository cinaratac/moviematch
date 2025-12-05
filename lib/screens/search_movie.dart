import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

import '../models/shelf_target.dart';
import '../secrets.dart';
// PosterImage widget'ını kullanmak görsel bütünlük ve performans (cache) sağlar
import '../widgets/poster_image.dart'; 
import '../screens/profilescreen.dart';

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

  String _hintFor(ShelfTarget t) {
    switch (t) {
      case ShelfTarget.fiveStar:
        return 'Sevdiğin filmi ara...';
      case ShelfTarget.disliked:
        return 'Sevmediğin filmi ara...';
      case ShelfTarget.favorites:
        return 'Favori filmini ara...';
      case ShelfTarget.watchlist:
        return 'İzlemek istediğin filmi ara...';
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
    final theme = Theme.of(context);
    final posterPath = movie['poster_path'];
    final posterUrl = (posterPath is String && posterPath.isNotEmpty)
        ? 'https://image.tmdb.org/t/p/w500$posterPath'
        : '';
    final String title = (movie['title'] ?? 'Başlık yok').toString();
    final String release = (movie['release_date'] ?? '').toString();
    final String year = release.length >= 4 ? release.substring(0, 4) : '';
    final String overview = (movie['overview'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 60,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Header: Poster + Title + Year ---
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: PosterImage(
                      posterUrl: posterUrl,
                      title: title,
                      width: 100,
                      height: 150,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (year.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              year,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // --- Overview (Optional) ---
              if (overview.isNotEmpty) ...[
                 Text(
                   overview,
                   maxLines: 4,
                   overflow: TextOverflow.ellipsis,
                   style: theme.textTheme.bodyMedium?.copyWith(
                     color: theme.colorScheme.onSurfaceVariant,
                   ),
                 ),
                 const SizedBox(height: 24),
              ],

              // --- Action Button ---
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Listeye Ekle', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    try {
                      final uid = FirebaseAuth.instance.currentUser?.uid;
                      if (uid == null) {
                        if (mounted) Navigator.of(context).pop();
                        return;
                      }

                      // Logic from original code
                      final int tmdbId = (movie['id'] as num).toInt();
                      final int yearInt = int.tryParse(year) ?? 0;

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
                      final String guessLbSlug = _slugify(title);

                      final db = FirebaseFirestore.instance;

                      String? primaryKey;
                      final byTmdb = await db
                          .collection('catalog_films')
                          .where('tmdbId', isEqualTo: tmdbId)
                          .limit(1)
                          .get();

                      if (byTmdb.docs.isNotEmpty) {
                        final foundId = byTmdb.docs.first.id;
                        if (foundId.startsWith('tmdb:')) {
                          final slugId = 'film:$guessLbSlug';
                          final slugRef = db.collection('catalog_films').doc(slugId);
                          await slugRef.set({
                            'title': title.isNotEmpty ? title : 'Başlık yok',
                            'posterUrl': posterUrl,
                            'tmdbId': tmdbId,
                            'year': yearInt,
                            'titleLc': titleLc,
                            'lbSlugGuess': guessLbSlug,
                            'aliases': FieldValue.arrayUnion(['tmdb:$tmdbId']),
                            'source': 'tmdb',
                            'updatedAt': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));
                          primaryKey = slugId; 
                        } else {
                          primaryKey = foundId;
                        }
                      } else {
                        final slugId = 'film:$guessLbSlug';
                        final slugDoc = await db.collection('catalog_films').doc(slugId).get();
                        if (slugDoc.exists) {
                          primaryKey = slugId;
                        } else {
                          final byTitleYear = await db
                              .collection('catalog_films')
                              .where('titleLc', isEqualTo: titleLc)
                              .where('year', isEqualTo: yearInt)
                              .limit(1)
                              .get();

                          if (byTitleYear.docs.isNotEmpty) {
                            primaryKey = byTitleYear.docs.first.id;
                          }
                        }
                      }

                      primaryKey ??= 'film:$guessLbSlug';

                      final docRef = db.collection('catalog_films').doc(primaryKey);
                      await docRef.set({
                        'title': title.isNotEmpty ? title : 'Başlık yok',
                        'posterUrl': posterUrl,
                        'tmdbId': tmdbId,
                        'year': yearInt,
                        'titleLc': titleLc,
                        'lbSlugGuess': guessLbSlug,
                        'aliases': FieldValue.arrayUnion(['tmdb:$tmdbId']),
                        'source': 'tmdb',
                        'updatedAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));

                      final String userArrayField = widget.target.userArrayField;

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
                      try {
                        // 1. Yeni film verisini hazırla (String olduğundan emin oluyoruz)
                        final Map<String, String> newLocalItem = {
                          'title': title,
                          'poster': posterUrl,
                          'posterUrl': posterUrl,
                        };

                        // 2. Listenin "değiştirilebilir" (mutable) bir kopyasını oluştur ve elemanı ekle
                        // Ardından eski listenin üzerine yaz (= operatörü ile)
                        switch (widget.target) {
                          case ShelfTarget.fiveStar:
                            // Mevcut listenin kopyasını al -> Ekle -> Yerine koy
                            UserShelfCache.fiveStar = List.from(UserShelfCache.fiveStar)..add(newLocalItem);
                            break;
                          case ShelfTarget.favorites:
                            UserShelfCache.favorites = List.from(UserShelfCache.favorites)..add(newLocalItem);
                            break;
                          case ShelfTarget.watchlist:
                            UserShelfCache.watchlist = List.from(UserShelfCache.watchlist)..add(newLocalItem);
                            break;
                          case ShelfTarget.disliked:
                            UserShelfCache.disliked = List.from(UserShelfCache.disliked)..add(newLocalItem);
                            break;
                        }
                      } catch (e) {
                        // Eğer UserShelfCache henüz hazır değilse veya başka sorun varsa çökmemesi için
                        debugPrint('Cache güncellenemedi: $e');
                      }

                      if (mounted) {
                        Navigator.of(context).pop(); // Alttan açılan detay penceresini kapatır
                        
                        // --- DÜZELTME BURADA: İKİNCİ POP EKLENDİ ---
                        Navigator.of(context).pop(true); // Arama sayfasını kapatır ve 'true' döner
                        // ------------------------------------------

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('$title başarıyla eklendi'),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: theme.colorScheme.primary,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_movies.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.movie, size: 80, color: Colors.grey.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(
              'Aradığınız filmi yukarı yazın.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    
    // Masonry-like grid or Standard Grid with better aspect ratio
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, // Daha yoğun, modern görünüm (3 sütun)
        childAspectRatio: 0.67, // Standart poster oranı (2:3)
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _movies.length,
      itemBuilder: (context, index) {
        final movie = _movies[index];
        return _buildGridItem(movie);
      },
    );
  }

  Widget _buildGridItem(dynamic movie) {
    final posterPath = movie['poster_path'];
    final posterUrl = (posterPath is String && posterPath.isNotEmpty)
        ? 'https://image.tmdb.org/t/p/w500$posterPath'
        : '';
    final title = movie['title'] ?? '';

    // TMDB ID'yi PosterImage'a geçirelim ki otomatik düzeltme/cache çalışsın
    final tmdbId = (movie['id'] is int) ? movie['id'] as int : null;

    return InkWell(
      onTap: () => _showMovieDetails(movie),
      borderRadius: BorderRadius.circular(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            PosterImage(
              posterUrl: posterUrl,
              title: title,
              tmdbId: tmdbId, // Robust poster fallback için önemli
              fit: BoxFit.cover,
            ),
            // Gradient Overlay for Title
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    shadows: [Shadow(color: Colors.black, blurRadius: 2)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Container(
          height: 45,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            textAlignVertical: TextAlignVertical.center,
            style: theme.textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: _hintFor(widget.target),
              hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7)),
              border: InputBorder.none,
              prefixIcon: Icon(Icons.search, color: theme.colorScheme.onSurfaceVariant),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        _searchMovies('');
                      },
                    )
                  : null,
            ),
            onChanged: (value) {
              setState(() {}); // suffixIcon update
              _searchMovies(value);
            },
          ),
        ),
      ),
      body: _buildBody(),
    );
  }
}