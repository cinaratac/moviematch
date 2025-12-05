import 'package:flutter/material.dart';
import 'package:fluttergirdi/models/gamification.dart';
import 'package:fluttergirdi/services/gamification_service.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart'; // Profil sayfasına gitmek için

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2, 
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Liderler', style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Theme.of(context).colorScheme.surface,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'En Popüler'),
              Tab(text: 'Film Kurtları'),
            ],
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
                const Text("Henüz veri yok veya yüklenemedi.", style: TextStyle(color: Colors.grey)),
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
            // İlk 3 kişiye özel renkler
            final isTop3 = index < 3;
            Color rankColor;
            if (index == 0) rankColor = const Color(0xFFFFD700); // Altın
            else if (index == 1) rankColor = const Color(0xFFC0C0C0); // Gümüş
            else if (index == 2) rankColor = const Color(0xFFCD7F32); // Bronz
            else rankColor = Theme.of(context).colorScheme.surfaceContainerHighest;

            return GestureDetector(
              onTap: () {
                // Profile git
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: user.uid)),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: isTop3 ? Border.all(color: rankColor.withOpacity(0.6), width: 1.5) : null,
                ),
                child: Row(
                  children: [
                    // Sıralama Rozeti
                    Container(
                      width: 32, height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isTop3 ? rankColor : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '#${user.rank}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isTop3 ? Colors.black : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    
                    // Profil Resmi
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: Colors.grey.shade800,
                      backgroundImage: (user.photoURL != null && user.photoURL!.isNotEmpty)
                          ? NetworkImage(user.photoURL!)
                          : null,
                      child: (user.photoURL == null || user.photoURL!.isEmpty)
                          ? const Icon(Icons.person, size: 20)
                          : null,
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