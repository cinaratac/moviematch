import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/screens/settings_page.dart';
import 'package:fluttergirdi/screens/search_profiles_screen.dart';
import 'package:fluttergirdi/screens/profilescreen.dart'; // for UserShelfCache
import 'package:fluttergirdi/services/feed_service.dart';
import 'package:fluttergirdi/widgets/post_tile.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';
import 'package:fluttergirdi/widgets/recommended_users.dart';
import 'package:fluttergirdi/widgets/green_characters.dart';
import 'package:fluttergirdi/widgets/notifications.dart';

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

  static const int _pageSize = 15;
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  List<DocumentSnapshot<Map<String, dynamic>>> _posts = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  Map<String, String>? _selectedMovie;

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
    if (pos.pixels > pos.maxScrollExtent - (pos.viewportDimension * 1.5)) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    if (_posts.isEmpty && mounted) {
      setState(() {
        _initialLoading = true;
      });
    }
    
    _hasMore = true;
    _lastDoc = null;

    final base = FirebaseFirestore.instance
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(_pageSize);

    try {
      final cacheQs = await base.get(const GetOptions(source: Source.cache));
      final cacheDocs = cacheQs.docs;
      if (cacheDocs.isNotEmpty && mounted) {
        setState(() {
          _posts = List<DocumentSnapshot<Map<String, dynamic>>>.from(cacheDocs);
          _lastDoc = cacheDocs.last;
          _hasMore = cacheDocs.length == _pageSize;
          _initialLoading = false;
        });
      }
    } catch (_) {}

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
      if (mounted) setState(() => _initialLoading = false);
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

    if (!mounted) return;

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
                child: items.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Listen boş. Profilinden senkronize et.',
                          ),
                        ),
                      )
                    : ListView.separated(
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
                            title: Text(title),
                            onTap: () {
                              Navigator.of(ctx).pop(items[i]);
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

    if (result != null && mounted) {
      setState(() {
        _selectedMovie = result;
      });
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

  Future<void> _createPost(String text) async {
    await FeedService.instance.createPost(
      text: text,
      movie: _selectedMovie,
    );

    if (mounted) {
      setState(() {
        _selectedMovie = null;
      });
      _controller.clear();
      _focusNode.unfocus();
      _refresh();
    }
  }

  static String _timeAgo(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}g';
    return '${diff.inDays ~/ 30}a';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          toolbarHeight: 60,
          titleSpacing: 12,
          title: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SearchProfilesScreen(),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Icon(Icons.search,
                          size: 20,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 5),
                      Text(
                        'Kullanıcı Adı Ara',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          actions: [
            const NotificationsButton(),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Ayarlar',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              },
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(44),
            child: Column(
              children: [
                TabBar(
                  isScrollable: false,
                  labelColor: Theme.of(context).colorScheme.onSurface,
                  unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  indicatorColor: Theme.of(context).colorScheme.primary,
                  tabs: const [
                    Tab(text: 'Popüler'),
                    Tab(text: 'Takip Edilenler'),
                  ],
                ),
                const Divider(height: 1),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            // 1) Popüler Akış
            RefreshIndicator(
              onRefresh: _refresh,
              child: _initialLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      controller: _listController,
                      cacheExtent: 500, 
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _posts.length + (_loadingMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        if (_loadingMore && i == _posts.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final d = _posts[i];
                        final m = d.data() ?? {};
                        
                        final createdAt = (m['createdAt'] as Timestamp?);
                        final timeLabel = createdAt == null
                            ? ''
                            : _timeAgo(createdAt.toDate());
                        
                        final movieTitle = ((m['movieTitle'] ?? (m['movie']?['title'])) ?? '').toString();
                        final moviePoster = ((m['moviePoster'] ?? (m['movie']?['poster'] ?? m['movie']?['posterUrl'])) ?? '').toString();

                        final postWidget = PostTile(
                          postId: d.id,
                          authorId: (m['authorId'] ?? '') as String,
                          displayName: (m['displayName'] ?? '') as String,
                          handle: (m['handle'] ?? '') as String,
                          photoURL: (m['photoURL'] ?? '') as String,
                          timeLabel: timeLabel,
                          movieTitle: movieTitle.isEmpty ? null : movieTitle,
                          moviePoster: moviePoster.isEmpty ? null : moviePoster,
                          text: (m['text'] ?? '') as String,
                          likeCount: ((m['likeCount'] ?? 0) as num).toInt(),
                          replyCount: ((m['replyCount'] ?? 0) as num).toInt(),
                          repostCount: ((m['repostCount'] ?? 0) as num).toInt(),
                          onToggleLike: (pid, like) => FeedService().toggleLike(postId: pid, like: like),
                          onStartChat: (String _) async {},
                          onFollow: (uid) async {
                             await FeedService().followUser(uid);
                             await FeedService().notifyFollow(toUid: uid);
                          },
                          onReport: (pid) => FeedService().reportPost(pid),
                        );

                        if (i == 3) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              postWidget,
                              const SizedBox(height: 12),
                              const RecommendedUsers(
                                title: 'Önerilen kullanıcılar',
                                limit: 10,
                              ),
                            ],
                          );
                        }
                        return postWidget;
                      },
                    ),
            ),

            // 2) Takip Edilenler Akışı
            const _FollowingFeed(),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          heroTag: 'feed_compose_fab', 
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (ctx) => _ComposePostPage(
                  controller: _controller,
                  focusNode: _focusNode,
                  maxChars: _maxChars,
                  selectedMovie: _selectedMovie,
                  onPickMovie: _pickMovie,
                  onClearMovie: () => setState(() => _selectedMovie = null),
                  onSend: (text) async {
                    await _createPost(text);
                    if (mounted) Navigator.of(context).pop();
                  },
                ),
              ),
            );
          },
          child: const Icon(Icons.edit_note_rounded),
        ),
      ),
    );
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

class _FollowingFeed extends StatefulWidget {
  const _FollowingFeed({super.key});

  @override
  State<_FollowingFeed> createState() => _FollowingFeedState();
}

class _FollowingFeedState extends State<_FollowingFeed> with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  List<DocumentSnapshot<Map<String, dynamic>>> _items = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_items.isEmpty) {
      setState(() => _loading = true);
    }
    
    try {
      final me = FirebaseAuth.instance.currentUser?.uid;
      if (me == null) {
        if(mounted) setState(() { _items = []; _loading = false; });
        return;
      }

      final followingQs = await FirebaseFirestore.instance
          .collection('users')
          .doc(me)
          .collection('following')
          .orderBy('createdAt', descending: true)
          .limit(30)
          .get();
      
      final uids = followingQs.docs.map((d) => d.id).toList();

      if (uids.isEmpty) {
        if(mounted) setState(() { _items = []; _loading = false; });
        return;
      }

      final List<DocumentSnapshot<Map<String, dynamic>>> acc = [];
      final processUids = uids.take(15).toList();

      for (var i = 0; i < processUids.length; i += 10) {
        final chunk = processUids.sublist(
          i,
          i + 10 > processUids.length ? processUids.length : i + 10,
        );
        
        final qs = await FirebaseFirestore.instance
            .collection('posts')
            .where('authorId', whereIn: chunk)
            .orderBy('createdAt', descending: true)
            .limit(5)
            .get(const GetOptions(source: Source.server));
            
        acc.addAll(qs.docs);
      }

      acc.sort((a, b) {
        final ta = (a.data()?['createdAt'] as Timestamp?)?.toDate();
        final tb = (b.data()?['createdAt'] as Timestamp?)?.toDate();
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });

      if (mounted) {
        setState(() {
          _items = acc;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const GreenEyesCharacter(size: 150),
                    const SizedBox(height: 16),
                    Text(
                      'Birilerini takip etmelisin',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        cacheExtent: 500, 
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final d = _items[i];
          final m = d.data() ?? {};
          
          final createdAt = (m['createdAt'] as Timestamp?);
          final timeLabel = createdAt == null ? '' : _FeedPageState._timeAgo(createdAt.toDate());
              
          final movieTitle = ((m['movieTitle'] ?? (m['movie']?['title'])) ?? '').toString();
          final moviePoster = ((m['moviePoster'] ?? (m['movie']?['poster'] ?? m['movie']?['posterUrl'])) ?? '').toString();

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
            likeCount: ((m['likeCount'] ?? 0) as num).toInt(),
            replyCount: ((m['replyCount'] ?? 0) as num).toInt(),
            repostCount: ((m['repostCount'] ?? 0) as num).toInt(),
            onToggleLike: (pid, like) => FeedService().toggleLike(postId: pid, like: like),
            onStartChat: (String _) async {},
            onFollow: (uid) async {
               await FeedService().followUser(uid);
               await FeedService().notifyFollow(toUid: uid);
            },
            onReport: (pid) => FeedService().reportPost(pid),
          );
        },
      ),
    );
  }
}

// --- ESKİ TASARIM (GERİ GETİRİLDİ) ---
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
                                child: PosterImage(
                                  posterUrl: selectedMovie!['poster']!,
                                  title: selectedMovie!['title'],
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

class _ComposePostPage extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final int maxChars;
  final Map<String, String>? selectedMovie;
  final VoidCallback onPickMovie;
  final VoidCallback onClearMovie;
  final void Function(String) onSend;

  const _ComposePostPage({
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
    return Scaffold(
      appBar: AppBar(title: const Text('Yeni Gönderi')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _Composer(
            controller: controller,
            focusNode: focusNode,
            maxChars: maxChars,
            selectedMovie: selectedMovie,
            onPickMovie: onPickMovie,
            onClearMovie: onClearMovie,
            onSend: onSend,
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}