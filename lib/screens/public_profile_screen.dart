import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/services/letterboxd_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/services/chat_service.dart';
import 'package:fluttergirdi/screens/chat_room_screen.dart';

const Map<String, String> _lbImageHeaders = {
  'Referer': 'https://letterboxd.com',
  'User-Agent':
      'Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/117.0',
};

class PublicProfileScreen extends StatefulWidget {
  final String uid;
  const PublicProfileScreen({super.key, required this.uid});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  Future<List<LetterboxdFilm>>? _futureFavs;
  Future<List<LetterboxdFilm>>? _futureFiveStars;
  Future<List<LetterboxdFilm>>? _futureDisliked;

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
          if (lb.isNotEmpty && _futureFiveStars == null) {
            _futureFiveStars = LetterboxdService.fetchFiveStar(lb);
          }
          if (lb.isNotEmpty && _futureDisliked == null) {
            _futureDisliked = LetterboxdService.fetchDisliked(lb);
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
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runAlignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Text(
                      'Letterboxd: @$lb',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton.icon(
                          onPressed: () =>
                              _openUrl('https://letterboxd.com/$lb/'),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Profili aç'),
                        ),
                        const SizedBox(width: 6),
                        TextButton.icon(
                          onPressed: () async {
                            final myUid =
                                FirebaseAuth.instance.currentUser!.uid;
                            final chatId = await ChatService.instance
                                .getOrCreateChat(myUid, widget.uid);
                            if (!context.mounted) return;
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
              // — Kullanıcı tercihleri (yaş, türler, yönetmenler, oyuncular) —
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(widget.uid)
                    .snapshots(),
                builder: (context, usnap) {
                  if (!usnap.hasData || !usnap.data!.exists) {
                    return const SizedBox.shrink();
                  }
                  final u = usnap.data!.data()!;
                  final age = u['age'];
                  final genres = List<String>.from(u['favGenres'] ?? const []);
                  final directors = List<String>.from(
                    u['favDirectors'] ?? const [],
                  );
                  final actors = List<String>.from(u['favActors'] ?? const []);

                  if ((age == null || (age is int && age <= 0)) &&
                      genres.isEmpty &&
                      directors.isEmpty &&
                      actors.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  Widget chipWrap(String title, List<String> items) {
                    if (items.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: items
                                .map((e) => Chip(label: Text(e)))
                                .toList(),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (age is int && age > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Row(
                            children: [
                              const Icon(Icons.cake, size: 18),
                              const SizedBox(width: 6),
                              Text('Yaş: $age'),
                            ],
                          ),
                        ),
                      chipWrap('Sevdiği türler', genres),
                      chipWrap('Sevdiği yönetmenler', directors),
                      chipWrap('Sevdiği oyuncular', actors),
                    ],
                  );
                },
              ),
              if (lb.isNotEmpty)
                Text(
                  'Favori Filmler',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              if (lb.isNotEmpty) const SizedBox(height: 8),
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
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.network(
                                    f.posterUrl,
                                    headers: _lbImageHeaders,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: Colors.black26,
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.image_not_supported,
                                      ),
                                    ),
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
                          );
                        },
                      ),
                    );
                  },
                ),
              if (lb.isNotEmpty) const SizedBox(height: 16),
              if (lb.isNotEmpty)
                Text(
                  'Sevdiği Filmler',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              if (lb.isNotEmpty)
                FutureBuilder<List<LetterboxdFilm>>(
                  future: _futureFiveStars,
                  builder: (context, s) {
                    if (s.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        height: 180,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (s.hasError) {
                      return const Text('5★ film bulunamadı.');
                    }
                    final items = s.data ?? [];
                    if (items.isEmpty) {
                      return const Text('5★ film bulunamadı.');
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
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.network(
                                    f.posterUrl,
                                    headers: _lbImageHeaders,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: Colors.black26,
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.image_not_supported,
                                      ),
                                    ),
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
                          );
                        },
                      ),
                    );
                  },
                ),
              if (lb.isNotEmpty) const SizedBox(height: 16),
              if (lb.isNotEmpty)
                Text(
                  'Sevmediği Filmler',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              if (lb.isNotEmpty)
                FutureBuilder<List<LetterboxdFilm>>(
                  future: _futureDisliked,
                  builder: (context, s) {
                    if (s.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        height: 180,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (s.hasError) {
                      return Text('Sevmediği filmler alınamadı: ${s.error}');
                    }
                    final items = s.data ?? [];
                    if (items.isEmpty) {
                      return const Text('Sevmediği film bulunamadı.');
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
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.network(
                                    f.posterUrl,
                                    headers: _lbImageHeaders,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: Colors.black26,
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.image_not_supported,
                                      ),
                                    ),
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
