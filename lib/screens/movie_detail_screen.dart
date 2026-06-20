import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/screens/actors_screen.dart';
import 'package:fluttergirdi/screens/director_screen.dart';
import 'package:fluttergirdi/services/catalog_service.dart';
import 'package:fluttergirdi/services/shelf_state_cache.dart';
import 'package:fluttergirdi/widgets/movie_review_section.dart';
import 'package:fluttergirdi/widgets/movie_action_sheet.dart';

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
  bool _loading   = true;
  bool _hasError  = false;
  String? _catalogDocId;

  bool _isWatched = false;

  StreamSubscription<DocumentSnapshot>? _userSub;

  @override
  void initState() {
    super.initState();
    _initWatchedState();
    _fetchDetails();
  }

  @override
  void dispose() {
    _userSub?.cancel();
    super.dispose();
  }

  void _initWatchedState() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final tmdbStr = widget.tmdbId.toString();
    final cache   = ShelfStateCache.instance;

    // Cache varsa hemen oku (0ms)
    if (cache.hasData(uid)) {
      _isWatched = _checkWatched(cache, uid, tmdbStr);
    }

    // Realtime listener: sheet açılmadan da değişiklik gelirse güncellenir
    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      cache.applyDoc(uid, doc);
      setState(() => _isWatched = _checkWatched(cache, uid, tmdbStr));
    }, onError: (_) {});
  }

  bool _checkWatched(ShelfStateCache cache, String uid, String tmdbStr) {
    for (final f in ['watchedKeys','favoritesKeys','fiveStarKeys','dislikedKeys']) {
      if (cache.get(uid, f).contains(tmdbStr)) return true;
    }
    return false;
  }

  Future<void> _fetchDetails() async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('callTMDB')
          .call({
        'endpoint': '/3/movie/${widget.tmdbId}',
        'params': {'language': 'tr-TR', 'append_to_response': 'credits,release_dates'},
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      if (mounted) {
        setState(() {
          _movieData = data;
          final Map credits = data['credits'] ?? {};
          _cast    = credits['cast'] ?? [];
          _crew    = credits['crew'] ?? [];
          _loading = false;
        });
        CatalogService().upsertFromTmdb(data).then((docId) {
          if (mounted) setState(() => _catalogDocId = docId);
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _hasError = true; });
    }
  }

  void _showAddSheet() {
    if (_movieData == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (_) => MovieActionSheet(
        tmdbId:       widget.tmdbId,
        movieData:    _movieData!,
        posterUrl:    widget.posterUrl,
        catalogDocId: _catalogDocId,
      ),
    );
  }

  String get _director {
    try {
      final d = _crew.firstWhere((m) => m['job'] == 'Director');
      return (d['name'] ?? 'Bilinmiyor').toString();
    } catch (_) { return 'Bilinmiyor'; }
  }

  Map<String, dynamic>? get _directorData {
    if (_crew.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(
          _crew.firstWhere((m) => m['job'] == 'Director') as Map);
    } catch (_) { return null; }
  }

  String get _rating => _movieData != null
      ? (_movieData!['vote_average'] as num).toStringAsFixed(1) : '-';

  String get _runtime {
    if (_movieData == null) return '';
    final mins = _movieData!['runtime'] as int?;
    if (mins == null || mins == 0) return '';
    return '${mins ~/ 60}s ${mins % 60}dk';
  }

  String get _year {
    if (_movieData == null) return '';
    final date = _movieData!['release_date'] as String?;
    return (date != null && date.length >= 4) ? date.substring(0, 4) : '';
  }

  Widget _buildTag(String text, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
      ),
      child: Text(text, style: TextStyle(
        fontSize: 12, fontWeight: FontWeight.w600,
        color: isDark ? Colors.white70 : Colors.black87,
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final bgColor   = Theme.of(context).scaffoldBackgroundColor;
    final textColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
            child: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isWatched)
            Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
              child: const Icon(Icons.check_circle, color: Colors.greenAccent, size: 22),
            ),
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
      body: Stack(children: [
        if (widget.posterUrl != null)
          Positioned.fill(child: Stack(fit: StackFit.expand, children: [
            CachedNetworkImage(imageUrl: widget.posterUrl!, fit: BoxFit.cover),
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Container(color: bgColor.withOpacity(0.85)),
            ),
          ])),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_hasError || _movieData == null)
          Center(child: Text('Detaylar yüklenemedi', style: TextStyle(color: textColor)))
        else
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(0, MediaQuery.of(context).padding.top + 60, 0, 40),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Hero(
                    tag: 'poster_${widget.tmdbId}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CachedNetworkImage(
                          imageUrl: widget.posterUrl ?? '',
                          width: 140, height: 210, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_movieData!['title'], style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold,
                        color: textColor, height: 1.2)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      if (_year.isNotEmpty)    _buildTag(_year, isDark),
                      if (_runtime.isNotEmpty) _buildTag(_runtime, isDark),
                      if (_isWatched)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
                          ),
                          child: const Text('✓ İzledim',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                  color: Colors.greenAccent)),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      const Icon(Icons.star_rounded, color: Colors.amber, size: 28),
                      const SizedBox(width: 4),
                      Text(_rating, style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800, color: textColor)),
                    ]),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () {
                        final d = _directorData;
                        if (d != null && d['id'] != null) {
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => DirectorScreen(
                              directorId:   d['id'] as int,
                              directorName: d['name'] ?? '',
                            ),
                          ));
                        }
                      },
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Yönetmen', style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500,
                            color: textColor.withOpacity(0.5))),
                        Text(_director, style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600,
                            color: textColor, decoration: TextDecoration.underline,
                            decorationColor: textColor.withOpacity(0.3))),
                      ]),
                    ),
                  ])),
                ]),
              ),
              const SizedBox(height: 30),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Özet', style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 8),
                  Text(_movieData!['overview'] ?? 'Özet bulunamadı.',
                      style: TextStyle(fontSize: 15,
                          color: textColor.withOpacity(0.8), height: 1.6)),
                ]),
              ),
              const SizedBox(height: 30),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('Oyuncular', style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 130,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _cast.length > 10 ? 10 : _cast.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 16),
                  itemBuilder: (context, i) {
                    final actor = _cast[i];
                    return GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ActorScreen(
                            actorId: actor['id'], actorName: actor['name']),
                      )),
                      child: Column(children: [
                        CircleAvatar(
                          radius: 35, backgroundColor: Colors.grey.shade800,
                          backgroundImage: actor['profile_path'] != null
                              ? NetworkImage('https://image.tmdb.org/t/p/w200${actor['profile_path']}')
                              : null,
                          child: actor['profile_path'] == null
                              ? const Icon(Icons.person) : null,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(width: 80, child: Text(actor['name'],
                          maxLines: 2, textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.9)),
                        )),
                      ]),
                    );
                  },
                ),
              ),
              const SizedBox(height: 30),
              MovieReviewSection(
                tmdbId:    widget.tmdbId,
                movieData: _movieData!,
                posterUrl: widget.posterUrl,
              ),
            ]),
          ),
      ]),
    );
  }
}