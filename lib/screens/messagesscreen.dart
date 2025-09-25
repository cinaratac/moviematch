import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/chat_room_screen.dart';

class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final fs = FirebaseFirestore.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('Sohbetler')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: fs
            .collection('chats')
            .where('participants', arrayContains: uid)
            .snapshots(),
        builder: (context, s) {
          if (s.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.hasError) {
            return Center(child: Text('Hata: ${s.error}'));
          }
          final docs = [...(s.data?.docs ?? [])];
          // Local sort to avoid composite index (lastMessageAt desc)
          docs.sort((a, b) {
            final ta = (a.data()['lastMessageAt'] as Timestamp?);
            final tb = (b.data()['lastMessageAt'] as Timestamp?);
            final da = ta?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
            final db = tb?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
            return db.compareTo(da); // desc
          });
          if (docs.isEmpty) {
            return const Center(child: Text('Sohbet yok'));
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final d = docs[i];
              final data = d.data();
              final participants = (data['participants'] as List)
                  .cast<String>();
              final otherUid = participants.firstWhere(
                (x) => x != uid,
                orElse: () => '',
              );
              final last = (data['lastMessage'] ?? '') as String;
              final lastAt = (data['lastMessageAt'] as Timestamp?)?.toDate();

              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: fs.collection('users').doc(otherUid).get(),
                builder: (context, uSnap) {
                  String title = otherUid;
                  String subtitle = last;
                  String? photoURL;
                  if (uSnap.hasData && uSnap.data!.exists) {
                    final u = uSnap.data!.data()!;
                    final username = (u['username'] ?? '') as String;
                    final displayName = (u['displayName'] ?? '') as String;
                    final lb = (u['letterboxdUsername'] ?? '') as String;
                    photoURL = (u['photoURL'] ?? '') as String;
                    title = username.isNotEmpty
                        ? username
                        : (displayName.isNotEmpty
                              ? displayName
                              : (lb.isNotEmpty ? '@$lb' : otherUid));
                  }

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: (photoURL != null && photoURL.isNotEmpty)
                          ? NetworkImage(photoURL)
                          : null,
                      child: (photoURL == null || photoURL.isEmpty)
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    title: Text(title, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: lastAt != null
                        ? Text(
                            _formatTime(lastAt),
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        : null,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ChatRoomScreen(chatId: d.id, otherUid: otherUid),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

String _formatTime(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final thatDay = DateTime(dt.year, dt.month, dt.day);
  if (thatDay == today) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
  return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}';
}
