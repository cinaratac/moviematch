import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/chat_room_screen.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:fluttergirdi/services/chat_service.dart';
import 'dart:async';
import 'package:fluttergirdi/screens/clubs_tab.dart'; // Kulüpler sekmesi için import

class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return DefaultTabController(
      length: 2, // İki sekme: Sohbetler ve Kulüpler
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 40,
          title: const Text('Mesajlar'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Sohbetler'),
              Tab(text: 'Kulüpler'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // 1. Sekme: Sohbetler (Eski kodunun refactor edilmiş hali)
            _ChatsView(uid: uid),
            
            // 2. Sekme: Kulüpler (Yeni özellik)
            const ClubsTab(),
          ],
        ),
      ),
    );
  }
}

// --- ESKİ MESAJ EKRANI İÇERİĞİ (SOHBETLER SEKMESİ) ---
class _ChatsView extends StatelessWidget {
  final String uid;
  const _ChatsView({required this.uid});

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;
    return Scaffold(
      // FAB sadece Sohbetler sekmesinde görünsün diye buraya koyduk
      floatingActionButton: _TrashFab(currentUid: uid),
      body: Column(
        children: [
          // Eşleşme Başlığı
          NewMatchHeader(currentUid: uid),

          // Sohbet Listesi
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: fs
                  .collection('chats')
                  .where('participants', arrayContains: uid)
                  .snapshots(includeMetadataChanges: true),
              builder: (context, s) {
                if (s.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                final docs = s.data?.docs.toList() ?? [];
                
                // Sıralama (En yeniden eskiye)
                docs.sort((a, b) {
                    final tA = (a.data()['updatedAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
                    final tB = (b.data()['updatedAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
                    return tB.compareTo(tA);
                });
                
                // Gizli sohbetleri filtreleme
                docs.removeWhere((doc) {
                    final vis = (doc.data()['visibleFor'] as Map?) ?? {};
                    return vis[uid] == false;
                });

                if (docs.isEmpty) return const _EmptyMessagesInteractive();

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  cacheExtent: 1000,
                  itemBuilder: (context, index) {
                    return ChatListTile(
                      key: ValueKey(docs[index].id),
                      chatDoc: docs[index],
                      currentUid: uid,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- AŞAĞIDAKİ SINIFLAR AYNEN KORUNDU ---

class NewMatchHeader extends StatefulWidget {
  final String currentUid;
  const NewMatchHeader({super.key, required this.currentUid});

  @override
  State<NewMatchHeader> createState() => _NewMatchHeaderState();
}

class _NewMatchHeaderState extends State<NewMatchHeader> {
  Future<Map<String, dynamic>?>? _matchFuture;

  @override
  void initState() {
    super.initState();
    _matchFuture = _findLatestMutualLike();
  }

  Future<Map<String, dynamic>?> _findLatestMutualLike() async {
    final fs = FirebaseFirestore.instance;
    final uid = widget.currentUid;

    final results = await Future.wait([
      fs.collection('likes').where('a', isEqualTo: uid).limit(50).get(),
      fs.collection('likes').where('b', isEqualTo: uid).limit(50).get(),
    ]);

    String? targetUid;
    DateTime? latestTime;

    void checkDoc(Map<String, dynamic> data) {
      final aLiked = data['aLiked'] == true;
      final bLiked = data['bLiked'] == true;
      
      if (!aLiked || !bLiked) return; 

      final a = (data['a'] ?? '').toString();
      final b = (data['b'] ?? '').toString();
      final other = (a == uid) ? b : a;

      final meIsA = (a == uid);
      final seen = meIsA ? (data['aSeen'] == true) : (data['bSeen'] == true);
      
      if (!seen) {
         final ts = (data['createdAt'] as Timestamp?)?.toDate();
         if (latestTime == null || (ts != null && ts.isAfter(latestTime!))) {
           latestTime = ts;
           targetUid = other;
         }
      }
    }

    for (var qs in results) {
      for (var doc in qs.docs) {
        checkDoc(doc.data());
      }
    }

    if (targetUid == null) return null;

    final chatCheck = await fs
        .collection('chats')
        .where('participants', arrayContains: uid)
        .get();

    for (var doc in chatCheck.docs) {
      final parts = List.from(doc.data()['participants'] ?? []);
      if (parts.contains(targetUid)) {
        return null; 
      }
    }

    final userDoc = await fs.collection('users').doc(targetUid).get();
    if (!userDoc.exists) return null;
    
    final userData = userDoc.data()!;
    return {
      'uid': targetUid,
      'username': userData['username'],
      'displayName': userData['displayName'],
      'photoURL': userData['photoURL'],
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _matchFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const SizedBox.shrink(); 
        }

        final data = snapshot.data!;
        final otherUid = data['uid'];
        final name = (data['displayName'] ?? data['username'] ?? 'Yeni Eşleşme').toString();
        final photo = data['photoURL'] as String?;

        return Container(
          decoration: BoxDecoration(
             color: Colors.greenAccent.withOpacity(0.10),
             border: Border(bottom: BorderSide(color: Colors.greenAccent.withOpacity(0.3))),
          ),
          child: ListTile(
            leading: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  backgroundImage: (photo != null && photo.isNotEmpty) 
                      ? NetworkImage(photo) 
                      : null,
                  child: (photo == null || photo.isEmpty) ? const Icon(Icons.person) : null,
                ),
                const CircleAvatar(
                  radius: 8,
                  backgroundColor: Colors.white,
                  child: CircleAvatar(
                    radius: 6,
                    backgroundColor: Colors.green,
                    child: Icon(Icons.favorite, size: 8, color: Colors.white),
                  ),
                ),
              ],
            ),
            title: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
            ),
            subtitle: const Text('Bu kişiyle birbirinizi beğendiniz!'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.green),
            onTap: () async {
               final chatId = await ChatService.instance
                 .getOrCreateChat(widget.currentUid, otherUid);
               
               if (!context.mounted) return;
               
               Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatRoomScreen(
                    chatId: chatId,
                    otherUid: otherUid,
                    otherTitle: name,
                  ),
                ),
              );
              
              setState(() {
                _matchFuture = _findLatestMutualLike();
              });
            },
          ),
        );
      },
    );
  }
}

class ChatListTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> chatDoc;
  final String currentUid;

  const ChatListTile({
    super.key,
    required this.chatDoc,
    required this.currentUid,
  });

  @override
  Widget build(BuildContext context) {
    final data = chatDoc.data();
    final parts = (data['participants'] as List<dynamic>?) ?? [];
    
    final otherUid = parts.firstWhere(
      (id) => id != currentUid,
      orElse: () => null,
    );

    if (otherUid == null) return const SizedBox.shrink();

    final lastMsg = (data['lastMessage'] ?? '').toString();
    final lastMsgTime = (data['lastMessageAt'] as Timestamp?)?.toDate();
    final titles = (data['titles'] as Map?) ?? {};
    final savedTitle = titles[currentUid] as String?;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(otherUid).snapshots(),
      builder: (context, userSnap) {
        
        String displayName = savedTitle ?? 'Kullanıcı';
        String? photoUrl;

        if (userSnap.hasData && userSnap.data!.exists) {
          final userData = userSnap.data!.data()!;
          final username = userData['username'] as String?;
          final name = userData['displayName'] as String?;
          photoUrl = userData['photoURL'] as String?;

          if (username != null && username.isNotEmpty) {
            displayName = username;
          } else if (name != null && name.isNotEmpty) {
            displayName = name;
          }
        }

        return ListTile(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatRoomScreen(
                  chatId: chatDoc.id,
                  otherUid: otherUid,
                  otherTitle: displayName,
                ),
              ),
            );
            
            ChatService.instance.markAsRead(chatDoc.id, currentUid);
          },
          onLongPress: () => _showHideDialog(context, chatDoc.id),
          leading: InkWell(
            onTap: () {
               Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PublicProfileScreen(uid: otherUid),
                ),
              );
            },
            child: CircleAvatar(
              backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                  ? NetworkImage(photoUrl)
                  : null,
              child: (photoUrl == null || photoUrl.isEmpty)
                  ? const Icon(Icons.person)
                  : null,
            ),
          ),
          title: Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Row(
            children: [
              Expanded(
                child: Text(
                  lastMsg.isNotEmpty ? lastMsg : 'Fotoğraf / Medya',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: lastMsg.isEmpty ? Colors.grey : null,
                    fontStyle: lastMsg.isEmpty ? FontStyle.italic : null,
                  ),
                ),
              ),
              if (lastMsgTime != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Text(
                    _formatTime(lastMsgTime),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
          trailing: _UnreadCountBadge(chatId: chatDoc.id, uid: currentUid),
        );
      },
    );
  }

  Future<void> _showHideDialog(BuildContext context, String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sohbeti gizle?'),
        content: const Text('Sohbet listenizden kaldırılacak (karşı taraf etkilenmez).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Gizle')),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('chats').doc(docId).set({
        'visibleFor': {currentUid: false},
      }, SetOptions(merge: true));
    }
  }
}

class _UnreadCountBadge extends StatelessWidget {
  final String chatId;
  final String uid;

  const _UnreadCountBadge({required this.chatId, required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: ChatService.instance.unreadCountForChat(chatId, uid),
      initialData: 0,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        if (count <= 0) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            count.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
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

    final chatsQs = await _fs
        .collection('chats')
        .where('participants', arrayContains: uid)
        .get();

    final items = <_TrashItem>[];

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
    const base = Color(0xFF1B5E20); 
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
  double _offsetY = -10; 

  void _updateOffsets(Offset p, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    double nx = ((p.dx - cx) / (cx.abs())).clamp(-1.0, 1.0);
    double ny = ((p.dy - cy) / (cy.abs())).clamp(-1.0, 1.0);

    const max = 10.0;
    setState(() {
      _offsetX = nx * max;
      _offsetY = ny * max;
    });
  }

  void _resetUp() {
    setState(() {
      _offsetX = 0;
      _offsetY = -10; 
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