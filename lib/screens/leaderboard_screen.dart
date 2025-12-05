import 'package:flutter/material.dart';
import 'package:fluttergirdi/models/gamification.dart';
import 'package:fluttergirdi/services/gamification_service.dart';

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2, // Popülerler ve En Aktifler
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Liderler', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'En Popüler'),
              Tab(text: 'Film Kurtları'), // İleride eklenebilir
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _LeaderboardList(fetcher: GamificationService.instance.getWeeklyTopUsers),
            const Center(child: Text("Çok yakında...")),
          ],
        ),
      ),
    );
  }
}

class _LeaderboardList extends StatelessWidget {
  final Future<List<LeaderboardUser>> Function() fetcher;
  const _LeaderboardList({required this.fetcher});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LeaderboardUser>>(
      future: fetcher(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snap.hasData || snap.data!.isEmpty) {
          return const Center(child: Text("Henüz veri yok."));
        }
        final users = snap.data!;

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: users.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final user = users[index];
            // İlk 3 kişiye özel stil
            final isTop3 = index < 3;
            final rankColor = index == 0 ? Colors.amber : (index == 1 ? Colors.grey.shade300 : (index == 2 ? Colors.brown.shade300 : Colors.white));

            return Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: isTop3 ? Border.all(color: rankColor.withOpacity(0.5)) : null,
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: rankColor,
                  foregroundColor: Colors.black,
                  child: Text('#${user.rank}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                title: Text(user.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${user.score} Takipçi',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                // Tıklayınca profile gitme eklenebilir
              ),
            );
          },
        );
      },
    );
  }
}