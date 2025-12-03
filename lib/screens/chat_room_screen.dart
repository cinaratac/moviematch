import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/services/chat_service.dart';
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
  final ValueNotifier<bool> _showGuideNotifier = ValueNotifier<bool>(false);
  final _svc = ChatService();
  final _ctrl = TextEditingController();
  StreamSubscription? _latestSub;

  @override
  void initState() {
    super.initState();
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    _svc.ensureChat(widget.chatId, myUid, widget.otherUid);

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

    _svc.markAsRead(widget.chatId, myUid);
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
      _svc.deleteIfEmpty(widget.chatId);
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

  // ÖNCEKİ DÜZELTİLMİŞ FİLM SEÇİCİ (Aynen korundu)
  Future<void> _openFilmPicker() async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent, // Şeffaf arka plan
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
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Filmlerim',
                  style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Expanded(
                child: Builder(
                  builder: (context) {
                    final merged = <Map<String, String>>[
                      ...UserShelfCache.fiveStar,
                      ...UserShelfCache.favorites,
                      ...UserShelfCache.watchlist,
                      ...UserShelfCache.disliked,
                    ];
                    final seen = <String>{};
                    final items = <Map<String, String>>[];
                    for (final m in merged) {
                      final t = (m['title'] ?? '').trim();
                      if (t.isEmpty) continue;
                      final key = t.toLowerCase();
                      if (seen.add(key)) {
                        items.add({
                          'title': t,
                          'poster': (m['poster'] ?? '').toString(),
                        });
                      }
                    }

                    if (items.isEmpty) {
                      return const Center(
                        child: Text(
                          'Listen boş. Profilinden senkronize et.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: items.length,
                      separatorBuilder: (_, i) => const Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: Colors.white10,
                      ),
                      itemBuilder: (_, i) {
                        final title = items[i]['title'] ?? '';
                        final poster = items[i]['poster'] ?? '';
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 4),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 45,
                              height: 68,
                              child: poster.isNotEmpty
                                  ? PosterImage(
                                      posterUrl: poster,
                                      title: title,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      color: Colors.grey.shade800,
                                      child: const Icon(Icons.movie,
                                          color: Colors.white54),
                                    ),
                            ),
                          ),
                          title: Text(
                            title.isEmpty ? 'İsimsiz Film' : title,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
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
    const txt ="";
       

    try {
      await _svc.send(
        widget.chatId,
        myUid,
        txt,
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
          otherUid: widget.otherUid,
          initialTitle: widget.otherTitle,
        ),
        elevation: 0,
        // DEĞİŞİKLİK: AppBar arka planını tema ile uyumlu hale getir
        backgroundColor: Theme.of(context).scaffoldBackgroundColor, 
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Container(
                  // DEĞİŞİKLİK: Chat body arka planını tema ile uyumlu hale getir
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

                          return _buildMessageBubble(
                            context,
                            text: text,
                            movie: m['movie'],
                            isMine: mine,
                            timestamp: dt,
                          );
                        },
                      );
                    },
                  ),
                ),
              ),

              // --- MESAJ GÖNDERME BARI (Dokunulmadı) ---
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
                            color: const Color(0xFF1E1E1E), // Hafif gri
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
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontFamily: null, // Özel fontu devre dışı bırakıp sistem fontunu kullanır
                                    ),
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

          // REHBER KARAKTER
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

  Widget _buildMessageBubble(
    BuildContext context, {
    required String text,
    dynamic movie,
    required bool isMine,
    DateTime? timestamp,
  }) {
    // Film verisini ayıkla
    String posterUrl = '';
    String movieTitle = '';
    bool hasMovie = false;
    if (movie is Map) {
      final mm = Map<String, dynamic>.from(movie);
      posterUrl = (mm['poster'] ?? '').toString();
      movieTitle = (mm['title'] ?? '').toString();
      hasMovie = true;
    }

    // Renk paleti ve sabitler
    final myGradient = LinearGradient(
      colors: [
        Theme.of(context).colorScheme.primary,
        Theme.of(context).colorScheme.primary.withOpacity(0.8),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    final otherColor = const Color(0xFF2C2C2E);

    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.75;
    const paddingHorizontal = 24.0; // İç padding (12 + 12)
    final maxContentWidth = maxBubbleWidth - paddingHorizontal;
    const movieCardWidth = 200.0;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        constraints: BoxConstraints(
          maxWidth: maxBubbleWidth, // Maksimum genişliği korur
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
          // ÇÖZÜM: IntrinsicWidth, Column'u içeriği kadar (yatayda) küçülmeye zorlar.
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min, // Dikeyde küçülme
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. FİLM KARTI
                if (hasMovie)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    width: movieCardWidth, // Sabit genişlik
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

                // 2. MESAJ METNİ
                if (text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    // ConstrainedBox, uzun metnin alt satıra geçmesini sağlar, 
                    // IntrinsicWidth'in yanlış hesap yapmasını engeller.
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        // Eğer film varsa, metin film genişliği kadar yayılır. Yoksa maxContentWidth kadar.
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

                // 3. SAAT BİLGİSİ
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
      ),
    );
  }
}

class _ChatAppBarTitle extends StatelessWidget {
  final String otherUid;
  final String? initialTitle;
  
  const _ChatAppBarTitle({
    required this.otherUid,
    this.initialTitle,
  });

  @override
  Widget build(BuildContext context) {
    // SADECE users/{otherUid} dokümanını dinliyoruz.
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

        // UI Bileşeni
        return InkWell(
          onTap: () {
            // PublicProfileScreen'e navigasyon
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

// --- Watchlist Wheel Sheet ---
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
  final _chatSvc = ChatService(); // Chat servisi mesaj göndermek için
  final _watchlistSvc = WatchlistService.instance; // Yeni watchlist servisi

  late Future<List<WatchlistMovie>> _loader;

  @override
  void initState() {
    super.initState();
    // Veri yükleme mantığı servise taşındı
    _loader = _watchlistSvc.loadSharedWatchlist(widget.myUid, widget.otherUid);
  }

  Future<void> _sendChosenToChat(WatchlistMovie m) async {
    try {
      final myUid = FirebaseAuth.instance.currentUser!.uid;
      // Chat servisi kullanılarak mesaj gönderildi
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