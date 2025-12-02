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

// ---- Local (device) profile films model & storage (no Firebase) ----
class LocalFilm {
  final String key; // optional external key or slug
  final String title;
  final int? year;
  final String? posterUrl;

  LocalFilm({
    required this.key,
    required this.title,
    this.year,
    this.posterUrl,
  });

  Map<String, dynamic> toJson() => {
    'key': key,
    'title': title,
    'year': year,
    'posterUrl': posterUrl,
  };

  static LocalFilm fromJson(Map<String, dynamic> j) => LocalFilm(
    key: (j['key'] ?? '') as String,
    title: (j['title'] ?? '') as String,
    year: (j['year'] is int)
        ? j['year'] as int
        : (j['year'] is String ? int.tryParse(j['year']) : null),
    posterUrl: (j['posterUrl'] ?? '') as String?,
  );
}



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
  final ValueNotifier<bool> _showGuideNotifier = ValueNotifier<bool>(false);
  final _svc = ChatService();
  final _ctrl = TextEditingController();
  StreamSubscription? _latestSub;

  @override
  void initState() {
    super.initState();
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    // Katılımcılar alanını garantiye al (kalıcılık için kritik)
    _svc.ensureChat(widget.chatId, myUid, widget.otherUid);

    // Oda açıkken yeni mesaj geldikçe okundu işaretle
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

    // İlk girişte de okundu bas
    _svc.markAsRead(widget.chatId, myUid);
    _checkAndShowGuide();
  }
  Future<void> _checkAndShowGuide() async {
    // Ekranın tamamen yüklenmesi için kısa bir süre bekle
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    try {
      final sp = await SharedPreferences.getInstance();
      // 'seen_watchlist_guide' anahtarı daha önce true yapılmış mı?
      final bool seen = sp.getBool('seen_watchlist_guide') ?? false;

      if (!seen) {
        // Gösterilmediyse şimdi göster
        _showGuideNotifier.value = true;
        // Ve bir daha göstermemek için kaydet
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

  Future<void> _openFilmPicker() async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Filmlerim',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Paylaşmak istediğin film profilinde olmalı',
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Expanded(
                child: Builder(
                  builder: (context) {
                    // Read only from in-memory cache filled by Profile screen
                    final merged = <Map<String, String>>[
                      ...UserShelfCache.fiveStar,
                      ...UserShelfCache.favorites,
                      ...UserShelfCache.watchlist,
                      ...UserShelfCache.disliked,
                    ];

                    // Deduplicate by lower-cased title to avoid repeats across shelves
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
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Film listesi boş. Profil ekranından senkronize et ve tekrar dene.',
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, i) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final title = items[i]['title'] ?? '';
                        final poster = items[i]['poster'] ?? '';
                        return ListTile(
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 40,
                              height: 60,
                              child: poster.isNotEmpty
                                  ? PosterImage(
                                      posterUrl: poster,
                                      title: title,
                                      fit: BoxFit.cover,
                                    )
                                  : const ColoredBox(
                                      color: Colors.black12,
                                      child: Center(child: Icon(Icons.movie)),
                                    ),
                            ),
                          ),
                          title: Text(title.isEmpty ? 'İsimsiz Film' : title),
                          onTap: () {
                            Navigator.of(context).pop(<String, String>{
                              'title': title,
                              'poster': poster,
                            });
                          },
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

    if (!mounted) return;
    if (result == null) return; // user cancelled

    final myUid = FirebaseAuth.instance.currentUser!.uid;
    final title = (result['title'] ?? '').trim();
    final poster = (result['poster'] ?? '').trim();
    final txt = title.isEmpty
        ? '🎬 Bir film önerisi'
        : '🎬 Film önerisi: $title';
    try {
      final fs = FirebaseFirestore.instance;
      final msgRef = await fs
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .add({
            'authorId': myUid,
            'text': txt,
            'type': 'movie',
            'movie': {'title': title, 'poster': poster},
            'createdAt': FieldValue.serverTimestamp(),
          });
      await fs.collection('chats').doc(widget.chatId).set({
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessageId': msgRef.id,
      }, SetOptions(merge: true));
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
      // BURASI DEĞİŞTİ: Column yerine Stack kullanıyoruz
      body: Stack(
        children: [
          // 1. KATMAN: Sohbet Arayüzü (Senin yazdığın Column kodu)
          Column(
            children: [
              // Mesajlar
              Expanded(
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
                      return const Center(child: Text('Henüz mesaj yok.'));
                    }
                    return ListView.builder(
                      reverse: true,
                      cacheExtent: 800,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final m = docs[i].data();
                        final author =
                            (m['authorId'] ?? m['from'] ?? '') as String;
                        final mine = author == myUid;
                        final text = (m['text'] ?? '') as String;
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
                                  bottomLeft: Radius.circular(
                                    mine ? 12 : 4,
                                  ), // kuyruk
                                  bottomRight: Radius.circular(
                                    mine ? 4 : 12,
                                  ), // kuyruk
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: mine
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (text.isNotEmpty)
                                    Text(
                                      text,
                                      style:
                                          const TextStyle(color: Colors.white),
                                    ),
                                  // Show movie poster if available
                                    Builder(
  builder: (_) {
    String posterUrl = '';
    String movieTitle = '';
    final movie = m['movie'];

    // Film verisini güvenli bir şekilde alıyoruz
    if (movie is Map) {
      final mm = Map<String, dynamic>.from(movie);
      posterUrl = (mm['poster'] ?? '').toString();
      movieTitle = (mm['title'] ?? '').toString();
    } else {
      // Eğer mesajda film verisi hiç yoksa gösterme
      return const SizedBox.shrink();
    }

    // Poster varsa resmi, yoksa İsim Kartını gösteriyoruz
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: posterUrl.isNotEmpty
          ? PosterImage( // Poster varsa bunu kullan
              posterUrl: posterUrl,
              title: movieTitle,
              width: 220,
              height: 330,
              fit: BoxFit.cover,
            )
          : Container( // Poster YOKSA bu kutuyu göster (Manuel Filmler İçin)
              width: 220,
              height: 330,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.movie_filter_outlined, size: 48, color: Colors.white54),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      movieTitle.isNotEmpty ? movieTitle : 'İsimsiz Film',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  },
),
                                   
                                  if (dt != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatTime(dt),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.white
                                            .withValues(alpha: 0.8),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              // Girdi alanı
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 8),
                              // Text input expands
                              Expanded(
                                child: TextField(
                                  controller: _ctrl,
                                  minLines: 1,
                                  maxLines: 4,
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _send(),
                                  decoration: const InputDecoration(
                                    hintText: 'Mesaj',
                                    isCollapsed: true,
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                              // Right-side actions inside the field
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Film paylaş icon
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    tooltip: 'Film paylaş',
                                    onPressed: _openFilmPicker,
                                    icon: Icon(
                                      Icons.local_movies_outlined,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Seçim Çarkı (Ortak Watchlist)
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    tooltip: 'Watchlist Çarkı',
                                    onPressed: () {
                                      showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        useSafeArea: true,
                                        builder: (_) => _WatchlistWheelSheet(
                                          chatId: widget.chatId,
                                          myUid: FirebaseAuth
                                              .instance.currentUser!.uid,
                                          otherUid: widget.otherUid,
                                        ),
                                      );
                                    },
                                    icon: Icon(
                                      Icons.donut_large,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Optional small send button; keep for convenience
                      CircleAvatar(
                        radius: 22,
                        backgroundColor:
                            Theme.of(context).colorScheme.primary,
                        child: IconButton(
                          onPressed: _send,
                          icon: const Icon(Icons.send, color: Colors.white),
                          tooltip: 'Gönder',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // 2. KATMAN: REHBER KARAKTER (Burası eksikti, ekledim)
          ValueListenableBuilder<bool>(
            valueListenable: _showGuideNotifier,
            builder: (context, isVisible, child) {
              if (!isVisible) return const SizedBox.shrink();

              return GuideCharacterOverlay(
                message:
                    "Beraber film izlemek için watchlist çarkını deneyebilirsin",
                isVisible: isVisible,
                onClose: () {
                  _showGuideNotifier.value = false;
                },
              );
            },
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

// --- Mutual Watchlist Sheet ---
class _MutualWatchlistSheet extends StatefulWidget {
  final String myUid;
  final String otherUid;
  const _MutualWatchlistSheet({required this.myUid, required this.otherUid});

  @override
  State<_MutualWatchlistSheet> createState() => _MutualWatchlistSheetState();
}

class _MutualWatchlistSheetState extends State<_MutualWatchlistSheet> {
  final _fs = FirebaseFirestore.instance;
  late Future<List<_MovieItem>> _loader;

  @override
  void initState() {
    super.initState();
    _loader = _load();
  }

  Future<List<_MovieItem>> _load() async {
    final a = await _fetchUserWatchlist(widget.myUid);
    final b = await _fetchUserWatchlist(widget.otherUid);

    // Intersect by normalized title
    final setB = b.map((m) => _norm((m['title'] ?? '').toString())).toSet();
    final out = <_MovieItem>[];
    for (final m in a) {
      final t = (m['title'] ?? '').toString();
      if (t.isEmpty) continue;
      if (setB.contains(_norm(t))) {
        out.add(
          _MovieItem(
            title: t,
            poster: (m['poster'] ?? m['posterUrl'] ?? '').toString(),
          ),
        );
      }
    }
    // If posters missing on A but present on B, patch
    if (out.any((x) => (x.poster ?? '').isEmpty)) {
      final mapB = {
        for (final m in b)
          _norm((m['title'] ?? '').toString()):
              (m['poster'] ?? m['posterUrl'] ?? '').toString(),
      };
      for (final it in out) {
        if ((it.poster ?? '').isEmpty) {
          final p = mapB[_norm(it.title)] ?? '';
          if (p.isNotEmpty) it.poster = p;
        }
      }
    }
    // Sort alphabetically
    out.sort((x, y) => x.title.toLowerCase().compareTo(y.title.toLowerCase()));
    return out;
  }

  Future<List<Map<String, dynamic>>> _fetchUserWatchlist(String uid) async {
    final res = <Map<String, dynamic>>[];
    // 1) Subcollection: /users/{uid}/watchlist
    try {
      final qs = await _fs
          .collection('users')
          .doc(uid)
          .collection('watchlist')
          .limit(500)
          .get();
      for (final d in qs.docs) {
        final m = d.data();
        final title = (m['title'] ?? m['name'] ?? '').toString();
        final poster = (m['poster'] ?? m['posterUrl'] ?? m['image'] ?? '')
            .toString();
        if (title.isNotEmpty) res.add({'title': title, 'poster': poster});
      }
    } catch (_) {}

    // 2) Nested: /users/{uid}/shelves/watchlist/items
    try {
      final items = await _fs
          .collection('users')
          .doc(uid)
          .collection('shelves')
          .doc('watchlist')
          .collection('items')
          .limit(500)
          .get();
      for (final d in items.docs) {
        final m = d.data();
        final title = (m['title'] ?? m['name'] ?? '').toString();
        final poster = (m['poster'] ?? m['posterUrl'] ?? m['image'] ?? '')
            .toString();
        if (title.isNotEmpty) res.add({'title': title, 'poster': poster});
      }
    } catch (_) {}

    // 3) Array field on user doc: users/{uid} -> watchlist: [ {title, poster} ] or [title]
    try {
      final u = await _fs.collection('users').doc(uid).get();
      if (u.exists) {
        final data = u.data() ?? {};
        final arr = data['watchlist'];
        if (arr is List) {
          for (final e in arr) {
            if (e is Map) {
              final title = (e['title'] ?? e['name'] ?? '').toString();
              final poster = (e['poster'] ?? e['posterUrl'] ?? e['image'] ?? '')
                  .toString();
              if (title.isNotEmpty) res.add({'title': title, 'poster': poster});
            } else if (e is String) {
              final title = e.trim();
              if (title.isNotEmpty) res.add({'title': title, 'poster': ''});
            }
          }
        }
      }
    } catch (_) {}

    // Deduplicate by normalized title (prefer ones with poster)
    final byKey = <String, Map<String, dynamic>>{};
    for (final m in res) {
      final key = _norm((m['title'] ?? '').toString());
      if (key.isEmpty) continue;
      if (!byKey.containsKey(key)) {
        byKey[key] = m;
      } else {
        final existing = byKey[key]!;
        final hasPoster = ((existing['poster'] ?? '').toString()).isNotEmpty;
        final newPoster = ((m['poster'] ?? '').toString()).isNotEmpty;
        if (!hasPoster && newPoster) { byKey[key] = m; }
      }
    }
    return byKey.values.toList();
  }

  static String _norm(String s) => s.toLowerCase().trim();

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
                    'Ortak Watchlist',
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
              child: FutureBuilder<List<_MovieItem>>(
                future: _loader,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final items = snap.data ?? const <_MovieItem>[];
                  if (items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Ortak watchlist bulunamadı.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: controller,
                    itemCount: items.length,
                    separatorBuilder: (_, i) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final it = items[i];
                      return ListTile(
                        leading: _PosterThumb(url: it.poster, title: it.title),
                        title: Text(
                          it.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
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

class _PosterThumb extends StatelessWidget {
  final String? url;
  final String title;
  const _PosterThumb({required this.url, required this.title});

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url!,
          width: 40,
          height: 60,
          fit: BoxFit.cover,
          errorBuilder: (_, error, stackTrace) => const SizedBox(
            width: 40,
            height: 60,
            child: ColoredBox(color: Colors.black12),
          ),
        ),
      );
    }
    return const SizedBox(
      width: 40,
      height: 60,
      child: ColoredBox(color: Colors.black12),
    );
  }
}

class _MovieItem {
  final String title;
  String? poster;
  _MovieItem({required this.title, this.poster});
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
  final _fs = FirebaseFirestore.instance;
  late Future<List<WatchlistMovie>> _loader;

  @override
  void initState() {
    super.initState();
    _loader = _loadWheelItems();
  }

  Future<List<WatchlistMovie>> _loadWheelItems() async {
    final a = await _fetchUserWatchlist(widget.myUid);
    final b = await _fetchUserWatchlist(widget.otherUid);

    final setB = b.map((m) => _norm((m['title'] ?? '').toString())).toSet();
    final out = <WatchlistMovie>[];
    for (final m in a) {
      final t = (m['title'] ?? '').toString();
      if (t.isEmpty) continue;
      if (setB.contains(_norm(t))) {
        out.add(
          WatchlistMovie(
            title: t,
            posterUrl: (m['poster'] ?? m['posterUrl'] ?? '').toString(),
          ),
        );
      }
    }
    if (out.any((x) => (x.posterUrl ?? '').isEmpty)) {
      final mapB = {
        for (final m in b)
          _norm((m['title'] ?? '').toString()):
              (m['poster'] ?? m['posterUrl'] ?? '').toString(),
      };
      for (var i = 0; i < out.length; i++) {
        final it = out[i];
        if ((it.posterUrl ?? '').isEmpty) {
          final p = mapB[_norm(it.title)] ?? '';
          if (p.isNotEmpty)
            out[i] = WatchlistMovie(title: it.title, posterUrl: p);
        }
      }
    }
    // If empty (no mutual), fall back to my list (so wheel still works)
    if (out.isEmpty) {
      return a
          .map(
            (m) => WatchlistMovie(
              title: (m['title'] ?? '').toString(),
              posterUrl: (m['poster'] ?? m['posterUrl'] ?? '').toString(),
            ),
          )
          .where((m) => m.title.isNotEmpty)
          .toList();
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _fetchUserWatchlist(String uid) async {
    final res = <Map<String, dynamic>>[];
    try {
      final qs = await _fs
          .collection('users')
          .doc(uid)
          .collection('watchlist')
          .limit(500)
          .get();
      for (final d in qs.docs) {
        final m = d.data();
        final title = (m['title'] ?? m['name'] ?? '').toString();
        final poster = (m['poster'] ?? m['posterUrl'] ?? m['image'] ?? '')
            .toString();
        if (title.isNotEmpty) res.add({'title': title, 'poster': poster});
      }
    } catch (_) {}

    try {
      final items = await _fs
          .collection('users')
          .doc(uid)
          .collection('shelves')
          .doc('watchlist')
          .collection('items')
          .limit(500)
          .get();
      for (final d in items.docs) {
        final m = d.data();
        final title = (m['title'] ?? m['name'] ?? '').toString();
        final poster = (m['poster'] ?? m['posterUrl'] ?? m['image'] ?? '')
            .toString();
        if (title.isNotEmpty) res.add({'title': title, 'poster': poster});
      }
    } catch (_) {}

    try {
      final u = await _fs.collection('users').doc(uid).get();
      if (u.exists) {
        final data = u.data() ?? {};
        final arr = data['watchlist'];
        if (arr is List) {
          for (final e in arr) {
            if (e is Map) {
              final title = (e['title'] ?? e['name'] ?? '').toString();
              final poster = (e['poster'] ?? e['posterUrl'] ?? e['image'] ?? '')
                  .toString();
              if (title.isNotEmpty) res.add({'title': title, 'poster': poster});
            } else if (e is String) {
              final title = e.trim();
              if (title.isNotEmpty) res.add({'title': title, 'poster': ''});
            }
          }
        }
      }
    } catch (_) {}

    // dedupe by normalized title
    final byKey = <String, Map<String, dynamic>>{};
    for (final m in res) {
      final key = _norm((m['title'] ?? '').toString());
      if (key.isEmpty) continue;
      if (!byKey.containsKey(key)) {
        byKey[key] = m;
      } else {
        final hasPoster = ((byKey[key]!['poster'] ?? '').toString()).isNotEmpty;
        final newPoster = ((m['poster'] ?? '').toString()).isNotEmpty;
        if (!hasPoster && newPoster) { byKey[key] = m; }
      }
    }
    return byKey.values.toList();
  }

  static String _norm(String s) => s.toLowerCase().trim();

  Future<void> _sendChosenToChat(WatchlistMovie m) async {
    try {
      final msgRef = await _fs
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .add({
            'authorId': widget.myUid,
            'text': m.title.isNotEmpty
                ? '🎯 Çark seçimi: ${m.title}'
                : '🎯 Çark seçimi',
            'type': 'movie',
            'movie': {'title': m.title, 'poster': m.posterUrl ?? ''},
            'createdAt': FieldValue.serverTimestamp(),
          });
      await _fs.collection('chats').doc(widget.chatId).set({
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMessageId': msgRef.id,
      }, SetOptions(merge: true));
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Seçilen film gönderildi: ${m.title}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gönderilemedi: $e')));
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
        return Column(
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
                            // Ask to send to chat
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
        );
      },
    );
  }
}