import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/utils/date_helper.dart';

// --- EKLENEN IMPORT ---
// Rozet sayısını dinamik çekmek için gerekli model dosyası
import 'package:fluttergirdi/models/gamification.dart'; 

import 'package:fluttergirdi/screens/badges_progress_screen.dart'; 
import 'package:fluttergirdi/screens/clubs_tab.dart';           
import 'package:fluttergirdi/screens/trivia_welcome_screen.dart';  

class DashboardStatsRow extends StatelessWidget {
  const DashboardStatsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          // 1. KART: ROZET İLERLEMESİ
          Expanded(child: _BadgeProgressCard()),
          const SizedBox(width: 10),

          // 2. KART: TRIVIA BİRİNCİSİ
          Expanded(child: _TriviaLeaderCard()),
          const SizedBox(width: 10),

          // 3. KART: EN POPÜLER KULÜP
          Expanded(child: _TopClubCard()),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. KART: ROZET İLERLEMESİ
// ---------------------------------------------------------------------------
class _BadgeProgressCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    
    // --- DÜZELTME BURADA YAPILDI ---
    // Artık sabit '5' yerine, tanımlı rozet listesinin uzunluğunu alıyoruz.
    final int totalBadges = AppBadge.allBadges.length;
    // -------------------------------

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
      builder: (context, snapshot) {
        double percent = 0;
        
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final myBadges = (data['badges'] as List?) ?? [];
          if (totalBadges > 0) {
            percent = (myBadges.length / totalBadges).clamp(0.0, 1.0);
          }
        }

        return _SquareCard(
          color: const Color.fromARGB(255, 51, 100, 206),
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const BadgesProgressScreen()));
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: percent,
                    backgroundColor: Colors.white24,
                    color: Colors.amber,
                    strokeWidth: 4,
                  ),
                  Text(
                    "%${(percent * 100).toInt()}",
                    style: const TextStyle(
                      color: Colors.white, 
                      fontWeight: FontWeight.bold, 
                      fontSize: 10
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                "Rozetler",
                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 2. KART: TRIVIA BİRİNCİSİ
// ---------------------------------------------------------------------------
class _TriviaLeaderCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final weekId = DateHelper.getCurrentWeekId();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('weekly_leaderboard')
          .doc(weekId)
          .collection('scores')
          .orderBy('score', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        String leaderName = "Lider Yok";
        String scoreText = "-";

        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
          leaderName = data['displayName'] ?? "Gizli";
          scoreText = "${data['score']}P";
        }

        return _SquareCard(
          color: const Color(0xFF1A1A2E), 
          border: Border.all(color: Colors.amber.withOpacity(0.5)),
          onTap: () {
            // Trivia ekranına yönlendirme
            Navigator.push(context, MaterialPageRoute(builder: (_) => const TriviaWelcomeScreen()));
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.emoji_events, color: Colors.amber, size: 24),
              const SizedBox(height: 4),
              const Text(
                "Haftanın Lideri",
                style: TextStyle(color: Colors.white54, fontSize: 9),
              ),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Text(
                  leaderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
              Text(
                scoreText,
                style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 3. KART: EN POPÜLER KULÜP
// ---------------------------------------------------------------------------
class _TopClubCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('clubs')
          .orderBy('memberCount', descending: true) 
          .limit(1)
          .get(),
      builder: (context, snapshot) {
        String clubName = "Kulüpler";
        int members = 0;

        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
          clubName = data['name'] ?? "Kulüp";
          members = data['memberCount'] ?? 0;
        }

        return _SquareCard(
          color: Color.fromARGB(139, 26, 138, 28),
          onTap: () {
             Navigator.push(context, MaterialPageRoute(builder: (_) => const ClubsScreen()));
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.groups_rounded, color: Colors.white, size: 24),
              const SizedBox(height: 4),
              const Text(
                "En Popüler",
                style: TextStyle(color: Colors.white70, fontSize: 9),
              ),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Text(
                  clubName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
              Text(
                "$members Üye",
                style: const TextStyle(color: Colors.white70, fontSize: 9),
              ),
            ],
          ),
        );
      },
    );
  }
}

// --- ORTAK KART TASARIMI ---
class _SquareCard extends StatelessWidget {
  final Widget child;
  final Color color;
  final VoidCallback onTap;
  final BoxBorder? border;

  const _SquareCard({
    required this.child,
    required this.color,
    required this.onTap,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1, 
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(16),
            border: border,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}