import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/services/chat_service.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:fluttergirdi/screens/profilescreen.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';

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

const _kLocalFilmsKey = 'profile_local_films';

Future<List<LocalFilm>> _loadLocalFilms() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_kLocalFilmsKey);
  if (raw == null || raw.isEmpty) return [];
  try {
    final list = (jsonDecode(raw) as List).cast<Map>();
    return list
        .map((e) => LocalFilm.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  } catch (_) {
    return [];
  }
}

Future<void> _saveLocalFilms(List<LocalFilm> films) async {
  final prefs = await SharedPreferences.getInstance();
  final s = jsonEncode(films.map((e) => e.toJson()).toList());
  await prefs.setString(_kLocalFilmsKey, s);
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
                      separatorBuilder: (_, __) => const Divider(height: 1),
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
        : '🎬 Film önerisi: ' + title;
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

  Future<void> _addLocalFilmDialog() async {
    final tCtrl = TextEditingController();
    final yCtrl = TextEditingController();
    final pCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Film ekle'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: tCtrl,
                    decoration: const InputDecoration(labelText: 'Başlık'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Gerekli' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: yCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Yıl (opsiyonel)',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: pCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Poster URL (opsiyonel)',
                    ),
                    keyboardType: TextInputType.url,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final title = tCtrl.text.trim();
                final year = int.tryParse(yCtrl.text.trim());
                final poster = pCtrl.text.trim().isEmpty
                    ? null
                    : pCtrl.text.trim();
                final films = await _loadLocalFilms();
                films.add(
                  LocalFilm(
                    key: title.toLowerCase(),
                    title: title,
                    year: year,
                    posterUrl: poster,
                  ),
                );
                await _saveLocalFilms(films);
                if (context.mounted) Navigator.pop(ctx);
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
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
        ),
      ),
      body: Column(
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
                    final author = (m['authorId'] ?? m['from'] ?? '') as String;
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
                                  style: const TextStyle(color: Colors.white),
                                ),
                              // Show movie poster if available
                              Builder(
                                builder: (_) {
                                  String posterUrl = '';
                                  final movie = m['movie'];
                                  if (movie is Map) {
                                    final mm = Map<String, dynamic>.from(movie);
                                    posterUrl =
                                        (mm['poster'] ?? '') as String? ?? '';
                                  }
                                  if (posterUrl.isEmpty)
                                    return const SizedBox.shrink();
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: PosterImage(
                                      posterUrl: posterUrl,
                                      title: (m['movie'] is Map)
                                          ? (Map<String, dynamic>.from(
                                                      m['movie'],
                                                    )['title']
                                                    as String? ??
                                                '')
                                          : '',
                                      width: 220,
                                      height: 330,
                                      fit: BoxFit.cover,
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
                                    color: Colors.white.withValues(alpha: 0.8),
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
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 6.0,
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Film paylaş',
                    onPressed: _openFilmPicker,
                    icon: const Icon(Icons.local_movies_outlined),
                  ),
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
