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
        // 1. Önce gönderiyi çek
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
          final authorId = (m['authorId'] ?? '').toString();

          // 2. Gönderi geldikten sonra yazarın GÜNCEL profil bilgilerini çek
          return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: FirebaseFirestore.instance.collection('users').doc(authorId).get(),
            builder: (context, userSnap) {
              
              // Varsayılan olarak post üzerindeki verileri al (cache/eski veri)
              String displayName = (m['displayName'] ?? '').toString();
              String handle = (m['handle'] ?? '').toString();
              String photoURL = (m['photoURL'] ?? '').toString();

              // Eğer kullanıcı verisi canlı olarak geldiyse, bilgileri güncelle
              if (userSnap.hasData && userSnap.data!.exists) {
                final userData = userSnap.data!.data();
                if (userData != null) {
                  // İsim
                  final uName = userData['displayName'] as String?;
                  if (uName != null && uName.isNotEmpty) displayName = uName;

                  // Kullanıcı Adı (@handle)
                  final uUser = userData['username'] as String?;
                  final uLb = userData['letterboxdUsername'] as String?;
                  if (uUser != null && uUser.isNotEmpty) {
                    handle = '@$uUser';
                  } else if (uLb != null && uLb.isNotEmpty) {
                    handle = '@$uLb';
                  }

                  // Profil Resmi (En önemlisi)
                  final uPhoto = userData['photoURL'] as String?;
                  if (uPhoto != null && uPhoto.isNotEmpty) photoURL = uPhoto;
                }
              }

              final createdAt = (m['createdAt'] as Timestamp?);
              final timeLabel = createdAt == null ? '' : _timeAgo(createdAt.toDate());

              return SingleChildScrollView(
                child: PostTile(
                  postId: d.id,
                  authorId: authorId,
                  displayName: displayName,
                  handle: handle,
                  photoURL: photoURL, // Güncellenmiş resim URL'i
                  timeLabel: timeLabel,
                  text: (m['text'] ?? '').toString(),
                  movieTitle: m['movieTitle'] ?? m['movie']?['title'],
                  moviePoster: m['moviePoster'] ?? m['movie']?['poster'],
                  postImage: m['postImage'], // Gönderi resmi varsa göster
                  likeCount: ((m['likeCount'] ?? 0) as num).toInt(),
                  replyCount: ((m['replyCount'] ?? 0) as num).toInt(),
                  onToggleLike: (pid, val) => FeedService().toggleLike(postId: pid, like: val),
                  onStartChat: (uid) async { 
                    // Chat başlatma kodu buraya gelebilir
                  }, 
                  onFollow: (uid) async {
                     await FeedService().followUser(uid);
                     await FeedService().notifyFollow(toUid: uid);
                  },
                  onReport: (pid) => FeedService().reportPost(pid),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}d';
    if (diff.inHours < 24) return '${diff.inHours}s';
    return '${diff.inDays}g';
  }
}