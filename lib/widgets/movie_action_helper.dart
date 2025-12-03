import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/services/chat_service.dart';
import 'package:fluttergirdi/services/feed_service.dart';
import 'package:fluttergirdi/widgets/compose_post_sheet.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';

class MovieActionHelper {
  /// Film seçenekleri menüsünü açar
  static void show(
    BuildContext context, {
    required String title,
    required String posterUrl,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true, // İçeriğin boyutuna göre esnemesi için
      useSafeArea: true, // Sistem barlarıyla çakışmayı önler (Çentik vs.)
      builder: (ctx) => _MovieActionSheet(title: title, posterUrl: posterUrl),
    );
  }
}

class _MovieActionSheet extends StatelessWidget {
  final String title;
  final String posterUrl;

  const _MovieActionSheet({required this.title, required this.posterUrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Alt kısımdaki sistem çubuğu (Home indicator) yüksekliğini al
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      // YENİ: Alt kısma güvenli alan + 20px ekstra boşluk ekliyoruz
      padding: EdgeInsets.fromLTRB(0, 20, 0, bottomPadding + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Üst Kısım: Film Önizleme
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
          
          // Seçenek 1: Feed'de Paylaş
          ListTile(
            leading: const Icon(Icons.edit_note_outlined),
            title: const Text('Feed\'de Paylaş'),
            onTap: () {
              Navigator.pop(context); // Menüyü kapat
              _shareOnFeed(context);
            },
          ),
          
          // Seçenek 2: Mesaj Olarak Gönder
          ListTile(
            leading: const Icon(Icons.send_rounded),
            title: const Text('Mesaj Olarak Gönder'),
            onTap: () {
              Navigator.pop(context); // Menüyü kapat
              _showInboxPicker(context);
            },
          ),
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
          onSend: (text, movie) async {
             await FeedService.instance.createPost(
               text: text,
               movie: movie,
             );
             
             if (context.mounted) {
               Navigator.pop(context); // Compose sayfasını kapat
               ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(content: Text('Gönderildi!')),
               );
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
      useSafeArea: true, // Tam ekran modunda güvenli alanı korur
      builder: (ctx) => _InboxPickerSheet(movieTitle: title, moviePoster: posterUrl),
    );
  }
}

class _InboxPickerSheet extends StatelessWidget {
  final String movieTitle;
  final String moviePoster;

  const _InboxPickerSheet({required this.movieTitle, required this.moviePoster});

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    // Listenin en altına da boşluk bırakalım
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
            // Listenin altına padding ekliyoruz ki son eleman home bar'ın altında kalmasın
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
      };
      
      await ChatService.instance.send(
        chatId, 
        myUid, 
        text, 
        otherUid: otherUid,
        movie: movieData,
      );

      if (context.mounted) {
        Navigator.pop(context); // Pencereyi kapat
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