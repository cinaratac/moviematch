import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

// --- YENİ IMPORTLAR (Controller ve Servisler) ---
import '../controllers/feed_controller.dart';
import '../services/user_cache_service.dart';
import '../widgets/post_skeleton.dart';
import '../services/feed_service.dart';

// MEVCUT IMPORTLAR (Projenizdeki widget'lar)
import 'package:fluttergirdi/screens/search_profiles_screen.dart';
import 'package:fluttergirdi/widgets/post_tile.dart';
import 'package:fluttergirdi/widgets/recommended_users.dart';
import 'package:fluttergirdi/widgets/notifications.dart'; // NotificationsButton için
import 'package:fluttergirdi/widgets/recommendation_card.dart';
import '../widgets/compose_post_sheet.dart';
import 'package:fluttergirdi/widgets/offline_banner.dart';
import 'package:fluttergirdi/widgets/custom_drawer.dart';
import 'package:fluttergirdi/widgets/dashboard_stats_row.dart';
import 'package:fluttergirdi/widgets/discovery_lists_widget.dart';
import 'package:fluttergirdi/widgets/green_characters.dart'; // Takip akışı boşsa gösterilen karakter

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  // Logic'i Controller'a taşıdık (Sadece Popüler akış için)
  final FeedController _controller = FeedController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Controller'daki değişiklikleri dinleyip ekranı yeniliyoruz
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
    
    _controller.init();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(() {}); 
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    
    // Listenin sonuna yaklaşıldığında yeni veri çek
    if (maxScroll - currentScroll <= 200) {
      _controller.loadMore();
    }
  }

  // Helper: Timestamp formatlama
  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}g';
    return '${diff.inDays ~/ 365}y';
  }

  int? _parseTmdbId(Map<String, dynamic> m) {
    dynamic rawId = (m['movie'] is Map) 
        ? (m['movie']['tmdbId'] ?? m['movie']['id']) 
        : m['tmdbId'];
    if (rawId is int) return rawId;
    if (rawId is String) return int.tryParse(rawId);
    if (rawId is double) return rawId.toInt();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        drawer: const CustomDrawer(),
        appBar: AppBar(
          backgroundColor: cs.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          toolbarHeight: 60,
          titleSpacing: 0,
          title: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchProfilesScreen())),
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 20, color: cs.onSurfaceVariant),
                      const SizedBox(width: 5),
                      Text('Kullanıcı Ara', style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          actions: const [
            NotificationsButton(),
            SizedBox(width: 8),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(50),
            child: Container(
              height: 36,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: TabBar(
                isScrollable: false,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                labelColor: cs.onSurface,
                unselectedLabelColor: cs.onSurfaceVariant,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: -0.2),
                labelPadding: EdgeInsets.zero,
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                tabs: const [Tab(text: 'Popüler'), Tab(text: 'Takip Edilenler')],
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            const OfflineBanner(),
            Expanded(
              child: TabBarView(
                children: [
                  // 1) POPÜLER AKIŞ (Controller ile yönetiliyor - Optimize Edilmiş)
                  RefreshIndicator(
                    onRefresh: _controller.refresh,
                    child: _buildPopularFeed(),
                  ),
            
                  // 2) TAKİP EDİLENLER (Eski Yapı Geri Getirildi)
                  const _FollowingFeed(),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(bottom: 70.0),
          child: FloatingActionButton(
            heroTag: 'feed_compose_fab',
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => ComposePostPage(
                  maxChars: 280,
                  onSend: ({required text, movie, image, rating, required isSpoiler, tags, reviewTitle}) async {
                    Navigator.pop(context);
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) return;
                    
                    try {
                      String? imageUrl;
                      if (image != null) {
                        final String fileName = '${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
                        final ref = FirebaseStorage.instance.ref().child('post_images').child(fileName);
                        await ref.putFile(image);
                        imageUrl = await ref.getDownloadURL();
                      }

                      await FeedService.instance.createPost(
                          text: text,
                          movie: movie,
                          photoURL: imageUrl,
                          displayName: user.displayName,
                          handle: user.email?.split('@')[0] ?? 'user',
                          rating: rating,
                          isSpoiler: isSpoiler,
                          tags: tags,
                          reviewTitle: reviewTitle,
                      );
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gönderildi!')));
                        _controller.refresh(); // Listeyi yenile
                      }
                    } catch (e) {
                      debugPrint('Post gönderme hatası: $e');
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hata oluştu.')));
                    }
                  },
                ),
              );
            },
            child: const Icon(Icons.edit_note_rounded),
          ),
        ),
      ),
    );
  }

  Widget _buildPopularFeed() {
    // 1. YÜKLENİYORSA: SKELETON GÖSTER
    if (_controller.isLoading) {
      return ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: 5, 
        itemBuilder: (ctx, index) => const PostSkeleton(),
      );
    }

    // 2. LİSTE DOLUYSA
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _controller.posts.length + 1 + (_controller.isLoadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        // En üstte Dashboard ve Öneriler
        if (i == 0) {
          return const Column(
            children: [
              RecommendationCard(),
              DashboardStatsRow(),
              DiscoveryListsWidget(),
            ],
          );
        }

        final postIndex = i - 1;

        // En altta yükleniyor ikonu
        if (postIndex >= _controller.posts.length) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final doc = _controller.posts[postIndex];
        final m = doc.data() ?? {};
        final pid = doc.id;
        final authorId = (m['authorId'] ?? '') as String;

        // --- CACHE'DEN KULLANICI BİLGİSİ ALMA ---
        final cachedUser = UserCacheService.instance.getFromCache(authorId);
        final displayName = cachedUser?.displayName ?? (m['displayName'] ?? 'Kullanıcı');
        final handle = cachedUser?.handle ?? (m['handle'] ?? '');
        final photoURL = cachedUser?.photoURL ?? (m['photoURL'] ?? '');

        final createdAt = (m['createdAt'] as Timestamp?);
        final timeLabel = createdAt == null ? '' : _FeedPageState._timeAgo(createdAt.toDate());

        final movieTitle = ((m['movieTitle'] ?? m['movie']?['title']) ?? '').toString();
        final moviePoster = ((m['moviePoster'] ?? m['movie']?['poster'] ?? m['movie']?['posterUrl']) ?? '').toString();
        
        final postWidget = PostTile(
          key: ValueKey(pid),
          postId: pid,
          authorId: authorId,
          displayName: displayName,
          handle: handle,
          photoURL: photoURL,
          timeLabel: timeLabel,
          movieTitle: movieTitle.isEmpty ? null : movieTitle,
          moviePoster: moviePoster.isEmpty ? null : moviePoster,
          movieTmdbId: _parseTmdbId(m),
          postImage: (m['postImage'] ?? '') as String,
          text: m['text'] ?? '',
          likeCount: ((m['likeCount'] ?? 0) as num).toInt(),
          replyCount: ((m['replyCount'] ?? 0) as num).toInt(),
          rating: (m['rating'] as num?)?.toDouble(),
          isSpoiler: m['isSpoiler'] == true,
          tags: List<String>.from(m['tags'] ?? []),
          reviewTitle: m['reviewTitle'] as String?,
          
          initialIsLiked: _controller.myLikedPostIds.contains(pid),
          initialIsFollowing: _controller.myFollowingUserIds.contains(authorId),
          
          onToggleLike: (id, liked) => _controller.toggleLike(id, liked),
          onFollow: (uid) => _controller.followUser(uid),
          onStartChat: (_) {}, 
          onReport: (id) => FeedService.instance.reportPost(id),
          onDelete: () => _controller.removePost(pid),
        );

        // Araya önerilen kullanıcıları eklemek istersen (Eski koddaki gibi 3. posttan sonra)
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
    );
  }
}

// ---------------------------------------------------------------------------
// AŞAĞISI ESKİ KODDAN KURTARILAN "TAKİP EDİLENLER" (FOLLOWING) KISMI
// ---------------------------------------------------------------------------

class _FollowingFeed extends StatefulWidget {
  const _FollowingFeed({Key? key}) : super(key: key);

  @override
  State<_FollowingFeed> createState() => _FollowingFeedState();
}

class _FollowingFeedState extends State<_FollowingFeed> with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  List<DocumentSnapshot<Map<String, dynamic>>> _items = [];
  final Map<String, Map<String, String>> _localAuthorCache = {};
  
  Set<String> _myLikedPostIds = {};
  Set<String> _myFollowingUserIds = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Bu fonksiyonu UserCacheService'e taşıyabiliriz ama eski kodun çalışması için bıraktım
  Future<void> _fetchAuthors(List<DocumentSnapshot> posts) async {
    final uids = <String>{};
    for(var d in posts) {
      final u = d.data() as Map<String, dynamic>?;
      final id = u?['authorId'] as String?;
      if(id != null && !_localAuthorCache.containsKey(id)) uids.add(id);
    }
    if(uids.isEmpty) return;
    
    // UserCacheService kullanarak optimize edelim
    await UserCacheService.instance.fetchUsers(uids.toList());
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

      final interactionsFuture = Future.wait([
        FeedService.instance.fetchUserLikedPostIds(me),
        FeedService.instance.fetchUserFollowingIds(me),
      ]);

      final followingQs = await FirebaseFirestore.instance
          .collection('users')
          .doc(me)
          .collection('following')
          .limit(200) 
          .get();
          
      final uids = followingQs.docs.map((d) => d.id).toList();

      if (uids.isEmpty) {
        if(mounted) setState(() { _items = []; _loading = false; });
        return;
      }

      List<Future<QuerySnapshot<Map<String, dynamic>>>> futures = [];
      
      for (var i = 0; i < uids.length; i += 10) {
        final end = (i + 10 < uids.length) ? i + 10 : uids.length;
        final chunk = uids.sublist(i, end);
        
        futures.add(
          FirebaseFirestore.instance
            .collection('posts')
            .where('authorId', whereIn: chunk)
            .orderBy('createdAt', descending: true)
            .limit(5)
            .get() 
        );
      }

      final results = await Future.wait(futures);
      
      final List<DocumentSnapshot<Map<String, dynamic>>> allPosts = [];
      for (var qs in results) {
        allPosts.addAll(qs.docs);
      }

      allPosts.sort((a, b) {
        final ta = (a.data()?['createdAt'] as Timestamp?)?.toDate();
        final tb = (b.data()?['createdAt'] as Timestamp?)?.toDate();
        if (ta == null) return 1; if (tb == null) return -1;
        return tb.compareTo(ta); 
      });

      final finalItems = allPosts.take(50).toList();

      await _fetchAuthors(finalItems);

      final interactionResults = await interactionsFuture;
      _myLikedPostIds = interactionResults[0];
      _myFollowingUserIds = interactionResults[1];

      if (mounted) {
        setState(() { _items = finalItems; _loading = false; });
      }
    } catch (e) {
      debugPrint("Takip akışı hatası: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  int? _parseTmdbId(Map<String, dynamic> m) {
    dynamic rawId;
    if (m['movie'] is Map) {
      final movieMap = m['movie'] as Map;
      rawId = movieMap['tmdbId'] ?? movieMap['id'];
    }
    rawId ??= m['tmdbId'];

    if (rawId is int) return rawId;
    if (rawId is String) return int.tryParse(rawId);
    if (rawId is double) return rawId.toInt();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    // Skeleton Loading Ekledik (Optimize edildi)
    if (_loading) {
      return ListView.builder(
        itemCount: 5,
        padding: const EdgeInsets.all(8),
        itemBuilder: (_,__) => const PostSkeleton()
      );
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
          
          // UserCacheService kullanarak veriyi çekiyoruz (daha hızlı)
          final cachedUser = UserCacheService.instance.getFromCache(authorId);
          final displayName = cachedUser?.displayName ?? (m['displayName'] ?? '') as String;
          final handle = cachedUser?.handle ?? (m['handle'] ?? '') as String;
          final photoURL = cachedUser?.photoURL ?? (m['photoURL'] ?? '') as String;
          
          final createdAt = (m['createdAt'] as Timestamp?);
          final timeLabel = createdAt == null ? '' : _FeedPageState._timeAgo(createdAt.toDate());
          final movieTitle = ((m['movieTitle'] ?? (m['movie']?['title'])) ?? '').toString();
          final moviePoster = ((m['moviePoster'] ?? (m['movie']?['poster'] ?? m['movie']?['posterUrl'])) ?? '').toString();
          
          int? movieTmdbId = _parseTmdbId(m);
          final postImage = (m['postImage'] ?? '') as String;
          
          final double? rating = (m['rating'] as num?)?.toDouble();
          final bool isSpoiler = (m['isSpoiler'] == true);
          final String? reviewTitle = m['reviewTitle'] as String?;
          final List<String> tags = List<String>.from(m['tags'] ?? []);

          return PostTile(
            key: ValueKey(d.id),
            postId: d.id,
            authorId: authorId,
            displayName: displayName,
            handle: handle,
            photoURL: photoURL,
            timeLabel: timeLabel,
            movieTitle: movieTitle.isEmpty ? null : movieTitle,
            moviePoster: moviePoster.isEmpty ? null : moviePoster,
            movieTmdbId: movieTmdbId,
            postImage: postImage.isEmpty ? null : postImage,
            text: (m['text'] ?? '') as String,
            likeCount: ((m['likeCount'] ?? 0) as num).toInt(),
            replyCount: ((m['replyCount'] ?? 0) as num).toInt(),
            rating: rating,
            isSpoiler: isSpoiler,
            reviewTitle: reviewTitle,
            tags: tags,
            
            initialIsLiked: _myLikedPostIds.contains(d.id),
            initialIsFollowing: _myFollowingUserIds.contains(authorId),
            
            onToggleLike: (pid, like) {
               if (like) {
                 _myLikedPostIds.add(pid);
               } else {
                 _myLikedPostIds.remove(pid);
               }
               FeedService.instance.toggleLike(postId: pid, like: like);
            },
            
            onStartChat: (String _) async {},
            onFollow: (uid) async {
               setState(() {
                 _myFollowingUserIds.add(uid);
               });
               await FeedService.instance.followUser(uid);
            },
            onReport: (pid) => FeedService.instance.reportPost(pid),
            onDelete: () {
              if (mounted) {
                setState(() {
                  _items.removeWhere((element) => element.id == d.id);
                });
              }
            },
          );
        },
      ),
    );
  }
}