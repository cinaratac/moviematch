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
      height: 154,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        itemCount: 3,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          return SizedBox(
            width: 156,
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
          accent: const Color(0xFF4F7CFF),
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
          accent: const Color(0xFFFFB020),
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
          accent: const Color(0xFF2EAD5F),
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
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isDark
          ? cs.surfaceContainerHighest.withValues(alpha: 0.34)
          : cs.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
            ),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 19, color: accent),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 19,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.68),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                eyebrow,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
              if (progress != null) ...[
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
              ],
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
