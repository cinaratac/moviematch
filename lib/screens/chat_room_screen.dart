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
  final _svc = ChatService.instance; // Singleton instance kullanımı
  final _ctrl = TextEditingController();
  StreamSubscription? _latestSub;

  @override
  void initState() {
    super.initState();
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    // Okundu bilgisini işaretle.
    // Not: Bu işlem döküman yoksa oluşturabilir (merge: true sayesinde),
    // ancak 'participants' alanı eklenmediği için sohbet listelerinde görünmez (Ghost Chat).
    _svc.markAsRead(widget.chatId, myUid);

    // Karşı taraf yeni mesaj atarsa anlık olarak okundu işaretlemek için dinleyici
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
      // DİKKAT: deleteIfEmpty BURADAN KALDIRILDI.
      // Lazy creation (tembel yükleme) sayesinde boş oda oluşmuyor.
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
      // Mesaj gönderildiği an ChatService.send metodu dökümanı yoksa oluşturacak (Upsert).
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
        "", // Boş metin (sadece film)
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
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('clubs').doc(chatId).snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.hasData || !snap.data!.exists) {
                  return const Center(child: Text("Kulüp bilgisi alınamadı."));
                }
                
                final data = snap.data!.data() as Map<String, dynamic>;
                final members = List<String>.from(data['members'] ?? []);
                final admins = List<String>.from(data['admins'] ?? []);
                final imageUrl = data['imageUrl'] as String?;
                final description = data['description'] as String?;
                final ownerId = data['ownerId'];
                
                final myUid = FirebaseAuth.instance.currentUser?.uid;
                
                // --- YETKİ KONTROLÜ ---
                // Sahibi veya herhangi bir yönetici mi?
                final isOwner = (ownerId == myUid);
                final isAdmin = admins.contains(myUid);
                
                // Menüyü görebilecek kişi: Sahip veya Yönetici
                final canManage = isOwner || isAdmin;

                return Column(
                  children: [
                    Stack(
                      children: [
                        Container(
                          height: 200,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade900,
                            image: (imageUrl != null && imageUrl.isNotEmpty)
                                ? DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover)
                                : null,
                          ),
                          child: (imageUrl == null || imageUrl.isEmpty)
                              ? const Center(child: Icon(Icons.groups, size: 64, color: Colors.white24))
                              : null,
                        ),
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                              ),
                            ),
                          ),
                        ),
                        if (isOwner)
                          Positioned(
                            top: 16,
                            right: 16,
                            child: IconButton(
                              icon: const Icon(Icons.edit, color: Colors.white),
                              tooltip: 'Kulübü Düzenle',
                              style: IconButton.styleFrom(backgroundColor: Colors.black45),
                              onPressed: () {
                                Navigator.pop(context);
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (_) => _EditClubSheet(
                                    clubId: chatId, 
                                    currentName: data['name'], 
                                    currentDesc: description,
                                    currentImage: imageUrl
                                  ),
                                );
                              },
                            ),
                          ),
                        Positioned(
                          bottom: 16,
                          left: 16,
                          right: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data['name'] ?? 'Kulüp',
                                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                              if (description != null && description.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    description,
                                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text("Üyeler", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      ),
                    ),
                    const Divider(height: 1),

                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
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
                                 
                                 // YÖNETİM MENÜSÜ (Eğer ben yetkiliysem ve o kişi ben değilsem ve o kişi kurucu değilse)
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
                      ),
                    ),
                  ],
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
                        'Bilgi >',
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