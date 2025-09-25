import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/services/letterboxd_service.dart';
import 'package:url_launcher/url_launcher.dart';

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
                    child: Text(
                      displayName.isNotEmpty ? displayName : '(İsimsiz)',
                      style: Theme.of(context).textTheme.titleLarge,
                      overflow: TextOverflow.ellipsis,
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
                    TextButton(
                      onPressed: () => _openUrl('https://letterboxd.com/$lb/'),
                      child: const Text('Profili aç'),
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
