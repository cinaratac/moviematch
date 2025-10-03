import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/services/chat_service.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';

class ChatRoomScreen extends StatefulWidget {
  final String chatId;
  final String otherUid;
  final String?
  otherTitle; // optional pre-resolved title (username/displayName)

  const ChatRoomScreen({
    super.key,
    required this.chatId,
    required this.otherUid,
    this.otherTitle,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _svc = ChatService();
  final _ctrl = TextEditingController();
  StreamSubscription? _latestSub;
  Timer? _markDebounce;

  // Pagination state for messages
  final ScrollController _scroll = ScrollController();
  final int _pageSize = 30;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];
  bool _loadingOlder = false;
  bool _hasMore = true;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _msgsSub;

  @override
  void initState() {
    super.initState();
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    // Katılımcılar alanını garantiye al (kalıcılık için kritik)
    _svc.ensureChat(widget.chatId, myUid, widget.otherUid);

    // Oda açıkken yeni mesaj geldikçe okundu işaretle (debounced)
    _latestSub = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .snapshots()
        .listen((snap) {
          final d = snap.data();
          if (d == null) return;
          final lastAuthor =
              (d['lastMessageAuthorId'] ?? d['lastAuthorId'] ?? '')
                  as String? ??
              '';
          if (lastAuthor == myUid) return; // kendi mesajım değilse okundu bas
          _markDebounce?.cancel();
          _markDebounce = Timer(const Duration(milliseconds: 500), () {
            _svc.markAsRead(widget.chatId, myUid);
          });
        });

    // İlk girişte de okundu bas
    _svc.markAsRead(widget.chatId, myUid);

    // ---- Mesajları sayfalı yükleme: canlı en son N + yukarı kaydırınca daha eski ----
    _msgsSub = ChatService.instance
        .latestMessagesStream(widget.chatId, limitCount: _pageSize)
        .listen((qs) {
          final fresh = qs.docs;
          final older = _docs
              .where((d) => !fresh.any((f) => f.id == d.id))
              .toList();
          setState(() {
            _docs
              ..clear()
              ..addAll(fresh)
              ..addAll(older);
          });
        });

    // reverse ListView kullandığımız için: "tepeye" yaklaşınca daha eski sayfayı getir
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
        _loadOlder();
      }
    });
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMore || _docs.isEmpty) return;
    setState(() => _loadingOlder = true);
    try {
      final lastDoc = _docs.isNotEmpty ? _docs.last : null;
      if (lastDoc == null) {
        _hasMore = false;
      } else {
        final qs = await ChatService.instance.fetchOlderMessagesPage(
          widget.chatId,
          startAfterDoc: lastDoc,
          pageSize: _pageSize,
        );
        if (qs.docs.isEmpty) {
          _hasMore = false;
        } else {
          setState(() {
            // yinelenenleri at
            for (final d in qs.docs) {
              if (!_docs.any((e) => e.id == d.id)) {
                _docs.add(d);
              }
            }
          });
        }
      }
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  @override
  void dispose() {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid != null) {
      _svc.markAsRead(widget.chatId, myUid);
    }
    _markDebounce?.cancel();
    _latestSub?.cancel();
    _msgsSub?.cancel();
    _scroll.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final txt = _ctrl.text.trim();
    if (txt.isEmpty) return;
    try {
      final myUid = FirebaseAuth.instance.currentUser!.uid;
      _ctrl.clear();
      await _svc.send(widget.chatId, myUid, txt, otherUid: widget.otherUid);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gönderilemedi: $e')));
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
        ),
      ),
      body: Column(
        children: [
          // Mesajlar
          Expanded(
            child: Stack(
              children: [
                if (_docs.isEmpty)
                  const Center(child: Text('Henüz mesaj yok.'))
                else
                  ListView.builder(
                    controller: _scroll,
                    reverse:
                        true, // en yeni altta, yukarı kaydırınca eski yüklenir
                    cacheExtent: 800,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: _docs.length,
                    itemBuilder: (context, i) {
                      final m = _docs[i].data();
                      final myUid = FirebaseAuth.instance.currentUser!.uid;
                      final author =
                          (m['authorId'] ?? m['from'] ?? '') as String;
                      final mine = author == myUid;
                      final text =
                          (m['text'] ?? m['message'] ?? m['content'] ?? '')
                              as String;
                      final ts = (m['createdAt'] as Timestamp?);
                      final dt = ts?.toDate();

                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 320),
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: mine
                                  ? Colors.blueAccent
                                  : Colors.grey.shade800,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(12),
                                topRight: const Radius.circular(12),
                                bottomLeft: Radius.circular(mine ? 12 : 4),
                                bottomRight: Radius.circular(mine ? 4 : 12),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: mine
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                Text(
                                  text,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                if (dt != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatTime(dt),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.white.withValues(
                                        alpha: 0.8,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                if (_loadingOlder)
                  const Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Girdi alanı
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 6.0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Mesaj yaz…',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(onPressed: _send, icon: const Icon(Icons.send)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatAppBarTitle extends StatelessWidget {
  final String chatId;
  final String otherUid;
  final String? initialTitle;
  const _ChatAppBarTitle({
    required this.chatId,
    required this.otherUid,
    this.initialTitle,
  });

  @override
  Widget build(BuildContext context) {
    // If an initial title is provided, we still fetch photo from users to show avatar fast.
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .snapshots(),
      builder: (context, snap) {
        String titleFromChat = initialTitle ?? '';
        String photoFromChat = '';

        // Try to read participantsMeta from chats
        if (snap.hasData && snap.data!.exists) {
          final d = snap.data!.data()!;
          final m = d['participantsMeta'];
          if (m is Map) {
            final m2 = Map<String, dynamic>.from(m);
            if (m2.containsKey(otherUid) && m2[otherUid] is Map) {
              final meta = Map<String, dynamic>.from(m2[otherUid] as Map);
              final username = (meta['username'] ?? '') as String;
              final displayName = (meta['displayName'] ?? '') as String;
              final lb =
                  (meta['lb'] ?? meta['letterboxdUsername'] ?? '') as String;
              final photo =
                  (meta['photoURL'] ?? meta['avatar'] ?? '') as String? ?? '';
              titleFromChat = titleFromChat.isNotEmpty
                  ? titleFromChat
                  : (username.isNotEmpty
                        ? username
                        : (displayName.isNotEmpty
                              ? displayName
                              : (lb.isNotEmpty ? '@$lb' : '')));
              photoFromChat = photo;
            }
          }
        }

        // Build a child that can be updated later if we fetch more
        Widget makeTile(String title, String photoUrl) {
          final showTitle = title.isNotEmpty ? title : '';
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
                  radius: 16,
                  backgroundImage: (photoUrl.isNotEmpty)
                      ? NetworkImage(photoUrl)
                      : null,
                  child: (photoUrl.isEmpty)
                      ? const Icon(Icons.person, size: 18)
                      : null,
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    showTitle,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          );
        }

        // If we have at least a name or photo from chat meta, render immediately.
        if (titleFromChat.isNotEmpty || photoFromChat.isNotEmpty) {
          return makeTile(titleFromChat, photoFromChat);
        }

        // Fallback 1: matches/{chatId} to seed chats.participantsMeta (and get a title/photo)
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection('matches')
              .doc(chatId)
              .get(),
          builder: (context, mSnap) {
            String title = '';
            String photo = '';
            if (mSnap.hasData && mSnap.data!.exists) {
              final md = mSnap.data!.data()!;
              final aP = md['aProfile'] as Map<String, dynamic>?;
              final bP = md['bProfile'] as Map<String, dynamic>?;
              Map<String, dynamic>? otherP;
              if (aP != null && aP['uid'] == otherUid) otherP = aP;
              if (bP != null && bP['uid'] == otherUid) otherP = bP;
              if (otherP != null) {
                final username = (otherP['username'] ?? '') as String;
                final disp = (otherP['displayName'] ?? '') as String;
                final lb =
                    (otherP['lb'] ?? otherP['letterboxdUsername'] ?? '')
                        as String;
                photo =
                    (otherP['photoURL'] ?? otherP['avatar'] ?? '') as String? ??
                    '';
                title = username.isNotEmpty
                    ? username
                    : (disp.isNotEmpty ? disp : (lb.isNotEmpty ? '@$lb' : ''));
                // Persist minimal meta to chats for next time
                FirebaseFirestore.instance.collection('chats').doc(chatId).set({
                  'participantsMeta': {
                    otherUid: {
                      'uid': otherUid,
                      'username': username,
                      'displayName': disp,
                      'lb': lb,
                      'photoURL': photo,
                    },
                  },
                }, SetOptions(merge: true));
              }
            }

            // Fallback 2: users/{uid}
            return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(otherUid)
                  .get(),
              builder: (context, uSnap) {
                String uname = title;
                String uphoto = photo;
                if (uSnap.hasData && uSnap.data!.exists) {
                  final u = uSnap.data!.data()!;
                  final username = (u['username'] ?? '') as String;
                  final disp = (u['displayName'] ?? '') as String;
                  final lb = (u['letterboxdUsername'] ?? '') as String;
                  final purl = (u['photoURL'] ?? '') as String;
                  if (uname.isEmpty) {
                    uname = username.isNotEmpty
                        ? username
                        : (disp.isNotEmpty
                              ? disp
                              : (lb.isNotEmpty ? '@$lb' : ''));
                  }
                  if (uphoto.isEmpty) uphoto = purl;
                }

                return makeTile(uname, uphoto);
              },
            );
          },
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
