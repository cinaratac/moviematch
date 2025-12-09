import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/chat_room_screen.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:fluttergirdi/services/chat_service.dart';
import 'dart:async';
import 'package:fluttergirdi/screens/clubs_tab.dart'; 
import 'package:fluttergirdi/services/club_service.dart';
import 'package:fluttergirdi/widgets/club_card.dart';
import 'package:fluttergirdi/screens/create_club_screen.dart'; 

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  
  // İki sekme için ayrı arama metinleri
  String _chatSearchText = '';
  String _clubSearchText = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabSelection);
  }

  void _handleTabSelection() {
    if (!mounted) return;

    // Sekme değiştiğinde arama çubuğundaki metni güncelle
    if (_tabController.indexIsChanging || 
        _tabController.animation!.value == _tabController.index.toDouble()) {
      _updateSearchControllerText();
    }
  }

  void _updateSearchControllerText() {
    if (!mounted) return;

    final targetText = _tabController.index == 0 ? _chatSearchText : _clubSearchText;
    
    // Sadece metin farklıysa güncelle
    if (_searchController.text != targetText) {
      setState(() {
        _searchController.text = targetText;
        _searchController.selection = TextSelection.fromPosition(
          TextPosition(offset: targetText.length),
        );
      });
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    if (!mounted) return;

    final rawInput = val.toLowerCase();
    
    if (_tabController.index == 0) {
      if (_chatSearchText != rawInput) {
        setState(() => _chatSearchText = rawInput);
      }
    } else {
      if (_clubSearchText != rawInput) {
        setState(() => _clubSearchText = rawInput);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        toolbarHeight: 65, 
        titleSpacing: 16, 
        
        title: Container(
          height: 40,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            indicator: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            labelColor: cs.onSurface,
            unselectedLabelColor: cs.onSurfaceVariant,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            overlayColor: WidgetStateProperty.all(Colors.transparent),
            tabs: const [
              Tab(text: 'Sohbetler'),
              Tab(text: 'Kulüplerim'),
            ],
          ),
        ),

        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  hintText: _tabController.index == 0 ? 'Sohbetlerde ara...' : 'Kulüplerde ara...',
                  hintStyle: TextStyle(color: cs.onSurfaceVariant.withOpacity(0.7), fontSize: 14),
                  prefixIcon: Icon(Icons.search, size: 20, color: cs.onSurfaceVariant),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  suffixIcon: _searchController.text.isNotEmpty 
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      ) 
                    : null,
                ),
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ChatsView(uid: uid, filterText: _chatSearchText.trim()),
          JoinedClubsList(filterText: _clubSearchText.trim()),
        ],
      ),
    );
  }
}

// --- SOHBETLER SEKMESİ ---
class _ChatsView extends StatefulWidget {
  final String uid;
  final String filterText;
  
  const _ChatsView({required this.uid, required this.filterText});

  @override
  State<_ChatsView> createState() => _ChatsViewState();
}

class _ChatsViewState extends State<_ChatsView> with AutomaticKeepAliveClientMixin {
  final Map<String, Map<String, dynamic>> _userCache = {};
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _chatsStream;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Sohbetler için stream'i burada oluşturuyoruz
    _chatsStream = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: widget.uid)
        .snapshots(includeMetadataChanges: true);
  }

  Future<void> _fetchMissingUsers(List<String> uids) async {
    final missing = uids.where((id) => !_userCache.containsKey(id)).toSet().toList();
    if (missing.isEmpty) return;

    for (var i = 0; i < missing.length; i += 10) {
      final chunk = missing.sublist(i, i + 10 > missing.length ? missing.length : i + 10);
      try {
        final qs = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        
        for (var doc in qs.docs) {
          _userCache[doc.id] = doc.data();
        }
      } catch (e) {
        debugPrint('Kullanıcı verisi çekilemedi: $e');
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return Scaffold(
      floatingActionButton: _TrashFab(currentUid: widget.uid),
      body: Column(
        children: [
          if (widget.filterText.isEmpty) 
            NewMatchHeader(currentUid: widget.uid),

          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _chatsStream,
              builder: (context, s) {
                if (s.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                var docs = s.data?.docs.toList() ?? [];
                
                docs.removeWhere((doc) {
                   final data = doc.data();
                   final isGroup = data['isGroup'] == true;
                   final vis = (data['visibleFor'] as Map?) ?? {};
                   final isHidden = vis[widget.uid] == false;
                   return isGroup || isHidden;
                });

                final otherUids = <String>{};
                for (var doc in docs) {
                  final parts = List.from(doc.data()['participants'] ?? []);
                  final other = parts.firstWhere((id) => id != widget.uid, orElse: () => null);
                  if (other != null) otherUids.add(other.toString());
                }

                if (otherUids.isNotEmpty) {
                  Future.microtask(() => _fetchMissingUsers(otherUids.toList()));
                }

                if (widget.filterText.isNotEmpty) {
                  docs = docs.where((doc) {
                    final data = doc.data();
                    final parts = List.from(data['participants'] ?? []);
                    final otherId = parts.firstWhere((id) => id != widget.uid, orElse: () => null);
                    
                    if (otherId == null) return false;

                    final cachedUser = _userCache[otherId];
                    if (cachedUser != null) {
                      final name = (cachedUser['displayName'] ?? '').toString().toLowerCase();
                      final username = (cachedUser['username'] ?? '').toString().toLowerCase();
                      return name.contains(widget.filterText) || username.contains(widget.filterText);
                    }
                    
                    final titles = (data['titles'] as Map?) ?? {};
                    final savedName = (titles[widget.uid] as String?)?.toLowerCase() ?? '';
                    return savedName.contains(widget.filterText);
                  }).toList();
                }

                docs.sort((a, b) {
                    final tA = (a.data()['updatedAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
                    final tB = (b.data()['updatedAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
                    return tB.compareTo(tA);
                });
                
                if (docs.isEmpty) {
                  return widget.filterText.isNotEmpty 
                    ? const Center(child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Text('Eşleşen sohbet bulunamadı.', style: TextStyle(color: Colors.black)),
                      )) 
                    : const _EmptyMessagesInteractive();
                }

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final parts = List.from(doc.data()['participants'] ?? []);
                    final otherId = parts.firstWhere((id) => id != widget.uid, orElse: () => null);
                    final cachedData = (otherId != null) ? _userCache[otherId] : null;

                    return ChatListTile(
                      key: ValueKey(doc.id),
                      chatDoc: doc,
                      currentUid: widget.uid,
                      cachedUserData: cachedData,
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

// --- YARDIMCI SINIFLAR ---
// (NewMatchHeader, ChatListTile, _UnreadCountBadge, _TrashFab, _HiddenMessagesSheet, _TrashItem, _formatTime, _ForestFace, _EmptyMessagesInteractive, _HiddenChatItem kodları aynı kalıyor, buraya tekrar eklenmiştir.)

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

    final chatCheck = await fs.collection('chats').where('participants', arrayContains: uid).get();
    for (var doc in chatCheck.docs) {
      final parts = List.from(doc.data()['participants'] ?? []);
      if (parts.contains(targetUid)) return null; 
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
                  backgroundImage: (photo != null && photo.isNotEmpty) ? NetworkImage(photo) : null,
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
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
            subtitle: const Text('Bu kişiyle birbirinizi beğendiniz!'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.green),
            onTap: () async {
               final chatId = await ChatService.instance.getOrCreateChat(widget.currentUid, otherUid);
               if (!context.mounted) return;
               Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatRoomScreen(chatId: chatId, otherUid: otherUid, otherTitle: name),
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
    Map<String, dynamic>? cachedUserData, 
  });
  
  Widget _buildTile(BuildContext context, String otherUid, String displayName, String? photoUrl, String lastMsg, DateTime? lastMsgTime) {
    return ListTile(
        onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => ChatRoomScreen(chatId: chatDoc.id, otherUid: otherUid, otherTitle: displayName)));
            ChatService.instance.markAsRead(chatDoc.id, currentUid);
        },
        onLongPress: () => _showHideDialog(context, chatDoc.id),
        leading: InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: otherUid))),
            child: CircleAvatar(
                backgroundImage: (photoUrl != null && photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                child: (photoUrl == null || photoUrl.isEmpty) ? const Icon(Icons.person) : null,
            ),
        ),
        title: Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
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
                        child: Text(_formatTime(lastMsgTime), style: Theme.of(context).textTheme.bodySmall),
                    ),
            ],
        ),
        trailing: _UnreadCountBadge(chatId: chatDoc.id, uid: currentUid),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = chatDoc.data();
    final parts = (data['participants'] as List<dynamic>?) ?? [];
    final otherUid = parts.firstWhere((id) => id != currentUid, orElse: () => null);

    if (otherUid == null) return const SizedBox.shrink();

    final lastMsg = (data['lastMessage'] ?? '').toString();
    final lastMsgTime = (data['lastMessageAt'] as Timestamp?)?.toDate();
    final titles = (data['titles'] as Map?) ?? {};
    final photos = (data['photos'] as Map?) ?? {};
    
    String displayName = (titles[currentUid] as String?) ?? ''; 
    String? photoUrl = (photos[currentUid] as String?); 
    
    if (displayName.isNotEmpty || (photoUrl != null && photoUrl.isNotEmpty)) {
        return _buildTile(context, otherUid, displayName.isNotEmpty ? displayName : 'Kullanıcı', photoUrl, lastMsg, lastMsgTime);
    }
    
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance.collection('users').doc(otherUid).get(),
        builder: (context, userSnap) {
            String fetchedDisplayName = 'Kullanıcı';
            String? fetchedPhotoUrl;
            
            if (userSnap.hasData && userSnap.data!.exists) {
                final userData = userSnap.data!.data()!;
                final username = userData['username'] as String?;
                final name = userData['displayName'] as String?;
                fetchedPhotoUrl = userData['photoURL'] as String?;
                if (username != null && username.isNotEmpty) fetchedDisplayName = username;
                else if (name != null && name.isNotEmpty) fetchedDisplayName = name;
            } else if (userSnap.connectionState == ConnectionState.waiting) {
                 return const Center(child: Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))));
            }
            return _buildTile(context, otherUid, fetchedDisplayName, fetchedPhotoUrl, lastMsg, lastMsgTime);
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
          child: Text(count.toString(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
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
    final chatsQs = await _fs.collection('chats').where('participants', arrayContains: uid).get();
    final items = <_TrashItem>[];

    for (final chatDoc in chatsQs.docs) {
      final chatId = chatDoc.id;
      final msgs = _fs.collection('chats').doc(chatId).collection('messages');
      final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[
        msgs.where('deletedFor.$uid', isEqualTo: true).limit(200).get(),
        msgs.where('hiddenFor.$uid', isEqualTo: true).limit(200).get(),
        msgs.where('deleted', isEqualTo: true).limit(200).get(),
      ];
      final results = await Future.wait(futures);
      final seen = <String>{};
      for (final qs in results) {
        for (final d in qs.docs) {
          if (seen.add(d.reference.path)) {
            final m = d.data();
            final text = (m['text'] ?? '').toString();
            final ts = (m['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
            items.add(_TrashItem(chatId: chatId, messageRef: d.reference, text: text, when: ts));
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
        'deleted': false,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mesaj geri alındı.')));
      setState(() {
        _loaderMsgs = _loadHiddenMessages();
        _loaderChats = _loadHiddenChats();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
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
      final parts = List.from(data['participants'] ?? []);
      final otherUid = parts.firstWhere((e) => e != uid, orElse: () => '');
      final last = (data['lastMessage'] ?? '') as String;
      final lastAt = (data['lastMessageAt'] as Timestamp?)?.toDate() ?? DateTime(2000);
      final titles = (data['titles'] as Map?) ?? {};
      final photos = (data['photos'] as Map?) ?? {};
      String title = (titles[uid] as String?) ?? '';
      String? photo = (photos[otherUid] as String?);
      items.add(_HiddenChatItem(chatId: d.id, otherUid: otherUid, title: title.isNotEmpty ? title : otherUid, photoURL: photo, lastMessage: last, lastAt: lastAt));
    }
    items.sort((a, b) => b.lastAt.compareTo(a.lastAt));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text('Geri Dönüşüm Kutusu', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => setState(() {
                      _loaderMsgs = _loadHiddenMessages();
                      _loaderChats = _loadHiddenChats();
                    }),
                  )
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Object>>(
                future: Future.wait([_loaderChats, _loaderMsgs]),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final chats = (snap.data?[0] as List<_HiddenChatItem>?) ?? [];
                  final items = (snap.data?[1] as List<_TrashItem>?) ?? [];
                  if (chats.isEmpty && items.isEmpty) return const Center(child: Text("Çöp kutusu boş."));

                  return ListView(
                    controller: controller,
                    children: [
                      if (chats.isNotEmpty) ...[
                        const Padding(padding: EdgeInsets.all(8.0), child: Text("Gizlenen Sohbetler", style: TextStyle(fontWeight: FontWeight.bold))),
                        ...chats.map((c) => ListTile(
                          title: Text(c.title),
                          subtitle: Text(c.lastMessage),
                          trailing: IconButton(
                            icon: const Icon(Icons.restore),
                            onPressed: () async {
                              await _fs.collection('chats').doc(c.chatId).set({'visibleFor': {widget.currentUid: true}}, SetOptions(merge: true));
                              if (mounted) setState(() => _loaderChats = _loadHiddenChats());
                            },
                          ),
                        ))
                      ],
                      if (items.isNotEmpty) ...[
                        const Padding(padding: EdgeInsets.all(8.0), child: Text("Silinen Mesajlar", style: TextStyle(fontWeight: FontWeight.bold))),
                        ...items.map((it) => ListTile(
                          title: Text(it.text),
                          subtitle: Text(_formatTime(it.when)),
                          trailing: IconButton(
                            icon: const Icon(Icons.restore),
                            onPressed: () => _restore(it),
                          ),
                        ))
                      ]
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
  _TrashItem({required this.chatId, required this.messageRef, required this.text, required this.when});
}

String _formatTime(DateTime dt) {
  final local = dt.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final thatDay = DateTime(local.year, local.month, local.day);
  if (thatDay == today) return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
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
    return Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: color));
  }

  static Widget _eye(double offsetX, double offsetY) {
    return Container(
      width: 28, height: 28,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment(offsetX / 10, offsetY / 10),
        child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle)),
      ),
    );
  }
}

class _EmptyMessagesInteractive extends StatefulWidget {
  const _EmptyMessagesInteractive();
  @override
  State<_EmptyMessagesInteractive> createState() => _EmptyMessagesInteractiveState();
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

  void _resetUp() => setState(() { _offsetX = 0; _offsetY = -10; });

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
                const Text('Yalnızsın galiba', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color.fromARGB(255, 124, 131, 116))),
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
  _HiddenChatItem({required this.chatId, required this.otherUid, required this.title, required this.photoURL, required this.lastMessage, required this.lastAt});
}

// --- KATILINAN KULÜPLER LİSTESİ WIDGET'I (DÜZELTME: Stream InitState'e taşındı) ---
class JoinedClubsList extends StatefulWidget {
  final String filterText; // Arama filtresi
  
  const JoinedClubsList({super.key, this.filterText = ''});

  @override
  State<JoinedClubsList> createState() => _JoinedClubsListState();
}

class _JoinedClubsListState extends State<JoinedClubsList> with AutomaticKeepAliveClientMixin {
  late Stream<QuerySnapshot> _clubsStream; // Stream'i saklayacağız

  @override
  bool get wantKeepAlive => true; // Sayfanın ölmesini engeller

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      // Stream'i burada bir kere oluşturuyoruz.
      // Böylece filterText değiştiğinde StreamBuilder sıfırlanmıyor.
      _clubsStream = ClubService.instance.getUserClubsStream(uid);
    } else {
      _clubsStream = const Stream.empty();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Mixin için gerekli
    
    // uid kontrolü (Stream boşsa zaten data gelmeyecek ama yine de)
    if (FirebaseAuth.instance.currentUser?.uid == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: _clubsStream, // Sabit stream kullanımı
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        var docs = snapshot.data?.docs ?? [];
        
        // Filtreleme işlemi
        if (widget.filterText.isNotEmpty) {
          docs = docs.where((d) {
             final data = d.data() as Map<String, dynamic>;
             final name = (data['name'] ?? '').toString().toLowerCase();
             return name.contains(widget.filterText);
          }).toList();
        }

        if (docs.isEmpty) {
          // Filtreli aramada sonuç yoksa
          if (widget.filterText.isNotEmpty) {
             return const Center(child: Text("Eşleşen kulüp bulunamadı.", style: TextStyle(color: Colors.grey)));
          }
          
          // Hiç kulüp yoksa
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.diversity_3_outlined, size: 64, color: Colors.grey.withOpacity(0.3)),
                const SizedBox(height: 16),
                const Text("Henüz bir kulübe üye değilsin.", style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 24),
                FilledButton.tonal(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateClubScreen()));
                  },
                  child: const Text("Yeni Bir Kulüp Kur"),
                )
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            return ClubCard(doc: docs[index], isJoinedView: true);
          },
        );
      },
    );
  }
}