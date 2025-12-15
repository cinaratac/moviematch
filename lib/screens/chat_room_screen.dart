import 'dart:async';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fluttergirdi/services/chat_service.dart';
import 'package:fluttergirdi/services/club_service.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:fluttergirdi/screens/profilescreen.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';
import 'package:fluttergirdi/widgets/watchlist_wheel.dart';
import 'package:fluttergirdi/widgets/green_characters.dart';
import 'package:fluttergirdi/services/watchlist_service.dart';
import '../services/text_filter_service.dart';
// YENİ İMPORTLAR
import 'package:fluttergirdi/screens/search_movie.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';

class ChatRoomScreen extends StatefulWidget {
  final String chatId;
  final String otherUid;
  final String? otherTitle;
  
  final bool isGroup;
  final String? groupName;

  const ChatRoomScreen({
    super.key,
    required this.chatId,
    required this.otherUid,
    this.otherTitle,
    this.isGroup = false, 
    this.groupName,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final ValueNotifier<bool> _showGuideNotifier = ValueNotifier<bool>(false);
  final _svc = ChatService.instance;
  final _ctrl = TextEditingController();
  StreamSubscription? _latestSub;

  @override
  void initState() {
    super.initState();
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    _svc.markAsRead(widget.chatId, myUid);

    _latestSub = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .listen((snap) {
          if (snap.docs.isEmpty) return;
          final data = snap.docs.first.data();
          final author = (data['authorId'] ?? data['from'] ?? '') as String;
          if (author != myUid) {
            _svc.markAsRead(widget.chatId, myUid);
          }
        });

    _checkAndShowGuide();
  }

  Future<void> _checkAndShowGuide() async {
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final bool seen = sp.getBool('seen_watchlist_guide') ?? false;
      if (!seen) {
        _showGuideNotifier.value = true;
        await sp.setBool('seen_watchlist_guide', true);
      }
    } catch (e) {
      debugPrint('Rehber hatası: $e');
    }
  }

  @override
  void dispose() {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid != null) {
      _svc.markAsRead(widget.chatId, myUid);
    }
    _latestSub?.cancel();
    _ctrl.dispose();
    _showGuideNotifier.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final txt = _ctrl.text.trim();
    if (txt.isEmpty) return;
    
    if (TextFilterService.hasProfanity(txt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mesajınız uygunsuz ifadeler içeriyor.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      final myUid = FirebaseAuth.instance.currentUser!.uid;
      _ctrl.clear();
      await _svc.send(widget.chatId, myUid, txt, otherUid: widget.otherUid);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gönderilemedi: $e')),
      );
    }
  }

  Future<void> _openFilmPicker() async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent, 
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          height: MediaQuery.of(ctx).size.height * 0.8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 12),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text('Filmlerim', style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold))),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Expanded(
                child: Builder(
                  builder: (context) {
                    final merged = <Map<String, String>>[...UserShelfCache.fiveStar, ...UserShelfCache.favorites, ...UserShelfCache.watchlist, ...UserShelfCache.disliked];
                    final seen = <String>{};
                    final items = <Map<String, String>>[];
                    for (final m in merged) {
                      final t = (m['title'] ?? '').trim();
                      if (t.isEmpty) continue;
                      final key = t.toLowerCase();
                      if (seen.add(key)) items.add({'title': t, 'poster': (m['poster'] ?? '').toString()});
                    }
                    if (items.isEmpty) return const Center(child: Text('Listen boş. Profilinden senkronize et.', style: TextStyle(color: Colors.white54)));

                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: items.length,
                      separatorBuilder: (_, i) => const Divider(height: 1, indent: 16, endIndent: 16, color: Colors.white10),
                      itemBuilder: (_, i) {
                        final title = items[i]['title'] ?? '';
                        final poster = items[i]['poster'] ?? '';
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                          leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 45, height: 68, child: poster.isNotEmpty ? PosterImage(posterUrl: poster, title: title, fit: BoxFit.cover) : Container(color: Colors.grey.shade800, child: const Icon(Icons.movie, color: Colors.white54)))),
                          title: Text(title.isEmpty ? 'İsimsiz Film' : title, style: const TextStyle(fontWeight: FontWeight.w500)),
                          onTap: () => Navigator.of(context).pop(items[i]),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || result == null) return;

    final myUid = FirebaseAuth.instance.currentUser!.uid;
    final title = (result['title'] ?? '').trim();
    final poster = (result['poster'] ?? '').trim();
       
    try {
      await _svc.send(
        widget.chatId,
        myUid,
        "", 
        otherUid: widget.otherUid,
        movie: {'title': title, 'poster': poster},
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gönderilemedi: $e')),
      );
    }
  }

  // --- YENİ WIDGET: HAFTANIN FİLMİ BANNERI ---
  Widget _buildFeaturedMovieBanner() {
    if (!widget.isGroup) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('clubs').doc(widget.chatId).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) return const SizedBox.shrink();
        final data = snap.data!.data() as Map<String, dynamic>;
        final movie = data['featuredMovie'] as Map<String, dynamic>?;

        if (movie == null) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 1),
          decoration: BoxDecoration(
            color: const Color(0xFF252525),
            border: Border(bottom: BorderSide(color: Colors.amber.withOpacity(0.3))),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0,2))]
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (movie['id'] != null) {
                   Navigator.push(context, MaterialPageRoute(
                     builder: (_) => MovieDetailScreen(tmdbId: movie['id'])
                   ));
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                     Container(
                       padding: const EdgeInsets.all(6),
                       decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
                       child: const Icon(Icons.star, color: Colors.black, size: 16),
                     ),
                     const SizedBox(width: 12),
                     Expanded(
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           const Text(
                             "HAFTANIN FİLMİ",
                             style: TextStyle(fontWeight: FontWeight.w900, color: Colors.amber, fontSize: 10, letterSpacing: 1),
                           ),
                           const SizedBox(height: 2),
                           Text(
                             movie['title'] ?? 'Film',
                             style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                             overflow: TextOverflow.ellipsis,
                           ),
                         ],
                       ),
                     ),
                     const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: _ChatAppBarTitle(
          chatId: widget.chatId,
          otherUid: widget.otherUid,
          initialTitle: widget.otherTitle,
          isGroup: widget.isGroup,
          groupName: widget.groupName,
        ),
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor, 
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // --- YENİ EKLENEN KISIM: HAFTANIN FİLMİ ---
              _buildFeaturedMovieBanner(),

              Expanded(
                child: Container(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('chats')
                        .doc(widget.chatId)
                        .collection('messages')
                        .orderBy('createdAt', descending: true)
                        .limit(60)
                        .snapshots(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final docs = snap.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat_bubble_outline,
                                  size: 48, color: Colors.grey.shade800),
                              const SizedBox(height: 16),
                              const Text(
                                'Sohbete başla!',
                                style: TextStyle(color: Colors.white54),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        itemCount: docs.length,
                        itemBuilder: (context, i) {
                          final m = docs[i].data();
                          final author =
                              (m['authorId'] ?? m['from'] ?? '') as String;
                          final mine = author == myUid;
                          final text = (m['text'] ?? '') as String;
                          final ts = (m['createdAt'] as Timestamp?);
                          final dt = ts?.toDate();

                          return _buildMessageRow(
                            context,
                            text: text,
                            movie: m['movie'],
                            isMine: mine,
                            timestamp: dt,
                            authorId: author,
                          );
                        },
                      );
                    },
                  ),
                ),
              ),

              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E), 
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _ctrl,
                                  minLines: 1,
                                  maxLines: 4,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _send(),
                                  style: const TextStyle(color: Colors.white),
                                  decoration: const InputDecoration(
                                    hintText: 'Mesaj...',
                                    hintStyle: TextStyle(color: Colors.white38),
                                    isCollapsed: true,
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    tooltip: 'Film paylaş',
                                    onPressed: _openFilmPicker,
                                    icon: const Icon(
                                        Icons.movie_filter_outlined,
                                        color: Colors.white54),
                                  ),
                                  const SizedBox(width: 12),
                                  if (!widget.isGroup)
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      tooltip: 'Watchlist Çarkı',
                                      onPressed: () {
                                        showModalBottomSheet(
                                          context: context,
                                          isScrollControlled: true,
                                          useSafeArea: true,
                                          backgroundColor: Colors.transparent,
                                          builder: (_) => _WatchlistWheelSheet(
                                            chatId: widget.chatId,
                                            myUid: myUid,
                                            otherUid: widget.otherUid,
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.donut_large,
                                          color: Colors.white54),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _send,
                        child: CircleAvatar(
                          radius: 22,
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          child: const Icon(Icons.send_rounded,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          ValueListenableBuilder<bool>(
            valueListenable: _showGuideNotifier,
            builder: (context, isVisible, child) {
              if (!isVisible) return const SizedBox.shrink();
              return GuideCharacterOverlay(
                message:
                    "Beraber film izlemek için watchlist çarkını deneyebilirsin",
                isVisible: isVisible,
                onClose: () => _showGuideNotifier.value = false,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessageRow(
    BuildContext context, {
    required String text,
    dynamic movie,
    required bool isMine,
    DateTime? timestamp,
    required String authorId,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end, 
        children: [
          if (!isMine) ...[
            _UserAvatar(uid: authorId, size: 16),
            const SizedBox(width: 8),
          ],

          _buildMessageBubble(
            context,
            text: text,
            movie: movie,
            isMine: isMine,
            timestamp: timestamp,
          ),

          if (isMine) ...[
             const SizedBox(width: 8), 
          ]
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
    BuildContext context, {
    required String text,
    dynamic movie,
    required bool isMine,
    DateTime? timestamp,
  }) {
    String posterUrl = '';
    String movieTitle = '';
    bool hasMovie = false;
    if (movie is Map) {
      final mm = Map<String, dynamic>.from(movie);
      posterUrl = (mm['poster'] ?? '').toString();
      movieTitle = (mm['title'] ?? '').toString();
      hasMovie = true;
    }

    final myGradient = LinearGradient(
      colors: [
        Theme.of(context).colorScheme.primary,
        Theme.of(context).colorScheme.primary.withOpacity(0.8),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    final otherColor = const Color(0xFF2C2C2E);

    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.70; 
    const paddingHorizontal = 24.0;
    final maxContentWidth = maxBubbleWidth - paddingHorizontal;
    const movieCardWidth = 200.0;

    return Container(
      constraints: BoxConstraints(
        maxWidth: maxBubbleWidth,
        minWidth: 40,
      ),
      decoration: BoxDecoration(
        gradient: isMine ? myGradient : null,
        color: isMine ? null : otherColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isMine ? 20 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasMovie)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  width: movieCardWidth,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.black26,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (posterUrl.isNotEmpty)
                        AspectRatio(
                          aspectRatio: 2 / 3,
                          child: PosterImage(
                            posterUrl: posterUrl,
                            title: movieTitle,
                            fit: BoxFit.cover,
                          ),
                        )
                      else
                        Container(
                          height: 120,
                          width: double.infinity,
                          color: Colors.grey.shade900,
                          child: const Center(
                            child: Icon(Icons.movie,
                                size: 32, color: Colors.white24),
                          ),
                        ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        color: Colors.black38,
                        child: Text(
                          movieTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              if (text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: hasMovie 
                        ? movieCardWidth 
                        : maxContentWidth, 
                    ),
                    child: Text(
                      text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),

              if (timestamp != null)
                Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _formatTime(timestamp),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ... (_UserAvatar ve _ChatAppBarTitle, _EditClubSheet vb. aynı kalıyor, sadece imports ve logic güncellemeleri yapıldı)
// ... Bu kod bloğunun devamında önceki kodunuzdaki diğer yardımcı sınıflar ( _ChatAppBarTitle, _FeaturedMovieTab vb.) olduğu gibi korunmuştur.
// ... Yer darlığı nedeniyle sadece değiştirilen ana widget (ChatRoomScreen) gösterilmiştir.
// ... Lütfen dosyanın geri kalanını silmeyin veya üstüne yazarken dikkatli olun.
// ... Yukarıdaki kodda _ChatAppBarTitle ve diğer yardımcı sınıflar EKSİK değil, sadece burada tekrar kopyalamadım.
// ... Tam dosya içeriğini sağlamak için aşağıya yardımcı sınıfları da ekliyorum:

class _UserAvatar extends StatelessWidget {
  final String uid;
  final double size;
  const _UserAvatar({required this.uid, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        String? url;
        if (snap.hasData && snap.data!.exists) {
          final data = snap.data!.data() as Map<String, dynamic>;
          url = data['photoURL'];
        }
        return CircleAvatar(
          radius: size,
          backgroundImage: (url != null && url.isNotEmpty) ? NetworkImage(url) : null,
          child: (url == null || url.isEmpty) ? Icon(Icons.person, size: size) : null,
        );
      },
    );
  }
}

class _ChatAppBarTitle extends StatelessWidget {
  final String chatId;
  final String otherUid;
  final String? initialTitle;
  final bool isGroup;
  final String? groupName;
  
  const _ChatAppBarTitle({
    required this.chatId,
    required this.otherUid,
    this.initialTitle,
    required this.isGroup,
    this.groupName,
  });

  void _showClubInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.95,
          minChildSize: 0.6,
          maxChildSize: 1.0,
          builder: (context, scrollController) {
            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('clubs').doc(chatId).snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                
                final data = snap.data!.data() as Map<String, dynamic>? ?? {};
                final members = List<String>.from(data['members'] ?? []);
                final admins = List<String>.from(data['admins'] ?? []);
                final imageUrl = data['imageUrl'] as String?;
                final ownerId = data['ownerId'];
                final featuredMovie = data['featuredMovie'] as Map<String, dynamic>?;

                final myUid = FirebaseAuth.instance.currentUser?.uid;
                final isOwner = (ownerId == myUid);
                final isAdmin = admins.contains(myUid);
                final canManage = isOwner || isAdmin;

                return Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      // Header
                      Stack(
                        children: [
                          Container(
                            height: 160,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade900,
                              image: (imageUrl != null && imageUrl.isNotEmpty)
                                  ? DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover)
                                  : null,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                            ),
                            child: imageUrl == null ? const Center(child: Icon(Icons.groups, size: 50, color: Colors.white24)) : null,
                          ),
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 16, left: 16, right: 16,
                            child: Text(
                              data['name'] ?? 'Kulüp',
                              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (canManage)
                            Positioned(
                              top: 10, right: 10,
                              child: IconButton(
                                icon: const Icon(Icons.edit, color: Colors.white),
                                onPressed: () {
                                  Navigator.pop(context);
                                  showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => _EditClubSheet(clubId: chatId, currentName: data['name'], currentDesc: data['description'], currentImage: imageUrl));
                                },
                              ),
                            ),
                        ],
                      ),

                      // Tabs
                      Expanded(
                        child: DefaultTabController(
                          length: 4, 
                          child: Column(
                            children: [
                              const TabBar(
                                isScrollable: true,
                                tabs: [
                                  Tab(text: "Haftanın Filmi"),
                                  Tab(text: "Etkinlikler"),
                                  Tab(text: "Anketler"),
                                  Tab(text: "Üyeler"),
                                ],
                              ),
                              Expanded(
                                child: TabBarView(
                                  children: [
                                    _FeaturedMovieTab(clubId: chatId, canManage: canManage, movieData: featuredMovie),
                                    _EventsTab(clubId: chatId, canManage: canManage),
                                    _PollsTab(clubId: chatId, canManage: canManage),
                                    _MembersTab(chatId: chatId, members: members, admins: admins, ownerId: ownerId, canManage: canManage, myUid: myUid),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
            );
          },
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isGroup) {
      return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('clubs').doc(chatId).snapshots(),
        builder: (context, snap) {
          String? imageUrl;
          if (snap.hasData && snap.data!.exists) {
            imageUrl = (snap.data!.data() as Map<String, dynamic>)['imageUrl'];
          }

          return InkWell(
            onTap: () => _showClubInfo(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.grey.shade800,
                  backgroundImage: (imageUrl != null && imageUrl.isNotEmpty) 
                      ? NetworkImage(imageUrl) 
                      : null,
                  child: (imageUrl == null || imageUrl.isEmpty) 
                      ? const Icon(Icons.groups, color: Colors.white, size: 20) 
                      : null,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        groupName ?? 'Kulüp Sohbeti',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        'Panoyu Aç >',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(otherUid)
          .snapshots(),
      builder: (context, uSnap) {
        String title = initialTitle ?? '';
        String photo = '';
        
        if (uSnap.hasData && uSnap.data!.exists) {
          final u = uSnap.data!.data()!;
          final username = (u['username'] ?? '') as String;
          final disp = (u['displayName'] ?? '') as String;
          final lb = (u['letterboxdUsername'] ?? '') as String;
          final purl = (u['photoURL'] ?? '') as String;

          title = username.isNotEmpty
              ? username
              : (disp.isNotEmpty
                  ? disp
                  : (lb.isNotEmpty ? '@$lb' : initialTitle ?? 'Kullanıcı'));
          photo = purl;
        } else if (title.isEmpty) {
          title = 'Kullanıcı';
        }

        final showTitle = title;
        final photoUrl = photo;

        return InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PublicProfileScreen(uid: otherUid),
              ),
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.grey.shade800,
                backgroundImage: (photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                child: (photoUrl.isEmpty)
                    ? Text(showTitle.isNotEmpty ? showTitle[0] : '?',
                        style: const TextStyle(color: Colors.white))
                    : null,
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  showTitle,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// --- TAB İÇERİKLERİ VE DİĞER YARDIMCI WIDGETLAR ---
// Bu kısımlar değişmedi, ancak dosyanın bütünlüğü için buraya ekliyorum.

class _FeaturedMovieTab extends StatelessWidget {
  final String clubId;
  final bool canManage;
  final Map<String, dynamic>? movieData;

  const _FeaturedMovieTab({required this.clubId, required this.canManage, this.movieData});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (movieData != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  const Text("🏆 HAFTANIN FİLMİ 🏆", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, letterSpacing: 2)),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: PosterImage(
                          posterUrl: movieData!['poster'] ?? '',
                          title: movieData!['title'] ?? '',
                          width: 100, height: 150,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(movieData!['title'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            if (movieData!['releaseDate'] != null)
                              Text("Yıl: ${movieData!['releaseDate'].toString().split('-').first}", style: const TextStyle(color: Colors.grey)),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () {
                                final tmdbId = movieData!['id'];
                                if (tmdbId != null) {
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => MovieDetailScreen(tmdbId: tmdbId)));
                                }
                              },
                              icon: const Icon(Icons.info_outline),
                              label: const Text("Detaylar"),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (canManage)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextButton.icon(
                  onPressed: () => ClubService.instance.removeFeaturedMovie(clubId),
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text("Filmi Kaldır", style: TextStyle(color: Colors.red)),
                ),
              ),
          ] else ...[
            const Icon(Icons.movie_filter, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            const Text("Bu hafta için henüz film seçilmemiş.", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            if (canManage)
              FilledButton.icon(
                onPressed: () async {
                  final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchMoviePage(isSelectionMode: true)));
                  if (result != null && result is Map<String, dynamic>) {
                    ClubService.instance.setFeaturedMovie(clubId, result);
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text("Film Seç"),
              ),
          ],
        ],
      ),
    );
  }
}

class _EventsTab extends StatelessWidget {
  final String clubId;
  final bool canManage;

  const _EventsTab({required this.clubId, required this.canManage});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (canManage)
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showAddEventDialog(context),
                icon: const Icon(Icons.add),
                label: const Text("Etkinlik Oluştur"),
              ),
            ),
          ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: ClubService.instance.getClubEvents(clubId),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) return const Center(child: Text("Planlanmış etkinlik yok."));

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final date = (data['date'] as Timestamp).toDate();
                  final participants = List<String>.from(data['participants'] ?? []);
                  final myUid = FirebaseAuth.instance.currentUser?.uid;
                  final isJoined = participants.contains(myUid);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("${date.day}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            Text(_getMonth(date.month), style: const TextStyle(fontSize: 10)),
                          ],
                        ),
                      ),
                      title: Text(data['title'] ?? 'Etkinlik'),
                      subtitle: Text("${date.hour.toString().padLeft(2,'0')}:${date.minute.toString().padLeft(2,'0')} • ${participants.length} Katılımcı"),
                      trailing: IconButton(
                        icon: Icon(isJoined ? Icons.check_circle : Icons.add_circle_outline, color: isJoined ? Colors.green : null),
                        onPressed: () => ClubService.instance.joinEvent(clubId, doc.id, myUid!),
                      ),
                      onLongPress: canManage ? () => ClubService.instance.deleteEvent(clubId, doc.id) : null,
                    ),
                  );
                },
              );
            }
          ),
        ),
      ],
    );
  }

  String _getMonth(int m) {
    const months = ["Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"];
    return months[m - 1];
  }

  void _showAddEventDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(hours: 1));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Yeni Etkinlik"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: "Etkinlik Adı", hintText: "Örn: Cumartesi Sineması"),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Tarih ve Saat"),
                subtitle: Text("${selectedDate.day}.${selectedDate.month} - ${selectedDate.hour}:${selectedDate.minute.toString().padLeft(2,'0')}"),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (d != null) {
                    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(selectedDate));
                    if (t != null) {
                      setDialogState(() {
                        selectedDate = DateTime(d.year, d.month, d.day, t.hour, t.minute);
                      });
                    }
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("İptal")),
            FilledButton(
              onPressed: () {
                if (titleCtrl.text.isNotEmpty) {
                  ClubService.instance.createEvent(clubId, titleCtrl.text.trim(), selectedDate);
                  Navigator.pop(context);
                }
              },
              child: const Text("Oluştur"),
            ),
          ],
        ),
      ),
    );
  }
}

class _PollsTab extends StatelessWidget {
  final String clubId;
  final bool canManage;

  const _PollsTab({required this.clubId, required this.canManage});

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Column(
      children: [
        if (canManage)
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showAddPollDialog(context),
                icon: const Icon(Icons.poll),
                label: const Text("Anket Oluştur"),
              ),
            ),
          ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: ClubService.instance.getClubPolls(clubId),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) return const Center(child: Text("Aktif anket yok."));

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final options = List<dynamic>.from(data['options']);
                  final voters = Map<String, dynamic>.from(data['voters'] ?? {});
                  final totalVotes = voters.length;
                  final myVoteIndex = voters[myUid];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(data['question'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                              if (canManage)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                                  onPressed: () => ClubService.instance.deletePoll(clubId, doc.id),
                                )
                            ],
                          ),
                          const SizedBox(height: 12),
                          ...List.generate(options.length, (idx) {
                            final opt = options[idx];
                            final count = opt['voteCount'] ?? 0;
                            final percent = totalVotes == 0 ? 0.0 : (count / totalVotes);
                            final isSelected = (myVoteIndex == idx);

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                onTap: () => ClubService.instance.votePoll(clubId, doc.id, myUid!, idx),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  height: 40,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: isSelected ? Colors.green : Colors.grey.withOpacity(0.3)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Stack(
                                    children: [
                                      FractionallySizedBox(
                                        widthFactor: percent,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: isSelected ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(7),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(opt['text']),
                                            Text("$count (${(percent * 100).toInt()}%)", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                          Text("$totalVotes oy", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  );
                },
              );
            }
          ),
        ),
      ],
    );
  }

  void _showAddPollDialog(BuildContext context) {
    final qCtrl = TextEditingController();
    final o1Ctrl = TextEditingController();
    final o2Ctrl = TextEditingController();
    final o3Ctrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Anket Oluştur"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: qCtrl, decoration: const InputDecoration(labelText: "Soru")),
              const SizedBox(height: 16),
              TextField(controller: o1Ctrl, decoration: const InputDecoration(labelText: "Seçenek 1")),
              TextField(controller: o2Ctrl, decoration: const InputDecoration(labelText: "Seçenek 2")),
              TextField(controller: o3Ctrl, decoration: const InputDecoration(labelText: "Seçenek 3 (Opsiyonel)")),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("İptal")),
          FilledButton(
            onPressed: () {
              if (qCtrl.text.isNotEmpty && o1Ctrl.text.isNotEmpty && o2Ctrl.text.isNotEmpty) {
                final opts = [o1Ctrl.text.trim(), o2Ctrl.text.trim()];
                if (o3Ctrl.text.isNotEmpty) opts.add(o3Ctrl.text.trim());
                ClubService.instance.createPoll(clubId, qCtrl.text.trim(), opts);
                Navigator.pop(context);
              }
            },
            child: const Text("Paylaş"),
          ),
        ],
      ),
    );
  }
}

class _MembersTab extends StatelessWidget {
  final String chatId;
  final List<String> members;
  final List<String> admins;
  final String? ownerId;
  final bool canManage;
  final String? myUid;

  const _MembersTab({
    required this.chatId,
    required this.members,
    required this.admins,
    this.ownerId,
    required this.canManage,
    this.myUid,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: members.length,
      itemBuilder: (ctx, i) {
        final uid = members[i];
        final isThisMemberOwner = (uid == ownerId);
        final isThisMemberAdmin = admins.contains(uid);

        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
          builder: (context, userSnap) {
             if (!userSnap.hasData) return const SizedBox.shrink();
             final userData = userSnap.data!.data() as Map<String, dynamic>?;
             final name = userData?['displayName'] ?? userData?['username'] ?? 'Kullanıcı';
             final photo = userData?['photoURL'];

             return ListTile(
               leading: CircleAvatar(
                 backgroundImage: (photo != null) ? NetworkImage(photo) : null,
                 child: photo == null ? const Icon(Icons.person) : null,
               ),
               title: Text(name),
               subtitle: isThisMemberOwner 
                  ? const Text('Kurucu', style: TextStyle(color: Colors.amber, fontSize: 12))
                  : (isThisMemberAdmin ? const Text('Yönetici', style: TextStyle(color: Colors.green, fontSize: 12)) : null),
               
               trailing: (canManage && uid != myUid && !isThisMemberOwner) 
                  ? PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'kick') {
                          ClubService.instance.kickMember(chatId, uid);
                        } else if (value == 'promote') {
                          ClubService.instance.toggleAdmin(chatId, uid, true);
                        } else if (value == 'demote') {
                          ClubService.instance.toggleAdmin(chatId, uid, false);
                        }
                      },
                      itemBuilder: (BuildContext context) {
                        return [
                          if (!isThisMemberAdmin)
                            const PopupMenuItem(
                              value: 'promote',
                              child: Text('Yönetici Yap'),
                            )
                          else
                            const PopupMenuItem(
                              value: 'demote',
                              child: Text('Yöneticilikten Al'),
                            ),
                          const PopupMenuItem(
                            value: 'kick',
                            child: Text('Kulüpten At', style: TextStyle(color: Colors.red)),
                          ),
                        ];
                      },
                    )
                  : null,
               onTap: () {
                 Navigator.push(
                   context,
                   MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: uid))
                 );
               },
             );
          }
        );
      }
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

class _EditClubSheet extends StatefulWidget {
  final String clubId;
  final String? currentName;
  final String? currentDesc;
  final String? currentImage;

  const _EditClubSheet({
    required this.clubId, 
    this.currentName, 
    this.currentDesc, 
    this.currentImage
  });

  @override
  State<_EditClubSheet> createState() => _EditClubSheetState();
}

class _EditClubSheetState extends State<_EditClubSheet> {
  late TextEditingController _descCtrl;
  bool _isLoading = false;
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _descCtrl = TextEditingController(text: widget.currentDesc);
  }

  Future<void> _pickImage() async {
    final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _imageFile = File(picked.path);
      });
    }
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);
    try {
      String? newImageUrl;

      if (_imageFile != null) {
        final fileName = '${widget.clubId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final ref = FirebaseStorage.instance.ref().child('club_images/$fileName');
        await ref.putFile(_imageFile!);
        newImageUrl = await ref.getDownloadURL();
      }

      final Map<String, dynamic> updates = {
        'description': _descCtrl.text.trim(),
      };
      
      if (newImageUrl != null) {
        updates['imageUrl'] = newImageUrl;
      }

      await FirebaseFirestore.instance.collection('clubs').doc(widget.clubId).update(updates);
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kulüp bilgileri güncellendi.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Kulübü Düzenle", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
              const SizedBox(height: 20),
              
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 120,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade800,
                    borderRadius: BorderRadius.circular(12),
                    image: _imageFile != null
                        ? DecorationImage(image: FileImage(_imageFile!), fit: BoxFit.cover)
                        : (widget.currentImage != null && widget.currentImage!.isNotEmpty)
                            ? DecorationImage(image: NetworkImage(widget.currentImage!), fit: BoxFit.cover)
                            : null,
                  ),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                      child: const Icon(Icons.add_a_photo, color: Colors.white),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              
              TextField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Kulüp Açıklaması',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              
              const SizedBox(height: 24),
              
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _isLoading ? null : _save,
                  child: _isLoading ? const CircularProgressIndicator() : const Text('Kaydet'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WatchlistWheelSheet extends StatefulWidget {
  final String chatId;
  final String myUid;
  final String otherUid;
  const _WatchlistWheelSheet({
    required this.chatId,
    required this.myUid,
    required this.otherUid,
  });

  @override
  State<_WatchlistWheelSheet> createState() => _WatchlistWheelSheetState();
}

class _WatchlistWheelSheetState extends State<_WatchlistWheelSheet> {
  final _chatSvc = ChatService.instance;
  final _watchlistSvc = WatchlistService.instance;

  late Future<List<WatchlistMovie>> _loader;

  @override
  void initState() {
    super.initState();
    _loader = _watchlistSvc.loadSharedWatchlist(widget.myUid, widget.otherUid);
  }

  Future<void> _sendChosenToChat(WatchlistMovie m) async {
    try {
      final myUid = FirebaseAuth.instance.currentUser!.uid;
      await _chatSvc.send(
        widget.chatId,
        myUid,
        m.title.isNotEmpty ? '🎯 Çark seçimi: ${m.title}' : '🎯 Çark seçimi',
        otherUid: widget.otherUid,
        movie: {'title': m.title, 'poster': m.posterUrl ?? ''},
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Seçilen film gönderildi: ${m.title}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gönderilemedi: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, controller) {
        return Container(
           decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Text(
                      'Watchlist Çarkı',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
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
                child: FutureBuilder<List<WatchlistMovie>>(
                  future: _loader,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final items = snap.data ?? const <WatchlistMovie>[];
                    if (items.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Ortak watchlist bulunamadı. Önce watchlist ekleyin.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                      );
                    }
                    return ListView(
                      controller: controller,
                      children: [
                        const SizedBox(height: 16),
                        Center(
                          child: WatchlistWheel(
                            items: items,
                            size: 340,
                            onChosen: (m) async {
                              final send = await showDialog<bool>(
                                context: context,
                                builder: (dctx) {
                                  return AlertDialog(
                                    title: const Text('Film seçildi'),
                                    content: Text(m.title),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dctx, false),
                                        child: const Text('Kapat'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(dctx, true),
                                        child: const Text('Mesaja ekle'),
                                      ),
                                    ],
                                  );
                                },
                              );
                              if (send == true) {
                                await _sendChosenToChat(m);
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}