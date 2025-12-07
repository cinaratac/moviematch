import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/models/gamification.dart';
import 'package:fluttergirdi/services/follow_system_service.dart';

class BadgesProgressScreen extends StatefulWidget {
  const BadgesProgressScreen({super.key});

  @override
  State<BadgesProgressScreen> createState() => _BadgesProgressScreenState();
}

class _BadgesProgressScreenState extends State<BadgesProgressScreen> {
  bool _loading = true;
  Map<String, double> _progress = {}; // BadgeID -> Yüzde (0.0 - 1.0)
  Map<String, String> _labels = {};   // BadgeID -> "85/100"

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
      final favs = List.from(userData['favoritesKeys'] ?? []);
      final fives = List.from(userData['fiveStarKeys'] ?? []);
      final watch = List.from(userData['watchlistKeys'] ?? []);
      final disliked = List.from(userData['dislikedKeys'] ?? []);
      final uniqueMovies = {...favs, ...fives, ...watch, ...disliked}.length;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rozet İlerlemesi')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: AppBadge.allBadges.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final badge = AppBadge.allBadges[index];
                final pct = _progress[badge.id] ?? 0.0;
                final label = _labels[badge.id] ?? '0/0';
                final isCompleted = pct >= 1.0;

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                    border: isCompleted 
                        ? Border.all(color: badge.color.withOpacity(0.5), width: 2) 
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: badge.color.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(badge.icon, color: badge.color),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(badge.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text(badge.description, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                          ),
                          if (isCompleted)
                            const Icon(Icons.check_circle, color: Colors.green),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(isCompleted ? 'Tamamlandı!' : 'İlerleme', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 8,
                          backgroundColor: Colors.grey.shade800,
                          color: badge.color,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}