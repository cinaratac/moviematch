import 'package:flutter/material.dart';
import 'package:fluttergirdi/utils/date_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:fluttergirdi/screens/news_list_page.dart';
import 'package:fluttergirdi/screens/search_page.dart';

import '../controllers/feed_controller.dart';
import '../services/user_cache_service.dart';
import '../widgets/post_skeleton.dart';
import '../services/feed_service.dart';
import 'package:fluttergirdi/widgets/post_tile.dart';
import 'package:fluttergirdi/widgets/recommended_users.dart';
import 'package:fluttergirdi/widgets/notifications.dart'; 
import 'package:fluttergirdi/widgets/recommendation_card.dart';
import '../widgets/compose_post_sheet.dart';
import 'package:fluttergirdi/widgets/offline_banner.dart';
import 'package:fluttergirdi/widgets/custom_drawer.dart';
import 'package:fluttergirdi/widgets/dashboard_stats_row.dart';
import 'package:fluttergirdi/widgets/discovery_lists_widget.dart';
import 'package:fluttergirdi/widgets/green_characters.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  // ARTIK SINGLETON KULLANIYORUZ
  final FeedController _controller = FeedController.instance; 
  final ScrollController _scrollController = ScrollController();
  
  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }
  
  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerUpdate);
    
    // Eğer arkada yüklenmediyse yükle (Sigorta amaçlı)
    if (!_controller.isInitialized) {
      _controller.init();
    }
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    // SADECE listener'ı kaldır. Controller singleton olduğu için DİSPOSE ETME!
    _controller.removeListener(_onControllerUpdate); 
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    
    // Kullanıcı sayfanın sonuna 1500 piksel (yaklaşık 3-4 post) yaklaştığında 
    // sessizce yeni verileri çekmeye başla.
    if (maxScroll - currentScroll <= 1500) {
      _controller.loadMore();
    }
  }

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
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage())),
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
                      Text('Kullanıcı Veya Film Ara', style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Sinema Gündemi',
              icon: const Icon(Icons.newspaper_rounded),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NewsListPage()),
                );
              },
            ),
            const NotificationsButton(),
            const SizedBox(width: 8),
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
                  RefreshIndicator(
                    onRefresh: _controller.refresh,
                    child: _buildPopularFeed(),
                  ),
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
                  // --- GÜNCELLENEN KISIM: images (List<File>) ALINIYOR ---
                  onSend: ({required text, movie, images, rating, required isSpoiler, tags, reviewTitle}) async {
                    Navigator.pop(context);
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) return;
                    
                    try {
                      // Çoklu resim yükleme
                      List<String> imageUrls = [];
                      if (images != null && images.isNotEmpty) {
                        for (var i = 0; i < images.length; i++) {
                           final image = images[i];
                           final String fileName = '${user.uid}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
                           final ref = FirebaseStorage.instance.ref().child('post_images').child(fileName);
                           await ref.putFile(image);
                           final url = await ref.getDownloadURL();
                           imageUrls.add(url);
                        }
                      }

                      await FeedService.instance.createPost(
                          text: text,
                          movie: movie,
                          photoURL: imageUrls.isNotEmpty ? imageUrls.first : null, // Geriye dönük uyumluluk
                          photoURLs: imageUrls, // Yeni liste
                          displayName: user.displayName,
                          handle: user.email?.split('@')[0] ?? 'user',
                          rating: rating,
                          isSpoiler: isSpoiler,
                          tags: tags,
                          reviewTitle: reviewTitle,
                      );
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gönderildi!')));
                        _controller.refresh(); 
                      }
                    } catch (e) {
                 
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
    if (_controller.isLoading) {
      return ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: 5, 
        itemBuilder: (ctx, index) => const PostSkeleton(),
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _controller.posts.length + 1 + (_controller.isLoadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
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

        final cachedUser = UserCacheService.instance.getFromCache(authorId);
        final displayName = cachedUser?.displayName ?? (m['displayName'] ?? 'Kullanıcı');
        final handle = cachedUser?.handle ?? (m['handle'] ?? '');
        final photoURL = cachedUser?.photoURL ?? (m['photoURL'] ?? '');

        final createdAt = (m['createdAt'] as Timestamp?);
        final timeLabel = DateHelper.timeAgo(createdAt);

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
          // --- EKLENDİ: Çoklu Fotoğraf Desteği ---
          postImages: List<String>.from(m['photoURLs'] ?? []),
          // ----------------------------------------
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

class _FollowingFeed extends StatefulWidget {
  const _FollowingFeed({Key? key}) : super(key: key);

  @override
  State<_FollowingFeed> createState() => _FollowingFeedState();
}

class _FollowingFeedState extends State<_FollowingFeed> with AutomaticKeepAliveClientMixin {
  final FeedController _controller = FeedController.instance; // SINGLETON KULLANIMI

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerUpdate);
    if (!_controller.isFollowingInitialized) {
      _controller.initFollowing();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    super.dispose();
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
    
    if (_controller.isFollowingLoading) {
      return ListView.builder(
        itemCount: 5,
        padding: const EdgeInsets.all(8),
        itemBuilder: (_,__) => const PostSkeleton()
      );
    }
    
    if (_controller.followingPosts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _controller.refreshFollowing,
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
      onRefresh: _controller.refreshFollowing,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _controller.followingPosts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final d = _controller.followingPosts[i];
          final m = d.data() ?? {};
          final authorId = (m['authorId'] ?? '') as String;
          
          final cachedUser = UserCacheService.instance.getFromCache(authorId);
          final displayName = cachedUser?.displayName ?? (m['displayName'] ?? '') as String;
          final handle = cachedUser?.handle ?? (m['handle'] ?? '') as String;
          final photoURL = cachedUser?.photoURL ?? (m['photoURL'] ?? '') as String;
          
          final createdAt = (m['createdAt'] as Timestamp?);
          final timeLabel = createdAt == null ? '' : DateHelper.timeAgo(createdAt.toDate());
          final movieTitle = ((m['movieTitle'] ?? (m['movie']?['title'])) ?? '').toString();
          final moviePoster = ((m['moviePoster'] ?? (m['movie']?['poster'] ?? m['movie']?['posterUrl'])) ?? '').toString();
          
          int? movieTmdbId = _parseTmdbId(m);
          final postImage = (m['postImage'] ?? '') as String;
          
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
            postImages: List<String>.from(m['photoURLs'] ?? []),
            text: (m['text'] ?? '') as String,
            likeCount: ((m['likeCount'] ?? 0) as num).toInt(),
            replyCount: ((m['replyCount'] ?? 0) as num).toInt(),
            rating: (m['rating'] as num?)?.toDouble(),
            isSpoiler: (m['isSpoiler'] == true),
            reviewTitle: m['reviewTitle'] as String?,
            tags: List<String>.from(m['tags'] ?? []),
            
            // Tüm etkileşim verilerini (Like ve Follow state'ini) Ana Controller üzerinden çekiyoruz!
            initialIsLiked: _controller.myLikedPostIds.contains(d.id),
            initialIsFollowing: _controller.myFollowingUserIds.contains(authorId),
            
            onToggleLike: (pid, like) => _controller.toggleLike(pid, like),
            onStartChat: (String _) async {},
            onFollow: (uid) => _controller.followUser(uid),
            onReport: (pid) => FeedService.instance.reportPost(pid),
            onDelete: () => _controller.removeFollowingPost(d.id),
          );
        },
      ),
    );
  }
}
