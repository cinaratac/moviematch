import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/chat_room_screen.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
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
            .snapshots(includeMetadataChanges: true),
        builder: (context, s) {
          if (s.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.hasError) {
            return const _EmptyMessagesInteractive();
          }

          // Local sort by most recent activity (updatedAt fallback to lastMessageAt)
          final docs = [
            ...(s.data?.docs ??
                <QueryDocumentSnapshot<Map<String, dynamic>>>[]),
          ];
          DateTime _pickDate(Map<String, dynamic> m) {
            final rawU = m['updatedAt'];
            final rawL = m['lastMessageAt'];
            if (rawL is Timestamp) return rawL.toDate();
            if (rawU is Timestamp) return rawU.toDate();
            return DateTime.fromMillisecondsSinceEpoch(0);
          }

          docs.sort((a, b) {
            final da = _pickDate(a.data());
            final db = _pickDate(b.data());
            // ensure newest chats appear first even if timestamps are missing
            return db.millisecondsSinceEpoch.compareTo(
              da.millisecondsSinceEpoch,
            );
          });

          // Hide chats that current user chose to hide (visibleFor[uid] == false)
          docs.removeWhere((doc) {
            final data = doc.data();
            final vis =
                (data['visibleFor'] as Map<String, dynamic>?) ?? const {};
            final v = vis[uid];
            return v is bool && v == false;
          });

          // Mutual likes limited to current user (either a==uid or b==uid)
          final likesCollection = fs.collection('likes');
          final mutualLikesFuture = Future.wait([
            likesCollection.where('a', isEqualTo: uid).limit(50).get(),
            likesCollection.where('b', isEqualTo: uid).limit(50).get(),
          ]);

          return FutureBuilder<List<QuerySnapshot<Map<String, dynamic>>>>(
            future: mutualLikesFuture,
            builder: (context, mutualSnap) {
              // Gather chats
              final chats = [...(docs)];

              // Prepare mutual like: pick the most recent unseen mutual if any
              String? mutualOtherUid;
              int latestTs = -1;
              if (mutualSnap.hasData) {
                final listA = mutualSnap.data![0].docs; // a == uid
                final listB = mutualSnap.data![1].docs; // b == uid

                void consider(
                  QueryDocumentSnapshot<Map<String, dynamic>> d, {
                  required bool meIsA,
                }) {
                  final m = d.data();
                  final a = (m['a'] ?? '').toString();
                  final b = (m['b'] ?? '').toString();
                  final aLiked = m['aLiked'] == true;
                  final bLiked = m['bLiked'] == true;
                  final aSeen = m['aSeen'] == true;
                  final bSeen = m['bSeen'] == true;
                  if (!(aLiked && bLiked)) return; // not mutual

                  final unseenForMe = meIsA ? !aSeen : !bSeen;
                  if (!unseenForMe) return; // already seen by me

                  final ts = (m['createdAt'] is Timestamp)
                      ? (m['createdAt'] as Timestamp).millisecondsSinceEpoch
                      : 0;
                  final candidateOther = meIsA ? b : a;
                  if (candidateOther.toString().isEmpty) return;

                  if (ts > latestTs) {
                    latestTs = ts;
                    mutualOtherUid = candidateOther;
                  }
                }

                for (final d in listA) {
                  consider(d, meIsA: true);
                }
                for (final d in listB) {
                  consider(d, meIsA: false);
                }
              }

              // If a chat with this user already exists, hide the promo ONLY if there is at least one message
              if (mutualOtherUid != null && mutualOtherUid!.isNotEmpty) {
                QueryDocumentSnapshot<Map<String, dynamic>>? existing;
                for (final c in chats) {
                  final data = c.data();
                  final partsAny = (data['participants'] as List?) ?? const [];
                  final parts = partsAny.map((e) => e.toString()).toList();
                  if (parts.contains(uid) && parts.contains(mutualOtherUid)) {
                    existing = c;
                    break;
                  }
                }
                if (existing != null) {
                  final eData = existing.data();
                  final hasAnyMsg =
                      (eData['lastMessageAt'] is Timestamp) ||
                      (((eData['lastMessage'] ?? '') as String)
                          .trim()
                          .isNotEmpty);
                  if (hasAnyMsg) {
                    mutualOtherUid = null; // already chatting, drop promo
                  }
                }
              }

              // Build a list that optionally includes the mutual-like tile at the very top
              final extra =
                  (mutualOtherUid != null && mutualOtherUid!.isNotEmpty)
                  ? 1
                  : 0;
              if (chats.isEmpty && extra == 0) {
                return const _EmptyMessagesInteractive();
              }

              return ListView.separated(
                itemCount: chats.length + extra,
                cacheExtent: 800,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  // Top promo row for mutual like
                  if (extra == 1 && i == 0) {
                    final otherUid = mutualOtherUid!;
                    return FutureBuilder<
                      DocumentSnapshot<Map<String, dynamic>>
                    >(
                      future: fs.collection('users').doc(otherUid).get(),
                      builder: (context, uSnap) {
                        String title = 'Yeni eşleşme!';
                        String? photo;
                        if (uSnap.hasData && uSnap.data!.exists) {
                          final u = uSnap.data!.data()!;
                          final username = (u['username'] ?? '') as String;
                          final displayName =
                              (u['displayName'] ?? '') as String;
                          final lb = (u['letterboxdUsername'] ?? '') as String;
                          final fetchedPhoto = (u['photoURL'] ?? '') as String;
                          title = username.isNotEmpty
                              ? username
                              : (displayName.isNotEmpty
                                    ? displayName
                                    : (lb.isNotEmpty ? '@$lb' : title));
                          photo = fetchedPhoto.isNotEmpty ? fetchedPhoto : null;
                        }

                        return ListTile(
                          leading: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PublicProfileScreen(uid: otherUid),
                                ),
                              );
                            },
                            child: Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                CircleAvatar(
                                  backgroundImage:
                                      (photo != null && photo.isNotEmpty)
                                      ? NetworkImage(photo)
                                      : null,
                                  child: (photo == null || photo.isEmpty)
                                      ? const Icon(Icons.person)
                                      : null,
                                ),
                                const Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: CircleAvatar(
                                    radius: 8,
                                    backgroundColor: Colors.green,
                                    child: Icon(
                                      Icons.favorite,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          title: Text(title, overflow: TextOverflow.ellipsis),
                          subtitle: const Text(
                            'Bu kişiyle birbirinizi beğendiniz.',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          tileColor: Colors.greenAccent.withOpacity(0.10),
                          onTap: () async {
                            // Reuse existing chat if any; otherwise create it
                            final chatId = await ChatService.instance
                                .getOrCreateChat(uid, otherUid);

                            if (!context.mounted) return;
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
                          },
                        );
                      },
                    );
                  }

                  // Regular chat rows below
                  final idx = i - extra;
                  final d = chats[idx];
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
                  final lastAt = (data['lastMessageAt'] as Timestamp?)
                      ?.toDate();

                  final titles =
                      (data['titles'] as Map<String, dynamic>?) ?? const {};
                  String title = (titles[uid] as String?)?.trim() ?? '';
                  final photos =
                      (data['photos'] as Map<String, dynamic>?) ?? const {};
                  String? photoURL = (photos[otherUid] as String?)?.trim();

                  return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: fs.collection('users').doc(otherUid).get(),
                    builder: (context, uSnap) {
                      String effectiveTitle = title;
                      String? effectivePhoto = photoURL;

                      if (uSnap.hasData && uSnap.data!.exists) {
                        final u = uSnap.data!.data()!;
                        final username = (u['username'] ?? '') as String;
                        final displayName = (u['displayName'] ?? '') as String;
                        final lb = (u['letterboxdUsername'] ?? '') as String;
                        final fetchedPhoto = (u['photoURL'] ?? '') as String;

                        final computed = username.isNotEmpty
                            ? username
                            : (displayName.isNotEmpty
                                  ? displayName
                                  : (lb.isNotEmpty ? '@$lb' : otherUid));

                        if (effectiveTitle.isEmpty) effectiveTitle = computed;
                        if (effectivePhoto == null || effectivePhoto.isEmpty) {
                          effectivePhoto = fetchedPhoto.isNotEmpty
                              ? fetchedPhoto
                              : null;
                        }

                        final needWriteTitle =
                            (titles[uid] as String?)?.trim() != computed;
                        final needWritePhoto =
                            (photos[otherUid] as String?)?.trim() !=
                            (effectivePhoto ?? '');
                        if (needWriteTitle || needWritePhoto) {
                          unawaited(
                            fs.collection('chats').doc(d.id).set({
                              if (needWriteTitle) 'titles': {uid: computed},
                              if (needWritePhoto)
                                'photos': {otherUid: effectivePhoto ?? ''},
                            }, SetOptions(merge: true)),
                          );
                        }
                      }

                      // BEGIN: Mutual like highlight logic
                      return FutureBuilder<
                        List<QuerySnapshot<Map<String, dynamic>>>
                      >(
                        future: Future.wait([
                          fs
                              .collection('likes')
                              .where('a', isEqualTo: uid)
                              .where('b', isEqualTo: otherUid)
                              .limit(1)
                              .get(),
                          fs
                              .collection('likes')
                              .where('a', isEqualTo: otherUid)
                              .where('b', isEqualTo: uid)
                              .limit(1)
                              .get(),
                        ]),
                        builder: (context, likeSnap) {
                          bool mutual = false;
                          if (likeSnap.hasData) {
                            for (final qs in likeSnap.data!) {
                              if (qs.docs.isNotEmpty) {
                                final m = qs.docs.first.data();
                                final aLiked = m['aLiked'] == true;
                                final bLiked = m['bLiked'] == true;
                                if (aLiked && bLiked) {
                                  mutual = true;
                                  break;
                                }
                              }
                            }
                          }
                          // Once any message exists in this chat, remove mutual highlight
                          final hasAnyMessage = lastAt != null;
                          if (hasAnyMessage) {
                            mutual = false;
                          }

                          return ListTile(
                            tileColor: mutual
                                ? Colors.greenAccent.withOpacity(0.10)
                                : null,
                            leading: InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        PublicProfileScreen(uid: otherUid),
                                  ),
                                );
                              },
                              child: CircleAvatar(
                                backgroundImage:
                                    (effectivePhoto != null &&
                                        effectivePhoto.isNotEmpty)
                                    ? NetworkImage(effectivePhoto)
                                    : null,
                                child:
                                    (effectivePhoto == null ||
                                        effectivePhoto.isEmpty)
                                    ? const Icon(Icons.person)
                                    : null,
                              ),
                            ),
                            title: Text(
                              effectiveTitle.isNotEmpty ? effectiveTitle : '…',
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle:
                                StreamBuilder<
                                  QuerySnapshot<Map<String, dynamic>>
                                >(
                                  stream: fs
                                      .collection('chats')
                                      .doc(d.id)
                                      .collection('messages')
                                      .orderBy('createdAt', descending: true)
                                      .limit(1)
                                      .snapshots(),
                                  builder: (context, mSnap) {
                                    String preview = last;
                                    if (mSnap.hasData &&
                                        mSnap.data!.docs.isNotEmpty) {
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
                                StreamBuilder<
                                  QuerySnapshot<Map<String, dynamic>>
                                >(
                                  stream: FirebaseFirestore.instance
                                      .collection('chats')
                                      .doc(d.id)
                                      .collection('messages')
                                      .orderBy('createdAt', descending: true)
                                      .limit(1)
                                      .snapshots(),
                                  builder: (context, ms) {
                                    DateTime? lastDt;
                                    if (ms.hasData &&
                                        ms.data!.docs.isNotEmpty) {
                                      final doc = ms.data!.docs.first;
                                      final m = doc.data();
                                      final raw = m['createdAt'];
                                      if (raw is Timestamp) {
                                        lastDt = raw.toDate().toLocal();
                                      } else if (doc
                                          .metadata
                                          .hasPendingWrites) {
                                        lastDt = DateTime.now();
                                      }
                                    }

                                    DateTime? showAt =
                                        lastDt ??
                                        lastAt ??
                                        (data['updatedAt'] as Timestamp?)
                                            ?.toDate();
                                    final t = (showAt != null)
                                        ? _formatTime(showAt)
                                        : '';
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Text(
                                        t,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    );
                                  },
                                ),
                                StreamBuilder<int>(
                                  stream: ChatService.instance
                                      .unreadCountForChat(d.id, uid),
                                  builder: (context, cSnap) {
                                    final count = cSnap.data ?? 0;
                                    if (count <= 0)
                                      return const SizedBox.shrink();
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
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
                              final chatId = d.id;
                              if (context.mounted) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatRoomScreen(
                                      chatId: chatId,
                                      otherUid: otherUid,
                                      otherTitle: (title.isNotEmpty
                                          ? title
                                          : null),
                                    ),
                                  ),
                                );
                              }
                              unawaited(
                                fs.collection('chats').doc(chatId).set({
                                  'participants': parts,
                                  'updatedAt': FieldValue.serverTimestamp(),
                                  'visibleFor': {uid: true},
                                }, SetOptions(merge: true)),
                              );
                              unawaited(
                                ChatService.instance.markAsRead(chatId, uid),
                              );
                            },
                            onLongPress: () async {
                              final chatId = d.id;
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text(
                                    'Bu sohbeti gizlemek istiyor musunuz?',
                                  ),
                                  content: const Text(
                                    'Yalnızca sende gizlenecek; karşı taraf etkilenmez.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(false),
                                      child: const Text('İptal'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(true),
                                      child: const Text('Gizle'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await fs.collection('chats').doc(chatId).set({
                                  'visibleFor': {uid: false},
                                }, SetOptions(merge: true));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Sohbet gizlendi.'),
                                    ),
                                  );
                                }
                              }
                            },
                          );
                        },
                      );
                      // END: Mutual like highlight logic
                    },
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: _TrashFab(currentUid: uid),
    );
  }
}

class _TrashFab extends StatelessWidget {
  final String currentUid;
  const _TrashFab({required this.currentUid});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      tooltip: 'Silinen/Gizlenen mesajlar',
      onPressed: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _HiddenMessagesSheet(currentUid: currentUid),
        );
      },
      child: const Icon(Icons.delete_outline),
    );
  }
}

class _HiddenMessagesSheet extends StatefulWidget {
  final String currentUid;
  const _HiddenMessagesSheet({required this.currentUid});

  @override
  State<_HiddenMessagesSheet> createState() => _HiddenMessagesSheetState();
}

class _HiddenMessagesSheetState extends State<_HiddenMessagesSheet> {
  final _fs = FirebaseFirestore.instance;
  late Future<List<_TrashItem>> _loaderMsgs;
  late Future<List<_HiddenChatItem>> _loaderChats;

  @override
  void initState() {
    super.initState();
    _loaderMsgs = _loadHiddenMessages();
    _loaderChats = _loadHiddenChats();
  }

  Future<List<_TrashItem>> _loadHiddenMessages() async {
    final uid = widget.currentUid;

    // 1) Fetch chats where I am a participant
    final chatsQs = await _fs
        .collection('chats')
        .where('participants', arrayContains: uid)
        .get();

    final items = <_TrashItem>[];

    // 2) For each chat, fetch messages marked hidden/deleted for me using separate queries
    for (final chatDoc in chatsQs.docs) {
      final chatId = chatDoc.id;
      final msgs = _fs.collection('chats').doc(chatId).collection('messages');

      final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[
        msgs.where('deletedFor.$uid', isEqualTo: true).limit(200).get(),
        msgs.where('hiddenFor.$uid', isEqualTo: true).limit(200).get(),
        msgs.where('softDeletedFor.$uid', isEqualTo: true).limit(200).get(),
        msgs.where('archivedFor.$uid', isEqualTo: true).limit(200).get(),
        msgs.where('deleted', isEqualTo: true).limit(200).get(),
        msgs.where('isDeleted', isEqualTo: true).limit(200).get(),
        msgs.where('deletedBy', arrayContains: uid).limit(200).get(),
        msgs.where('hiddenBy', arrayContains: uid).limit(200).get(),
      ];

      final results = await Future.wait(futures);

      // 3) Merge unique docs by full path
      final seen = <String>{};
      for (final qs in results) {
        for (final d in qs.docs) {
          final key = d.reference.path;
          if (seen.add(key)) {
            final m = d.data();
            final text = (m['text'] ?? m['message'] ?? m['content'] ?? '')
                .toString();
            final ts = (m['deletedAt'] is Timestamp)
                ? (m['deletedAt'] as Timestamp).toDate()
                : ((m['createdAt'] is Timestamp)
                      ? (m['createdAt'] as Timestamp).toDate()
                      : DateTime.fromMillisecondsSinceEpoch(0));
            items.add(
              _TrashItem(
                chatId: chatId,
                messageRef: d.reference,
                text: text.isEmpty ? '(medya / içerik)' : text,
                when: ts,
              ),
            );
          }
        }
      }
    }

    // 4) Sort newest first
    items.sort((a, b) => b.when.compareTo(a.when));
    return items;
  }

  Future<void> _restore(_TrashItem it) async {
    try {
      await it.messageRef.update({
        'deletedFor.${widget.currentUid}': FieldValue.delete(),
        'hiddenFor.${widget.currentUid}': FieldValue.delete(),
        'softDeletedFor.${widget.currentUid}': FieldValue.delete(),
        'archivedFor.${widget.currentUid}': FieldValue.delete(),
        'deleted': false,
        'isDeleted': false,
        'deletedBy': FieldValue.arrayRemove([widget.currentUid]),
        'hiddenBy': FieldValue.arrayRemove([widget.currentUid]),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Mesaj geri alındı.')));
      setState(() {
        _loaderMsgs = _loadHiddenMessages();
        _loaderChats = _loadHiddenChats();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Geri alma başarısız: $e')));
    }
  }

  Future<List<_HiddenChatItem>> _loadHiddenChats() async {
    final uid = widget.currentUid;
    final qs = await _fs
        .collection('chats')
        .where('participants', arrayContains: uid)
        .where('visibleFor.$uid', isEqualTo: false)
        .get();

    final items = <_HiddenChatItem>[];
    for (final d in qs.docs) {
      final data = d.data();
      final partsAny = (data['participants'] as List?) ?? const [];
      final parts = partsAny.map((e) => e.toString()).toList();
      final otherUid = parts.firstWhere((e) => e != uid, orElse: () => '');
      final last = (data['lastMessage'] ?? '') as String;
      final lastAt = (data['lastMessageAt'] is Timestamp)
          ? (data['lastMessageAt'] as Timestamp).toDate()
          : ((data['updatedAt'] is Timestamp)
                ? (data['updatedAt'] as Timestamp).toDate()
                : DateTime.fromMillisecondsSinceEpoch(0));

      // Prefer cached display if present
      final titles = (data['titles'] as Map<String, dynamic>?) ?? const {};
      final photos = (data['photos'] as Map<String, dynamic>?) ?? const {};
      String title = (titles[uid] as String?)?.trim() ?? '';
      String? photo = (photos[otherUid] as String?)?.trim();

      items.add(
        _HiddenChatItem(
          chatId: d.id,
          otherUid: otherUid,
          title: title.isNotEmpty ? title : otherUid,
          photoURL: (photo != null && photo.isNotEmpty) ? photo : null,
          lastMessage: last,
          lastAt: lastAt,
        ),
      );
    }

    // Sort newest first
    items.sort((a, b) => b.lastAt.compareTo(a.lastAt));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text(
                    'Silinen / Gizlenen Mesajlar',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Yenile',
                    onPressed: () => setState(() {
                      _loaderMsgs = _loadHiddenMessages();
                      _loaderChats = _loadHiddenChats();
                    }),
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<Object>>(
                future: Future.wait([_loaderChats, _loaderMsgs]),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final chats = (snap.data != null && snap.data!.isNotEmpty)
                      ? (snap.data![0] as List<_HiddenChatItem>)
                      : const <_HiddenChatItem>[];
                  final items = (snap.data != null && snap.data!.length > 1)
                      ? (snap.data![1] as List<_TrashItem>)
                      : const <_TrashItem>[];

                  if (chats.isEmpty && items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Çöpte bir içerik yok.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    );
                  }

                  return ListView(
                    controller: controller,
                    children: [
                      if (chats.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Text(
                            'Gizlenen Sohbetler',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        const Divider(height: 1),
                        ...chats.map(
                          (c) => ListTile(
                            leading: CircleAvatar(
                              backgroundImage: (c.photoURL != null)
                                  ? NetworkImage(c.photoURL!)
                                  : null,
                              child: (c.photoURL == null)
                                  ? const Icon(Icons.person)
                                  : null,
                            ),
                            title: Text(
                              c.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              (c.lastMessage.isNotEmpty)
                                  ? c.lastMessage
                                  : _formatTime(c.lastAt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: TextButton.icon(
                              onPressed: () async {
                                try {
                                  await _fs
                                      .collection('chats')
                                      .doc(c.chatId)
                                      .set({
                                        'visibleFor': {widget.currentUid: true},
                                      }, SetOptions(merge: true));
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Sohbet geri alındı.'),
                                    ),
                                  );
                                  setState(() {
                                    _loaderChats = _loadHiddenChats();
                                  });
                                } catch (e) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Sohbet geri alma başarısız: $e',
                                      ),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.restore),
                              label: const Text('Geri al'),
                            ),
                            onTap: () async {
                              // Open chat (it will remain hidden until user restores; offering quick restore then navigate)
                              try {
                                final snap = await _fs
                                    .collection('chats')
                                    .doc(c.chatId)
                                    .get();
                                String? other;
                                if (snap.exists) {
                                  final data = snap.data() ?? {};
                                  final partsAny =
                                      (data['participants'] as List?) ??
                                      const [];
                                  final parts = partsAny
                                      .map((e) => e.toString())
                                      .toList();
                                  other = parts.firstWhere(
                                    (e) => e != widget.currentUid,
                                    orElse: () => '',
                                  );
                                  if (other.isEmpty) other = null;
                                }
                                if (other == null) return;
                                if (!mounted) return;
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ChatRoomScreen(
                                      chatId: c.chatId,
                                      otherUid: other!,
                                    ),
                                  ),
                                );
                              } catch (_) {}
                            },
                          ),
                        ),
                        const Divider(height: 1),
                      ],

                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Text(
                          'Silinen / Gizlenen Mesajlar',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      const Divider(height: 1),
                      if (items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Mesaj bulunamadı.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        )
                      else
                        ...items.map(
                          (it) => ListTile(
                            leading: const Icon(Icons.delete_outline),
                            title: Text(
                              it.text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              _formatTime(it.when),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            trailing: TextButton.icon(
                              onPressed: () => _restore(it),
                              icon: const Icon(Icons.restore),
                              label: const Text('Geri al'),
                            ),
                            onTap: () async {
                              String? other;
                              try {
                                final snap = await _fs
                                    .collection('chats')
                                    .doc(it.chatId)
                                    .get();
                                if (snap.exists) {
                                  final data = snap.data() ?? {};
                                  final partsAny =
                                      (data['participants'] as List?) ??
                                      const [];
                                  final parts = partsAny
                                      .map((e) => e.toString())
                                      .toList();
                                  other = parts.firstWhere(
                                    (e) => e != widget.currentUid,
                                    orElse: () => '',
                                  );
                                  if (other.isEmpty) other = null;
                                }
                              } catch (_) {}
                              if (other == null) return;
                              if (!mounted) return;
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ChatRoomScreen(
                                    chatId: it.chatId,
                                    otherUid: other!,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TrashItem {
  final String chatId;
  final DocumentReference<Map<String, dynamic>> messageRef;
  final String text;
  final DateTime when;
  _TrashItem({
    required this.chatId,
    required this.messageRef,
    required this.text,
    required this.when,
  });
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

class _HiddenChatItem {
  final String chatId;
  final String otherUid;
  final String title;
  final String? photoURL;
  final String lastMessage;
  final DateTime lastAt;
  _HiddenChatItem({
    required this.chatId,
    required this.otherUid,
    required this.title,
    required this.photoURL,
    required this.lastMessage,
    required this.lastAt,
  });
}
