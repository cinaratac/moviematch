import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fluttergirdi/services/match_service.dart' as global_match;
import 'package:fluttergirdi/services/follow_system_service.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';

class FilmItem {
  final String id;
  final String title;
  final String posterUrl;
  final int? tmdbId;

  const FilmItem({
    required this.id,
    required this.title,
    required this.posterUrl,
    this.tmdbId,
  });
}

// GARANTİLİ FİLM ÇEKME FONKSİYONU
Future<List<FilmItem>> fetchFilmsByKeys(List<String> keys) async {
  if (keys.isEmpty) return [];
  final db = FirebaseFirestore.instance;
  final cleanKeys = keys.map((k) => k.trim()).where((k) => k.isNotEmpty).toSet().toList();
  final items = <FilmItem>[];
  
  for (var i = 0; i < cleanKeys.length; i += 10) {
    final chunk = cleanKeys.sublist(i, math.min(i + 10, cleanKeys.length));
    try {
      final qs = await db.collection('catalog_films').where(FieldPath.documentId, whereIn: chunk).get();
      final foundIds = <String>{};
      for (final doc in qs.docs) {
        foundIds.add(doc.id);
        final d = doc.data();
        items.add(FilmItem(
          id: doc.id,
          title: (d['title'] ?? d['name'] ?? '').toString(),
          posterUrl: (d['posterUrl'] ?? d['poster'] ?? '').toString(),
          tmdbId: d['tmdbId'] as int?,
        ));
      }
      for (final id in chunk) {
        if (!foundIds.contains(id)) {
          final doc = await db.collection('catalog_films').doc(id).get();
          if (doc.exists) {
            final d = doc.data()!;
            items.add(FilmItem(
              id: doc.id,
              title: (d['title'] ?? d['name'] ?? '').toString(),
              posterUrl: (d['posterUrl'] ?? d['poster'] ?? '').toString(),
              tmdbId: d['tmdbId'] as int?,
            ));
          }
        }
      }
    } catch (_) {}
  }
  return items;
}

// Simple in-memory cache
class _MatchListSessionCache {
  static List<global_match.MatchResult>? results;
}

class MatchListScreen extends StatefulWidget {
  const MatchListScreen({super.key});

  @override
  State<MatchListScreen> createState() => _MatchListScreenState();
}

class _MatchListScreenState extends State<MatchListScreen> {
  List<global_match.MatchResult> _all = [];
  bool _loading = true;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadMatches({bool forceRefresh = false}) async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    if (forceRefresh) {
      global_match.MatchService.instance.clearCache();
      _MatchListSessionCache.results = null;
    } else {
      if (_MatchListSessionCache.results != null && _MatchListSessionCache.results!.isNotEmpty) {
        _all = _MatchListSessionCache.results!;
        global_match.MatchService.instance.markAsSeen(me.uid, _all.first.uid);
        if (mounted) setState(() => _loading = false);
        return;
      }
    }

    if (mounted) setState(() => _loading = true);

    try {
      final results = await global_match.MatchService.instance.findMatches(me.uid);
      if (!mounted) return;

      _all = results;
      _MatchListSessionCache.results = results;

      if (_all.isNotEmpty) {
        global_match.MatchService.instance.markAsSeen(me.uid, _all.first.uid);
      }

      setState(() {
        _loading = false;
      });

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _all = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Öneriler alınamadı: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;

    if (me == null) {
      return const Scaffold(body: Center(child: Text('Oturum açmanız gerekiyor')));
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black, 
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Önerilen Sinefiller',
          style: TextStyle(
            color: Colors.white, 
            fontWeight: FontWeight.bold, 
            fontSize: 22, 
            shadows: [Shadow(color: Colors.black54, blurRadius: 10)]
          ),
        ),
        centerTitle: true,
        // YENİ: Sağ üst köşeye yenileme butonu eklendi
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 28),
            onPressed: () {
              if (_pageController.hasClients) {
                _pageController.jumpToPage(0); // Listeyi en başa sar
              }
              _loadMatches(forceRefresh: true);
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : _all.isEmpty
              ? const _NoMatchesCharacter()
              // YENİ: RefreshIndicator kaldırıldı, sadece PageView kullanıldı
              : PageView.builder(
                  scrollDirection: Axis.vertical, 
                  controller: _pageController,
                  physics: const BouncingScrollPhysics(), // Daha hassas ve akıcı kaydırma hissi
                  onPageChanged: (index) {
                    if (me != null) {
                      // Kaydırılan kişiyi arka planda sessizce "görüldü" olarak işaretler
                      global_match.MatchService.instance.markAsSeen(me.uid, _all[index].uid);
                    }
                  },
                  itemCount: _all.length,
                  itemBuilder: (context, index) {
                    final m = _all[index];
                    return _VerticalUserCard(
                      key: ValueKey(m.uid),
                      result: m,
                    );
                  },
                ),
    );
  }
}

// ==========================================
// GELİŞMİŞ DİKEY KULLANICI KARTI
// ==========================================
class _VerticalUserCard extends StatefulWidget {
  final global_match.MatchResult result;

  const _VerticalUserCard({super.key, required this.result});

  @override
  State<_VerticalUserCard> createState() => _VerticalUserCardState();
}

class _VerticalUserCardState extends State<_VerticalUserCard> {
  bool _isAdded = false;
  bool _isLoading = false;
  
  Map<String, dynamic>? _userData;
  List<FilmItem>? _commonFilms;
  List<FilmItem>? _favoriteFilms;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;
    
    try {
      final followDoc = await FirebaseFirestore.instance.collection('users').doc(me).collection('following').doc(widget.result.uid).get();
      if (mounted) setState(() => _isAdded = followDoc.exists);
    } catch (_) {}

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(widget.result.uid).get();
      if (mounted && doc.exists) {
        setState(() => _userData = doc.data());
        final data = doc.data()!;
        var favKeys = List<String>.from(data['favoritesKeys'] ?? []);
        if (favKeys.isEmpty) favKeys = List<String>.from(data['fiveStarKeys'] ?? []);
        
        if (favKeys.isNotEmpty) {
          final films = await fetchFilmsByKeys(favKeys.take(8).toList());
          if (mounted) setState(() => _favoriteFilms = films);
        } else {
          if (mounted) setState(() => _favoriteFilms = []);
        }
      } else {
         if (mounted) setState(() => _favoriteFilms = []);
      }
    } catch (_) {
      if (mounted) setState(() => _favoriteFilms = []);
    }

    final m = widget.result;
    final commonKeys = <String>{...m.commonFavorites, ...m.commonFiveStars, ...m.commonWatchlist}.toList();
    if (commonKeys.isNotEmpty) {
      final films = await fetchFilmsByKeys(commonKeys.take(8).toList());
      if (mounted) setState(() => _commonFilms = films);
    } else {
      if (mounted) setState(() => _commonFilms = []);
    }
  }

  Future<void> _addFriend() async {
    setState(() => _isLoading = true);
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me != null) {
      try {
        await FollowSystemService.I.followUser(widget.result.uid);
        if (mounted) setState(() => _isAdded = true);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _handleFilmTap(BuildContext context, FilmItem film) async {
    int? id = film.tmdbId;

    if (id == null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.green)),
      );

      try {
        final result = await FirebaseFunctions.instance.httpsCallable('callTMDB').call({
          'endpoint': '/3/search/movie',
          'params': {
            'query': film.title,
            'language': 'tr-TR',
            'include_adult': 'false'
          }
        });
        
        if (!context.mounted) return;
        Navigator.pop(context); 

        final data = result.data as Map<String, dynamic>;
        final results = data['results'] as List?;

        if (results != null && results.isNotEmpty) {
          id = results[0]['id'];
          if (film.id.isNotEmpty && id != null) {
            FirebaseFirestore.instance
                .collection('catalog_films')
                .doc(film.id)
                .set({'tmdbId': id}, SetOptions(merge: true));
          }
        } else {
           if (!context.mounted) return;
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Film detayları bulunamadı.')));
          return;
        }
      } catch (e) {
        if (!context.mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
        return;
      }
    }

    if (id != null && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MovieDetailScreen(
            tmdbId: id!,
            title: film.title,
            posterUrl: film.posterUrl,
          ),
        ),
      );
    }
  }

  Widget _buildFilmRow(String title, List<FilmItem> films) {
    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 110, 
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: films.length,
              itemBuilder: (context, index) {
                final film = films[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: GestureDetector(
                    onTap: () => _handleFilmTap(context, film), 
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: PosterImage(posterUrl: film.posterUrl, title: film.title),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.result;
    final pct = m.score.clamp(0, 100).toStringAsFixed(0);

    String? photoUrl = _userData?['photoURL'];
    String? username = _userData?['username'];

    return Stack(
      fit: StackFit.expand,
      children: [
        if (photoUrl != null && photoUrl.isNotEmpty)
          Image.network(photoUrl, fit: BoxFit.cover)
        else
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1E1E1E), Color(0xFF121212)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: const Icon(Icons.person, size: 120, color: Colors.white24),
          ),

        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.75),
                Colors.black.withValues(alpha: 0.98),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.1, 0.45, 1.0],
            ),
          ),
        ),

        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.greenAccent, width: 1.5),
                  ),
                  child: Text(
                    '%$pct Sinema Uyumu',
                    style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 12),
                
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context, 
                      MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: m.uid))
                    );
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.displayName ?? 'İsimsiz Sinefil',
                        style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, height: 1.1),
                      ),
                      if (username != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            '@$username',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16),
                          ),
                        ),
                    ],
                  ),
                ),
                
                if (_commonFilms == null && _favoriteFilms == null)
                   const Padding(
                     padding: EdgeInsets.symmetric(vertical: 40.0),
                     child: Center(child: SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey))),
                   )
                else ...[
                   if (_commonFilms != null && _commonFilms!.isNotEmpty)
                     _buildFilmRow('Ortak Filmleriniz', _commonFilms!),
                   if (_favoriteFilms != null && _favoriteFilms!.isNotEmpty)
                     _buildFilmRow('Favori Filmleri', _favoriteFilms!),
                ],
                  
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isAdded || _isLoading ? null : _addFriend,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isAdded ? Colors.white24 : const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    icon: _isLoading 
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(_isAdded ? Icons.how_to_reg_rounded : Icons.person_add_alt_1_rounded),
                    label: Text(
                      _isAdded ? 'Arkadaş Eklendi' : 'Arkadaş Ekle',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 8), 
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NoMatchesCharacter extends StatelessWidget {
  const _NoMatchesCharacter();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.theater_comedy_rounded, size: 100, color: Colors.grey[700]),
          const SizedBox(height: 16),
          const Text('Şimdilik bu kadar!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 8),
          const Text('Daha fazla ortak zevk için filmlerini puanla.', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}