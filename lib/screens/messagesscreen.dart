import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/chat_room_screen.dart';
import 'package:fluttergirdi/services/chat_service.dart';
import 'dart:async';

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
            // Chats sorgusu yetkiden düştüyse: matches fallback
            return _MatchesFallbackList(uid: uid);
          }

          // Local sort by lastMessageAt desc to avoid composite index
          final docs = [
            ...(s.data?.docs ??
                <QueryDocumentSnapshot<Map<String, dynamic>>>[]),
          ];
          docs.sort((a, b) {
            final ta = a.data()['lastMessageAt'] as Timestamp?;
            final tb = b.data()['lastMessageAt'] as Timestamp?;
            final da = ta?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
            final db = tb?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
            return db.compareTo(da);
          });

          if (docs.isEmpty) {
            // Hiç chat yoksa (veya görünmüyorsa) matches fallback göster
            return _MatchesFallbackList(uid: uid);
          }

          return ListView.separated(
            itemCount: docs.length,
            cacheExtent: 800,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data();
              final partsAny = (data['participants'] as List?) ?? const [];
              final parts = partsAny.map((e) => e.toString()).toList();
              if (!parts.contains(uid)) return const SizedBox.shrink();
              final otherUid = parts.firstWhere(
                (e) => e != uid,
                orElse: () => '',
              );
              if (otherUid.isEmpty) return const SizedBox.shrink();

              final last = (data['lastMessage'] ?? '') as String;
              final lastAt = (data['lastMessageAt'] as Timestamp?)?.toDate();

              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: fs.collection('users').doc(otherUid).get(),
                builder: (context, uSnap) {
                  String title = otherUid;
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
                      last,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (lastAt != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              _formatTime(lastAt),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        StreamBuilder<int>(
                          stream: ChatService.instance.unreadCountForChat(
                            d.id,
                            uid,
                          ),
                          builder: (context, cSnap) {
                            final count = cSnap.data ?? 0;
                            if (count <= 0) return const SizedBox.shrink();
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                count.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    onTap: () async {
                      final chatId = d.id; // chats id zaten pairId

                      // Hemen odaya git (UI bloklanmasın)
                      if (context.mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatRoomScreen(
                              chatId: chatId,
                              otherUid: otherUid,
                              otherTitle: title,
                            ),
                          ),
                        );
                      }

                      // Arkadan chat stub onarımı + okundu işareti (fire-and-forget)
                      unawaited(
                        fs.collection('chats').doc(chatId).set({
                          'participants': parts,
                          'updatedAt': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true)),
                      );

                      unawaited(ChatService.instance.markAsRead(chatId, uid));
                    },
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

class _MatchesFallbackList extends StatelessWidget {
  final String uid;
  const _MatchesFallbackList({required this.uid});

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: fs
          .collection('matches')
          .where('uids', arrayContains: uid)
          .snapshots(),
      builder: (context, s) {
        if (s.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) {
          return Center(child: Text('Hata: ${s.error}'));
        }
        final docs = [...(s.data?.docs ?? const [])];
        if (docs.isEmpty) {
          return const Center(child: Text('Sohbet yok'));
        }
        // Client-side sort by updatedAt DESC to avoid composite index
        docs.sort((a, b) {
          final ta = a.data()['updatedAt'] as Timestamp?;
          final tb = b.data()['updatedAt'] as Timestamp?;
          final da = ta?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = tb?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        });
        return ListView.separated(
          itemCount: docs.length,
          cacheExtent: 800,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final d = docs[i].data();
            final uids = List<String>.from(d['uids'] ?? const []);
            if (uids.length < 2) return const SizedBox.shrink();
            final otherUid = (uids[0] == uid) ? uids[1] : uids[0];
            return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: fs.collection('users').doc(otherUid).get(),
              builder: (context, uSnap) {
                String title = otherUid;
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

                final chatId = (uid.compareTo(otherUid) < 0)
                    ? '${uid}_$otherUid'
                    : '${otherUid}_$uid';

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
                  subtitle: const Text('Eşleşme'),
                  trailing: StreamBuilder<int>(
                    stream: ChatService.instance.unreadCountForChat(
                      chatId,
                      uid,
                    ),
                    builder: (context, cSnap) {
                      final count = cSnap.data ?? 0;
                      if (count <= 0) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          count.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    },
                  ),
                  onTap: () async {
                    // Hemen odaya git
                    if (context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatRoomScreen(
                            chatId: chatId,
                            otherUid: otherUid,
                            otherTitle: title,
                          ),
                        ),
                      );
                    }

                    // Arkadan chat stub ve okundu
                    unawaited(
                      fs.collection('chats').doc(chatId).set({
                        'participants': [uid, otherUid],
                        'updatedAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true)),
                    );

                    unawaited(ChatService.instance.markAsRead(chatId, uid));
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
