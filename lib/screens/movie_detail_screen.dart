
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

import 'package:fluttergirdi/models/shelf_target.dart';
import 'package:fluttergirdi/services/catalog_service.dart';
import 'package:fluttergirdi/services/custom_list_service.dart';
import 'package:fluttergirdi/models/custom_list.dart';
import 'package:cloud_functions/cloud_functions.dart';
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

  @override
  void initState() {
    super.initState();
    _fetchDetails();
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
    // YENİ: Cloud Functions Kullanımı
    final result = await FirebaseFunctions.instance.httpsCallable('callTMDB').call({
      'endpoint': '/3/movie/${widget.tmdbId}',
      'params': {
        'language': 'tr-TR',
        'append_to_response': 'credits,release_dates'
      }
    });

    final data = Map<String, dynamic>.from(result.data as Map);
    
    if (mounted) {
      setState(() {
        _movieData = data;
        // Credits verisi de bir Map olduğu için onu da güvenli almak gerekebilir:
        final Map credits = data['credits'] ?? {};
        _cast = credits['cast'] ?? [];
        _crew = credits['crew'] ?? [];
        _loading = false;
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
          // Film verilerini buradaki yapıya göre gönderiyoruz
          initialMovie: {
            'id': widget.tmdbId,
            'title': _movieData!['title'],
            'poster': widget.posterUrl,
          },
          onSend: ({required text, movie, images, rating, required isSpoiler, tags, reviewTitle}) async {
            final user = FirebaseAuth.instance.currentUser;
            if (user == null) return;

            List<String> postImageUrls = [];
            
            // 1. Resimleri Firebase Storage'a yükle
            if (images != null && images.isNotEmpty) {
              for (var i = 0; i < images.length; i++) {
                final image = images[i];
                final String fileName = '${user.uid}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
                final ref = FirebaseStorage.instance.ref().child('post_images').child(fileName);
                await ref.putFile(image);
                final url = await ref.getDownloadURL();
                postImageUrls.add(url);
              }
            }

            // 2. FeedService üzerinden gönderiyi oluştur
            await FeedService.instance.createPost(
              text: text,
              movie: movie,
              photoURL: postImageUrls.isNotEmpty ? postImageUrls.first : null,
              photoURLs: postImageUrls,
              displayName: user.displayName,
              handle: user.email?.split('@')[0],
              rating: rating,
              isSpoiler: isSpoiler,
              tags: tags,
              reviewTitle: reviewTitle,
            );
            
            if (context.mounted) {
              Navigator.pop(context); // Paylaşım sayfasını kapat
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Gönderiniz Paylaşıldı!'), behavior: SnackBarBehavior.floating)
              );
            }
          },
        ),
      ),
    );
  }
  // --- KATALOG VE LİSTE İŞLEMLERİ ---

  Future<String?> _registerMovieToCatalog() async {
  if (_movieData == null) return null;
  return await CatalogService().upsertFromTmdb(_movieData!); // ID'yi döndür
}

// 2. Metot: Listeye ekleme mantığını ve field isimlerini düzeltin
Future<void> _addToStandardList(ShelfTarget target) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null || _movieData == null) return;

  // Önce kataloğa kaydet ve sistemdeki gerçek ID'yi (primaryKey) al
  final String? primaryKey = await _registerMovieToCatalog(); 
  if (primaryKey == null) return;

  final db = FirebaseFirestore.instance;
  final batch = db.batch();

  // Koleksiyon field isimlerini belirle
  String field = '';
  switch (target) {
    case ShelfTarget.fiveStar: field = 'fiveStarKeys'; break;
    case ShelfTarget.disliked: field = 'dislikedKeys'; break;
    case ShelfTarget.favorites: field = 'favoritesKeys'; break;
    case ShelfTarget.watchlist: field = 'watchlistKeys'; break;
  }

  final userRef = db.collection('users').doc(user.uid);
  batch.set(userRef, {
    field: FieldValue.arrayUnion([primaryKey]),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  // Taste Profile güncellemeleri (Field isimleri shelf_target.dart ile aynı olmalı)
  final tasteRef = db.collection('userTasteProfiles').doc(user.uid);
  if (target == ShelfTarget.fiveStar) {
    batch.set(tasteRef, {
      'fiveStars': FieldValue.arrayUnion([primaryKey]), // 'loved' yerine 'fiveStars'
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } else if (target == ShelfTarget.disliked) {
    batch.set(tasteRef, {
      'lowRatings': FieldValue.arrayUnion([primaryKey]), // 'disliked' yerine 'lowRatings'
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

    await batch.commit();

    if (mounted) {
      Navigator.pop(context); // Sheet'i kapat
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_movieData!['title']} listeye eklendi!'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _addToCustomList(String listId, String listTitle) async {
    if (_movieData == null) return;
    
    // CustomList servisi movie map'i bekler
    final movieMap = {
      'id': widget.tmdbId,
      'title': _movieData!['title'],
      'poster': _movieData!['poster_path'] != null 
          ? 'https://image.tmdb.org/t/p/w500${_movieData!['poster_path']}' 
          : null,
    };

    await CustomListService.instance.addMovieToList(listId, movieMap);

    if (mounted) {
      Navigator.pop(context); // Sheet'i kapat
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_movieData!['title']}, "$listTitle" listesine eklendi.'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  void _showAddSheet() {
    if (_movieData == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                    width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Listelere Ekle', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                
                // STANDART LİSTELER (Grid)
                const Text('Profil Listeleri', style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 4,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  children: [
                    _buildQuickAction(Icons.bookmark_add_rounded, 'İzlenecekler', Colors.blue, () => _addToStandardList(ShelfTarget.watchlist)),
                    _buildQuickAction(Icons.favorite_rounded, 'Favoriler', Colors.pink, () => _addToStandardList(ShelfTarget.favorites)),
                    _buildQuickAction(Icons.star_rounded, 'Sevdiklerim', Colors.amber, () => _addToStandardList(ShelfTarget.fiveStar)),
                    _buildQuickAction(Icons.thumb_down_rounded, 'Sevmedim', Colors.redAccent, () => _addToStandardList(ShelfTarget.disliked)),
                  ],
                ),
                
                const Divider(height: 40),
                
                // ÖZEL LİSTELER
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Özel Listelerim', style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
                    
                  ],
                ),
                
                StreamBuilder<List<CustomList>>(
                  stream: CustomListService.instance.getUserLists(uid),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final lists = snapshot.data ?? [];
                    if (lists.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('Henüz özel bir listen yok.', style: TextStyle(color: Colors.grey)),
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
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade800,
                              borderRadius: BorderRadius.circular(8),
                              image: list.coverImageUrl != null 
                                ? DecorationImage(image: NetworkImage(list.coverImageUrl!), fit: BoxFit.cover)
                                : null,
                            ),
                            child: list.coverImageUrl == null ? const Icon(Icons.list, color: Colors.white54) : null,
                          ),
                          title: Text(list.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${list.movieCount} film', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          trailing: const Icon(Icons.add_circle_outline),
                          onTap: () => _addToCustomList(list.id, list.title),
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

  Widget _buildQuickAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  // --- GETTERS ---
 /// 1. Yazı olarak isim döndüren metot (Hatanı bu çözecek)
  String get _director {
    final d = _crew.firstWhere((m) => m['job'] == 'Director', orElse: () => null);
    return d != null ? d['name'] : 'Bilinmiyor';
  }

  // 2. Tıklanma ve detaylar için tüm veriyi döndüren metot
  Map<String, dynamic>? get _directorData {
    if (_crew.isEmpty) return null;
    try {
      return _crew.firstWhere((m) => m['job'] == 'Director');
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
            decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
            child: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            onPressed: _showAddSheet,
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
              child: const Icon(Icons.playlist_add_rounded, color: Colors.white),
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
                  CachedNetworkImage(imageUrl: widget.posterUrl!, fit: BoxFit.cover),
                  BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Container(color: bgColor.withOpacity(0.85)),
                  ),
                ],
              ),
            ),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_hasError || _movieData == null)
            Center(child: Text("Detaylar yüklenemedi", style: TextStyle(color: textColor)))
          else
            SingleChildScrollView(
              // KRİTİK: Yanlardaki 20 padding'i kaldırdık (Sadece üst ve alt kaldı)
              padding: EdgeInsets.fromLTRB(0, MediaQuery.of(context).padding.top + 60, 0, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- 1. POSTER & BAŞLIK (Padding eklendi) ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Hero(
                          tag: 'poster_${widget.tmdbId}',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: CachedNetworkImage(
                              imageUrl: widget.posterUrl ?? '',
                              width: 140, height: 210, fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _movieData!['title'],
                                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor, height: 1.2),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (_year.isNotEmpty) _buildTag(_year, isDark),
                                  if (_runtime.isNotEmpty) _buildTag(_runtime, isDark),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Icon(Icons.star_rounded, color: Colors.amber, size: 28),
                                  const SizedBox(width: 4),
                                  Text(_rating, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: textColor)),
                                ],
                              ),
                              GestureDetector(
  onTap: () {
    final director = _directorData;
    if (director != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ActorScreen(
            actorId: director['id'],
            actorName: director['name'],
          ),
        ),
      );
    }
  },
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        "Yönetmen",
        style: TextStyle(
          fontSize: 12, 
          fontWeight: FontWeight.w500, 
          color: textColor.withOpacity(0.5),
          letterSpacing: 0.5,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        _director, // Mevcut getter metot isminiz
        style: TextStyle(
          fontSize: 15, 
          fontWeight: FontWeight.w600, 
          color: textColor,
          decoration: TextDecoration.underline, // Tıklanabilir olduğunu belli etmek için
          decorationColor: textColor.withOpacity(0.3),
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

                  // --- 2. ÖZET (Padding eklendi) ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Özet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                        const SizedBox(height: 8),
                        Text(
                          _movieData!['overview'] ?? 'Özet bulunamadı.',
                          style: TextStyle(fontSize: 15, color: textColor.withOpacity(0.8), height: 1.6),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // --- 3. OYUNCULAR (Padding eklendi) ---
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text("Oyuncular", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 130,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20), // ListView içi padding
                      itemCount: _cast.length > 10 ? 10 : _cast.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 16),
                      itemBuilder: (context, index) {
  final actor = _cast[index];
  return GestureDetector(
    onTap: () {
      // OYUNCU SAYFASINA GİT
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
          backgroundImage: actor['profile_path'] != null 
              ? NetworkImage('https://image.tmdb.org/t/p/w200${actor['profile_path']}') 
              : null,
          child: actor['profile_path'] == null ? const Icon(Icons.person) : null,
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 80,
          child: Text(
            actor['name'], 
            maxLines: 2, 
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.9)),
          ),
        ),
      ],
    ),
  );
},
                    ),
                  ),

                  const SizedBox(height: 30),

                  // --- 4. GÖNDERİLER BÖLÜMÜ (KENARA SIFIR ARKA PLAN) ---
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('posts')
                        .where(Filter.or(
                          Filter('movie.id', isEqualTo: widget.tmdbId.toString()),
                          Filter('movie.id', isEqualTo: widget.tmdbId),
                          Filter('movie.tmdbId', isEqualTo: widget.tmdbId),
                          Filter('movieTmdbId', isEqualTo: widget.tmdbId),
                        ))
                        .limit(10)
                        .snapshots(),
                    builder: (context, snapshot) {
                      final docs = snapshot.data?.docs ?? [];
                      final hasPosts = docs.isNotEmpty;

                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 30),
                        decoration: BoxDecoration(
                          // POST VARSA: Yanlardaki boşluğu kapatmak için tam tema rengi
                          color: hasPosts ? bgColor : Colors.transparent,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Text(
                                "Bu Film Hakkında Söylenenler", 
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)
                              ),
                            ),
                            const SizedBox(height: 20),

                            if (snapshot.connectionState == ConnectionState.waiting)
                              const Center(child: CircularProgressIndicator())
                            
                            else if (!hasPosts)
                              // --- BOŞ DURUM: PAYLAŞIMA YÖNLENDİREN KUTU ---
                              GestureDetector(
                                onTap: () => _navigateToCompose(context), // <--- BURASI GÜNCELLENDİ
                                child: Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.symmetric(horizontal: 20),
                                  padding: const EdgeInsets.all(30),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(Icons.add_comment_rounded, color: textColor.withOpacity(0.4), size: 40),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Henüz kimse bir şey söylememiş.\nİlk yorumu sen yaparak tartışmayı başlat!',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 14, height: 1.5),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              // --- POST LİSTESİ ---
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                itemCount: docs.length,
                                separatorBuilder: (context, index) => const SizedBox(height: 16),
                                itemBuilder: (context, index) {
                                  final d = docs[index];
                                  final m = d.data() as Map<String, dynamic>;
                                  return PostTile(
                                    postId: d.id,
                                    authorId: (m['authorId'] ?? '').toString(),
                                    displayName: (m['displayName'] ?? '').toString(),
                                    handle: (m['handle'] ?? '').toString(),
                                    photoURL: (m['photoURL'] ?? '').toString(),
                                    timeLabel: m['createdAt'] == null ? '' : _timeAgo((m['createdAt'] as Timestamp).toDate()),
                                    text: (m['text'] ?? '').toString(),
                                    movieTitle: m['movieTitle'] ?? (m['movie'] != null ? m['movie']['title'] : null),
                                    moviePoster: m['moviePoster'] ?? (m['movie'] != null ? m['movie']['poster'] : null),
                                    movieTmdbId: _parseTmdbId(m),
                                    postImage: m['postImage'],
                                    postImages: List<String>.from(m['photoURLs'] ?? []),
                                    rating: (m['rating'] as num?)?.toDouble(),
                                    isSpoiler: m['isSpoiler'] == true,
                                    tags: List<String>.from(m['tags'] ?? []),
                                    reviewTitle: m['reviewTitle'] as String?,
                                    likeCount: ((m['likeCount'] ?? 0) as num).toInt(),
                                    replyCount: ((m['replyCount'] ?? 0) as num).toInt(),
                                    initialIsLiked: false,
                                    initialIsFollowing: false,
                                    onToggleLike: (pid, val) => FeedService.instance.toggleLike(postId: pid, like: val),
                                    onStartChat: (uid) {},
                                    onFollow: (uid) => FeedService.instance.followUser(uid),
                                    onReport: (pid) => FeedService.instance.reportPost(pid),
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
        color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black87)),
    );
  }
}