import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/screens/settings_page.dart';
import 'package:fluttergirdi/screens/search_profiles_screen.dart';
import 'package:fluttergirdi/services/feed_service.dart';
import 'package:fluttergirdi/widgets/post_tile.dart';
import 'package:fluttergirdi/widgets/recommended_users.dart';
import 'package:fluttergirdi/widgets/green_characters.dart';
import 'package:fluttergirdi/widgets/notifications.dart';
import 'package:fluttergirdi/widgets/recommendation_card.dart';
import '../widgets/compose_post_sheet.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final ScrollController _listController = ScrollController();

  static const int _pageSize = 20;
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  
  List<DocumentSnapshot<Map<String, dynamic>>> _posts = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  
  final Map<String, Map<String, String>> _authorCache = {};

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

  // --- Yazarları Topluca Çek ---
  Future<void> _fetchAuthorsForPosts(List<DocumentSnapshot> posts) async {
    final uidsToFetch = <String>{};
    for (var doc in posts) {
      final data = doc.data() as Map<String, dynamic>?;
      final uid = data?['authorId'] as String?;
      if (uid != null && uid.isNotEmpty && !_authorCache.containsKey(uid)) {
        uidsToFetch.add(uid);
      }
    }

    if (uidsToFetch.isEmpty) return;

    final chunks = <List<String>>[];
    final list = uidsToFetch.toList();
    for (var i = 0; i < list.length; i += 10) {
      chunks.add(list.sublist(i, i + 10 > list.length ? list.length : i + 10));
    }

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
    _authorCache.clear();
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

    try {
      final cacheQs = await base.get(const GetOptions(source: Source.cache));
      final cacheDocs = cacheQs.docs;
      if (cacheDocs.isNotEmpty) {
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

    try {
      final serverQs = await base.get(const GetOptions(source: Source.server));
      final serverDocs = serverQs.docs;
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

      await _fetchAuthorsForPosts(docs);

      setState(() {
        _posts.addAll(docs);
        _lastDoc = docs.isNotEmpty ? docs.last : _lastDoc;
        _hasMore = docs.length == _pageSize;
      });
    } catch (_) {
      // Hata durumunda cache veya sessiz geçiş
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _refresh() async {
    await _loadInitial();
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
                      itemCount: _posts.length + 1 + (_loadingMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        if (i == 0) return const RecommendationCard();
                        
                        final postIndex = i - 1;
                        if (_loadingMore && postIndex == _posts.length) {
                          return const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator()));
                        }
                        
                        final d = _posts[postIndex];
                        final m = d.data() ?? {};
                        final authorId = (m['authorId'] ?? '') as String;

                        final cachedUser = _authorCache[authorId];
                        final displayName = cachedUser?['displayName'] ?? (m['displayName'] ?? '') as String;
                        final handle = cachedUser?['handle'] ?? (m['handle'] ?? '') as String;
                        final photoURL = cachedUser?['photoURL'] ?? (m['photoURL'] ?? '') as String;

                        final createdAt = (m['createdAt'] as Timestamp?);
                        final timeLabel = createdAt == null ? '' : _timeAgo(createdAt.toDate());
                        final movieTitle = ((m['movieTitle'] ?? (m['movie']?['title'])) ?? '').toString();
                        final moviePoster = ((m['moviePoster'] ?? (m['movie']?['poster'] ?? m['movie']?['posterUrl'])) ?? '').toString();
                        
                        // --- DÜZELTME: postImage ALINIYOR ---
                        final postImage = (m['postImage'] ?? '') as String;
                        // ------------------------------------

                        final postWidget = PostTile(
                          postId: d.id,
                          authorId: authorId,
                          displayName: displayName, 
                          handle: handle,
                          photoURL: photoURL,
                          timeLabel: timeLabel,
                          movieTitle: movieTitle.isEmpty ? null : movieTitle,
                          moviePoster: moviePoster.isEmpty ? null : moviePoster,
                          // --- DÜZELTME: postImage EKLENDİ ---
                          postImage: postImage.isEmpty ? null : postImage,
                          // -----------------------------------
                          text: (m['text'] ?? '') as String,
                          likeCount: ((m['likeCount'] ?? 0) as num).toInt(),
                          replyCount: ((m['replyCount'] ?? 0) as num).toInt(),
                          onToggleLike: (pid, like) => FeedService().toggleLike(postId: pid, like: like),
                          onStartChat: (String _) async {},
                          onFollow: (uid) async {
                             await FeedService().followUser(uid);
                             await FeedService().notifyFollow(toUid: uid);
                          },
                          onReport: (pid) => FeedService().reportPost(pid),
                        );

                        if (postIndex == 3) {
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
        
        // --- POST OLUŞTURMA BUTONU ---
        floatingActionButton: FloatingActionButton(
          heroTag: 'feed_compose_fab',
          onPressed: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => ComposePostPage(
                maxChars: 280,
                // onSend fonksiyonu artık imageFile da alıyor
                onSend: (text, movie, imageFile) async {
                  Navigator.pop(context);
                  
                  final user = FirebaseAuth.instance.currentUser;
                  if (user == null) return;

                  try {
                    String? imageUrl;

                    // 1. Resim varsa yükle
                    if (imageFile != null) {
                      final String fileName = '${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
                      final ref = FirebaseStorage.instance
                          .ref()
                          .child('post_images')
                          .child(fileName);

                      await ref.putFile(imageFile);
                      imageUrl = await ref.getDownloadURL();
                    }

                    // 2. Firestore'a kaydet
                    await FirebaseFirestore.instance.collection('posts').add({
                      'text': text,
                      'authorId': user.uid,
                      'displayName': user.displayName,
                      'handle': user.email?.split('@')[0] ?? 'user',
                      'photoURL': user.photoURL ?? '',
                      
                      if (movie != null) ...{
                        'movieTitle': movie['title'],
                        'moviePoster': movie['poster'],
                      },

                      // Resim URL'ini ekle
                      if (imageUrl != null) 'postImage': imageUrl,

                      'createdAt': FieldValue.serverTimestamp(),
                      'likeCount': 0,
                      'replyCount': 0,
                    });

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Gönderildi!')),
                      );
                      // Listeyi yenile
                      _refresh();
                    }
                  } catch (e) {
                    debugPrint('Post gönderme hatası: $e');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Hata oluştu.')),
                      );
                    }
                  }
                },
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
    _listController.removeListener(_onScroll);
    _listController.dispose();
    super.dispose();
  }
}

class _FollowingFeed extends StatefulWidget {
  const _FollowingFeed({Key? key}) : super(key: key);

  @override
  State<_FollowingFeed> createState() => _FollowingFeedState();
}

class _FollowingFeedState extends State<_FollowingFeed> with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  List<DocumentSnapshot<Map<String, dynamic>>> _items = [];
  final Map<String, Map<String, String>> _localAuthorCache = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

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
    _localAuthorCache.clear();
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
          final cachedUser = _localAuthorCache[authorId];
          final displayName = cachedUser?['displayName'] ?? (m['displayName'] ?? '') as String;
          final handle = cachedUser?['handle'] ?? (m['handle'] ?? '') as String;
          final photoURL = cachedUser?['photoURL'] ?? (m['photoURL'] ?? '') as String;
          final createdAt = (m['createdAt'] as Timestamp?);
          final timeLabel = createdAt == null ? '' : _FeedPageState._timeAgo(createdAt.toDate());
          final movieTitle = ((m['movieTitle'] ?? (m['movie']?['title'])) ?? '').toString();
          final moviePoster = ((m['moviePoster'] ?? (m['movie']?['poster'] ?? m['movie']?['posterUrl'])) ?? '').toString();
          
          // --- DÜZELTME: Takip edilenler akışına da postImage eklendi ---
          final postImage = (m['postImage'] ?? '') as String;
          // -----------------------------------------------------------

          return PostTile(
            postId: d.id,
            authorId: authorId,
            displayName: displayName,
            handle: handle,
            photoURL: photoURL,
            timeLabel: timeLabel,
            movieTitle: movieTitle.isEmpty ? null : movieTitle,
            moviePoster: moviePoster.isEmpty ? null : moviePoster,
            // Resmi PostTile'a gönderiyoruz
            postImage: postImage.isEmpty ? null : postImage,
            text: (m['text'] ?? '') as String,
            likeCount: ((m['likeCount'] ?? 0) as num).toInt(),
            replyCount: ((m['replyCount'] ?? 0) as num).toInt(),
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