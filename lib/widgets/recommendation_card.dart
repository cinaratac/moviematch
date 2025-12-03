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
        backgroundColor: Colors.transparent, // Arkaplanı şeffaf yapıyoruz ki kendi şeklimizi verelim
        insetPadding: const EdgeInsets.all(20), // Ekran kenarlarından boşluk
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360), // Çok geniş olmasın
          decoration: BoxDecoration(
            // Hafif bir gradyan ile derinlik katalım
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.surfaceContainerHighest, // Üst taraf biraz daha açık
                cs.surface,                 // Alt taraf koyu
              ],
            ),
            borderRadius: BorderRadius.circular(24), // Daha yuvarlak köşeler
            // İnce, şık bir kenarlık (border)
            border: Border.all(
              color: cs.outlineVariant.withOpacity(0.2),
              width: 1,
            ),
            // Hafif gölge
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
              // 1. ÜST İKON (Parlayan efektli)
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

              // 2. BAŞLIK
              Text(
                'Sistem Nasıl Çalışıyor?',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 24),

              // 3. MADDELER (Yardımcı widget ile)
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

              // 4. KAPAT BUTONU (Tam genişlik)
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

  // Maddeleri düzenli göstermek için küçük yardımcı widget
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
    super.build(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

  
    if (_loading) {
      return Container(
        height: 200, // Yüklenirken de daha kısa görünsün
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [cs.primaryContainer, cs.secondaryContainer],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16), // Radius biraz küçüldü
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_recommendations == null || _recommendations!.isEmpty) {
       return const SizedBox.shrink();
    }

    final recommendation = _recommendations![_currentIndex];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), // Dikey margin azaldı
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primaryContainer, cs.secondaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16), // Radius 20 -> 16
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, // İçeriği kadar yer kaplasın
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Başlık Kısmı (Daha kompakt) ---
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), // Boşluklar sıkılaştırıldı
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
                const Spacer(), // Sağa yaslamak için boşluk
                
                // --- YENİ EKLENEN BİLGİ BUTONU ---
                SizedBox(
                  height: 32,
                  width: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 20,
                    icon: Icon(Icons.info_outline, color: cs.onSurfaceVariant.withOpacity(0.7)),
                    tooltip: 'Bu liste nasıl oluşuyor?',
                    onPressed: _showInfoDialog, // Fonksiyonu çağırıyoruz
                  ),
                ),
              ],
            ),
          ),

          // --- Film İçeriği ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Poster (Küçültüldü: 120x180 -> 100x150)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 100, 
                    height: 150, 
                    child: PosterImage(
                      posterUrl: recommendation.posterUrl,
                      title: recommendation.title,
                      tmdbId: recommendation.tmdbId,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                
                // Bilgiler
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recommendation.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 16, // Font boyutu sabitlendi
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6), // 8 -> 6
                      
                      // Uyum Skoru
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
                      
                      // Sebep (Daha küçük kutu)
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
                      
                      // IMDB Puanı
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
                      
                      // Türler (Daha kompakt wrap)
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

          const SizedBox(height: 12), // 16 -> 12

          // --- Alt Butonlar ---
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), // Alt boşluk 12
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Navigasyon (Önceki/Sonraki)
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

                // Ekle Butonu
                SizedBox(
                  height: 36,
                  child: FilledButton.icon(
                    onPressed: _actionInProgress 
                      ? null 
                      : () => _showAddToShelfDialog(context, recommendation),
                    icon: _actionInProgress 
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) 
                      : const Icon(Icons.add, size: 18),
                    label: const Text('Ekle'),
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      visualDensity: VisualDensity.compact, // Sıkılaştırılmış görünüm
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
}