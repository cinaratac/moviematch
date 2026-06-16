import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/chat_room_screen.dart';
import 'package:fluttergirdi/screens/clubs_tab.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:fluttergirdi/services/chat_service.dart';
import 'dart:async';
import 'package:fluttergirdi/services/club_service.dart';
import 'package:fluttergirdi/widgets/club_card.dart';
import 'package:fluttergirdi/screens/create_club_screen.dart';
import 'package:fluttergirdi/widgets/messages_skeleton.dart';
import 'package:fluttergirdi/services/global_data_service.dart';
// --- YENİ EKLENEN: Merkezi Önbellek Servisi ---
import 'package:fluttergirdi/services/user_cache_service.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

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
    if (_tabController.indexIsChanging ||
        _tabController.animation!.value == _tabController.index.toDouble()) {
      _updateSearchControllerText();
    }
  }

  void _updateSearchControllerText() {
    if (!mounted) return;
    final targetText = _tabController.index == 0
        ? _chatSearchText
        : _clubSearchText;
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
      if (_chatSearchText != rawInput)
        setState(() => _chatSearchText = rawInput);
    } else {
      if (_clubSearchText != rawInput)
        setState(() => _clubSearchText = rawInput);
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
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
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
                  hintText: _tabController.index == 0
                      ? 'Sohbetlerde ara...'
                      : 'Kulüplerde ara...',
                  hintStyle: TextStyle(
                    color: cs.onSurfaceVariant.withOpacity(0.7),
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
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
          JoinedClubsList(uid: uid, filterText: _clubSearchText.trim()),
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

class _ChatsViewState extends State<_ChatsView>
    with AutomaticKeepAliveClientMixin {
  late Stream<QuerySnapshot<Map<String, dynamic>>> _chatsStream;
  final Set<String> _requestedUserUids = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  @override
  void didUpdateWidget(covariant _ChatsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _requestedUserUids.clear();
      _initStream();
    }
  }

  void _initStream() {
    _chatsStream = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: widget.uid)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      body: Column(
        children: [
          if (widget.filterText.isEmpty) NewMatchHeader(currentUid: widget.uid),

          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _chatsStream,
              builder: (context, s) {
                // --- KESİN ÇÖZÜM: GLOBAL CACHE VARSA SKELETON GÖSTERME ---
                final hasGlobalData = GlobalDataService.instance.myChats != null;
                
                if (s.connectionState == ConnectionState.waiting && !hasGlobalData) {
                  return const MessagesSkeleton();
                }

                // Veriyi canlı stream'den VEYA arka plan cache'inden al!
                var docs = s.hasData 
                    ? s.data!.docs.toList() 
                    : (GlobalDataService.instance.myChats ?? []);

                // (BURADAN AŞAĞISI SENİN MEVCUT KODLARIN, AYNEN DEVAM EDİYOR)
                docs.removeWhere((doc) {
                  final data = doc.data();
                  final parts = List.from(data['participants'] ?? []);

                  if (!parts.contains(widget.uid)) return true;
                  if (data['isGroup'] == true) return true;
                  final hiddenFor = data['hiddenFor'];
                  if (hiddenFor is Map && hiddenFor[widget.uid] == true) {
                    return true;
                  }

                  return false;
                });

                final otherUids = <String>{};
                for (var doc in docs) {
                  final parts = List.from(doc.data()['participants'] ?? []);
                  final other = parts.firstWhere(
                    (id) => id != widget.uid,
                    orElse: () => null,
                  );
                  if (other != null) otherUids.add(other.toString());
                }

                // --- MERKEZİ CACHE KULLANIMI ---
                final missingUids = otherUids
                    .where(
                      (id) =>
                          UserCacheService.instance.getFromCache(id) == null &&
                          !_requestedUserUids.contains(id),
                    )
                    .toList();
                if (missingUids.isNotEmpty) {
                  _requestedUserUids.addAll(missingUids);
                  Future.microtask(() async {
                    await UserCacheService.instance.fetchUsers(missingUids);
                    if (mounted)
                      setState(() {}); // Veriler geldiğinde ekranı yenile
                  });
                }
                // --------------------------------

                if (widget.filterText.isNotEmpty) {
                  docs = docs.where((doc) {
                    final data = doc.data();
                    final parts = List.from(data['participants'] ?? []);
                    final otherId = parts.firstWhere(
                      (id) => id != widget.uid,
                      orElse: () => null,
                    );

                    if (otherId == null) return false;

                    // Aramayı merkezi cache üzerinden yap
                    final cachedUser = UserCacheService.instance.getFromCache(
                      otherId,
                    );
                    if (cachedUser != null) {
                      final name = cachedUser.displayName.toLowerCase();
                      final username = cachedUser.handle.toLowerCase();
                      return name.contains(widget.filterText) ||
                          username.contains(widget.filterText);
                    }

                    final titles = (data['titles'] as Map?) ?? {};
                    final savedName =
                        (titles[widget.uid] as String?)?.toLowerCase() ?? '';
                    return savedName.contains(widget.filterText);
                  }).toList();
                }

                docs.sort((a, b) {
                  final tA =
                      (a.data()['updatedAt'] as Timestamp?)?.toDate() ??
                      DateTime(2000);
                  final tB =
                      (b.data()['updatedAt'] as Timestamp?)?.toDate() ??
                      DateTime(2000);
                  return tB.compareTo(tA);
                });

                if (docs.isEmpty) {
                  return widget.filterText.isNotEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20.0),
                            child: Text(
                              'Eşleşen sohbet bulunamadı.',
                              style: TextStyle(color: Colors.black),
                            ),
                          ),
                        )
                      : const _EmptyMessagesInteractive();
                }

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final parts = List.from(doc.data()['participants'] ?? []);
                    final otherId = parts.firstWhere(
                      (id) => id != widget.uid,
                      orElse: () => null,
                    );

                    final cachedUser = (otherId != null)
                        ? UserCacheService.instance.getFromCache(otherId)
                        : null;

                    return ChatListTile(
                      key: ValueKey(doc.id),
                      chatDoc: doc,
                      currentUid: widget.uid,
                      cachedUser:
                          cachedUser, // Artık özel Map yerine CachedUser objesi gidiyor
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

// --- YARDIMCI WIDGET'LAR ---
class ChatListTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> chatDoc;
  final String currentUid;
  final CachedUser? cachedUser;

  const ChatListTile({
    super.key,
    required this.chatDoc,
    required this.currentUid,
    this.cachedUser,
  });

  Widget _buildTile(
    BuildContext context,
    String otherUid,
    String displayName,
    String? photoUrl,
    String lastMsg,
    DateTime? lastMsgTime,
  ) {
    final data = chatDoc.data();
    final unreadMap = (data['unreadCounts'] as Map?) ?? {};
    final int count = (unreadMap[currentUid] as num?)?.toInt() ?? 0;

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
      onLongPress: () => _showDeleteDialog(context, chatDoc.id),
      leading: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: otherUid)),
        ),
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
      trailing: count > 0
          ? Container(
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
            )
          : null,
    );
  }

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
    final photos = (data['photos'] as Map?) ?? {};

    String? denormName = (titles[currentUid] as String?);
    String? denormPhoto = (photos[currentUid] as String?);

    String? cachedName;
    String? cachedPhoto;
    if (cachedUser != null) {
      cachedName = cachedUser!.displayName;
      cachedPhoto = cachedUser!.photoURL;
    }

    String finalName = (denormName != null && denormName.isNotEmpty)
        ? denormName
        : (cachedName ?? 'Kullanıcı');
    String? finalPhoto = (denormPhoto != null && denormPhoto.isNotEmpty)
        ? denormPhoto
        : cachedPhoto;

    return _buildTile(
      context,
      otherUid,
      finalName,
      finalPhoto,
      lastMsg,
      lastMsgTime,
    );
  }

  Future<void> _showDeleteDialog(BuildContext context, String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sohbeti Sil?'),
        content: const Text('Sohbet listenizden kaldırılacak.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ChatService.instance.hideChatFor(docId, currentUid);
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Sohbet kaldırılamadı.')));
      }
    }
  }
}

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
    _matchFuture = _findLatestMatch();
  }

  @override
  void didUpdateWidget(covariant NewMatchHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUid != widget.currentUid) {
      _matchFuture = _findLatestMatch();
    }
  }

  Future<Map<String, dynamic>?> _findLatestMatch() async {
    final fs = FirebaseFirestore.instance;
    final uid = widget.currentUid;

    try {
      final matchQs = await fs
          .collection('matches')
          .where('users', arrayContains: uid)
          .orderBy('matchedAt', descending: true)
          .limit(10)
          .get();

      if (matchQs.docs.isEmpty) return null;

      String? targetUid;
      for (var doc in matchQs.docs) {
        final matchUsers = List.from(doc.data()['users'] ?? []);
        final matchedUid = matchUsers.firstWhere(
          (id) => id != uid,
          orElse: () => '',
        );

        if (matchedUid.isEmpty) continue;

        final chatId = ChatService.instance.getChatId(uid, matchedUid);
        var chatExists = false;
        try {
          final cachedChat = await fs
              .collection('chats')
              .doc(chatId)
              .get(const GetOptions(source: Source.cache));
          chatExists = cachedChat.exists;
        } catch (_) {}
        if (!chatExists) {
          final serverChat = await fs.collection('chats').doc(chatId).get();
          chatExists = serverChat.exists;
        }

        if (!chatExists) {
          targetUid = matchedUid;
          break;
        }
      }

      if (targetUid == null) return null;

      final cachedUser = await UserCacheService.instance.getUser(targetUid);
      if (cachedUser != null) {
        return {
          'uid': targetUid,
          'username': cachedUser.handle.replaceFirst('@', ''),
          'displayName': cachedUser.displayName,
          'photoURL': cachedUser.photoURL,
        };
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
    } catch (e) {
      return null;
    }
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
        final name = (data['displayName'] ?? data['username'] ?? 'Yeni Sinefil')
            .toString();
        final photo = data['photoURL'] as String?;

        return Container(
          decoration: BoxDecoration(
            color: Colors.greenAccent.withOpacity(0.10),
            border: Border(
              bottom: BorderSide(color: Colors.greenAccent.withOpacity(0.3)),
            ),
          ),
          child: ListTile(
            leading: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  backgroundImage: (photo != null && photo.isNotEmpty)
                      ? NetworkImage(photo)
                      : null,
                  child: (photo == null || photo.isEmpty)
                      ? const Icon(Icons.person)
                      : null,
                ),
                const CircleAvatar(
                  radius: 8,
                  backgroundColor: Colors.white,
                  child: CircleAvatar(
                    radius: 6,
                    backgroundColor: Colors.green,
                    child: Icon(Icons.people_alt, size: 8, color: Colors.white),
                  ),
                ),
              ],
            ),
            title: Text(
              name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            subtitle: const Text('Artık karşılıklı takip ediyorsunuz!'),
            trailing: const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.green,
            ),
            onTap: () async {
              final chatId = await ChatService.instance.getOrCreateChat(
                widget.currentUid,
                otherUid,
              );
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
                _matchFuture = _findLatestMatch();
              });
            },
          ),
        );
      },
    );
  }
}

String _formatTime(DateTime dt) {
  final local = dt.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final thatDay = DateTime(local.year, local.month, local.day);
  if (thatDay == today)
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
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

  void _resetUp() => setState(() {
    _offsetX = 0;
    _offsetY = -10;
  });

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

class JoinedClubsList extends StatefulWidget {
  final String uid;
  final String filterText;

  const JoinedClubsList({super.key, required this.uid, this.filterText = ''});

  @override
  State<JoinedClubsList> createState() => _JoinedClubsListState();
}

class _JoinedClubsListState extends State<JoinedClubsList>
    with AutomaticKeepAliveClientMixin {
  late Stream<QuerySnapshot> _clubsStream;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  @override
  void didUpdateWidget(covariant JoinedClubsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _initStream();
    }
  }

  void _initStream() {
    _clubsStream = ClubService.instance.getUserClubsStream(widget.uid);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return StreamBuilder<QuerySnapshot>(
      stream: _clubsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        var docs = snapshot.data?.docs ?? [];

        if (widget.filterText.isNotEmpty) {
          docs = docs.where((d) {
            final data = d.data() as Map<String, dynamic>;
            final name = (data['name'] ?? '').toString().toLowerCase();
            return name.contains(widget.filterText);
          }).toList();
        }

        if (docs.isEmpty) {
          if (widget.filterText.isNotEmpty) {
            return const Center(
              child: Text(
                "Eşleşen kulüp bulunamadı.",
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.diversity_3_outlined,
                  size: 64,
                  color: Colors.grey.withOpacity(0.3),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Henüz bir kulübe üye değilsin.",
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                FilledButton.tonal(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CreateClubScreen(),
                      ),
                    );
                  },
                  child: const Text("Yeni Bir Kulüp Kur"),
                ),
                const SizedBox(height: 5),
                FilledButton.tonal(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ClubsScreen()),
                    );
                  },
                  child: const Text("Kulüpleri Keşfet"),
                ),
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
