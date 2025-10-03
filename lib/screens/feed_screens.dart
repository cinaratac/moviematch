import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/screens/settings_page.dart';
import 'package:fluttergirdi/widgets/post_tile.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  static const int _maxChars = 280;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _listController = ScrollController();
  final Map<String, String> _lbCache = {};
  String _lbFor(String uid, String handle) {
    // if post already carries an @lb handle, use it
    if (handle.isNotEmpty && handle.startsWith('@')) return handle;
    // serve from cache if present
    final cached = _lbCache[uid];
    if (cached != null && cached.isNotEmpty) return '@$cached';
    // fire-and-forget fetch to hydrate cache (avoid per-item StreamBuilder)
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get()
        .then((d) {
          final lb = (d.data()?['letterboxdUsername'] ?? '').toString().trim();
          if (lb.isNotEmpty && _lbCache[uid] != lb && mounted) {
            setState(() => _lbCache[uid] = lb);
          }
        })
        .catchError((_) {});
    return '';
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Feed'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'settings') {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Ayarlar'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('posts')
            .orderBy('createdAt', descending: true)
            .limit(200)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return const Center(child: Text('Gönderiler yüklenemedi'));
          }
          final docs = snap.data?.docs ?? const [];
          // Build a single scrolling list where index 0 is the composer
          return ListView.separated(
            controller: _listController,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: docs.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Column(
                  children: [
                    _Composer(
                      controller: _controller,
                      focusNode: _focusNode,
                      maxChars: _maxChars,
                      onSend: (text) async {
                        await _createPost(text);
                        _controller.clear();
                        _focusNode.requestFocus();
                      },
                    ),
                    const Divider(height: 1),
                  ],
                );
              }
              final d = docs[i - 1];
              final m = d.data();
              final createdAt = (m['createdAt'] as Timestamp?);
              final timeLabel = createdAt == null
                  ? ''
                  : _timeAgo(createdAt.toDate());
              return PostTile(
                postId: d.id,
                authorId: (m['authorId'] ?? '') as String,
                displayName: (m['displayName'] ?? '') as String,
                handle: _lbFor(
                  (m['authorId'] ?? '') as String,
                  (m['handle'] ?? '') as String,
                ),
                photoURL: (m['photoURL'] ?? '') as String,
                timeLabel: timeLabel,
                text: (m['text'] ?? '') as String,
                likeCount: (m['likeCount'] ?? 0) is int
                    ? m['likeCount'] as int
                    : ((m['likeCount'] ?? 0) as num).toInt(),
                replyCount: (m['replyCount'] ?? 0) is int
                    ? m['replyCount'] as int
                    : ((m['replyCount'] ?? 0) as num).toInt(),
                repostCount: (m['repostCount'] ?? 0) is int
                    ? m['repostCount'] as int
                    : ((m['repostCount'] ?? 0) as num).toInt(),
                onToggleLike: _toggleLike,
                onStartChat: _startChat,
                onFollow: _follow,
                onReport: _reportPost,
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _createPost(String text) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Fetch letterboxdUsername from users/{uid}
    String lb = '';
    try {
      final u = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      lb = (u.data()?['letterboxdUsername'] ?? '').toString().trim();
    } catch (_) {}

    final doc = FirebaseFirestore.instance.collection('posts').doc();
    await doc.set({
      'authorId': user.uid,
      'displayName': user.displayName ?? '',
      'handle': lb.isNotEmpty ? '@$lb' : '',
      'photoURL': user.photoURL ?? '',
      'text': text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'likeCount': 0,
      'replyCount': 0,
      'repostCount': 0,
      'visibility': 'public',
    });
  }

  static String _timeAgo(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}g';
    final months = diff.inDays ~/ 30;
    if (months < 12) return '${months}a';
    final years = diff.inDays ~/ 365;
    return '${years}y';
  }

  Future<void> _toggleLike(String postId, bool like) async {
    final fs = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final postRef = fs.collection('posts').doc(postId);
    final likeRef = postRef.collection('likes').doc(uid);
    final batch = fs.batch();
    if (like) {
      batch.set(likeRef, {'createdAt': FieldValue.serverTimestamp()});
      batch.update(postRef, {'likeCount': FieldValue.increment(1)});
    } else {
      batch.delete(likeRef);
      batch.update(postRef, {'likeCount': FieldValue.increment(-1)});
    }
    await batch.commit();
  }

  String _pairIdOf(String a, String b) =>
      (a.compareTo(b) < 0) ? '${a}_$b' : '${b}_$a';

  Future<void> _startChat(String otherUid) async {
    final fs = FirebaseFirestore.instance;
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null || me == otherUid) return;
    final chatId = _pairIdOf(me, otherUid);
    final chatRef = fs.collection('chats').doc(chatId);
    await chatRef.set({
      'participants': [me, otherUid],
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sohbet hazır')));
    }
  }

  Future<void> _follow(String otherUid) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null || me == otherUid) return;
    final fs = FirebaseFirestore.instance;
    await fs
        .collection('users')
        .doc(me)
        .collection('following')
        .doc(otherUid)
        .set({
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> _reportPost(String postId) async {
    final me = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
    await FirebaseFirestore.instance.collection('reports').add({
      'type': 'post',
      'postId': postId,
      'by': me,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _listController.dispose();
    super.dispose();
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final int maxChars;
  final void Function(String)? onSend;

  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.maxChars,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final text = value.text;
        final remaining = maxChars - text.characters.length;
        final isEmpty = text.trim().isEmpty;

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(radius: 20, child: Icon(Icons.person)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: controller,
                      focusNode: focusNode,
                      maxLines: null,
                      minLines: 1,
                      decoration: const InputDecoration(
                        hintText: 'Neler oluyor?',
                        border: InputBorder.none,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.image_outlined),
                          tooltip: 'Medya',
                        ),
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.poll_outlined),
                          tooltip: 'Anket',
                        ),
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.emoji_emotions_outlined),
                          tooltip: 'Emoji',
                        ),
                        const Spacer(),
                        if (remaining <= 40)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Text(
                              remaining.toString(),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: remaining < 0
                                    ? cs.error
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        FilledButton(
                          onPressed: isEmpty || remaining < 0
                              ? null
                              : () => onSend?.call(text),
                          child: const Text('Gönder'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
