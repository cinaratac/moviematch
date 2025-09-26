import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/services/like_service.dart';

class MatchesTab extends StatelessWidget {
  const MatchesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Eşleşmelerim')),
      body: const _MatchesList(),
    );
  }
}

class _MatchesList extends StatelessWidget {
  const _MatchesList();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: LikeService.instance.myMatchesStream(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Hata: ${snap.error}'));
        }
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const Center(
            child: Text('Henüz eşleşme yok. Beğeni göndererek başlayın.'),
          );
        }

        final me = FirebaseAuth.instance.currentUser?.uid;

        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final d = docs[i].data();
            final uids = List<String>.from(d['uids'] ?? const []);
            if (uids.length < 2 || me == null) {
              return const SizedBox.shrink();
            }
            final otherUid = (uids[0] == me) ? uids[1] : uids[0];
            final commonFavs = (d['commonFavoritesCount'] ?? 0) as int;
            final commonFive = (d['commonFiveStarsCount'] ?? 0) as int;

            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: _UserTitle(uid: otherUid),
              subtitle: Text('Ortak 5★: $commonFive • Ortak fav: $commonFavs'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                // TODO: Bir sohbet ekranına veya detay sayfasına yönlendir.
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Sohbet ekranını bağlayın (TODO)'),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Diğer kullanıcının görünen adını çözer.
/// Öncelik: users/{uid}.displayName -> userTasteProfiles/{uid}.profile.displayName -> uid
class _UserTitle extends StatelessWidget {
  final String uid;
  const _UserTitle({required this.uid});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    return FutureBuilder<Map<String, dynamic>>(
      future: () async {
        // users/{uid}
        final u = await db.collection('users').doc(uid).get();
        final um = u.data() ?? const {};
        final display = (um['displayName'] as String?)?.trim();
        if (display != null && display.isNotEmpty) {
          return {'title': display};
        }
        // userTasteProfiles/{uid}
        final t = await db.collection('userTasteProfiles').doc(uid).get();
        final tm = t.data() ?? const {};
        final profile = (tm['profile'] ?? const {}) as Map<String, dynamic>;
        final tDisplay = (profile['displayName'] as String?)?.trim();
        if (tDisplay != null && tDisplay.isNotEmpty) {
          return {'title': tDisplay};
        }
        return {'title': uid};
      }(),
      builder: (context, snap) {
        final title = (snap.data ?? const {'title': ''})['title'] as String?;
        return Text(title == null || title.isEmpty ? uid : title);
      },
    );
  }
}
