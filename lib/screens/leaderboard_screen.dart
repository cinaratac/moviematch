import 'package:flutter/material.dart';
import 'package:fluttergirdi/models/gamification.dart';
import 'package:fluttergirdi/services/gamification_service.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Trivia verisi için     // Trivia'da kendini görmek için
import '../utils/date_helper.dart';                    // Trivia tarihi için

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 3, // <--- 3 SEKME OLARAK GÜNCELLENDİ
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          
          title: const Text(
            'Liderlik Tablosu', 
            style: TextStyle(fontWeight: FontWeight.bold)
          ),

          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: Container(
              height: 45,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12), 
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
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
                  Tab(text: 'Yarışma'), // <--- 3. SEKME EKLENDİ
                ],
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            // 1. MEVCUT SEKME (KORUNDU)
            _LeaderboardList(
              fetcher: GamificationService.instance.getWeeklyTopUsers, 
              metricLabel: 'Takipçi'
            ),
            // 2. MEVCUT SEKME (KORUNDU)
            _LeaderboardList(
              fetcher: GamificationService.instance.getTopFilmBuffs,
              metricLabel: 'Film',
            ),
            // 3. YENİ EKLENEN SEKME (Trivia)
            const _TriviaRankingTab(),
          ],
        ),
      ),
    );
  }
}

// --- MEVCUT YAPINIZ (DOKUNULMADI) ---
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
            return _buildRankItem(
              context: context,
              index: index,
              rank: user.rank,
              uid: user.uid,
              displayName: user.displayName,
              photoURL: user.photoURL,
              scoreText: '${user.score} $metricLabel',
            );
          },
        );
      },
    );
  }
}

// --- YENİ EKLENEN TRIVIA TABI (Senin tasarımına uyarlandı) ---
class _TriviaRankingTab extends StatelessWidget {
  const _TriviaRankingTab();

  @override
  Widget build(BuildContext context) {
    final weekId = DateHelper.getCurrentWeekId();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('weekly_leaderboard')
          .doc(weekId)
          .collection('scores')
          .orderBy('score', descending: true)
          .orderBy('timestamp', descending: false)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.quiz_outlined, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                const Text("Bu hafta henüz kimse yarışmadı.", style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final uid = data['uid'] ?? '';
            final displayName = data['displayName'] ?? 'Gizli';
            final score = data['score'] ?? 0;
            final photoURL = data['photoURL'] as String?;

            // Senin tasarım fonksiyonunu kullanarak çiziyoruz
            return _buildRankItem(
              context: context,
              index: index,
              rank: index + 1,
              uid: uid,
              displayName: displayName,
              photoURL: photoURL,
              scoreText: '$score Puan',
            );
          },
        );
      },
    );
  }
}

// --- ORTAK TASARIM WIDGETI (Senin kodundan çıkarıp ortak hale getirdim ki hepsi aynı görünsün) ---
Widget _buildRankItem({
  required BuildContext context,
  required int index,
  required int rank,
  required String uid,
  required String displayName,
  required String? photoURL,
  required String scoreText,
}) {
  Color? bgColor;
  Color? borderColor;
  Color rankBadgeColor;
  bool showCrown = false;

  if (index == 0) {
    bgColor = const Color(0xFFFFD700).withOpacity(0.15);
    borderColor = const Color(0xFFFFD700);
    rankBadgeColor = const Color(0xFFFFD700);
    showCrown = true;
  } else if (index == 1) {
    bgColor = const Color(0xFFC0C0C0).withOpacity(0.15);
    borderColor = const Color(0xFFC0C0C0);
    rankBadgeColor = const Color(0xFFC0C0C0);
  } else if (index == 2) {
    bgColor = const Color(0xFFCD7F32).withOpacity(0.15);
    borderColor = const Color(0xFFCD7F32);
    rankBadgeColor = const Color(0xFFCD7F32);
  } else {
    bgColor = Theme.of(context).colorScheme.surfaceContainerLow;
    borderColor = Colors.transparent;
    rankBadgeColor = Theme.of(context).colorScheme.surfaceContainerHighest;
  }

  return GestureDetector(
    onTap: () {
      if (uid.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: uid)),
        );
      }
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
              '#$rank',
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
                backgroundImage: (photoURL != null && photoURL.isNotEmpty)
                    ? NetworkImage(photoURL)
                    : null,
                child: (photoURL == null || photoURL.isEmpty)
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
              displayName,
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
              scoreText,
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
}