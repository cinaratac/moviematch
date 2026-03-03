import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'movie_detail_screen.dart'; // Yönlendirme için

class ActorScreen extends StatefulWidget {
  final int actorId;
  final String actorName;

  const ActorScreen({super.key, required this.actorId, required this.actorName});

  @override
  State<ActorScreen> createState() => _ActorScreenState();
}

class _ActorScreenState extends State<ActorScreen> {
  Map<String, dynamic>? _actorDetails;
  List<dynamic> _movies = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchActorData();
  }

  Future<void> _fetchActorData() async {
    try {
      // 1. Oyuncu Detayları (Biyografi vs)
      final detailsResult = await FirebaseFunctions.instance.httpsCallable('callTMDB').call({
        'endpoint': '/3/person/${widget.actorId}',
        'params': {'language': 'tr-TR'}
      });

      // 2. Oyuncunun Filmleri (Movie Credits)
      final moviesResult = await FirebaseFunctions.instance.httpsCallable('callTMDB').call({
        'endpoint': '/3/person/${widget.actorId}/movie_credits',
        'params': {'language': 'tr-TR'}
      });

      if (mounted) {
        setState(() {
          _actorDetails = Map<String, dynamic>.from(detailsResult.data as Map);
          _movies = (moviesResult.data['cast'] as List);
          // Filmleri popülerliğe göre sıralayalım
          _movies.sort((a, b) => (b['popularity'] ?? 0).compareTo(a['popularity'] ?? 0));
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _loading 
        ? const Center(child: CircularProgressIndicator())
        : CustomScrollView(
            slivers: [
              // Üst Kısım: Fotoğraf ve İsim
              SliverAppBar(
                expandedHeight: 300,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(widget.actorName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  background: _actorDetails?['profile_path'] != null
                      ? CachedNetworkImage(
                          imageUrl: 'https://image.tmdb.org/t/p/w500${_actorDetails!['profile_path']}',
                          fit: BoxFit.cover,
                        )
                      : Container(color: Colors.grey),
                ),
              ),

              // Oyuncu Bilgileri ve Filmografisi
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_actorDetails?['biography'] != null && _actorDetails!['biography'].isNotEmpty) ...[
                        const Text("Biyografi", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(
                          _actorDetails!['biography'],
                          style: TextStyle(color: textColor.withOpacity(0.8), height: 1.5),
                        ),
                        const SizedBox(height: 30),
                      ],
                      Text("${widget.actorName} Filmleri", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),

              // Film Izgarası (Grid)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.6,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final movie = _movies[index];
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => MovieDetailScreen(
                            tmdbId: movie['id'],
                            title: movie['title'],
                            posterUrl: movie['poster_path'] != null ? 'https://image.tmdb.org/t/p/w500${movie['poster_path']}' : null,
                          )));
                        },
                        child: Column(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: movie['poster_path'] != null 
                                      ? 'https://image.tmdb.org/t/p/w200${movie['poster_path']}' 
                                      : 'https://via.placeholder.com/200x300',
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              movie['title'] ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      );
                    },
                    childCount: _movies.length > 30 ? 30 : _movies.length, // Performans için ilk 30 film
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 50)),
            ],
          ),
    );
  }
}