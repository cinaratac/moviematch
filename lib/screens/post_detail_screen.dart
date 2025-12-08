import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // FirebaseAuth eklendi
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
        // 1. Adım: Gönderi verisini çek
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
          
          final me = FirebaseAuth.instance.currentUser?.uid;

          // 2. Adım: Yazar profili, Beğeni durumu ve Takip durumunu PARALEL çek
          return FutureBuilder<List<dynamic>>(
            future: Future.wait([
              // [0] Yazarın güncel profili
              FirebaseFirestore.instance.collection('users').doc(authorId).get(),
              
              // [1] Beğeni kontrolü (Ben bu postu beğendim mi?)
              (me != null)
                  ? FirebaseFirestore.instance.collection('posts').doc(postId).collection('likes').doc(me).get()
                  : Future.value(null),
                  
              // [2] Takip kontrolü (Ben bu yazarı takip ediyor muyum?)
              (me != null && me != authorId)
                  ? FirebaseFirestore.instance.collection('users').doc(me).collection('following').doc(authorId).get()
                  : Future.value(null),
            ]),
            builder: (context, combinedSnap) {
              
              // Veriler yüklenirken de post içeriğini (eski verilerle) gösterebiliriz
              // ama temiz olması için loading gösteriyoruz.
              if (combinedSnap.connectionState == ConnectionState.waiting) {
                 return const Center(child: CircularProgressIndicator());
              }

              final results = combinedSnap.data ?? [];

              // Yazar Verilerini İşle
              final userSnap = results.isNotEmpty ? (results[0] as DocumentSnapshot<Map<String, dynamic>>?) : null;
              
              // Cache/Post üzerindeki varsayılan veriler
              String displayName = (m['displayName'] ?? '').toString();
              String handle = (m['handle'] ?? '').toString();
              String photoURL = (m['photoURL'] ?? '').toString();

              // Güncel kullanıcı verisi varsa güncelle
              if (userSnap != null && userSnap.exists) {
                final userData = userSnap.data();
                if (userData != null) {
                  final uName = userData['displayName'] as String?;
                  if (uName != null && uName.isNotEmpty) displayName = uName;

                  final uUser = userData['username'] as String?;
                  final uLb = userData['letterboxdUsername'] as String?;
                  if (uUser != null && uUser.isNotEmpty) {
                    handle = '@$uUser';
                  } else if (uLb != null && uLb.isNotEmpty) {
                    handle = '@$uLb';
                  }

                  final uPhoto = userData['photoURL'] as String?;
                  if (uPhoto != null && uPhoto.isNotEmpty) photoURL = uPhoto;
                }
              }

              // Beğeni Durumunu Çıkar
              bool isLiked = false;
              if (results.length > 1 && results[1] != null) {
                 final likeDoc = results[1] as DocumentSnapshot;
                 isLiked = likeDoc.exists;
              }

              // Takip Durumunu Çıkar
              bool isFollowing = false;
              if (results.length > 2 && results[2] != null) {
                final followDoc = results[2] as DocumentSnapshot;
                isFollowing = followDoc.exists;
              }

              final createdAt = (m['createdAt'] as Timestamp?);
              final timeLabel = createdAt == null ? '' : _timeAgo(createdAt.toDate());

              return SingleChildScrollView(
                child: PostTile(
                  key: ValueKey(d.id),
                  postId: d.id,
                  authorId: authorId,
                  displayName: displayName,
                  handle: handle,
                  photoURL: photoURL,
                  timeLabel: timeLabel,
                  text: (m['text'] ?? '').toString(),
                  movieTitle: m['movieTitle'] ?? m['movie']?['title'],
                  moviePoster: m['moviePoster'] ?? m['movie']?['poster'],
                  postImage: m['postImage'],
                  likeCount: ((m['likeCount'] ?? 0) as num).toInt(),
                  replyCount: ((m['replyCount'] ?? 0) as num).toInt(),
                  
                  // EKLENEN ZORUNLU PARAMETRELER:
                  initialIsLiked: isLiked,
                  initialIsFollowing: isFollowing,

                  onToggleLike: (pid, val) => FeedService.instance.toggleLike(postId: pid, like: val),
                  onStartChat: (uid) async { 
                    // ChatService entegrasyonu
                  }, 
                  onFollow: (uid) async {
                     await FeedService.instance.followUser(uid);
                     await FeedService.instance.notifyFollow(toUid: uid);
                  },
                  onReport: (pid) => FeedService.instance.reportPost(pid),
                  // Detay sayfasından silerse sayfayı kapat
                  onDelete: () => Navigator.pop(context), 
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
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}g';
    final years = diff.inDays ~/ 365;
    return '${years}y';
  }
}