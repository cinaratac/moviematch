import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttergirdi/widgets/post_tile.dart';
import 'package:fluttergirdi/widgets/compose_post_sheet.dart';
import 'package:fluttergirdi/services/feed_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

// ---------------------------------------------------------------------------
// Film başına post listesini bellekte tutar.
// Aynı film detay sayfası tekrar açılınca Firestore'a gitmez.
// ---------------------------------------------------------------------------
class _ReviewCache {
  static final _ReviewCache instance = _ReviewCache._();
  _ReviewCache._();

  // tmdbId → (timestamp, posts)
  final Map<int, ({DateTime fetchedAt, List<QueryDocumentSnapshot> docs})> _data = {};

  static const _ttl = Duration(minutes: 5);

  List<QueryDocumentSnapshot>? get(int tmdbId) {
    final entry = _data[tmdbId];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.fetchedAt) > _ttl) {
      _data.remove(tmdbId);
      return null;
    }
    return entry.docs;
  }

  void set(int tmdbId, List<QueryDocumentSnapshot> docs) {
    _data[tmdbId] = (fetchedAt: DateTime.now(), docs: docs);
  }
}

class MovieReviewSection extends StatefulWidget {
  final int tmdbId;
  final Map<String, dynamic> movieData;
  final String? posterUrl;

  const MovieReviewSection({
    super.key,
    required this.tmdbId,
    required this.movieData,
    this.posterUrl,
  });

  @override
  State<MovieReviewSection> createState() => _MovieReviewSectionState();
}

class _MovieReviewSectionState extends State<MovieReviewSection> {
  // Cache'den gelen anlık sonuç (varsa skeleton gösterilmez)
  List<QueryDocumentSnapshot>? _cachedDocs;
  // Firestore'dan gelen canlı stream sonucu
  List<QueryDocumentSnapshot>? _liveDocs;
  bool _loadingLive = false;
  StreamSubscription<QuerySnapshot>? _sub;

  @override
  void initState() {
    super.initState();

    // 1. Cache'de var mı? Varsa hemen göster.
    _cachedDocs = _ReviewCache.instance.get(widget.tmdbId);

    // 2. Her durumda canlı sorguyu başlat (cache varsa arka planda günceller).
    _startStream();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _startStream() {
    setState(() => _loadingLive = _cachedDocs == null);

    // Firestore compound Filter.or() yerine tek field sorgusu:
    // movie.tmdbId hem int hem string olarak kaydediliyor olabilir.
    // İkisini de ayrı ayrı çekip birleştirmek daha hızlı (index gerektirmez).
    final db = FirebaseFirestore.instance;

    // Birincil sorgu: tmdbId integer
    final q1 = db
        .collection('posts')
        .where('movie.tmdbId', isEqualTo: widget.tmdbId)
        .orderBy('createdAt', descending: true)
        .limit(10);

    _sub = q1.snapshots().listen(
      (snap) {
        if (!mounted) return;
        final docs = snap.docs;
        _ReviewCache.instance.set(widget.tmdbId, docs);
        setState(() {
          _liveDocs   = docs;
          _loadingLive = false;
        });

        // Eğer hiç sonuç yoksa string ID ile de dene (eski kayıtlar için)
        if (docs.isEmpty) _tryStringFallback();
      },
      onError: (_) {
        if (mounted) setState(() => _loadingLive = false);
      },
    );
  }

  // Eski kayıtlarda movie.id string olabilir — tek seferlik fetch
  Future<void> _tryStringFallback() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('posts')
          .where('movie.id', isEqualTo: widget.tmdbId.toString())
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get(const GetOptions(source: Source.serverAndCache));

      if (!mounted || snap.docs.isEmpty) return;

      final merged = <QueryDocumentSnapshot>[
        ...(_liveDocs ?? []),
        ...snap.docs,
      ];
      // Duplicate postId temizle
      final seen  = <String>{};
      final dedup = merged.where((d) => seen.add(d.id)).toList();

      _ReviewCache.instance.set(widget.tmdbId, dedup);
      if (mounted) setState(() => _liveDocs = dedup);
    } catch (_) {}
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24)   return '${diff.inHours}h';
    if (diff.inDays < 7)     return '${diff.inDays}g';
    return '${diff.inDays ~/ 7}h';
  }

  void _navigateToCompose(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ComposePostPage(
        maxChars: 280,
        initialMovie: {
          'id':     widget.tmdbId,
          'title':  widget.movieData['title'],
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
              final ref = FirebaseStorage.instance
                  .ref()
                  .child('post_images')
                  .child('${user.uid}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg');
              await ref.putFile(images[i]);
              postImageUrls.add(await ref.getDownloadURL());
            }
          }

          await FeedService.instance.createPost(
            text:         text,
            movie:        movie,
            photoURL:     postImageUrls.isNotEmpty ? postImageUrls.first : null,
            photoURLs:    postImageUrls,
            displayName:  user.displayName,
            handle:       user.email?.split('@')[0],
            rating:       rating,
            isSpoiler:    isSpoiler,
            tags:         tags,
            reviewTitle:  reviewTitle,
          );

          // Cache'i geçersiz kıl — sonraki açılışta taze veri gelsin
          _ReviewCache.instance._data.remove(widget.tmdbId);

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
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final bgColor   = Theme.of(context).scaffoldBackgroundColor;
    final textColor = isDark ? Colors.white : Colors.black;

    // Gösterilecek docs: önce canlı, yoksa cache
    final docs    = _liveDocs ?? _cachedDocs ?? [];
    final hasPosts = docs.isNotEmpty;

    // Skeleton: ne cache ne canlı veri var ve hâlâ yükleniyor
    final showSkeleton = _loadingLive && _cachedDocs == null && _liveDocs == null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30),
      decoration: BoxDecoration(
        color: hasPosts ? bgColor : Colors.transparent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Bu Film Hakkında Söylenenler',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ),
                // Canlı güncelleme bekleniyorsa küçük indicator
                if (_loadingLive && _cachedDocs != null)
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (showSkeleton)
            _buildSkeleton(isDark)
          else if (!hasPosts)
            _buildEmpty(context, isDark, textColor)
          else
            _buildList(docs, textColor),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Skeleton — cache boşken gösterilir, genellikle sadece ilk açılışta
  // ---------------------------------------------------------------------------
  Widget _buildSkeleton(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: List.generate(2, (_) => _skeletonCard(isDark)),
      ),
    );
  }

  Widget _skeletonCard(bool isDark) {
    final base = isDark ? Colors.white10 : Colors.black.withOpacity(0.06);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _bone(36, 36, base, shape: BoxShape.circle),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _bone(100, 12, base),
              const SizedBox(height: 6),
              _bone(60, 10, base),
            ]),
          ]),
          const SizedBox(height: 12),
          _bone(double.infinity, 12, base),
          const SizedBox(height: 6),
          _bone(200, 12, base),
        ],
      ),
    );
  }

  Widget _bone(double w, double h, Color color, {BoxShape shape = BoxShape.rectangle}) {
    return Container(
      width: w, height: h,
      decoration: BoxDecoration(
        color: color,
        shape: shape,
        borderRadius: shape == BoxShape.rectangle ? BorderRadius.circular(6) : null,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Boş durum
  // ---------------------------------------------------------------------------
  Widget _buildEmpty(BuildContext context, bool isDark, Color textColor) {
    return GestureDetector(
      onTap: () => _navigateToCompose(context),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.black12,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.add_comment_rounded,
              color: textColor.withOpacity(0.4),
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              'Henüz kimse bir şey söylememiş.\nİlk yorumu sen yaparak tartışmayı başlat!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor.withOpacity(0.7),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Post listesi
  // ---------------------------------------------------------------------------
  Widget _buildList(List<QueryDocumentSnapshot> docs, Color textColor) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final d = docs[index];
        final m = d.data() as Map<String, dynamic>;
        final ts = m['createdAt'];

        return PostTile(
          postId:         d.id,
          authorId:       (m['authorId']    ?? '').toString(),
          displayName:    (m['displayName'] ?? '').toString(),
          handle:         (m['handle']      ?? '').toString(),
          photoURL:       (m['photoURL']    ?? '').toString(),
          timeLabel: ts == null
              ? ''
              : _timeAgo((ts as Timestamp).toDate()),
          text:           (m['text']        ?? '').toString(),
          movieTitle:  m['movieTitle'] ??
              (m['movie'] is Map ? m['movie']['title'] : null),
          moviePoster: m['moviePoster'] ??
              (m['movie'] is Map ? m['movie']['poster'] : null),
          movieTmdbId:    widget.tmdbId,
          postImage:      m['postImage'],
          postImages:     List<String>.from(m['photoURLs'] ?? []),
          rating:         (m['rating'] as num?)?.toDouble(),
          isSpoiler:      m['isSpoiler'] == true,
          tags:           List<String>.from(m['tags'] ?? []),
          reviewTitle:    m['reviewTitle'] as String?,
          likeCount:      ((m['likeCount']  ?? 0) as num).toInt(),
          replyCount:     ((m['replyCount'] ?? 0) as num).toInt(),
          initialIsLiked:     false,
          initialIsFollowing: false,
          onToggleLike: (pid, val) =>
              FeedService.instance.toggleLike(postId: pid, like: val),
          onStartChat: (_) {},
          onFollow:  (uid) => FeedService.instance.followUser(uid),
          onReport:  (pid) => FeedService.instance.reportPost(pid),
        );
      },
    );
  }
}