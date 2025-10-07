import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/screens/settings_page.dart';
import 'package:fluttergirdi/screens/search_profiles_screen.dart';
import 'package:fluttergirdi/screens/profilescreen.dart'; // for UserShelfCache
import 'package:fluttergirdi/services/feed_service.dart';
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
  Map<String, String>? _selectedMovie; // { 'title': ..., 'poster': ... }

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

  Future<void> _pickMovie() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

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
                      if (seen.add(key))
                        items.add({
                          'title': t,
                          'poster': (m['poster'] ?? '').toString(),
                        });
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
                          leading: CircleAvatar(
                            backgroundImage: poster.isNotEmpty
                                ? NetworkImage(poster)
                                : null,
                            child: poster.isEmpty
                                ? const Icon(Icons.movie)
                                : null,
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
    if (result != null) {
      setState(() {
        _selectedMovie = result;
      });
      // Metni otomatik doldur (başlık), kullanıcı isterse düzenler
      final t = result['title'] ?? '';
      if (t.isNotEmpty) {
        final existing = _controller.text.trim();
        _controller.text = existing.isEmpty ? '🎬 $t' : existing;
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );
        _focusNode.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 160,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '/Cinematch',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
        title: Text(
          'Feed',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        iconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.onSurface,
        ),
        actionsIconTheme: IconThemeData(
          color: Theme.of(context).colorScheme.onSurface,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SearchProfilesScreen()),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: Theme.of(context).colorScheme.primary,
        backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
        child: _initialLoading
            ? Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              )
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
                          selectedMovie: _selectedMovie,
                          onPickMovie: _pickMovie,
                          onClearMovie: () {
                            setState(() => _selectedMovie = null);
                          },
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
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(
                            Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    );
                  }
                  final d = _posts[i - 1];
                  final m = d.data() ?? const <String, dynamic>{};
                  final createdAt = (m['createdAt'] as Timestamp?);
                  final timeLabel = createdAt == null
                      ? ''
                      : _timeAgo(createdAt.toDate());
                  final movieTitle =
                      ((m['movieTitle'] ?? (m['movie']?['title'])) ?? '')
                          .toString();
                  final moviePoster =
                      ((m['moviePoster'] ??
                                  (m['movie']?['poster'] ??
                                      m['movie']?['posterUrl'])) ??
                              '')
                          .toString();
                  return PostTile(
                    postId: d.id,
                    authorId: (m['authorId'] ?? '') as String,
                    displayName: (m['displayName'] ?? '') as String,
                    handle: (m['handle'] ?? '') as String,
                    photoURL: (m['photoURL'] ?? '') as String,
                    timeLabel: timeLabel,
                    movieTitle: movieTitle.isEmpty ? null : movieTitle,
                    moviePoster: moviePoster.isEmpty ? null : moviePoster,
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
    final data = {
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
    };
    if (_selectedMovie != null) {
      final title = _selectedMovie!['title'] ?? '';
      final poster = _selectedMovie!['poster'] ?? '';
      if (title.isNotEmpty) data['movieTitle'] = title;
      if (poster.isNotEmpty) data['moviePoster'] = poster;
    }
    await docRef.set(data);

    // Clear selected movie after posting
    if (mounted) {
      setState(() {
        _selectedMovie = null;
      });
    }

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
    await FeedService().toggleLike(postId: postId, like: like);
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
  final Map<String, String>? selectedMovie;
  final VoidCallback onPickMovie;
  final VoidCallback onClearMovie;

  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.maxChars,
    required this.selectedMovie,
    required this.onPickMovie,
    required this.onClearMovie,
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
                    if (selectedMovie != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: cs.outlineVariant),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            if ((selectedMovie!['poster'] ?? '').isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  selectedMovie!['poster']!,
                                  width: 44,
                                  height: 66,
                                  fit: BoxFit.cover,
                                ),
                              )
                            else
                              const Icon(Icons.movie, size: 40),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                selectedMovie!['title'] ?? 'Seçili film',
                                style: theme.textTheme.titleSmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              onPressed: onClearMovie,
                              icon: const Icon(Icons.close),
                              tooltip: 'Kaldır',
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.image_outlined),
                          tooltip: 'Medya',
                          color: cs.onSurfaceVariant,
                        ),
                        IconButton(
                          onPressed: onPickMovie,
                          icon: const Icon(Icons.movie),
                          tooltip: 'Film seç',
                          color: cs.onSurfaceVariant,
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
