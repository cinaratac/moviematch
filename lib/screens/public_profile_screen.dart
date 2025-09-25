import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/services/letterboxd_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/services/chat_service.dart';
import 'package:fluttergirdi/screens/chat_room_screen.dart';

class PublicProfileScreen extends StatefulWidget {
  final String uid;
  const PublicProfileScreen({super.key, required this.uid});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  Future<List<LetterboxdFilm>>? _futureFavs;

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final doc = FirebaseFirestore.instance.collection('users').doc(widget.uid);
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: doc.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text('Kullanıcı bulunamadı'));
          }
          final data = snap.data!.data()!;
          final displayName = (data['displayName'] ?? '') as String;
          final lb = (data['letterboxdUsername'] ?? '') as String;
          final photoURL = (data['photoURL'] ?? '') as String;
          final appUsername = (data['username'] ?? '') as String; // NEW

          // Title fallback: username → displayName → @letterboxd → (İsimsiz)
          final titleText = appUsername.isNotEmpty
              ? appUsername
              : (displayName.isNotEmpty
                    ? displayName
                    : (lb.isNotEmpty ? '@$lb' : '(İsimsiz)'));

          // Favorileri tetikle
          if (lb.isNotEmpty && _futureFavs == null) {
            _futureFavs = LetterboxdService.fetchFavorites(lb);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundImage: photoURL.isNotEmpty
                        ? NetworkImage(photoURL)
                        : null,
                    child: photoURL.isEmpty
                        ? Text(
                            displayName.isNotEmpty
                                ? displayName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(fontSize: 24),
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titleText,
                          style: Theme.of(context).textTheme.titleLarge,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (displayName.isNotEmpty && titleText != displayName)
                          Text(
                            displayName,
                            style: Theme.of(context).textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (lb.isNotEmpty)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Letterboxd: @$lb',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () =>
                              _openUrl('https://letterboxd.com/$lb/'),
                          child: const Text('Profili aç'),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () async {
                            final myUid =
                                FirebaseAuth.instance.currentUser!.uid;
                            final chatId = await ChatService().getOrCreateChat(
                              myUid,
                              widget.uid,
                            );
                            if (!mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatRoomScreen(
                                  chatId: chatId,
                                  otherUid: widget.uid,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.message),
                          label: const Text('Mesaj gönder'),
                        ),
                      ],
                    ),
                  ],
                )
              else
                const Text('Letterboxd bağlı değil'),

              const SizedBox(height: 12),
              if (lb.isNotEmpty)
                FutureBuilder<List<LetterboxdFilm>>(
                  future: _futureFavs,
                  builder: (context, s) {
                    if (s.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        height: 180,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (s.hasError) {
                      return Text('Favoriler alınamadı: ${s.error}');
                    }
                    final items = s.data ?? [];
                    if (items.isEmpty) {
                      return const Text('Favori film bulunamadı.');
                    }
                    return SizedBox(
                      height: 180,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, i) {
                          final f = items[i];
                          return AspectRatio(
                            aspectRatio: 2 / 3,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                onTap: () => _openUrl(f.url),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(
                                      f.posterUrl,
                                      fit: BoxFit.cover,
                                    ),
                                    Align(
                                      alignment: Alignment.bottomCenter,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 4,
                                        ),
                                        color: Colors.black54,
                                        child: Text(
                                          f.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
