import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/models/gamification.dart';
import 'package:fluttergirdi/services/follow_system_service.dart';
import 'package:share_plus/share_plus.dart'; // Paylaşım paketi

class BadgesProgressScreen extends StatefulWidget {
  const BadgesProgressScreen({super.key});

  @override
  State<BadgesProgressScreen> createState() => _BadgesProgressScreenState();
}

class _BadgesProgressScreenState extends State<BadgesProgressScreen> {
  bool _loading = true;
  final Map<String, double> _progress = {}; // BadgeID -> Yüzde (0.0 - 1.0)
  final Map<String, String> _labels = {};   // BadgeID -> "85/100"

  @override
  void initState() {
    super.initState();
    _calculateProgress();
  }

  Future<void> _calculateProgress() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final db = FirebaseFirestore.instance;
    
    try {
      // 1. Film Kurdu Verisi
      final userDoc = await db.collection('users').doc(uid).get();
      final userData = userDoc.data() ?? {};
      final uniqueMovies = {
        ...List.from(userData['favoritesKeys'] ?? []),
        ...List.from(userData['fiveStarKeys'] ?? []),
        ...List.from(userData['watchlistKeys'] ?? []),
        ...List.from(userData['dislikedKeys'] ?? [])
      }.length;

      // 2. Eleştirmen Verisi
      final postsSnap = await db.collection('posts')
          .where('authorId', isEqualTo: uid)
          .where('isReview', isEqualTo: true)
          .count()
          .get();
      final reviewCount = postsSnap.count ?? 0;

      // 3. Arşivci Verisi
      final listSnap = await db.collection('custom_lists')
          .where('ownerId', isEqualTo: uid)
          .count()
          .get();
      final listCount = listSnap.count ?? 0;

      // 4. Popüler Verisi
      final followersCount = await FollowSystemService.I.fetchFollowerCountOnce(uid);

      if (!mounted) return;

      setState(() {
        for (var badge in AppBadge.allBadges) {
          int current = 0;
          switch (badge.type) {
            case BadgeType.filmBuff: current = uniqueMovies; break;
            case BadgeType.critic: current = reviewCount; break;
            case BadgeType.archivist: current = listCount; break;
            case BadgeType.socialite: current = followersCount; break;
            default: current = 0;
          }

          double pct = (current / badge.threshold).clamp(0.0, 1.0);
          _progress[badge.id] = pct;
          _labels[badge.id] = '$current / ${badge.threshold}';
        }
        _loading = false;
      });

    } catch (e) {
      debugPrint('Rozet hesaplama hatası: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _earnedCount => _progress.values.where((p) => p >= 1.0).length;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: cs.surface,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // 1. NEON HEADER ALANI
                SliverAppBar(
                  expandedHeight: 260,
                  pinned: true,
                  stretch: true,
                  backgroundColor: cs.surface,
                  surfaceTintColor: Colors.transparent,
                  flexibleSpace: FlexibleSpaceBar(
                    background: _HeaderSection(
                      earned: _earnedCount,
                      total: AppBadge.allBadges.length,
                    ),
                  ),
                  title: _earnedCount > -1 ? null : const Text("Başarılar"), 
                ),

                // 2. NEON LİSTE
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final badge = AppBadge.allBadges[index];
                        return _BadgeCard(
                          badge: badge,
                          progress: _progress[badge.id] ?? 0.0,
                          label: _labels[badge.id] ?? '',
                          onTap: () => _showBadgeDetails(context, badge, _progress[badge.id] ?? 0.0, _labels[badge.id] ?? ''),
                        );
                      },
                      childCount: AppBadge.allBadges.length,
                    ),
                  ),
                ),
                
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
    );
  }

  void _showBadgeDetails(BuildContext context, AppBadge badge, double progress, String label) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _BadgeDetailSheet(badge: badge, progress: progress, label: label),
    );
  }
}

// --- NEON HEADER WIDGET ---
class _HeaderSection extends StatelessWidget {
  final int earned;
  final int total;
  const _HeaderSection({required this.earned, required this.total});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = (total == 0) ? 0.0 : (earned / total);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Arkaplan Gradyanı
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                cs.primary.withOpacity(0.15),
                cs.surface,
              ],
            ),
          ),
        ),
        
        // Dekoratif Halkalar
        Positioned(
          top: -50, right: -50,
          child: Container(
            width: 200, height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primary.withOpacity(0.05),
            ),
          ),
        ),

        // İçerik
        SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'BAŞARI SEVİYESİ',
                style: TextStyle(letterSpacing: 2, fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              // Dairesel Gösterge
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Arka Halka
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: 1.0,
                        color: cs.surfaceContainerHighest,
                        strokeWidth: 10,
                      ),
                    ),
                    // Ön Halka (Parlayan)
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: pct,
                        color: cs.primary,
                        strokeCap: StrokeCap.round,
                        strokeWidth: 10,
                      ),
                    ),
                    // Metin
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(pct * 100).toInt()}%',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: cs.primary),
                        ),
                      ],
                    )
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '$earned / $total Rozet Kazanıldı',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- NEON BADGE CARD WIDGET ---
class _BadgeCard extends StatelessWidget {
  final AppBadge badge;
  final double progress;
  final String label;
  final VoidCallback onTap;

  const _BadgeCard({required this.badge, required this.progress, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isCompleted = progress >= 1.0;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        height: 100, // Sabit yükseklik
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          // NEON GRADYAN
          gradient: LinearGradient(
            colors: [
              badge.color.withOpacity(0.15),
              Theme.of(context).colorScheme.surfaceContainer,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          // Parlak Çerçeve
          border: Border.all(
            color: isCompleted ? badge.color.withOpacity(0.6) : Colors.transparent,
            width: 1.5,
          ),
          // NEON GLOW (Gölge)
          boxShadow: [
            BoxShadow(
              color: badge.color.withOpacity(isCompleted ? 0.25 : 0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            // SOL: İkon Alanı (Halo Efektli)
            Container(
              width: 80,
              decoration: BoxDecoration(
                color: badge.color.withOpacity(0.2),
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
              ),
              child: Center(
                child: Hero(
                  tag: 'badge_${badge.id}',
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                         BoxShadow(
                           color: badge.color.withOpacity(0.4),
                           blurRadius: 15,
                           spreadRadius: -2,
                         )
                      ]
                    ),
                    child: Icon(badge.icon, size: 36, color: badge.color),
                  ),
                ),
              ),
            ),
            
            // ORTA: Bilgiler
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      badge.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      badge.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const Spacer(),
                    // Modern Progress Bar
                    Row(
                      children: [
                        Expanded(
                          child: Stack(
                            children: [
                              Container(
                                height: 6,
                                decoration: BoxDecoration(
                                  color: Colors.black12,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  return Container(
                                    height: 6,
                                    width: constraints.maxWidth * progress,
                                    decoration: BoxDecoration(
                                      color: badge.color,
                                      borderRadius: BorderRadius.circular(4),
                                      boxShadow: [
                                        BoxShadow(color: badge.color.withOpacity(0.6), blurRadius: 4)
                                      ]
                                    ),
                                  );
                                }
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          label, 
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badge.color),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // SAĞ: Kilit Durumu
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Icon(
                isCompleted ? Icons.workspace_premium : Icons.lock_outline,
                color: isCompleted ? Colors.amber : Colors.grey.withOpacity(0.4),
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- NEON DETAIL SHEET (PAYLAŞ BUTONU İLE) ---
class _BadgeDetailSheet extends StatelessWidget {
  final AppBadge badge;
  final double progress;
  final String label;

  const _BadgeDetailSheet({required this.badge, required this.progress, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompleted = progress >= 1.0;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tutamaç
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 32),

          // Büyük İkon (Animasyonlu Geçiş ve Glow)
          Hero(
            tag: 'badge_${badge.id}',
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: badge.color.withOpacity(0.15),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: badge.color.withOpacity(0.5), blurRadius: 40, spreadRadius: 5)
                ]
              ),
              child: Icon(badge.icon, size: 64, color: badge.color),
            ),
          ),
          const SizedBox(height: 24),

          Text(badge.name, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(badge.description, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
          
          const SizedBox(height: 32),
          
          // Durum Kutusu
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isCompleted ? Colors.green.withOpacity(0.3) : Colors.transparent),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isCompleted ? Icons.check_circle : Icons.timelapse, color: isCompleted ? Colors.green : Colors.orange),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isCompleted ? 'ROZET KAZANILDI' : 'DEVAM EDİYOR', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
                    Text(isCompleted ? 'Tebrikler!' : 'İlerleme: $label', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Butonlar (PAYLAŞ BUTONU EKLENDİ)
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: theme.colorScheme.outline),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Kapat'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    // Paylaşım İşlemi
                    final text = "MovieMatch uygulamasında '${badge.name}' rozetini kazandım! 🎬✨";
                    try {
                       Share.share(text); 
                    } catch (e) {
                       // Paket yoksa veya web ise fallback
                       ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(content: Text('Paylaşım özelliği şu an kullanılamıyor.')),
                       );
                    }
                  },
                  icon: const Icon(Icons.share),
                  label: const Text('Paylaş'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: badge.color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    shadowColor: badge.color.withOpacity(0.4),
                    elevation: 8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}