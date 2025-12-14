import 'package:flutter/material.dart';
import 'package:fluttergirdi/models/gamification.dart';
import 'package:fluttergirdi/services/gamification_service.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart'; 

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 2, 
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          
          // 1. BAŞLIK
          title: const Text(
            'Liderlik Tablosu', 
            style: TextStyle(fontWeight: FontWeight.bold)
          ),

          // 2. BUBBLE TAB (Başlığın Altında)
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60), // Tab alanı yüksekliği
            child: Container(
              height: 45, // İçteki barın yüksekliği
              // Yanlardan boşluk (16), alttan boşluk (12)
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12), 
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.5), // Gri zemin
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                // Kayan Beyaz Baloncuk
                indicator: BoxDecoration(
                  color: cs.surface, 
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                labelColor: cs.onSurface,
                unselectedLabelColor: cs.onSurfaceVariant,
                labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                tabs: const [
                  Tab(text: 'En Popüler'),
                  Tab(text: 'Film Kurtları'),
                ],
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _LeaderboardList(
              fetcher: GamificationService.instance.getWeeklyTopUsers, 
              metricLabel: 'Takipçi'
            ),
            _LeaderboardList(
              fetcher: GamificationService.instance.getTopFilmBuffs,
              metricLabel: 'Film',
            ),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardList extends StatelessWidget {
  final Future<List<LeaderboardUser>> Function() fetcher;
  final String metricLabel;

  const _LeaderboardList({required this.fetcher, required this.metricLabel});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LeaderboardUser>>(
      future: fetcher(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final users = snap.data ?? [];
        
        if (users.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.emoji_events_outlined, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                const Text("Henüz veri yok.", style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: users.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final user = users[index];
            
            // Renk ve Taç Ayarları
            Color? bgColor;
            Color? borderColor;
            Color rankBadgeColor;
            bool showCrown = false;

            if (index == 0) {
              // 1. Sıra (Altın)
              bgColor = const Color(0xFFFFD700).withOpacity(0.15); 
              borderColor = const Color(0xFFFFD700);
              rankBadgeColor = const Color(0xFFFFD700);
              showCrown = true;
            } else if (index == 1) {
              // 2. Sıra (Gümüş)
              bgColor = const Color(0xFFC0C0C0).withOpacity(0.15);
              borderColor = const Color(0xFFC0C0C0);
              rankBadgeColor = const Color(0xFFC0C0C0);
            } else if (index == 2) {
              // 3. Sıra (Bronz)
              bgColor = const Color(0xFFCD7F32).withOpacity(0.15);
              borderColor = const Color(0xFFCD7F32);
              rankBadgeColor = const Color(0xFFCD7F32);
            } else {
              // Diğerleri
              bgColor = Theme.of(context).colorScheme.surfaceContainerLow;
              borderColor = Colors.transparent;
              rankBadgeColor = Theme.of(context).colorScheme.surfaceContainerHighest;
            }

            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: user.uid)),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: borderColor,
                    width: index < 3 ? 1.5 : 0 
                  ),
                ),
                child: Row(
                  children: [
                    // Sıralama Rozeti
                    Container(
                      width: 32, height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: rankBadgeColor,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '#${user.rank}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: index < 3 ? Colors.black : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    
                    // Profil Resmi + Taç (Varsa)
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.grey.shade800,
                          backgroundImage: (user.photoURL != null && user.photoURL!.isNotEmpty)
                              ? NetworkImage(user.photoURL!)
                              : null,
                          child: (user.photoURL == null || user.photoURL!.isEmpty)
                              ? const Icon(Icons.person, size: 24)
                              : null,
                        ),
                        if (showCrown)
                          Positioned(
                            top: -12,
                            right: -6,
                            child: Transform.rotate(
                              angle: 0.2,
                              child: const Icon(
                                Icons.workspace_premium, 
                                color: Color(0xFFFFD700),
                                size: 28,
                                shadows: [
                                  Shadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1))
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    
                    // İsim
                    Expanded(
                      child: Text(
                        user.displayName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    
                    // Puan
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${user.score} $metricLabel',
                        style: TextStyle(
                          fontSize: 12, 
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onPrimaryContainer
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}