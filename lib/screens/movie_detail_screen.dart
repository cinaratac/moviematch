
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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

    final data = result.data as Map<String, dynamic>;
    
    if (mounted) {
      setState(() {
        _movieData = data;
        _cast = data['credits']['cast'] ?? [];
        _crew = data['credits']['crew'] ?? [];
        _loading = false;
      });
    }
  } catch (e) {
    debugPrint('Film detayı çekilemedi: $e');
    if (mounted) {
      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
  }
}

  // --- KATALOG VE LİSTE İŞLEMLERİ ---

  Future<void> _registerMovieToCatalog() async {
    if (_movieData == null) return;
    // Filmi kataloğa kaydet/güncelle ki ID'si sistemde geçerli olsun
    await CatalogService().upsertFromTmdb(_movieData!);
  }

  Future<void> _addToStandardList(ShelfTarget target) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _movieData == null) return;

    // Önce kataloğa kaydet
    await _registerMovieToCatalog();

    final String primaryKey = CatalogService.canonicalKeyFromTmdb(widget.tmdbId);
    final db = FirebaseFirestore.instance;
    final batch = db.batch();

    // 1. Kullanıcı ana dökümanına ekle (Hızlı erişim ve profil görünümü için)
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

    // 2. Taste Profile (Algoritma için) güncellemesi
    // Beğenilen veya Sevilmeyen olarak işaretlendiyse taste profile da güncellenmeli
    if (target == ShelfTarget.fiveStar) {
      final tasteRef = db.collection('userTasteProfiles').doc(user.uid);
      batch.set(tasteRef, {
        'loved': FieldValue.arrayUnion([primaryKey]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else if (target == ShelfTarget.disliked) {
      final tasteRef = db.collection('userTasteProfiles').doc(user.uid);
      batch.set(tasteRef, {
        'disliked': FieldValue.arrayUnion([primaryKey]),
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
  String get _director {
    final d = _crew.firstWhere((m) => m['job'] == 'Director', orElse: () => null);
    return d != null ? d['name'] : 'Bilinmiyor';
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
          // YENİ EKLE BUTONU
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
          // 1. ARKA PLAN (Blur Efekti)
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

          // 2. İÇERİK
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_hasError || _movieData == null)
            Center(child: Text("Detaylar yüklenemedi", style: TextStyle(color: textColor)))
          else
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 60, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // POSTER & BAŞLIK ALANI
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Poster
                      Hero(
                        tag: 'poster_${widget.tmdbId}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: CachedNetworkImage(
                            imageUrl: widget.posterUrl ?? '',
                            width: 140,
                            height: 210,
                            fit: BoxFit.cover,
                            errorWidget: (_,__,___) => Container(color: Colors.grey, width: 140, height: 210),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      
                      // Bilgiler
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
                                if(_year.isNotEmpty) _buildTag(_year, isDark),
                                if(_runtime.isNotEmpty) _buildTag(_runtime, isDark),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Puan
                            Row(
                              children: [
                                const Icon(Icons.star_rounded, color: Colors.amber, size: 28),
                                const SizedBox(width: 4),
                                Text(
                                  _rating,
                                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: textColor),
                                ),
                                Text(
                                  '/10',
                                  style: TextStyle(fontSize: 14, color: textColor.withOpacity(0.6), height: 2),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Yönetmen:\n$_director",
                              style: TextStyle(fontSize: 14, color: textColor.withOpacity(0.8), height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 30),

                  // ÖZET
                  Text("Özet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 8),
                  Text(
                    _movieData!['overview'] ?? 'Özet bulunamadı.',
                    style: TextStyle(fontSize: 15, color: textColor.withOpacity(0.8), height: 1.6),
                  ),

                  const SizedBox(height: 30),

                  // OYUNCULAR
                  Text("Oyuncular", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 130, // Yüksekliği biraz artırdık ki isimler sığsın
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _cast.length > 10 ? 10 : _cast.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 16),
                      itemBuilder: (context, index) {
                        final actor = _cast[index];
                        final photoPath = actor['profile_path'];
                        return Column(
                          children: [
                            CircleAvatar(
                              radius: 35, // Avatarı biraz büyüttük
                              backgroundColor: Colors.grey.shade800,
                              backgroundImage: photoPath != null 
                                ? NetworkImage('https://image.tmdb.org/t/p/w200$photoPath') 
                                : null,
                              child: photoPath == null ? const Icon(Icons.person) : null,
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
                        );
                      },
                    ),
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