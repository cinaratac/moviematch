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

  static const int _pageSize = 20;
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  
  List<DocumentSnapshot<Map<String, dynamic>>> _posts = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  
  // YENİ: Yazarların önbelleği (ID -> İsim, Foto, Handle)
  final Map<String, Map<String, String>> _authorCache = {};

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
    if (pos.pixels > pos.maxScrollExtent - (pos.viewportDimension * 2)) {
      _loadMore();
    }
  }

  // --- YENİ FONKSİYON: Yazarları Topluca Çek ---
  Future<void> _fetchAuthorsForPosts(List<DocumentSnapshot> posts) async {
    final uidsToFetch = <String>{};
    
    // 1. Önbellekte olmayan yazarları bul
    for (var doc in posts) {
      final data = doc.data() as Map<String, dynamic>?;
      final uid = data?['authorId'] as String?;
      if (uid != null && uid.isNotEmpty && !_authorCache.containsKey(uid)) {
        uidsToFetch.add(uid);
      }
    }

    if (uidsToFetch.isEmpty) return;

    // 2. Firestore 'whereIn' limiti 10 olduğu için parçalara böl
    final chunks = <List<String>>[];
    final list = uidsToFetch.toList();
    for (var i = 0; i < list.length; i += 10) {
      chunks.add(list.sublist(i, i + 10 > list.length ? list.length : i + 10));
    }

    // 3. Her parça için verileri çek ve cache'e at
    for (var chunk in chunks) {
      try {
        final qs = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get(const GetOptions(source: Source.serverAndCache));
        
        for (var uDoc in qs.docs) {
          final d = uDoc.data();
          final name = (d['displayName'] ?? '').toString();
          final user = (d['username'] ?? '').toString();
          final lb = (d['letterboxdUsername'] ?? '').toString();
          final photo = (d['photoURL'] ?? '').toString();
          
          String handle = '';
          if (user.isNotEmpty) handle = '@$user';
          else if (lb.isNotEmpty) handle = '@$lb';

          _authorCache[uDoc.id] = {
            'displayName': name.isNotEmpty ? name : 'Kullanıcı',
            'handle': handle,
            'photoURL': photo,
          };
        }
      } catch (e) {
        debugPrint('Yazar verisi çekilemedi: $e');
      }
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

    // Cache'den hızlı yükleme
    try {
      final cacheQs = await base.get(const GetOptions(source: Source.cache));
      final cacheDocs = cacheQs.docs;
      if (cacheDocs.isNotEmpty) {
        // Önce yazarları hazırla (Cache'ten gelse bile)
        await _fetchAuthorsForPosts(cacheDocs);
        
        if (!mounted) return;
        setState(() {
          _posts = List<DocumentSnapshot<Map<String, dynamic>>>.from(cacheDocs);
          _lastDoc = cacheDocs.isNotEmpty ? cacheDocs.last : null;
          _hasMore = cacheDocs.length == _pageSize;
          _initialLoading = false;
        });
      }
    } catch (_) {}

    // Sunucudan güncel yükleme
    try {
      final serverQs = await base.get(const GetOptions(source: Source.server));
      final serverDocs = serverQs.docs;
      
      // Yazarları hazırla
      await _fetchAuthorsForPosts(serverDocs);

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

      // Yeni gelenlerin yazarlarını hazırla
      await _fetchAuthorsForPosts(docs);

      setState(() {
        _posts.addAll(docs);
        _lastDoc = docs.isNotEmpty ? docs.last : _lastDoc;
        _hasMore = docs.length == _pageSize;
      });
    } catch (_) {
      // Hata olursa cache dene
      try {
        final q = FirebaseFirestore.instance
            .collection('posts')
            .orderBy('createdAt', descending: true)
            .startAfterDocument(_lastDoc!)
            .limit(_pageSize);
        final qs = await q.get(const GetOptions(source: Source.cache));
        final docs = qs.docs;
        if (docs.isNotEmpty) {
          await _fetchAuthorsForPosts(docs);
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

  // ... (Film seçme ve post atma fonksiyonları aynen kalıyor) ...
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
                child: Text('Filmlerim', style: Theme.of(ctx).textTheme.titleLarge),
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
                      if (seen.add(key)) items.add({'title': t, 'poster': (m['poster'] ?? '').toString()});
                    }
                    if (items.isEmpty) {
                      return const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('Listen boş.')));
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
                              width: 40, height: 60,
                              child: poster.isNotEmpty
                                  ? PosterImage(posterUrl: poster, title: title, fit: BoxFit.cover)
                                  : const ColoredBox(color: Colors.black12, child: Center(child: Icon(Icons.movie))),
                            ),
                          ),
                          title: Text(title),
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

    if (result != null && mounted) {
      setState(() => _selectedMovie = result);
      final t = result['title'] ?? '';
      if (t.isNotEmpty) {
        final existing = _controller.text.trim();
        _controller.text = existing.isEmpty ? '🎬 $t' : existing;
        _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
        _focusNode.requestFocus();
      }
    }
  }

  Future<void> _createPost(String text) async {
    // FeedService kullanılarak post atılıyor (önceki düzeltme ile uyumlu)
    await FeedService.instance.createPost(
      text: text,
      movie: _selectedMovie,
    );
    if (mounted) {
      setState(() => _selectedMovie = null);
      _controller.clear();
      _focusNode.unfocus();
      // Listeyi yenile ki yeni post en üstte görünsün
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
    final years = diff.inDays ~/ 365;
    return '${years}y';
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
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchProfilesScreen()));
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
                      Icon(Icons.search, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 5),
                      Text('Kullanıcı Adı Ara', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
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
                  tabs: const [Tab(text: 'Popüler'), Tab(text: 'Takip Edilenler')],
                ),
                const Divider(height: 1),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: [
            // 1) POPÜLER AKIŞ
            RefreshIndicator(
              onRefresh: _refresh,
              child: _initialLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      controller: _listController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _posts.length + (_loadingMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        if (_loadingMore && i == _posts.length) {
                          return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator()));
                        }
                        
                        final d = _posts[i];
                        final m = d.data() ?? {};
                        final authorId = (m['authorId'] ?? '') as String;

                        // BURASI KRİTİK NOKTA:
                        // Post verisindeki isim/resim yerine, Feed sayfasında topluca çektiğimiz güncel veriyi (Cache) kullan.
                        // Eğer cache'de yoksa (çok nadir), postun içindekini kullan.
                        final cachedUser = _authorCache[authorId];
                        
                        final displayName = cachedUser?['displayName'] ?? (m['displayName'] ?? '') as String;
                        final handle = cachedUser?['handle'] ?? (m['handle'] ?? '') as String;
                        final photoURL = cachedUser?['photoURL'] ?? (m['photoURL'] ?? '') as String;

                        final createdAt = (m['createdAt'] as Timestamp?);
                        final timeLabel = createdAt == null ? '' : _timeAgo(createdAt.toDate());
                        final movieTitle = ((m['movieTitle'] ?? (m['movie']?['title'])) ?? '').toString();
                        final moviePoster = ((m['moviePoster'] ?? (m['movie']?['poster'] ?? m['movie']?['posterUrl'])) ?? '').toString();

                        final postWidget = PostTile(
                          postId: d.id,
                          authorId: authorId,
                          // Artık dolu dolu veriyi gönderiyoruz:
                          displayName: displayName, 
                          handle: handle,
                          photoURL: photoURL,
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
                              const RecommendedUsers(title: 'Önerilen kullanıcılar', limit: 10),
                            ],
                          );
                        }
                        return postWidget;
                      },
                    ),
            ),

            // 2) TAKİP EDİLENLER
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

// --- FOLLOWING FEED ---
// Benzer mantığı buraya da uyguluyoruz ki takip edilenler sekmesi de hızlı olsun
class _FollowingFeed extends StatefulWidget {
  const _FollowingFeed({Key? key}) : super(key: key);

  @override
  State<_FollowingFeed> createState() => _FollowingFeedState();
}

class _FollowingFeedState extends State<_FollowingFeed> with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  List<DocumentSnapshot<Map<String, dynamic>>> _items = [];
  // Burası için de ayrı cache veya global cache kullanılabilir, şimdilik yerel yapalım
  final Map<String, Map<String, String>> _localAuthorCache = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Yardımcı: Yazarları çek
  Future<void> _fetchAuthors(List<DocumentSnapshot> posts) async {
    final uids = <String>{};
    for(var d in posts) {
      final u = d.data() as Map<String, dynamic>?;
      final id = u?['authorId'] as String?;
      if(id != null && !_localAuthorCache.containsKey(id)) uids.add(id);
    }
    if(uids.isEmpty) return;
    
    final list = uids.toList();
    for(var i=0; i<list.length; i+=10) {
      final chunk = list.sublist(i, i+10 > list.length ? list.length : i+10);
      try {
        final qs = await FirebaseFirestore.instance.collection('users').where(FieldPath.documentId, whereIn: chunk).get();
        for(var ud in qs.docs) {
          final d = ud.data();
          final nm = (d['displayName'] ?? '').toString();
          final ph = (d['photoURL'] ?? '').toString();
          final usr = (d['username'] ?? '').toString();
          final lb = (d['letterboxdUsername'] ?? '').toString();
          String h = '';
          if(usr.isNotEmpty) h='@$usr'; else if(lb.isNotEmpty) h='@$lb';
          _localAuthorCache[ud.id] = {'displayName': nm.isNotEmpty?nm:'Kullanıcı', 'handle': h, 'photoURL': ph};
        }
      } catch(_){}
    }
  }

  Future<void> _load() async {
    if (_items.isEmpty) setState(() => _loading = true);
    
    try {
      final me = FirebaseAuth.instance.currentUser?.uid;
      if (me == null) {
        if(mounted) setState(() { _items = []; _loading = false; });
        return;
      }

      final followingQs = await FirebaseFirestore.instance
          .collection('users').doc(me).collection('following')
          .orderBy('createdAt', descending: true).limit(30).get();
      
      final uids = followingQs.docs.map((d) => d.id).toList();

      if (uids.isEmpty) {
        if(mounted) setState(() { _items = []; _loading = false; });
        return;
      }

      final List<DocumentSnapshot<Map<String, dynamic>>> acc = [];
      final processUids = uids.take(15).toList();

      for (var i = 0; i < processUids.length; i += 10) {
        final chunk = processUids.sublist(i, i + 10 > processUids.length ? processUids.length : i + 10);
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
        if (ta == null) return 1; if (tb == null) return -1;
        return tb.compareTo(ta);
      });

      // Yazarları hazırla
      await _fetchAuthors(acc);

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

    if (_loading) return const Center(child: CircularProgressIndicator());

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
                    Text('Birilerini takip etmelisin', style: Theme.of(context).textTheme.titleMedium),
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
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final d = _items[i];
          final m = d.data() ?? {};
          final authorId = (m['authorId'] ?? '') as String;
          
          // Following feed için de cache kullanıyoruz
          final cachedUser = _localAuthorCache[authorId];
          final displayName = cachedUser?['displayName'] ?? (m['displayName'] ?? '') as String;
          final handle = cachedUser?['handle'] ?? (m['handle'] ?? '') as String;
          final photoURL = cachedUser?['photoURL'] ?? (m['photoURL'] ?? '') as String;

          final createdAt = (m['createdAt'] as Timestamp?);
          final timeLabel = createdAt == null ? '' : _FeedPageState._timeAgo(createdAt.toDate());
          final movieTitle = ((m['movieTitle'] ?? (m['movie']?['title'])) ?? '').toString();
          final moviePoster = ((m['moviePoster'] ?? (m['movie']?['poster'] ?? m['movie']?['posterUrl'])) ?? '').toString();

          return PostTile(
            postId: d.id,
            authorId: authorId,
            displayName: displayName,
            handle: handle,
            photoURL: photoURL,
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

// ... _Composer ve _ComposePostPage sınıfları aynen kalacak (değişiklik yok) ...
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