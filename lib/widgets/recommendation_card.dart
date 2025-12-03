import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/recommendation_engine.dart';
import '../widgets/poster_image.dart';
import '../models/shelf_target.dart';
import '../screens/profilescreen.dart'; // UserShelfCache için gerekli

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

class _RecommendationCardState extends State<RecommendationCard> {
  List<MovieRecommendation>? _recommendations;
  bool _loading = true;
  int _currentIndex = 0;
  bool _actionInProgress = false; // Tıklama koruması

  @override
  void initState() {
    super.initState();
    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    if (mounted) setState(() => _loading = true);

    try {
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

  // --- Yardımcı String Fonksiyonları (SearchMovie'den alındı) ---
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
      
      // 1. Catalog Film kaydı oluştur veya bul
      final tmdbId = rec.tmdbId;
      final title = rec.title;
      final posterUrl = rec.posterUrl;
      
      // Yıl bilgisini releaseDate'den al
      int yearInt = 0;
      if (rec.releaseDate.length >= 4) {
        yearInt = int.tryParse(rec.releaseDate.substring(0, 4)) ?? 0;
      }

      final titleLc = _normTitle(title);
      final guessLbSlug = _slugify(title);
      
      String? primaryKey;

      // TMDB ID ile ara
      final byTmdb = await db.collection('catalog_films')
          .where('tmdbId', isEqualTo: tmdbId).limit(1).get();

      if (byTmdb.docs.isNotEmpty) {
        final foundId = byTmdb.docs.first.id;
        // Eğer eski tip ID (tmdb:...) ise yeni tipe geçirilebilir ama şimdilik ID'yi kullan
        primaryKey = foundId;
      } else {
        // ID yoksa slug ile dene
        final slugId = 'film:$guessLbSlug';
        final slugDoc = await db.collection('catalog_films').doc(slugId).get();
        if (slugDoc.exists) {
          primaryKey = slugId;
        } else {
          // O da yoksa primaryKey bu olacak, oluşturacağız.
          primaryKey = slugId;
        }
      }

      // Catalog film verisini yaz/güncelle
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

      // 2. Kullanıcı Profiline Ekle
      final String userArrayField = target.userArrayField;
      await db.collection('users').doc(uid).set({
        userArrayField: FieldValue.arrayUnion([primaryKey]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 3. UserTasteProfiles Güncelle
      if (target == ShelfTarget.fiveStar) {
        await db.collection('userTasteProfiles').doc(uid).set({
          'fiveStars': FieldValue.arrayUnion([primaryKey]),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else if (target == ShelfTarget.disliked) {
        await db.collection('userTasteProfiles').doc(uid).set({
          'lowRatings': FieldValue.arrayUnion([primaryKey]),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // 4. Local Cache Güncelle (Hızlı UI tepkisi için)
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
        // Listeden çıkarıp bir sonrakine geçelim
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

  // --- Build Metodu (Mevcut tasarımın aynısı, sadece buton fonksiyonları bağlandı) ---
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
            colors: [cs.primaryContainer, cs.secondaryContainer],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_recommendations == null || _recommendations!.isEmpty) {
      return Container(
         margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
         padding: const EdgeInsets.all(20),
         child: Center(child: Text("Şimdilik başka önerimiz yok!")),
      );
    }

    final recommendation = _recommendations![_currentIndex];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primaryContainer, cs.secondaryContainer],
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
                Icon(Icons.auto_awesome, color: cs.primary, size: 24),
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
                    // Cache'i temizleyerek zorla yenileme yapılabilir ama şimdilik normal load
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recommendation.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.favorite, size: 16, color: Colors.red),
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
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                      if (recommendation.genres.isNotEmpty)
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: recommendation.genres.take(3).map((genre) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: cs.surface.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(genre, style: theme.textTheme.labelSmall),
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
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios, size: 18),
                      onPressed: _previousRecommendation,
                    ),
                    Text(
                      '${_currentIndex + 1} / ${_recommendations!.length}',
                      style: theme.textTheme.labelMedium,
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios, size: 18),
                      onPressed: _nextRecommendation,
                    ),
                  ],
                ),
                FilledButton.icon(
                  onPressed: _actionInProgress 
                    ? null 
                    : () => _showAddToShelfDialog(context, recommendation),
                  icon: _actionInProgress 
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) 
                    : const Icon(Icons.add, size: 18),
                  label: const Text('Ekle'),
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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