import 'dart:io'; // EKLENDİ (File kullanımı için)
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart'; 
import 'package:fluttergirdi/services/chat_service.dart';
import 'package:fluttergirdi/widgets/compose_post_sheet.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';
import 'package:fluttergirdi/models/shelf_target.dart'; 
import 'package:fluttergirdi/services/feed_service.dart';

import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:fluttergirdi/secrets.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';

class MovieActionHelper {
  static void show(
    BuildContext context, {
    required String title,
    required String posterUrl,
    String? docId,
    ShelfTarget? target,
    VoidCallback? onItemDeleted,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true, 
      useSafeArea: true, 
      builder: (ctx) => _MovieActionSheet(
        title: title, 
        posterUrl: posterUrl,
        docId: docId,
        target: target,
        onItemDeleted: onItemDeleted,
      ),
    );
  }
}

class _MovieActionSheet extends StatelessWidget {
  final String title;
  final String posterUrl;
  final String? docId;
  final ShelfTarget? target;
  final VoidCallback? onItemDeleted;

  const _MovieActionSheet({
    required this.title, 
    required this.posterUrl,
    this.docId,
    this.target,
    this.onItemDeleted,
  });

  String? _getFieldForTarget(ShelfTarget t) {
    switch (t) {
      case ShelfTarget.fiveStar: return 'fiveStarKeys';
      case ShelfTarget.disliked: return 'dislikedKeys';
      case ShelfTarget.favorites: return 'favoritesKeys';
      case ShelfTarget.watchlist: return 'watchlistKeys';
    }
  }

  Future<void> _fetchAndNavigateToDetails(BuildContext context) async {
    int? tmdbId;
    if (docId != null) {
      final doc = await FirebaseFirestore.instance.collection('catalog_films').doc(docId).get();
      if (doc.exists) {
        tmdbId = doc.data()?['tmdbId'];
      }
    }

    if (tmdbId == null) {
      try {
        final searchUrl = Uri.parse(
          'https://api.themoviedb.org/3/search/movie?query=${Uri.encodeComponent(title)}&language=tr-TR&include_adult=false'
        );
        final res = await http.get(searchUrl, headers: Secrets.tmdbHeaders);
        
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          final results = data['results'] as List?;
          if (results != null && results.isNotEmpty) {
            tmdbId = results[0]['id'];
            if (docId != null && tmdbId != null) {
              FirebaseFirestore.instance
                  .collection('catalog_films')
                  .doc(docId)
                  .set({'tmdbId': tmdbId}, SetOptions(merge: true));
            }
          }
        }
      } catch (_) {}
    }

    if (!context.mounted) return;
    
    Navigator.pop(context);

    if (tmdbId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MovieDetailScreen(
            tmdbId: tmdbId!,
            title: title,
            posterUrl: posterUrl,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Film detayları bulunamadı.'))
      );
    }
  }

  Future<void> _deleteFromProfile(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || docId == null || target == null) return;

    final field = _getFieldForTarget(target!);
    if (field == null) return;

    Navigator.pop(context); 

    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();

      final userRef = db.collection('users').doc(uid);
      batch.update(userRef, {
        field: FieldValue.arrayRemove([docId])
      });

      if (target == ShelfTarget.fiveStar) {
        final tasteRef = db.collection('userTasteProfiles').doc(uid);
        batch.update(tasteRef, {
          'fiveStars': FieldValue.arrayRemove([docId])
        });
      } else if (target == ShelfTarget.disliked) {
        final tasteRef = db.collection('userTasteProfiles').doc(uid);
        batch.update(tasteRef, {
          'lowRatings': FieldValue.arrayRemove([docId])
        });
      }

      await batch.commit();

      if (onItemDeleted != null) {
        onItemDeleted!();
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$title profilinden silindi.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Silme hatası: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Silinirken bir hata oluştu.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(0, 20, 0, bottomPadding + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 50,
                    height: 75,
                    child: PosterImage(posterUrl: posterUrl, title: title, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Film Detayları'),
            onTap: () => _fetchAndNavigateToDetails(context),
          ),
          ListTile(
            leading: const Icon(Icons.edit_note_outlined),
            title: const Text('Feed\'de Paylaş'),
            onTap: () {
              Navigator.pop(context); 
              _shareOnFeed(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.send_rounded),
            title: const Text('Mesaj Olarak Gönder'),
            onTap: () {
              Navigator.pop(context); 
              _showInboxPicker(context);
            },
          ),
          if (docId != null && target != null) ...[
            const Divider(),
            ListTile(
              leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              title: Text(
                'Profilden Sil',
                style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.bold),
              ),
              onTap: () => _deleteFromProfile(context),
            ),
          ],
        ],
      ),
    );
  }

  void _shareOnFeed(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComposePostPage(
          maxChars: 280,
          initialMovie: {'title': title, 'poster': posterUrl}, 
          // --- GÜNCELLENEN KISIM ---
          onSend: ({required text, movie, images, rating, required isSpoiler, tags, reviewTitle}) async {
             final user = FirebaseAuth.instance.currentUser;
             if (user == null) return;

             List<String> postImageUrls = [];
             
             // Çoklu resim yükleme
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

             await FeedService.instance.createPost(
               text: text,
               movie: movie,
               photoURL: postImageUrls.isNotEmpty ? postImageUrls.first : null, // Geriye uyumluluk
               photoURLs: postImageUrls, // Yeni liste desteği
               displayName: user.displayName,
               handle: user.email?.split('@')[0],
               rating: rating,
               isSpoiler: isSpoiler,
               tags: tags,
               reviewTitle: reviewTitle,
             );
             
             if (context.mounted) {
               Navigator.pop(context); 
               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paylaşıldı!')));
             }
          }, 
        ),
      ),
    );
  }

  void _showInboxPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true, 
      builder: (ctx) => _InboxPickerSheet(
        movieTitle: title, 
        moviePoster: posterUrl,
        docId: docId, 
      ),
    );
  }
}

class _InboxPickerSheet extends StatelessWidget {
  final String movieTitle;
  final String moviePoster;
  final String? docId; 

  const _InboxPickerSheet({
    required this.movieTitle, 
    required this.moviePoster,
    this.docId,
  });

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    if (myUid == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesaj Gönder'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .where('participants', arrayContains: myUid)
            .orderBy('updatedAt', descending: true)
            .limit(20)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Hata: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Text('Henüz kimseyle sohbetin yok.'),
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.only(bottom: bottomPadding + 20),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final chatData = docs[index].data() as Map<String, dynamic>;
              final chatId = docs[index].id;
              final participants = List<String>.from(chatData['participants'] ?? []);

              final otherUid = participants.firstWhere(
                (id) => id != myUid,
                orElse: () => '',
              );

              if (otherUid.isEmpty) return const SizedBox.shrink();

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('users').doc(otherUid).get(),
                builder: (context, userSnap) {
                  if (!userSnap.hasData) {
                    return const ListTile(
                      leading: CircleAvatar(child: Icon(Icons.person)),
                      title: Text('Yükleniyor...'),
                    );
                  }

                  final userData = userSnap.data!.data() as Map<String, dynamic>?;
                  if (userData == null) return const SizedBox.shrink();

                  final name = userData['username'] ?? userData['displayName'] ?? 'Kullanıcı';
                  final photo = userData['photoURL'];

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: photo != null ? NetworkImage(photo) : null,
                      child: photo == null ? Text(name[0].toUpperCase()) : null,
                    ),
                    title: Text(name),
                    subtitle: Text(
                      'Son mesaj: ${chatData['lastMessage'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.send, color: Colors.green),
                    onTap: () => _sendMovieMessage(context, chatId, otherUid, name),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _sendMovieMessage(
    BuildContext context, 
    String chatId, 
    String otherUid, 
    String otherName
  ) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    try {
      final text = "🎬 Film önerisi: $movieTitle";
      
      final movieData = {
        'title': movieTitle,
        'poster': moviePoster,
        if (docId != null) 'id': docId, 
      };
      
      await ChatService.instance.send(
        chatId, 
        myUid, 
        text, 
        otherUid: otherUid,
        movie: movieData,
      );

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$otherName kişisine gönderildi.')),
        );
      }
    } catch (e) {
      debugPrint("Gönderim hatası: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata oluştu: $e')),
        );
      }
    }
  }
}