import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/widgets/post_tile.dart';
import 'package:fluttergirdi/services/feed_service.dart';

class PostDetailScreen extends StatelessWidget {
  final String postId;

  const PostDetailScreen({super.key, required this.postId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gönderi')),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance.collection('posts').doc(postId).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (!snapshot.hasData || !snapshot.data!.exists) {
             return const Center(child: Text('Bu gönderi silinmiş veya bulunamadı.'));
          }

          final d = snapshot.data!;
          final m = d.data()!;
          
          // Timestamp dönüşümü
          final createdAt = (m['createdAt'] as Timestamp?);
          final timeLabel = createdAt == null ? '' : _timeAgo(createdAt.toDate());

          // PostTile widget'ını kullanıyoruz
          return SingleChildScrollView(
            child: PostTile(
              postId: d.id,
              authorId: (m['authorId'] ?? '').toString(),
              displayName: (m['displayName'] ?? '').toString(),
              handle: (m['handle'] ?? '').toString(),
              photoURL: (m['photoURL'] ?? '').toString(),
              timeLabel: timeLabel,
              text: (m['text'] ?? '').toString(),
              movieTitle: m['movieTitle'] ?? m['movie']?['title'],
              moviePoster: m['moviePoster'] ?? m['movie']?['poster'],
              likeCount: (m['likeCount'] ?? 0) as int,
              replyCount: (m['replyCount'] ?? 0) as int,
              repostCount: (m['repostCount'] ?? 0) as int,
              // Fonksiyonları FeedService'e bağlıyoruz
              onToggleLike: (pid, val) => FeedService().toggleLike(postId: pid, like: val),
              onStartChat: (uid) async { /* Chat başlatma kodu */ }, 
              onFollow: (uid) => FeedService().followUser(uid),
              onReport: (pid) => FeedService().reportPost(pid),
            ),
          );
        },
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    // FeedPage'deki timeAgo mantığının aynısı
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}d';
    if (diff.inHours < 24) return '${diff.inHours}s';
    return '${diff.inDays}g';
  }
}