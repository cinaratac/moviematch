import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/recommendation_engine.dart';
import '../widgets/poster_image.dart';
import '../models/shelf_target.dart';
import '../screens/profilescreen.dart'; // UserShelfCache için gerekli
import 'package:fluttergirdi/screens/movie_detail_screen.dart';

// Extension: SearchMoviePage'deki gibi target -> field dönüşümü
extension ShelfTargetXLocal on ShelfTarget {
  String get userArrayField {
    switch (this) {
      case ShelfTarget.fiveStar: return 'fiveStarKeys';
      case ShelfTarget.disliked: return 'dislikedKeys';
      case ShelfTarget.favorites: return 'favoritesKeys';
      case ShelfTarget.watchlist: return 'watchlistKeys';
    }
  }
}

class RecommendationCard extends StatefulWidget {
  const RecommendationCard({super.key});

  @override
  State<RecommendationCard> createState() => _RecommendationCardState();
}

class _RecommendationCardState extends State<RecommendationCard> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  List<MovieRecommendation>? _recommendations;
  bool _loading = true;
  int _currentIndex = 0;
  bool _actionInProgress = false; // Tıklama koruması

  @override
  void initState() {
    super.initState();
    _loadRecommendations();
  }

  Future<void> _loadRecommendations({bool forceRefresh = false}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    if (mounted) setState(() => _loading = true);

    try {
      if (forceRefresh) {
        RecommendationEngine.instance.clearMemoryCache();
      }
      var recs = await RecommendationEngine.instance.getCachedRecommendations(uid);
      if (recs == null || recs.isEmpty) {
        recs = await RecommendationEngine.instance.generateRecommendations(uid);
      }

      if (mounted) {
        setState(() {
          _recommendations = recs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showInfoDialog() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent, 
        insetPadding: const EdgeInsets.all(20), 
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360), 
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.surfaceContainerHighest, 
                cs.surface,                 
              ],
            ),
            borderRadius: BorderRadius.circular(24), 
            border: Border.all(
              color: cs.outlineVariant.withOpacity(0.2),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withOpacity(0.2),
                      blurRadius: 20,
                      spreadRadius: -5,
                    ),
                  ],
                ),
                child: Icon(Icons.auto_awesome, color: cs.primary, size: 32),
              ),
              
              const SizedBox(height: 20),

              Text(
                'Sistem Nasıl Çalışıyor?',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 24),

              _buildFancyInfoItem(
                context,
                icon: Icons.person_search_rounded,
                title: 'Sana Özel Analiz',
                desc: 'Sevdiğin türler, yönetmenler ve izleme geçmişin yapay zeka ile analiz edilir.',
              ),
              const SizedBox(height: 16),
              _buildFancyInfoItem(
                context,
                icon: Icons.calendar_month_rounded,
                title: 'Haftalık Yenilenme',
                desc: 'Her hafta listen sıfırlanır ve keşfetmen için yepyeni, taze öneriler getirilir.',
              ),

              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Süper, Anlaşıldı',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFancyInfoItem(BuildContext context, {required IconData icon, required String title, required String desc}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: cs.onSurfaceVariant),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  void _nextRecommendation() {
    if (_recommendations == null || _recommendations!.isEmpty) return;
    setState(() {
      _currentIndex = (_currentIndex + 1) % _recommendations!.length;
    });
  }

  void _previousRecommendation() {
    if (_recommendations == null || _recommendations!.isEmpty) return;
    setState(() {
      _currentIndex = (_currentIndex - 1 + _recommendations!.length) % _recommendations!.length;
    });
  }

  String _slugify(String s) {
    var t = s.toLowerCase();
    t = t.replaceAll(RegExp(r'[çÇ]'), 'c')
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
    t = t.replaceAll(RegExp(r'[çÇ]'), 'c')
         .replaceAll(RegExp(r'[ğĞ]'), 'g')
         .replaceAll(RegExp(r'[ıİ]'), 'i')
         .replaceAll(RegExp(r'[öÖ]'), 'o')
         .replaceAll(RegExp(r'[şŞ]'), 's')
         .replaceAll(RegExp(r'[üÜ]'), 'u');
    t = t.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  Future<void> _addToShelf(ShelfTarget target) async {
    if (_recommendations == null || _recommendations!.isEmpty) return;
    final rec = _recommendations![_currentIndex];
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _actionInProgress = true);

    try {
      final db = FirebaseFirestore.instance;
      
      final tmdbId = rec.tmdbId;
      final title = rec.title;
      final posterUrl = rec.posterUrl;
      
      int yearInt = 0;
      if (rec.releaseDate.length >= 4) {
        yearInt = int.tryParse(rec.releaseDate.substring(0, 4)) ?? 0;
      }

      final titleLc = _normTitle(title);
      final guessLbSlug = _slugify(title);
      
      String? primaryKey;

      final byTmdb = await db.collection('catalog_films')
          .where('tmdbId', isEqualTo: tmdbId).limit(1).get();

      if (byTmdb.docs.isNotEmpty) {
        primaryKey = byTmdb.docs.first.id;
      } else {
        final slugId = 'film:$guessLbSlug';
        
        primaryKey = slugId; 
      }

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

      final String userArrayField = target.userArrayField;
      await db.collection('users').doc(uid).set({
        userArrayField: FieldValue.arrayUnion([primaryKey]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // DÜZELTME: Alan isimleri 'loved' ve 'disliked' olarak güncellendi (UserProfileService ile uyumlu olması için)
      if (target == ShelfTarget.fiveStar) {
        await db.collection('userTasteProfiles').doc(uid).set({
          'loved': FieldValue.arrayUnion([primaryKey]), // 'fiveStars' -> 'loved'
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else if (target == ShelfTarget.disliked) {
        await db.collection('userTasteProfiles').doc(uid).set({
          'disliked': FieldValue.arrayUnion([primaryKey]), // 'lowRatings' -> 'disliked'
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      try {
        final Map<String, String> newLocalItem = {
          'title': title,
          'poster': posterUrl,
          'posterUrl': posterUrl,
        };
        switch (target) {
          case ShelfTarget.fiveStar:
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
        debugPrint('Cache güncelleme hatası: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${rec.title} listene eklendi!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
        setState(() {
          _recommendations!.removeAt(_currentIndex);
          if (_currentIndex >= _recommendations!.length) {
            _currentIndex = 0;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

  
    if (_loading) {
      return Container(
        height: 200, 
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [cs.primaryContainer, cs.secondaryContainer],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16), 
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                'Yapay zeka sana göre filmler seçiyor...',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Geçmişin, yönetmenlerin ve sevdiğin oyuncular taranıyor.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onPrimaryContainer.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_recommendations == null || _recommendations!.isEmpty) {
       return const SizedBox.shrink();
    }

    final recommendation = _recommendations![_currentIndex];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), 
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primaryContainer, cs.secondaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16), 
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, 
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), 
            child: Row(
              children: [
                Icon(Icons.auto_awesome, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Haftalık Keşif Listen',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const Spacer(), 
                
                SizedBox(
                  height: 32,
                  width: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 20,
                    icon: Icon(Icons.info_outline, color: cs.onSurfaceVariant.withOpacity(0.7)),
                    tooltip: 'Bu liste nasıl oluşuyor?',
                    onPressed: _showInfoDialog, 
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 100, 
                    height: 150, 
                    // Tıklama özelliği eklendi:
                    child: GestureDetector( 
                      onTap: () {
                         if (recommendation.tmdbId != 0) {
                           Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MovieDetailScreen(
                                tmdbId: recommendation.tmdbId,
                                title: recommendation.title,
                                posterUrl: recommendation.posterUrl,
                              ),
                            ),
                          );
                         }
                      },
                      child: PosterImage(
                        posterUrl: recommendation.posterUrl,
                        title: recommendation.title,
                        tmdbId: recommendation.tmdbId,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recommendation.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 16, 
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6), 
                      
                      Row(
                        children: [
                          Icon(Icons.favorite, size: 14, color: Colors.red),
                          const SizedBox(width: 4),
                          Text(
                            '%${recommendation.matchScore.toInt()} Uyum',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.surface.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          recommendation.matchReason,
                          style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 6),
                      
                      Row(
                        children: [
                          const Icon(Icons.star, size: 14, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            recommendation.voteAverage.toStringAsFixed(1),
                            style: theme.textTheme.labelMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      
                      if (recommendation.genres.isNotEmpty)
                        SizedBox(
                          height: 20,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: recommendation.genres.take(3).length,
                            separatorBuilder: (_, __) => const SizedBox(width: 4),
                            itemBuilder: (ctx, i) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: cs.surface.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  recommendation.genres[i], 
                                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 10)
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12), 

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), 
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: cs.surface.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32),
                        onPressed: _previousRecommendation,
                      ),
                      Text(
                        '${_currentIndex + 1}/${_recommendations!.length}',
                        style: theme.textTheme.labelSmall,
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32),
                        onPressed: _nextRecommendation,
                      ),
                    ],
                  ),
                ),

               
              ],
            ),
          ),
        ],
      ),
    );
  }
}