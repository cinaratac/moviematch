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
import 'package:fluttergirdi/widgets/friends_popular_watched.dart';
import 'package:fluttergirdi/widgets/green_characters.dart';
import 'package:fluttergirdi/services/tab_service.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final FeedController _controller = FeedController.instance;

  // --- YENİ EKLENEN: Hassas Şeffaflık (Opacity) Motoru ---
  double _appBarOpacity = 1.0;
  double _lastOffset = 0.0;

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerUpdate);
    if (!_controller.isInitialized) {
      _controller.init();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  bool _onScrollNotification(ScrollUpdateNotification scrollInfo) {
    // 1. Sonsuz kaydırma (Pagination) mantığı
    if (scrollInfo.metrics.maxScrollExtent - scrollInfo.metrics.pixels <=
        1500) {
      _controller.loadMore();
    }

    // 2. Özel Şeffaflık (Fade) Animasyon Mantığı
    if (scrollInfo.metrics.axis == Axis.vertical) {
      final currentOffset = scrollInfo.metrics.pixels;
      final delta = currentOffset - _lastOffset;

      // İlk 150 pikseldeyken AppBar her zaman %100 görünür kalır
      if (currentOffset <= 150) {
        if (_appBarOpacity != 1.0) {
          setState(() => _appBarOpacity = 1.0);
        }
      } else {
        double newOpacity = _appBarOpacity;

        if (delta > 0) {
          // Aşağı kaydırma: Yavaş yavaş saydamlaşır (Yaklaşık 200 pikselde erir)
          newOpacity -= delta * 0.005;
        } else if (delta < 0) {
          // Yukarı kaydırma: ÇOK DAHA HIZLI opaklaşır (Sadece 40px kaysa tamamen geri döner)
          newOpacity -= delta * 0.005;
        }

        // Değeri 0 ile 1 arasına sabitle
        newOpacity = newOpacity.clamp(0.0, 1.0);

        // Gereksiz setState çağrılarını engellemek için delta farkını kontrol et
        if ((newOpacity - _appBarOpacity).abs() > 0.01 ||
            newOpacity == 0.0 ||
            newOpacity == 1.0) {
          setState(() {
            _appBarOpacity = newOpacity;
          });
        }
      }
      _lastOffset = currentOffset;
    }
    return false;
  }

  int? _parseTmdbId(Map<String, dynamic> m) {
    dynamic rawId = (m['movie'] is Map)
        ? (m['movie']['tmdbId'] ?? m['movie']['id'] ?? m['movie']['movieId'])
        : null;
    rawId ??= m['tmdbId'] ?? m['movieId'] ?? m['id'];
    if (rawId is int) return rawId;
    if (rawId is String) return int.tryParse(rawId);
    if (rawId is double) return rawId.toInt();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Status bar (çentik) boyutu + Özel AppBar'ın toplam boyutu
    final topPadding = MediaQuery.of(context).padding.top + 110.0;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        drawer: const CustomDrawer(),
        // Body AppBar'ın altından (y=0'dan) başlar, böylece AppBar saydamlaştıkça postlar üstten akar
        extendBodyBehindAppBar: true,

        // --- ÖZEL APPBAR TASARIMI ---
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Opacity(
            opacity: _appBarOpacity,
            child: IgnorePointer(
              // Şeffaflık yarıyı geçtiğinde tıklamaları listeye geçir (postlara tıklanabilsin)
              ignoring: _appBarOpacity < 0.5,
              child: AppBar(
                backgroundColor: cs.surface.withOpacity(
                  0.96,
                ), // Hafif buzlu cam/saydam zemin
                elevation: 0,
                scrolledUnderElevation: 0,
                toolbarHeight: 60,
                titleSpacing: 0,
                title: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SearchPage()),
                      ),
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
                            Icon(
                              Icons.search,
                              size: 20,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Kullanıcı Veya Film Ara',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
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
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
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
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: -0.2,
                      ),
                      labelPadding: EdgeInsets.zero,
                      overlayColor: WidgetStateProperty.all(Colors.transparent),
                      tabs: const [
                        Tab(text: 'Popüler'),
                        Tab(text: 'Takip Edilenler'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // --- ANA GÖVDE VE KAYDIRMA DİNLEYİCİSİ ---
        body: NotificationListener<ScrollUpdateNotification>(
          onNotification: _onScrollNotification,
          child: TabBarView(
            children: [
              RefreshIndicator(
                edgeOffset:
                    topPadding, // Yenileme ikonunun AppBar altında çıkması için
                onRefresh: _controller.refresh,
                child: _buildPopularFeed(topPadding),
              ),
              _FollowingFeed(topPadding: topPadding),
            ],
          ),
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
                  maxChars: 1000,
                  onSend:
                      ({
                        required text,
                        movie,
                        images,
                        rating,
                        required isSpoiler,
                        tags,
                        reviewTitle,
                      }) async {
                        final user = FirebaseAuth.instance.currentUser;
                        if (user == null) return;

                        try {
                          List<String> imageUrls = [];
                          if (images != null && images.isNotEmpty) {
                            for (var i = 0; i < images.length; i++) {
                              final image = images[i];
                              final String fileName =
                                  '${user.uid}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
                              final ref = FirebaseStorage.instance
                                  .ref()
                                  .child('post_images')
                                  .child(fileName);
                              await ref.putFile(image);
                              final url = await ref.getDownloadURL();
                              imageUrls.add(url);
                            }
                          }

                          await FeedService.instance.createPost(
                            text: text,
                            movie: movie,
                            photoURL: imageUrls.isNotEmpty
                                ? imageUrls.first
                                : null,
                            photoURLs: imageUrls,
                            displayName: user.displayName,
                            handle: user.email?.split('@')[0] ?? 'user',
                            rating: rating,
                            isSpoiler: isSpoiler,
                            tags: tags,
                            reviewTitle: reviewTitle,
                          );

                          if (mounted) {
                            Navigator.of(context).pop();
                            TabService.instance.changeTab(0);
                            _controller.refresh();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Gönderildi!')),
                            );
                          }
                        } catch (e) {
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
      ),
    );
  }

  Widget _buildPopularFeed(double topPadding) {
    if (_controller.isLoading) {
      return ListView.builder(
        padding: EdgeInsets.only(top: topPadding + 8, bottom: 8),
        itemCount: 5,
        itemBuilder: (ctx, index) => const PostSkeleton(),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.only(top: topPadding + 8, bottom: 8),
      itemCount:
          _controller.posts.length + 1 + (_controller.isLoadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        if (i == 0) {
          return const Column(
            children: [
              OfflineBanner(), // İnternet yoksa afişi sorunsuzca liste içine gömdük
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
        final displayName =
            cachedUser?.displayName ?? (m['displayName'] ?? 'Kullanıcı');
        final handle = cachedUser?.handle ?? (m['handle'] ?? '');
        final photoURL = cachedUser?.photoURL ?? (m['photoURL'] ?? '');

        final createdAt = (m['createdAt'] as Timestamp?);
        final timeLabel = DateHelper.timeAgo(createdAt);

        final movieMap = m['movie'] is Map ? m['movie'] as Map : null;
        final movieTitle = ((m['movieTitle'] ?? movieMap?['title']) ?? '')
            .toString();
        final moviePoster =
            ((m['moviePoster'] ??
                        movieMap?['poster'] ??
                        movieMap?['posterUrl']) ??
                    '')
                .toString();

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
          postImages: List<String>.from(m['photoURLs'] ?? []),
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
  final double topPadding;
  const _FollowingFeed({Key? key, required this.topPadding}) : super(key: key);

  @override
  State<_FollowingFeed> createState() => _FollowingFeedState();
}

class _FollowingFeedState extends State<_FollowingFeed>
    with AutomaticKeepAliveClientMixin {
  final FeedController _controller = FeedController.instance;
  int _friendsPopularReloadToken = 0;

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
      rawId = movieMap['tmdbId'] ?? movieMap['id'] ?? movieMap['movieId'];
    }
    rawId ??= m['tmdbId'] ?? m['movieId'] ?? m['id'];
    if (rawId is int) return rawId;
    if (rawId is String) return int.tryParse(rawId);
    if (rawId is double) return rawId.toInt();
    return null;
  }

  Future<void> _refreshFollowing() async {
    await _controller.refreshFollowing();
    if (!mounted) return;
    setState(() => _friendsPopularReloadToken++);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_controller.isFollowingLoading) {
      return ListView.builder(
        itemCount: 5,
        padding: EdgeInsets.only(top: widget.topPadding + 8, bottom: 8),
        itemBuilder: (_, __) => const PostSkeleton(),
      );
    }

    if (_controller.followingPosts.isEmpty) {
      final hasFollowing = _controller.myFollowingUserIds.isNotEmpty;
      return RefreshIndicator(
        edgeOffset: widget.topPadding,
        onRefresh: _refreshFollowing,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.only(top: widget.topPadding + 8),
              sliver: SliverToBoxAdapter(
                child: FriendsPopularWatched(
                  followingUserIds: _controller.myFollowingUserIds,
                  reloadToken: _friendsPopularReloadToken,
                ),
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const GreenEyesCharacter(size: 150),
                    const SizedBox(height: 16),
                    Text(
                      hasFollowing
                          ? 'Takip ettiklerinin henüz gönderisi yok'
                          : 'Birilerini takip etmelisin',
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
      edgeOffset: widget.topPadding,
      onRefresh: _refreshFollowing,
      child: ListView.separated(
        padding: EdgeInsets.only(top: widget.topPadding + 8, bottom: 8),
        itemCount: _controller.followingPosts.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Column(
              children: [
                const OfflineBanner(),
                FriendsPopularWatched(
                  followingUserIds: _controller.myFollowingUserIds,
                  reloadToken: _friendsPopularReloadToken,
                ),
              ],
            );
          }

          final d = _controller.followingPosts[i - 1];
          final m = d.data() ?? {};
          final authorId = (m['authorId'] ?? '') as String;

          final cachedUser = UserCacheService.instance.getFromCache(authorId);
          final displayName =
              cachedUser?.displayName ?? (m['displayName'] ?? '') as String;
          final handle = cachedUser?.handle ?? (m['handle'] ?? '') as String;
          final photoURL =
              cachedUser?.photoURL ?? (m['photoURL'] ?? '') as String;

          final createdAt = (m['createdAt'] as Timestamp?);
          final timeLabel = createdAt == null
              ? ''
              : DateHelper.timeAgo(createdAt.toDate());
          final movieMap = m['movie'] is Map ? m['movie'] as Map : null;
          final movieTitle = ((m['movieTitle'] ?? movieMap?['title']) ?? '')
              .toString();
          final moviePoster =
              ((m['moviePoster'] ??
                          movieMap?['poster'] ??
                          movieMap?['posterUrl']) ??
                      '')
                  .toString();

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

            initialIsLiked: _controller.myLikedPostIds.contains(d.id),
            initialIsFollowing: _controller.myFollowingUserIds.contains(
              authorId,
            ),

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
