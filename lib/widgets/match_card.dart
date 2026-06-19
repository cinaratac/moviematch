import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:math' as math;

import 'package:fluttergirdi/services/match_service.dart' as global_match;
import 'package:fluttergirdi/services/follow_system_service.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';

// ==========================================
// 1. FİLM VERİSİ VE CACHE MANTIĞI
// ==========================================
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

final Map<String, FilmItem> _filmItemCache = {};
final Set<String> _missingFilmKeys = {};

FilmItem _filmItemFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data();
  final rawTmdbId = data['tmdbId'];
  return FilmItem(
    id: doc.id,
    title: (data['title'] ?? data['name'] ?? '').toString(),
    posterUrl: (data['posterUrl'] ?? data['poster'] ?? '').toString(),
    tmdbId: rawTmdbId is num ? rawTmdbId.toInt() : null,
  );
}

Future<List<FilmItem>> fetchFilmsByKeys(List<String> keys) async {
  if (keys.isEmpty) return [];
  final db = FirebaseFirestore.instance;
  final cleanKeys = keys.map((k) => k.trim()).where((k) => k.isNotEmpty).toSet().toList();
  final missingKeys = cleanKeys
      .where((key) => !_filmItemCache.containsKey(key))
      .where((key) => !_missingFilmKeys.contains(key))
      .toList();

  for (var i = 0; i < missingKeys.length; i += 10) {
    final chunk = missingKeys.sublist(i, math.min(i + 10, missingKeys.length));
    try {
      final qs = await db.collection('catalog_films').where(FieldPath.documentId, whereIn: chunk).get();
      final foundIds = <String>{};
      for (final doc in qs.docs) {
        foundIds.add(doc.id);
        _filmItemCache[doc.id] = _filmItemFromDoc(doc);
      }
      for (final id in chunk) {
        if (!foundIds.contains(id)) {
          _missingFilmKeys.add(id);
        }
      }
    } catch (_) {}
  }

  return [
    for (final key in cleanKeys)
      if (_filmItemCache[key] != null) _filmItemCache[key]!,
  ];
}

// ==========================================
// 2. GELİŞMİŞ EŞLEŞME KARTI WIDGET'I
// ==========================================
class MatchCard extends StatefulWidget {
  final global_match.MatchResult result;

  const MatchCard({super.key, required this.result});

  @override
  State<MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends State<MatchCard> with AutomaticKeepAliveClientMixin {
  bool _isAdded = false;
  bool _isLoading = false;

  Map<String, dynamic>? _userData;
  List<FilmItem>? _commonFilms;
  List<FilmItem>? _favoriteFilms;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;

    final m = widget.result;
    final commonKeys = <String>{
      ...m.commonFavorites,
      ...m.commonFiveStars,
      ...m.commonWatchlist,
    }.take(5).toList();

    Future<DocumentSnapshot<Map<String, dynamic>>?> loadFollow() async {
      try {
        return await FirebaseFirestore.instance.collection('users').doc(me).collection('following').doc(widget.result.uid).get();
      } catch (_) { return null; }
    }

    Future<DocumentSnapshot<Map<String, dynamic>>?> loadUser() async {
      try {
        return await FirebaseFirestore.instance.collection('users').doc(widget.result.uid).get();
      } catch (_) { return null; }
    }

    final commonFuture = commonKeys.isEmpty ? Future.value(<FilmItem>[]) : fetchFilmsByKeys(commonKeys);
    final userFuture = loadUser();
    final followFuture = loadFollow();

    try {
      final films = await commonFuture;
      if (mounted) setState(() => _commonFilms = films);
    } catch (_) {
      if (mounted) setState(() => _commonFilms = []);
    }

    try {
      final doc = await userFuture;
      if (mounted && doc != null && doc.exists) {
        setState(() => _userData = doc.data());
        final data = doc.data()!;
        var favKeys = List<String>.from(data['favoritesKeys'] ?? []);
        if (favKeys.isEmpty) {
          favKeys = List<String>.from(data['fiveStarKeys'] ?? []);
        }

        final films = favKeys.isEmpty ? <FilmItem>[] : await fetchFilmsByKeys(favKeys.take(5).toList());
        if (mounted) setState(() => _favoriteFilms = films);
      } else {
        if (mounted) setState(() => _favoriteFilms = []);
      }
    } catch (_) {
      if (mounted) setState(() => _favoriteFilms = []);
    }

    try {
      final followDoc = await followFuture;
      if (mounted && followDoc != null) {
        setState(() => _isAdded = followDoc.exists);
      }
    } catch (_) {}
  }

  Future<void> _addFriend() async {
    setState(() => _isLoading = true);
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me != null) {
      try {
        await FollowSystemService.I.followUser(widget.result.uid);
        if (mounted) setState(() => _isAdded = true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
        }
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _handleFilmTap(BuildContext context, FilmItem film) async {
    int? id = film.tmdbId;
    String currentPoster = film.posterUrl;

    if (id == null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.green)),
      );

      try {
        final result = await FirebaseFunctions.instance.httpsCallable('callTMDB').call({
          'endpoint': '/3/search/movie',
          'params': {'query': film.title, 'language': 'tr-TR', 'include_adult': 'false'},
        });

        if (!context.mounted) return;
        Navigator.pop(context);

        final data = result.data as Map<String, dynamic>;
        final results = data['results'] as List?;

        if (results != null && results.isNotEmpty) {
          id = results[0]['id'];
          final fetchedPosterPath = results[0]['poster_path'];
          if (fetchedPosterPath != null) {
            currentPoster = 'https://image.tmdb.org/t/p/w500$fetchedPosterPath';
          }

          if (film.id.isNotEmpty && id != null) {
            FirebaseFirestore.instance.collection('catalog_films').doc(film.id).set({
              'tmdbId': id,
              if (fetchedPosterPath != null) 'posterUrl': currentPoster,
            }, SetOptions(merge: true));
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

    if (currentPoster.startsWith('/')) {
      currentPoster = 'https://image.tmdb.org/t/p/w500$currentPoster';
    } else if (currentPoster.contains('ltrbxd.com')) {
      currentPoster = '';
    }

    if (id != null && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MovieDetailScreen(tmdbId: id!, title: film.title, posterUrl: currentPoster),
        ),
      );
    }
  }

  // --- UI YARDIMCI METOTLARI ---

  Widget _buildFilmRow(String title, List<FilmItem> films) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: math.min(films.length, 5),
              itemBuilder: (context, index) {
                final film = films[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: GestureDetector(
                    onTap: () => _handleFilmTap(context, film),
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: PosterImage(posterUrl: film.posterUrl, title: film.title, tmdbId: film.tmdbId, enableFallback: true, cacheWidth: 120),
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

  Widget _buildPrefChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildTextRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            child: Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRowWithChips(String title, List<dynamic> items, Color chipColor) {
    final validItems = items
        .map((e) => e is Map ? (e['name'] ?? '') : e.toString())
        .where((e) => e.toString().trim().isNotEmpty)
        .take(3)
        .toList();
        
    if (validItems.isEmpty) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            child: Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: validItems.map((item) => _buildPrefChip(item.toString(), chipColor)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final m = widget.result;
    final pct = m.score.clamp(0, 100).toStringAsFixed(0);
    String? photoUrl = _userData?['photoURL'];
    String? username = _userData?['username'];
    
    final int? age = _userData?['age'];
    final String bio = (_userData?['bio'] ?? '').toString().trim();
    final List<dynamic> genres = _userData?['favGenres'] ?? [];
    final List<dynamic> directors = _userData?['favDirectors'] ?? [];
    final List<dynamic> actors = _userData?['favActors'] ?? [];

    return Stack(
      fit: StackFit.expand,
      children: [
        if (photoUrl != null && photoUrl.isNotEmpty)
          Image.network(photoUrl, fit: BoxFit.cover)
        else
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF1E1E1E), Color(0xFF121212)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
            ),
            child: const Icon(Icons.person, size: 120, color: Colors.white24),
          ),

        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.80), Colors.black.withValues(alpha: 0.99)],
              begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: const [0.05, 0.40, 1.0],
            ),
          ),
        ),

        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 10.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.greenAccent, width: 1.2),
                  ),
                  child: Text('%$pct Sinema Uyumu', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                const SizedBox(height: 8),

                GestureDetector(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: m.uid)));
                  },
                  child: Text(
                    m.displayName ?? 'İsimsiz Sinefil',
                    style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold, height: 1.1),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ),
                
                if (username != null)
                  Text('@$username', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14)),

                if (bio.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                    child: Text(bio, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),

                // --- ALT ALTA YENİ LİSTE TASARIMI ---
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (age != null && age > 0)
                        _buildTextRow('Yaş:', age.toString()),
                      if (genres.isNotEmpty)
                        _buildDetailRowWithChips('Sevilen Türler:', genres, Colors.blueAccent),
                      if (directors.isNotEmpty)
                        _buildDetailRowWithChips('Yönetmenler:', directors, Colors.amberAccent),
                      if (actors.isNotEmpty)
                        _buildDetailRowWithChips('Oyuncular:', actors, Colors.purpleAccent),
                    ],
                  ),
                ),

                if (_commonFilms == null && _favoriteFilms == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20.0),
                    child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey))),
                  )
                else ...[
                  if (_commonFilms != null && _commonFilms!.isNotEmpty)
                    _buildFilmRow('Ortak Filmleriniz', _commonFilms!),
                  if (_favoriteFilms != null && _favoriteFilms!.isNotEmpty)
                    _buildFilmRow('Favori Filmleri', _favoriteFilms!),
                ],

                const SizedBox(height: 14),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isAdded || _isLoading ? null : _addFriend,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isAdded ? Colors.white24 : const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.white24, 
                      disabledForegroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    icon: _isLoading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(_isAdded ? Icons.how_to_reg_rounded : Icons.person_add_alt_1_rounded, size: 20),
                    label: Text(_isAdded ? 'Arkadaş Eklendi' : 'Arkadaş Ekle', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}