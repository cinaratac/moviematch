import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/recommendation_engine.dart';
import '../widgets/poster_image.dart';
import '../models/shelf_target.dart';

/// Feed içinde gösterilen film önerileri kartı
class RecommendationCard extends StatefulWidget {
  const RecommendationCard({super.key});

  @override
  State<RecommendationCard> createState() => _RecommendationCardState();
}

class _RecommendationCardState extends State<RecommendationCard> {
  List<MovieRecommendation>? _recommendations;
  bool _loading = true;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _loading = true);

    try {
      // Önce cache'den dene
      var recs = await RecommendationEngine.instance.getCachedRecommendations(uid);
      
      // Cache yoksa veya eskiyse yeniden oluştur
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
      if (mounted) {
        setState(() => _loading = false);
      }
    }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              cs.primaryContainer,
              cs.secondaryContainer,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_recommendations == null || _recommendations!.isEmpty) {
      return const SizedBox.shrink();
    }

    final recommendation = _recommendations![_currentIndex];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primaryContainer,
            cs.secondaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: cs.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Senin İçin Öneri',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Yeni öneriler oluştur',
                  onPressed: () async {
                    setState(() => _loading = true);
                    await _loadRecommendations();
                  },
                ),
              ],
            ),
          ),

          // Film kartı
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Poster
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 120,
                    height: 180,
                    child: PosterImage(
                      posterUrl: recommendation.posterUrl,
                      title: recommendation.title,
                      tmdbId: recommendation.tmdbId,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Bilgiler
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Başlık
                      Text(
                        recommendation.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),

                      // Eşleşme skoru
                      Row(
                        children: [
                          Icon(
                            Icons.favorite,
                            size: 16,
                            color: Colors.red,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '%${recommendation.matchScore.toInt()} Uyum',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Sebep
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surface.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          recommendation.matchReason,
                          style: theme.textTheme.labelSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // IMDB puanı
                      Row(
                        children: [
                          const Icon(Icons.star, size: 16, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            recommendation.voteAverage.toStringAsFixed(1),
                            style: theme.textTheme.labelMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Türler
                      if (recommendation.genres.isNotEmpty)
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: recommendation.genres.take(3).map((genre) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: cs.surface.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                genre,
                                style: theme.textTheme.labelSmall,
                              ),
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Navigasyon ve Aksiyon Butonları
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Geri/İleri
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios, size: 18),
                      onPressed: _previousRecommendation,
                      tooltip: 'Önceki öneri',
                    ),
                    Text(
                      '${_currentIndex + 1} / ${_recommendations!.length}',
                      style: theme.textTheme.labelMedium,
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios, size: 18),
                      onPressed: _nextRecommendation,
                      tooltip: 'Sonraki öneri',
                    ),
                  ],
                ),

                // İzledim butonu
                FilledButton.icon(
                  onPressed: () {
                    // İzledim olarak işaretle
                    _showAddToShelfDialog(context, recommendation);
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Ekle'),
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAddToShelfDialog(BuildContext context, MovieRecommendation rec) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${rec.title} filmini nereye eklemek istersin?',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.star, color: Colors.amber),
                title: const Text('5 Yıldız (Sevdiklerim)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _addToShelf(ShelfTarget.fiveStar);
                },
              ),
              ListTile(
                leading: const Icon(Icons.favorite, color: Colors.red),
                title: const Text('Favorilerim'),
                onTap: () {
                  Navigator.pop(ctx);
                  _addToShelf(ShelfTarget.favorites);
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmark, color: Colors.blue),
                title: const Text('İzleme Listem'),
                onTap: () {
                  Navigator.pop(ctx);
                  _addToShelf(ShelfTarget.watchlist);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _addToShelf(ShelfTarget target) {
    // SearchMoviePage'deki ekleme mantığını kullanarak filme ekle
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_recommendations![_currentIndex].title} eklendi!'),
        action: SnackBarAction(
          label: 'Geri Al',
          onPressed: () {
            // TODO: Geri alma işlemi
          },
        ),
      ),
    );

    // Sonraki öneriye geç
    _nextRecommendation();
  }
}