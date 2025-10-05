import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/screens/settings_page.dart';
import 'package:fluttergirdi/widgets/post_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static const int _pageSize = 20;
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  List<DocumentSnapshot<Map<String, dynamic>>> _posts = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;

  @override
  void initState() {
    super.initState();
    _listController.addListener(_onScroll);
    _loadInitial();
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore) return;
    if (!_listController.hasClients) return;
    final pos = _listController.position;
    // When the user is within 2 screen-heights of the bottom, load more
    if (pos.pixels > pos.maxScrollExtent - (pos.viewportDimension * 2)) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _initialLoading = true;
      _hasMore = true;
      _posts.clear();
      _lastDoc = null;
    });

    final base = FirebaseFirestore.instance
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(_pageSize);

    // Phase 1: try cache for fast first paint
    try {
      final cacheQs = await base.get(const GetOptions(source: Source.cache));
      final cacheDocs = cacheQs.docs;
      if (cacheDocs.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _posts = List<DocumentSnapshot<Map<String, dynamic>>>.from(cacheDocs);
          _lastDoc = cacheDocs.isNotEmpty ? cacheDocs.last : null;
          _hasMore = cacheDocs.length == _pageSize;
          _initialLoading = false; // show cached UI immediately
        });
      }
    } catch (_) {}

    // Phase 2: fetch fresh from server and overwrite
    try {
      final serverQs = await base.get(const GetOptions(source: Source.server));
      final serverDocs = serverQs.docs;
      if (!mounted) return;
      setState(() {
        _posts = List<DocumentSnapshot<Map<String, dynamic>>>.from(serverDocs);
        _lastDoc = serverDocs.isNotEmpty ? serverDocs.last : null;
        _hasMore = serverDocs.length == _pageSize;
        _initialLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _initialLoading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    if (_lastDoc == null) return;
    setState(() => _loadingMore = true);
    try {
      final q = FirebaseFirestore.instance
          .collection('posts')
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastDoc!)
          .limit(_pageSize);
      final qs = await q.get(const GetOptions(source: Source.server));
      final docs = qs.docs;
      setState(() {
        _posts.addAll(docs);
        _lastDoc = docs.isNotEmpty ? docs.last : _lastDoc;
        _hasMore = docs.length == _pageSize;
      });
    } catch (_) {
      // fallback to cache for pagination if available
      try {
        final q = FirebaseFirestore.instance
            .collection('posts')
            .orderBy('createdAt', descending: true)
            .startAfterDocument(_lastDoc!)
            .limit(_pageSize);
        final qs = await q.get(const GetOptions(source: Source.cache));
        final docs = qs.docs;
        if (docs.isNotEmpty) {
          setState(() {
            _posts.addAll(docs);
            _lastDoc = docs.last;
            _hasMore = docs.length == _pageSize;
          });
        }
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _refresh() async {
    await _loadInitial();
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
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _initialLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView.separated(
                controller: _listController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _posts.length + 1 + (_loadingMore ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  // Composer at index 0
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
                  // Loading indicator at the very end when paging
                  if (_loadingMore && i == _posts.length + 1) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final d = _posts[i - 1];
                  final m = d.data() ?? const <String, dynamic>{};
                  final createdAt = (m['createdAt'] as Timestamp?);
                  final timeLabel = createdAt == null
                      ? ''
                      : _timeAgo(createdAt.toDate());
                  return PostTile(
                    postId: d.id,
                    authorId: (m['authorId'] ?? '') as String,
                    displayName: (m['displayName'] ?? '') as String,
                    handle: (m['handle'] ?? '') as String,
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
                    onStartChat: (String _) async {},
                    onFollow: _follow,
                    onReport: _reportPost,
                  );
                },
              ),
      ),
    );
  }

  Future<void> _createPost(String text) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    String lb = '';
    try {
      final sp = await SharedPreferences.getInstance();
      lb = (sp.getString('lb_username_${user.uid}') ?? '').trim();
    } catch (_) {}

    final docRef = FirebaseFirestore.instance.collection('posts').doc();
    await docRef.set({
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

    // Read only the new post (server) and prepend without reloading the whole list
    try {
      final snap = await docRef.get(const GetOptions(source: Source.server));
      if (!mounted) return;
      setState(() {
        _posts.insert(0, snap);
        // _lastDoc değişmedi; sayfalama mantığı korunur
      });
    } catch (_) {
      // Server başarısızsa, minimal yerel placeholder eklemek istersen burada ekleyebilirsin.
    }
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
    final likeRef = fs
        .collection('posts')
        .doc(postId)
        .collection('likes')
        .doc(uid);
    if (like) {
      await likeRef.set({
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      await likeRef.delete();
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
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;
    final reports = FirebaseFirestore.instance.collection('reports');
    final docId = '${postId}_$me';
    await reports.doc(docId).set({
      'type': 'post',
      'postId': postId,
      'by': me,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _listController.removeListener(_onScroll);
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
