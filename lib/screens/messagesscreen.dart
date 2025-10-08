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
      appBar: AppBar(toolbarHeight: 40, title: const Text('Sohbetler')),
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
            return Center(child: Text('Sohbetler yüklenemedi'));
          }

          // Local sort by lastMessageAt desc to avoid composite index
          final docs = [
            ...(s.data?.docs ??
                <QueryDocumentSnapshot<Map<String, dynamic>>>[]),
          ];
          docs.sort((a, b) {
            final ta = a.data()['lastMessageAt'];
            final tb = b.data()['lastMessageAt'];
            final da = (ta is Timestamp)
                ? ta.toDate()
                : DateTime.fromMillisecondsSinceEpoch(0);
            final db = (tb is Timestamp)
                ? tb.toDate()
                : DateTime.fromMillisecondsSinceEpoch(0);
            return db.compareTo(da); // newest first strictly by lastMessageAt
          });

          if (docs.isEmpty) {
            return const _EmptyMessagesInteractive();
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
                    subtitle:
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: fs
                              .collection('chats')
                              .doc(d.id)
                              .collection('messages')
                              .orderBy('createdAt', descending: true)
                              .limit(1)
                              .snapshots(),
                          builder: (context, mSnap) {
                            String preview = last;
                            if (mSnap.hasData && mSnap.data!.docs.isNotEmpty) {
                              final m = mSnap.data!.docs.first.data();
                              preview =
                                  (m['text'] ??
                                          m['message'] ??
                                          m['content'] ??
                                          preview)
                                      .toString();
                            }
                            return Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            );
                          },
                        ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Last message sent time (live)
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('chats')
                              .doc(d.id)
                              .collection('messages')
                              .orderBy('createdAt', descending: true)
                              .limit(1)
                              .snapshots(),
                          builder: (context, ms) {
                            DateTime? lastDt;
                            if (ms.hasData && ms.data!.docs.isNotEmpty) {
                              final doc = ms.data!.docs.first;
                              final m = doc.data();
                              final raw = m['createdAt'];
                              if (raw is Timestamp) {
                                lastDt = raw.toDate().toLocal();
                              } else if (doc.metadata.hasPendingWrites) {
                                lastDt = DateTime.now();
                              }
                            }

                            DateTime? showAt =
                                lastDt ??
                                lastAt ??
                                (data['updatedAt'] as Timestamp?)?.toDate();
                            final t = (showAt != null)
                                ? _formatTime(showAt)
                                : '';
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                t,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            );
                          },
                        ),

                        // Unread badge
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
  final local = dt.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final thatDay = DateTime(local.year, local.month, local.day);
  if (thatDay == today) {
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
  return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}';
}

class _ForestFace extends StatelessWidget {
  final double offsetX;
  final double offsetY;
  const _ForestFace({this.offsetX = 0, this.offsetY = 0});

  @override
  Widget build(BuildContext context) {
    const base = Color(0xFF1B5E20); // forest green
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _ring(140, base.withOpacity(0.90)),
          _ring(112, base.withOpacity(0.75)),
          _ring(88, base.withOpacity(0.55)),
          _ring(64, base.withOpacity(0.35)),
          _ring(44, base.withOpacity(0.20)),
          Positioned(left: 38, top: 54, child: _eye(offsetX, offsetY)),
          Positioned(right: 38, top: 54, child: _eye(offsetX, offsetY)),
        ],
      ),
    );
  }

  static Widget _ring(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  static Widget _eye(double offsetX, double offsetY) {
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment(offsetX / 10, offsetY / 10),
        child: Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: Colors.black87,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _EmptyMessagesInteractive extends StatefulWidget {
  const _EmptyMessagesInteractive();
  @override
  State<_EmptyMessagesInteractive> createState() =>
      _EmptyMessagesInteractiveState();
}

class _EmptyMessagesInteractiveState extends State<_EmptyMessagesInteractive> {
  double _offsetX = 0;
  double _offsetY = -10; // default: look slightly upward

  void _updateOffsets(Offset p, Size size) {
    // Normalize position to [-1,1] range around the center of the available area
    final cx = size.width / 2;
    final cy = size.height / 2;
    double nx = ((p.dx - cx) / (cx.abs())).clamp(-1.0, 1.0);
    double ny = ((p.dy - cy) / (cy.abs())).clamp(-1.0, 1.0);

    const max = 10.0; // max eye travel in our _ForestFace alignment mapping
    setState(() {
      _offsetX = nx * max;
      _offsetY = ny * max;
    });
  }

  void _resetUp() {
    setState(() {
      _offsetX = 0;
      _offsetY = -10; // back to looking up in empty state
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanDown: (details) => _updateOffsets(details.localPosition, size),
          onPanUpdate: (details) => _updateOffsets(details.localPosition, size),
          onPanEnd: (_) => _resetUp(),
          onTapDown: (details) => _updateOffsets(details.localPosition, size),
          onTapUp: (_) => _resetUp(),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ForestFace(offsetX: _offsetX, offsetY: _offsetY),
                const SizedBox(height: 12),
                const Text(
                  'Yalnızsın galiba',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color.fromARGB(255, 124, 131, 116),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
