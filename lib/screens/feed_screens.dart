import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/screens/search_profiles_screen.dart';
import 'package:fluttergirdi/services/feed_service.dart';
import 'package:fluttergirdi/widgets/post_tile.dart';
import 'package:fluttergirdi/widgets/recommended_users.dart';
import 'package:fluttergirdi/widgets/green_characters.dart';
import 'package:fluttergirdi/widgets/notifications.dart';
import 'package:fluttergirdi/widgets/recommendation_card.dart';
import '../widgets/compose_post_sheet.dart';
import 'package:fluttergirdi/widgets/offline_banner.dart';
import 'package:fluttergirdi/widgets/custom_drawer.dart';
// YENİ İMPORTLAR
import 'package:fluttergirdi/widgets/dashboard_stats_row.dart';
import 'package:fluttergirdi/widgets/discovery_lists_widget.dart';

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
  Set<String> _myLikedPostIds = {};
  Set<String> _myFollowingUserIds = {};
  
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
      } catch (e) { debugPrint('Yazar verisi çekilemedi: $e'); }
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

    try {
      final me = FirebaseAuth.instance.currentUser?.uid;
      
      // Postları ve Kullanıcı etkileşimlerini PARALEL (aynı anda) çekiyoruz:
      final results = await Future.wait([
        FeedService.instance.fetchInitial(limit: _pageSize), // Postlar
        if (me != null) FeedService.instance.fetchUserLikedPostIds(me), // Beğenilerim
        if (me != null) FeedService.instance.fetchUserFollowingIds(me), // Takiplerim
      ]);

      final serverQs = results[0] as QuerySnapshot<Map<String, dynamic>>;
      
      if (me != null) {
        _myLikedPostIds = results[1] as Set<String>;
        _myFollowingUserIds = results[2] as Set<String>;
      }

      final serverDocs = serverQs.docs;
      await _fetchAuthorsForPosts(serverDocs); // (Bunu sonraki adımda kaldıracağız ama şimdilik kalsın)

      if (!mounted) return;
      setState(() {
        _posts = List<DocumentSnapshot<Map<String, dynamic>>>.from(serverDocs);
        _lastDoc = serverDocs.isNotEmpty ? serverDocs.last : null;
        _hasMore = serverDocs.length == _pageSize;
        _initialLoading = false;
      });
    } catch (e) { 
      debugPrint('Feed Yükleme Hatası: $e');
      if (mounted) setState(() => _initialLoading = false); 
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    if (_lastDoc == null) return;
    setState(() => _loadingMore = true);
    try {
      final qs = await FeedService.instance.fetchMore(lastDoc: _lastDoc!, limit: _pageSize);
      final docs = qs.docs;
      await _fetchAuthorsForPosts(docs);
      setState(() {
        _posts.addAll(docs);
        _lastDoc = docs.isNotEmpty ? docs.last : _lastDoc;
        _hasMore = docs.length == _pageSize;
      });
    } catch (_) {
    } finally { if (mounted) setState(() => _loadingMore = false); }
  }

  Future<void> _refresh() async { await _loadInitial(); }

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
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchProfilesScreen()));
                },
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.centerLeft,
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
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700, 
                  fontSize: 13,
                  letterSpacing: -0.2
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
        
        body: Column(
          children: [
            const OfflineBanner(), 
            Expanded(
              child: TabBarView(
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
                              // 1. ÖĞE: ÖNERİ KARTI + DASHBOARD
if (i == 0) {
  return const Column(
    children: [
      RecommendationCard(),
      // Araya biraz boşluk bırakmak istersen SizedBox ekleyebilirsin
      // SizedBox(height: 8), 
      DashboardStatsRow(),
      DiscoveryListsWidget(),
    ],
  );
}
                              
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
                              
                              int? movieTmdbId = _parseTmdbId(m);

                              final postImage = (m['postImage'] ?? '') as String;

                              final double? rating = (m['rating'] as num?)?.toDouble();
                              final bool isSpoiler = (m['isSpoiler'] == true);
                              final String? reviewTitle = m['reviewTitle'] as String?;
                              final List<String> tags = List<String>.from(m['tags'] ?? []);

                              final postWidget = PostTile(
                                initialIsLiked: _myLikedPostIds.contains(d.id),
    initialIsFollowing: _myFollowingUserIds.contains(authorId),
                                // PERFORMANS İÇİN ÖNEMLİ: Key eklendi!
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
                                  await FeedService.instance.notifyFollow(toUid: uid);
                                },
                                onReport: (pid) => FeedService.instance.reportPost(pid),
                                onDelete: () {
                                  if (mounted) {
                                    setState(() {
                                      _posts.removeWhere((element) => element.id == d.id);
                                    });
                                  }
                                },
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
            ),
          ],
        ),
        
        // BUTON YUKARI TAŞINDI
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(bottom: 70.0), // Biraz daha yukarı alındı (50->70)
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
                        _refresh();
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
  
  // Beğeni ve Takip durumlarını tutacak listeler
  Set<String> _myLikedPostIds = {};
  Set<String> _myFollowingUserIds = {};

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

      // 1. Etkileşim verilerini (Like/Follow) paralel çek
      final interactionsFuture = Future.wait([
        FeedService.instance.fetchUserLikedPostIds(me),
        FeedService.instance.fetchUserFollowingIds(me),
      ]);

      // 2. Takip edilen kişilerin listesini çek (Limiti artırdık: 200)
      // Sıralama önemli değil çünkü hepsini alıp postları tarihe göre biz dizeceğiz.
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

      // 3. Kullanıcıları 10'arlı gruplara böl ve PARALEL sorgu hazırla
      // Firestore 'whereIn' limiti 30'dur, güvenli olması için 10 kullanıyoruz.
      List<Future<QuerySnapshot<Map<String, dynamic>>>> futures = [];
      
      for (var i = 0; i < uids.length; i += 10) {
        final end = (i + 10 < uids.length) ? i + 10 : uids.length;
        final chunk = uids.sublist(i, end);
        
        // Her gruptan en güncel 5 postu iste
        futures.add(
          FirebaseFirestore.instance
            .collection('posts')
            .where('authorId', whereIn: chunk)
            .orderBy('createdAt', descending: true)
            .limit(5)
            .get() // Source belirtmiyoruz, cache veya server
        );
      }

      // 4. Tüm sorguları aynı anda çalıştır (Hız optimizasyonu)
      final results = await Future.wait(futures);
      
      final List<DocumentSnapshot<Map<String, dynamic>>> allPosts = [];
      for (var qs in results) {
        allPosts.addAll(qs.docs);
      }

      // 5. Gelen tüm postları bellekte tarihe göre (Yeniden Eskiye) sırala
      allPosts.sort((a, b) {
        final ta = (a.data()?['createdAt'] as Timestamp?)?.toDate();
        final tb = (b.data()?['createdAt'] as Timestamp?)?.toDate();
        if (ta == null) return 1; if (tb == null) return -1;
        return tb.compareTo(ta); // Descending (Yeniden eskiye)
      });

      // 6. İlk 50 tanesini göster (Performans için sınırla)
      final finalItems = allPosts.take(50).toList();

      await _fetchAuthors(finalItems);

      // Etkileşim verilerini bekle
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
            
            // Beğeni ve Takip durumu
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
               // Bildirim fonksiyonunu kaldırdık (Cloud Functions hallediyor)
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
