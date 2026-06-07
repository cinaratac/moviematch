import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';

/// Feed içinde postların arasına yerleştirilebilen önerilen kullanıcılar şeridi.
/// Yan yana avatar + altında isim gösterir; dokununca profil sayfasına gider.
class RecommendedUsers extends StatelessWidget {
  /// Kaç kullanıcı gösterileceği
  final int limit;

  /// Zorunlu değil ama istersen başlık gösterebilirsin
  final String? title;

  /// İstenmeyen kullanıcı id'leri (örn. zaten listede görünen yazarlar)
  final Set<String> excludeUserIds;

  const RecommendedUsers({
    super.key,
    this.limit = 12,
    this.title,
    this.excludeUserIds = const {},
  });

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetch() async {
    final me = FirebaseAuth.instance.currentUser?.uid;

    // Pull a broader pool (server first, fallback to cache), then pick random `limit` users.
    final pullSize = math.min(100, limit * 8); // cap to avoid big downloads

    QuerySnapshot<Map<String, dynamic>> qs;
    try {
      qs = await FirebaseFirestore.instance
          .collection('users')
          .limit(pullSize)
          .get(const GetOptions(source: Source.server));
    } catch (_) {
      qs = await FirebaseFirestore.instance
          .collection('users')
          .limit(pullSize)
          .get(const GetOptions(source: Source.cache));
    }

    // Filter out current user and excluded IDs
    final pool = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in qs.docs) {
  final uid = d.id;
  final data = d.data();

  // KRİTİK DEĞİŞİKLİK: Sadece username alanı olan ve boş olmayan kullanıcıları al
  final username = data['username'] as String?;
  if (username == null || username.trim().isEmpty) {
    continue; // Username yoksa bu kullanıcıyı atla
  }

  if (uid == me) continue;
  if (excludeUserIds.contains(uid)) continue;
  pool.add(d);
}

    // Shuffle randomly and take `limit`
    pool.shuffle(math.Random());
    if (pool.length > limit) {
      return pool.take(limit).toList();
    }
    return pool;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      future: _fetch(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: 122,
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(cs.primary),
              ),
            ),
          );
        }
        if (snap.hasError) {
          return const SizedBox(height: 1);
        }
        if (!snap.hasData || (snap.data?.isEmpty ?? true)) {
          // En azından küçük bir boş alan bırak ki feed içine yerleştiği görülsün
          return const SizedBox(height: 8);
        }

        final users = snap.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Text(
                  title!,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            if (title != null) const SizedBox(height: 6),
            SizedBox(
              height: 150,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  final u = users[index].data();
                  final uid = users[index].id;
                  final displayName = (u['displayName'] ?? '') as String;
                  final username = (u['username'] ?? '') as String;
                  final lb = (u['letterboxdUsername'] ?? '') as String;
                  final photoURL = (u['photoURL'] ?? '') as String;

                  final subtitle = username.isNotEmpty
                      ? '@$username'
                      : (lb.isNotEmpty ? '@$lb' : '');

                  return _UserChip(
                    uid: uid,
                    name: displayName.isNotEmpty
                        ? displayName
                        : (username.isNotEmpty ? username : 'Kullanıcı'),
                    subtitle: subtitle,
                    photoURL: photoURL,
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemCount: users.length,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _UserChip extends StatelessWidget {
  final String uid;
  final String name;
  final String subtitle;
  final String photoURL;

  const _UserChip({
    required this.uid,
    required this.name,
    required this.subtitle,
    required this.photoURL,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: uid)),
        );
      },
      child: Container(
        width: 120,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 38,
              backgroundImage: photoURL.isNotEmpty
                  ? NetworkImage(photoURL)
                  : null,
              child: photoURL.isEmpty ? const Icon(Icons.person) : null,
            ),
            const SizedBox(height: 8),
            Text(
              name,
              style: theme.textTheme.labelLarge,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
}
