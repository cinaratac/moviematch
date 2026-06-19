import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttergirdi/widgets/post_tile.dart';
import 'package:fluttergirdi/widgets/compose_post_sheet.dart';
import 'package:fluttergirdi/services/feed_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

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
  late Stream<QuerySnapshot> _postsStream;

  @override
  void initState() {
    super.initState();
    // Ağır sorgu sadece widget ilk oluştuğunda 1 KERE çalışır!
    _postsStream = FirebaseFirestore.instance
        .collection('posts')
        .where(
          Filter.or(
            Filter('movie.id', isEqualTo: widget.tmdbId.toString()),
            Filter('movie.id', isEqualTo: widget.tmdbId),
            Filter('movie.tmdbId', isEqualTo: widget.tmdbId),
            Filter('movieTmdbId', isEqualTo: widget.tmdbId),
          ),
        )
        .limit(10)
        .snapshots();
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}g';
    return '${diff.inDays ~/ 365}y';
  }

  void _navigateToCompose(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComposePostPage(
          maxChars: 280,
          initialMovie: {
            'id': widget.tmdbId,
            'title': widget.movieData['title'],
            'poster': widget.posterUrl,
          },
          onSend: ({required text, movie, images, rating, required isSpoiler, tags, reviewTitle}) async {
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
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Gönderiniz Paylaşıldı!'), behavior: SnackBarBehavior.floating),
              );
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final textColor = isDark ? Colors.white : Colors.black;

    return StreamBuilder<QuerySnapshot>(
      stream: _postsStream,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final hasPosts = docs.isNotEmpty;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 30),
          decoration: BoxDecoration(color: hasPosts ? bgColor : Colors.transparent),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  "Bu Film Hakkında Söylenenler",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                ),
              ),
              const SizedBox(height: 20),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator())
              else if (!hasPosts)
                GestureDetector(
                  onTap: () => _navigateToCompose(context),
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
                      movieTmdbId: widget.tmdbId,
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
    );
  }
}