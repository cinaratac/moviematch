import 'dart:async';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/actors_screen.dart';
import 'package:fluttergirdi/widgets/compose_post_sheet.dart';
import 'package:fluttergirdi/widgets/post_tile.dart';
import 'package:fluttergirdi/services/feed_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluttergirdi/screens/director_screen.dart';
import 'package:fluttergirdi/models/shelf_target.dart';
import 'package:fluttergirdi/services/catalog_service.dart';
import 'package:fluttergirdi/services/custom_list_service.dart';
import 'package:fluttergirdi/models/custom_list.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fluttergirdi/services/user_profile_service.dart';
import 'package:fluttergirdi/services/streak_service.dart';

class MovieDetailScreen extends StatefulWidget {
  final int tmdbId;
  final String? title;
  final String? posterUrl;

  const MovieDetailScreen({
    super.key,
    required this.tmdbId,
    this.title,
    this.posterUrl,
  });

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  Map<String, dynamic>? _movieData;
  List<dynamic> _cast = [];
  List<dynamic> _crew = [];
  bool _loading = true;
  bool _hasError = false;

  String? _catalogDocId;

  // Stream nesneleri – sadece StreamBuilder'lara veriliyor, ayrıca .listen() YOK
  Stream<DocumentSnapshot>? _userProfileStream;
  Stream<List<CustomList>>? _customListsStream;

  // Cache: stream'den gelen son veriyi tutuyoruz
  // StreamBuilder'lar zaten veriyi kendileri yönetiyor;
  // bu cache sadece bottom sheet ilk açıldığında boş göstermemek için.
  Map<String, dynamic>? _userProfileCache;
  List<CustomList>? _customListsCache;

  // ÖNEMLİ: .listen() kullandığımız subscription'ları burada saklıyoruz
  // ki dispose()'da iptal edebilelim.
  StreamSubscription<DocumentSnapshot>? _profileSub;
  StreamSubscription<List<CustomList>>? _listsSub;

  @override
  void initState() {
    super.initState();
    _fetchDetails();
    _initStreams();
  }

  void _initStreams() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Stream nesnelerini oluştur (StreamBuilder için)
    _userProfileStream =
        FirebaseFirestore.instance.collection('users').doc(uid).snapshots();

    _customListsStream = CustomListService.instance.getUserLists(uid);

    // Cache güncellemek için .listen() – subscription'ı MUTLAKA kaydet
    _profileSub = _userProfileStream!.listen((snap) {
      if (mounted) {
        setState(() {
          _userProfileCache = snap.data() as Map<String, dynamic>?;
        });
      }
    });

    _listsSub = _customListsStream!.listen((lists) {
      if (mounted) {
        setState(() {
          _customListsCache = lists;
        });
      }
    });
  }

  @override
  void dispose() {
    // Stream'leri burada iptal ediyoruz.
    // Bu olmazsa Firestore listener'ları arka planda sonsuza dek çalışır,
    // her değişiklikte kapalı ekrana setState yapmaya çalışır ve
    // tüm uygulamayı yavaşlatır.
    _profileSub?.cancel();
    _listsSub?.cancel();
    super.dispose();
  }

  String _timeAgo(DateTime dt) {
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

  Future<void> _fetchDetails() async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('callTMDB')
          .call({
        'endpoint': '/3/movie/${widget.tmdbId}',
        'params': {
          'language': 'tr-TR',
          'append_to_response': 'credits,release_dates',
        },
      });

      final data = Map<String, dynamic>.from(result.data as Map);

      if (mounted) {
        setState(() {
          _movieData = data;
          final Map credits = data['credits'] ?? {};
          _cast = credits['cast'] ?? [];
          _crew = credits['crew'] ?? [];
          _loading = false;
        });

        // Catalog kaydını arka planda yap, UI'ı bekleme
        CatalogService().upsertFromTmdb(data).then((docId) {
          if (mounted) setState(() => _catalogDocId = docId);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _hasError = true;
        });
      }
    }
  }

  void _navigateToCompose(BuildContext context) {
    if (_movieData == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComposePostPage(
          maxChars: 280,
          initialMovie: {
            'id': widget.tmdbId,
            'title': _movieData!['title'],
            'poster': widget.posterUrl,
          },
          onSend: ({
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

            List<String> postImageUrls = [];
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
                postImageUrls.add(url);
              }
            }

            await FeedService.instance.createPost(
              text: text,
              movie: movie,
              photoURL:
                  postImageUrls.isNotEmpty ? postImageUrls.first : null,
              photoURLs: postImageUrls,
              displayName: user.displayName,
              handle: user.email?.split('@')[0],
              rating: rating,
              isSpoiler: isSpoiler,
              tags: tags,
              reviewTitle: reviewTitle,
            );

            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Gönderiniz Paylaşıldı!'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _toggleWatched(bool isCurrentlyAdded) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _movieData == null) return;

    final title = _movieData!['title'];
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(isCurrentlyAdded
          ? "'$title', izlediklerimden çıkarıldı."
          : "'$title', izledim olarak işaretlendi."),
      backgroundColor: isCurrentlyAdded ? Colors.redAccent : Colors.teal,
      behavior: SnackBarBehavior.floating,
    ));

    UserProfileService.instance.fastToggleWatched(
      uid: user.uid,
      movieData: _movieData!,
      tmdbId: widget.tmdbId,
      catalogDocId: _catalogDocId,
      isCurrentlyAdded: isCurrentlyAdded,
    );

    // --- STREAK TETİKLEYİCİSİ BURAYA EKLENDİ ---
    // Eğer listeye yeni ekleniyorsa (çıkarılmıyorsa) seriyi kontrol et
    if (!isCurrentlyAdded) {
      StreakService.instance.triggerAction(context);
    }
  }

  Future<void> _toggleStandardList(
      ShelfTarget target, bool isCurrentlyAdded) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _movieData == null) return;

    final title = _movieData!['title'];
    Navigator.pop(context);

    final targetName = switch (target) {
      ShelfTarget.fiveStar  => 'Sevdiklerim',
      ShelfTarget.disliked  => 'Sevmedim',
      ShelfTarget.favorites => 'Favoriler',
      ShelfTarget.watchlist => 'İzlenecekler',
    };

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(isCurrentlyAdded
          ? "'$title', $targetName listesinden çıkartıldı."
          : "'$title', $targetName listesine eklendi."),
      backgroundColor:
          isCurrentlyAdded ? Colors.redAccent : Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
    ));

    UserProfileService.instance.fastToggleStandardList(
      uid: user.uid,
      movieData: _movieData!,
      tmdbId: widget.tmdbId,
      catalogDocId: _catalogDocId,
      target: target,
      isCurrentlyAdded: isCurrentlyAdded,
      posterUrl: widget.posterUrl,
    );

    // --- STREAK TETİKLEYİCİSİ BURAYA EKLENDİ ---
    // Eğer listeye yeni ekleniyorsa VE bu liste Watchlist DEĞİLSE seriyi kontrol et
    if (!isCurrentlyAdded && target != ShelfTarget.watchlist) {
      StreakService.instance.triggerAction(context);
    }
  }

  
  Future<void> _addToCustomList(String listId, String listTitle) async {
    if (_movieData == null) return;
    final messenger = ScaffoldMessenger.of(context);

    final query = await FirebaseFirestore.instance
        .collection('custom_lists')
        .doc(listId)
        .collection('items')
        .where('id', isEqualTo: widget.tmdbId)
        .get();

    if (query.docs.isNotEmpty) {
      messenger.showSnackBar(SnackBar(
        content: Text('Bu film zaten "$listTitle" listesinde ekli!'),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ));
      Navigator.pop(context);
      return;
    }

    Navigator.pop(context);

    final movieMap = {
      'id': widget.tmdbId,
      'title': _movieData!['title'],
      'poster': _movieData!['poster_path'] != null
          ? 'https://image.tmdb.org/t/p/w500${_movieData!['poster_path']}'
          : null,
    };

    CustomListService.instance.addMovieToList(listId, movieMap);

    messenger.showSnackBar(SnackBar(
      content:
          Text('${_movieData!['title']}, "$listTitle" listesine eklendi.'),
      backgroundColor: Colors.green.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showAddSheet() {
    if (_movieData == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (context) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) return const SizedBox.shrink();

        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Listelere Ekle',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                const Text('Profil Listeleri',
                    style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),

                // StreamBuilder – stream'i initState'de açtık, burada sadece dinliyoruz.
                // Ayrıca .listen() YOK, bu yüzden subscription sızıntısı olmaz.
                StreamBuilder<DocumentSnapshot>(
                  stream: _userProfileStream,
                  builder: (context, snapshot) {
                    final data =
                        snapshot.data?.data() as Map<String, dynamic>? ??
                            _userProfileCache ??
                            {};

                    // Tek seferinde Set'e dönüştür – döngü içinde tekrar hesaplama yok
                    final watchedSet   = _toNormalizedSet(data['watchedKeys']);
                    final watchlistSet = _toNormalizedSet(data['watchlistKeys']);
                    final favoritesSet = _toNormalizedSet(data['favoritesKeys']);
                    final fiveStarSet  = _toNormalizedSet(data['fiveStarKeys']);
                    final dislikedSet  = _toNormalizedSet(data['dislikedKeys']);

                    final tmdbStr = widget.tmdbId.toString();
                    final catalogId = _catalogDocId?.toLowerCase();

                    bool isIn(Set<String> set) =>
                        set.contains(tmdbStr) ||
                        (catalogId != null && set.contains(catalogId));

                    return GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 3,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      children: [
                        _buildQuickAction(Icons.visibility_rounded, 'İzledim',
                            Colors.teal, isIn(watchedSet),
                            () => _toggleWatched(isIn(watchedSet))),
                        _buildQuickAction(Icons.bookmark_add_rounded,
                            'İzlenecekler', Colors.blue, isIn(watchlistSet),
                            () => _toggleStandardList(ShelfTarget.watchlist, isIn(watchlistSet))),
                        _buildQuickAction(Icons.favorite_rounded, 'Favoriler',
                            Colors.pink, isIn(favoritesSet),
                            () => _toggleStandardList(ShelfTarget.favorites, isIn(favoritesSet))),
                        _buildQuickAction(Icons.star_rounded, 'Sevdiklerim',
                            Colors.amber, isIn(fiveStarSet),
                            () => _toggleStandardList(ShelfTarget.fiveStar, isIn(fiveStarSet))),
                        _buildQuickAction(Icons.thumb_down_rounded, 'Sevmedim',
                            Colors.redAccent, isIn(dislikedSet),
                            () => _toggleStandardList(ShelfTarget.disliked, isIn(dislikedSet))),
                      ],
                    );
                  },
                ),

                const Divider(height: 40),
                const Text('Özel Listelerim',
                    style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold)),

                StreamBuilder<List<CustomList>>(
                  stream: _customListsStream,
                  initialData: _customListsCache,
                  builder: (context, snapshot) {
                    final lists =
                        snapshot.data ?? _customListsCache ?? [];

                    if (snapshot.connectionState ==
                            ConnectionState.waiting &&
                        lists.isEmpty) {
                      return const SizedBox(
                          height: 100,
                          child:
                              Center(child: CircularProgressIndicator()));
                    }

                    if (lists.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('Henüz özel bir listen yok.',
                            style: TextStyle(color: Colors.grey)),
                      );
                    }

                    return ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: lists.length,
                      itemBuilder: (context, index) {
                        final list = lists[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade800,
                              borderRadius: BorderRadius.circular(8),
                              image: list.coverImageUrl != null
                                  ? DecorationImage(
                                      image: NetworkImage(
                                          list.coverImageUrl!),
                                      fit: BoxFit.cover)
                                  : null,
                            ),
                            child: list.coverImageUrl == null
                                ? const Icon(Icons.list,
                                    color: Colors.white54)
                                : null,
                          ),
                          title: Text(list.title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                          subtitle: Text('${list.movieCount} film',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                          trailing:
                              const Icon(Icons.add_circle_outline),
                          onTap: () =>
                              _addToCustomList(list.id, list.title),
                        );
                      },
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Liste verilerini normalize edilmiş Set'e dönüştür.
  /// Bu sayede checkIsAdded her render'da tekrar dönüşüm yapmaz.
  Set<String> _toNormalizedSet(dynamic raw) {
    if (raw == null) return {};
    return List<dynamic>.from(raw as List)
        .map((e) => e.toString().trim().toLowerCase())
        .toSet();
  }

  Widget _buildQuickAction(
    IconData icon,
    String label,
    Color color,
    bool isAdded,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isAdded ? color : color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isAdded ? Icons.check_rounded : icon,
              color: isAdded ? Colors.white : color,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight:
                  isAdded ? FontWeight.bold : FontWeight.w600,
              color: isAdded ? color : Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String get _director {
    final d = _crew.firstWhere(
      (m) => m['job'] == 'Director',
      orElse: () => null,
    );
    return d != null ? d['name'] : 'Bilinmiyor';
  }

  Map<String, dynamic>? get _directorData {
    if (_crew.isEmpty) return null;
    try {
      final d = _crew.firstWhere((m) => m['job'] == 'Director');
      return Map<String, dynamic>.from(d as Map);
    } catch (e) {
      return null;
    }
  }

  String get _rating => _movieData != null
      ? (_movieData!['vote_average'] as num).toStringAsFixed(1)
      : '-';

  String get _runtime {
    if (_movieData == null) return '';
    final mins = _movieData!['runtime'] as int?;
    if (mins == null || mins == 0) return '';
    final h = mins ~/ 60;
    final m = mins % 60;
    return '${h}s ${m}dk';
  }

  String get _year {
    if (_movieData == null) return '';
    final date = _movieData!['release_date'] as String?;
    if (date == null || date.length < 4) return '';
    return date.substring(0, 4);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final textColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Colors.black26,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            onPressed: _showAddSheet,
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Colors.black26,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.playlist_add_rounded,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          if (widget.posterUrl != null)
            Positioned.fill(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: widget.posterUrl!,
                    fit: BoxFit.cover,
                  ),
                  BackdropFilter(
                    filter:
                        ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child:
                        Container(color: bgColor.withOpacity(0.85)),
                  ),
                ],
              ),
            ),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_hasError || _movieData == null)
            Center(
              child: Text("Detaylar yüklenemedi",
                  style: TextStyle(color: textColor)),
            )
          else
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                0,
                MediaQuery.of(context).padding.top + 60,
                0,
                40,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Hero(
                          tag: 'poster_${widget.tmdbId}',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: CachedNetworkImage(
                              imageUrl: widget.posterUrl ?? '',
                              width: 140,
                              height: 210,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                _movieData!['title'],
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (_year.isNotEmpty)
                                    _buildTag(_year, isDark),
                                  if (_runtime.isNotEmpty)
                                    _buildTag(_runtime, isDark),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Icon(Icons.star_rounded,
                                      color: Colors.amber, size: 28),
                                  const SizedBox(width: 4),
                                  Text(
                                    _rating,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: textColor,
                                    ),
                                  ),
                                ],
                              ),
                              GestureDetector(
                                onTap: () {
                                  final director = _directorData;
                                  if (director != null &&
                                      director['id'] != null) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => DirectorScreen(
                                          directorId:
                                              director['id'] as int,
                                          directorName:
                                              director['name'] ??
                                                  'Bilinmiyor',
                                        ),
                                      ),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(const SnackBar(
                                      content: Text(
                                          'Yönetmen bilgisi bulunamadı.'),
                                    ));
                                  }
                                },
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Yönetmen",
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color:
                                            textColor.withOpacity(0.5),
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _director,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: textColor,
                                        decoration:
                                            TextDecoration.underline,
                                        decorationColor:
                                            textColor.withOpacity(0.3),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Özet",
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: textColor)),
                        const SizedBox(height: 8),
                        Text(
                          _movieData!['overview'] ?? 'Özet bulunamadı.',
                          style: TextStyle(
                            fontSize: 15,
                            color: textColor.withOpacity(0.8),
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20),
                    child: Text("Oyuncular",
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: textColor)),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 130,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 20),
                      itemCount:
                          _cast.length > 10 ? 10 : _cast.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(width: 16),
                      itemBuilder: (context, index) {
                        final actor = _cast[index];
                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ActorScreen(
                                  actorId: actor['id'],
                                  actorName: actor['name'],
                                ),
                              ),
                            );
                          },
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 35,
                                backgroundColor: Colors.grey.shade800,
                                backgroundImage:
                                    actor['profile_path'] != null
                                        ? NetworkImage(
                                            'https://image.tmdb.org/t/p/w200${actor['profile_path']}')
                                        : null,
                                child: actor['profile_path'] == null
                                    ? const Icon(Icons.person)
                                    : null,
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: 80,
                                child: Text(
                                  actor['name'],
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: textColor.withOpacity(0.9),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 30),

                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('posts')
                        .where(
                          Filter.or(
                            Filter('movie.id',
                                isEqualTo: widget.tmdbId.toString()),
                            Filter('movie.id',
                                isEqualTo: widget.tmdbId),
                            Filter('movie.tmdbId',
                                isEqualTo: widget.tmdbId),
                            Filter('movieTmdbId',
                                isEqualTo: widget.tmdbId),
                          ),
                        )
                        .limit(10)
                        .snapshots(),
                    builder: (context, snapshot) {
                      final docs = snapshot.data?.docs ?? [];
                      final hasPosts = docs.isNotEmpty;

                      return Container(
                        width: double.infinity,
                        padding:
                            const EdgeInsets.symmetric(vertical: 30),
                        decoration: BoxDecoration(
                          color: hasPosts ? bgColor : Colors.transparent,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20),
                              child: Text(
                                "Bu Film Hakkında Söylenenler",
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: textColor),
                              ),
                            ),
                            const SizedBox(height: 20),
                            if (snapshot.connectionState ==
                                ConnectionState.waiting)
                              const Center(
                                  child: CircularProgressIndicator())
                            else if (!hasPosts)
                              GestureDetector(
                                onTap: () =>
                                    _navigateToCompose(context),
                                child: Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  padding: const EdgeInsets.all(30),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withOpacity(0.05)
                                        : Colors.black.withOpacity(0.05),
                                    borderRadius:
                                        BorderRadius.circular(20),
                                    border: Border.all(
                                        color: isDark
                                            ? Colors.white12
                                            : Colors.black12),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(Icons.add_comment_rounded,
                                          color:
                                              textColor.withOpacity(0.4),
                                          size: 40),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Henüz kimse bir şey söylememiş.\nİlk yorumu sen yaparak tartışmayı başlat!',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color:
                                              textColor.withOpacity(0.7),
                                          fontSize: 14,
                                          height: 1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics:
                                    const NeverScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20),
                                itemCount: docs.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 16),
                                itemBuilder: (context, index) {
                                  final d = docs[index];
                                  final m = d.data()
                                      as Map<String, dynamic>;
                                  return PostTile(
                                    postId: d.id,
                                    authorId: (m['authorId'] ?? '')
                                        .toString(),
                                    displayName:
                                        (m['displayName'] ?? '')
                                            .toString(),
                                    handle:
                                        (m['handle'] ?? '').toString(),
                                    photoURL:
                                        (m['photoURL'] ?? '').toString(),
                                    timeLabel: m['createdAt'] == null
                                        ? ''
                                        : _timeAgo(
                                            (m['createdAt'] as Timestamp)
                                                .toDate()),
                                    text: (m['text'] ?? '').toString(),
                                    movieTitle: m['movieTitle'] ??
                                        (m['movie'] != null
                                            ? m['movie']['title']
                                            : null),
                                    moviePoster: m['moviePoster'] ??
                                        (m['movie'] != null
                                            ? m['movie']['poster']
                                            : null),
                                    movieTmdbId: _parseTmdbId(m),
                                    postImage: m['postImage'],
                                    postImages: List<String>.from(
                                        m['photoURLs'] ?? []),
                                    rating: (m['rating'] as num?)
                                        ?.toDouble(),
                                    isSpoiler: m['isSpoiler'] == true,
                                    tags: List<String>.from(
                                        m['tags'] ?? []),
                                    reviewTitle:
                                        m['reviewTitle'] as String?,
                                    likeCount:
                                        ((m['likeCount'] ?? 0) as num)
                                            .toInt(),
                                    replyCount:
                                        ((m['replyCount'] ?? 0) as num)
                                            .toInt(),
                                    initialIsLiked: false,
                                    initialIsFollowing: false,
                                    onToggleLike: (pid, val) =>
                                        FeedService.instance.toggleLike(
                                            postId: pid, like: val),
                                    onStartChat: (uid) {},
                                    onFollow: (uid) => FeedService
                                        .instance
                                        .followUser(uid),
                                    onReport: (pid) => FeedService
                                        .instance
                                        .reportPost(pid),
                                  );
                                },
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTag(String text, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white10
            : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: isDark ? Colors.white24 : Colors.black12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white70 : Colors.black87,
        ),
      ),
    );
  }
}