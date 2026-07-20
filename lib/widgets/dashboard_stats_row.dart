import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/models/gamification.dart';
import 'package:fluttergirdi/screens/badges_progress_screen.dart';
import 'package:fluttergirdi/screens/clubs_tab.dart';
import 'package:fluttergirdi/screens/trivia_welcome_screen.dart';
import 'package:fluttergirdi/utils/date_helper.dart';

class DashboardStatsRow extends StatelessWidget {
  const DashboardStatsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height:
          172, // Kartların yeni tasarımda daha rahat nefes alması için hafifçe artırıldı
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        itemCount: 3,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return SizedBox(
            width: 160,
            child: switch (index) {
              0 => const _BadgeProgressCard(),
              1 => const _TriviaLeaderCard(),
              _ => const _TopClubCard(),
            },
          );
        },
      ),
    );
  }
}

class _BadgeProgressCard extends StatelessWidget {
  const _BadgeProgressCard();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final totalBadges = AppBadge.allBadges.length;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user?.uid)
          .snapshots(),
      builder: (context, snapshot) {
        var earnedBadges = 0;

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          earnedBadges = ((data['badges'] as List?) ?? const []).length;
        }

        final percent = totalBadges == 0
            ? 0.0
            : (earnedBadges / totalBadges).clamp(0.0, 1.0);

        return _DashboardCard(
          accent: const Color(0xFF8B5CF6), // Canlı, modern bir Mor
          icon: Icons.workspace_premium_rounded,
          eyebrow: 'Rozetler',
          title: '$earnedBadges/$totalBadges',
          subtitle: 'Koleksiyon ilerlemesi',
          progress: percent,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BadgesProgressScreen()),
            );
          },
        );
      },
    );
  }
}

class _TriviaLeaderCard extends StatelessWidget {
  const _TriviaLeaderCard();

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
        var leaderName = 'Lider Yok';
        var scoreText = 'Bu hafta bekleniyor';

        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
          leaderName = (data['displayName'] ?? 'Gizli').toString();
          scoreText = '${_readInt(data['score'])} puan';
        }

        return _DashboardCard(
          accent: const Color(0xFFF59E0B), // Zengin Kehribar/Altın
          icon: Icons.emoji_events_rounded,
          eyebrow: 'Haftanın Lideri',
          title: leaderName,
          subtitle: scoreText,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TriviaWelcomeScreen()),
            );
          },
        );
      },
    );
  }
}

class _TopClubCard extends StatelessWidget {
  const _TopClubCard();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('clubs')
          .orderBy('memberCount', descending: true)
          .limit(1)
          .get(),
      builder: (context, snapshot) {
        var clubName = 'Kulüpler';
        var members = 0;

        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
          clubName = (data['name'] ?? 'Kulüp').toString();
          members = _readInt(data['memberCount']);
        }

        return _DashboardCard(
          accent: const Color(0xFF10B981), // Sinematik Zümrüt Yeşili
          icon: Icons.groups_rounded,
          eyebrow: 'Popüler Kulüp',
          title: clubName,
          subtitle: members > 0 ? '$members üye' : 'Kulüpleri keşfet',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ClubsScreen()),
            );
          },
        );
      },
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final Color accent;
  final IconData icon;
  final String eyebrow;
  final String title;
  final String subtitle;
  final double? progress;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.accent,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Kart zemin renkleri
    final surfaceColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final titleColor = isDark ? Colors.white : Colors.black87;
    final mutedColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20), // Daha modern oval köşeler
        color: surfaceColor,
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.25 : 0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: isDark ? 0.05 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ARKA PLAN FİLİGRANI (Watermark) - Çok daha profesyonel bir his katar
              Positioned(
                right: -16,
                bottom: -16,
                child: Icon(
                  icon,
                  size: 96,
                  color: accent.withValues(alpha: isDark ? 0.06 : 0.04),
                ),
              ),
              // İÇERİK KISMI
              Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: accent.withValues(
                              alpha: isDark ? 0.2 : 0.12,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(icon, size: 20, color: accent),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: mutedColor.withValues(alpha: 0.5),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      eyebrow.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                        letterSpacing:
                            0.8, // Editoryal bir görünüm için harf arası boşluk
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: titleColor,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: mutedColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (progress != null) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4, // İnce ve zarif bir bar
                          backgroundColor: accent.withValues(alpha: 0.15),
                          valueColor: AlwaysStoppedAnimation<Color>(accent),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

int _readInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
