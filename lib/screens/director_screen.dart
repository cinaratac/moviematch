import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DirectorScreen extends StatefulWidget {
  final int directorId;
  final String directorName;

  const DirectorScreen({
    super.key,
    required this.directorId,
    required this.directorName,
  });

  @override
  State<DirectorScreen> createState() => _DirectorScreenState();
}

class _DirectorScreenState extends State<DirectorScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _directorDetails;
  List<dynamic> _directedMovies = [];
  bool _isFavorited = false;

  @override
  void initState() {
    super.initState();
    _fetchDirectorData();
    _checkIfFavorited();
  }

  Future<void> _checkIfFavorited() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (doc.exists) {
      final List favDirectors = doc.data()?['favDirectors'] ?? [];
      if (mounted) {
        setState(() {
          _isFavorited = favDirectors.any((item) {
            if (item is Map) return item['id'] == widget.directorId;
            return item == widget.directorName;
          });
        });
      }
    }
  }

  Future<void> _fetchDirectorData() async {
    try {
      final functions = FirebaseFunctions.instance;

      // 1. Yönetmen Detaylarını (Biyografi vb.) Çek
      final detailsRes = await functions.httpsCallable('callTMDB').call({
        'endpoint': '/3/person/${widget.directorId}',
        'params': {'language': 'tr-TR'},
      });

      // 2. Yönetmenin Filmografisini Çek
      final creditsRes = await functions.httpsCallable('callTMDB').call({
        'endpoint': '/3/person/${widget.directorId}/movie_credits',
        'params': {'language': 'tr-TR'},
      });

      final creditsData = creditsRes.data;
      final List<dynamic> crew = creditsData['crew'] ?? [];

      // Sadece 'Director' (Yönetmen) olarak görev aldığı filmleri filtrele
      List<dynamic> directed = crew
          .where((c) => c['job'] == 'Director')
          .toList();

      // Filmleri popülerliğe veya çıkış tarihine göre sırala (Popülerlik daha iyidir)
      directed.sort((a, b) {
        final popA = (a['popularity'] as num?) ?? 0;
        final popB = (b['popularity'] as num?) ?? 0;
        return popB.compareTo(popA);
      });

      // Aynı filmin birden fazla kez gelmesini engellemek için (bazen API çift gönderebilir)
      final seenIds = <int>{};
      _directedMovies = directed.where((movie) {
        final id = movie['id'] as int;
        if (seenIds.contains(id)) return false;
        seenIds.add(id);
        return true;
      }).toList();

      setState(() {
        _directorDetails = detailsRes.data;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Yönetmen verisi çekilirken hata: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yönetmen bilgileri yüklenemedi.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.directorName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isFavorited
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: _isFavorited ? Colors.green : Colors.grey,
                size: 22,
              ),
            ),
            onPressed: () async {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid == null) return;

              // 1. OPTIMISTIC UI: Arayüzü anında güncelle (Kullanıcı beklemesin)
              final bool wasFavorited = _isFavorited;
              setState(() {
                _isFavorited = !wasFavorited;
              });

              final userRef = FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid);
              final directorData = {
                'name': widget.directorName,
                'id': widget.directorId,
              };

              try {
                // 2. Arka planda Firestore işlemlerini yap
                if (wasFavorited) {
                  // Eskiden favoriydi, şimdi çıkarıyoruz
                  final doc = await userRef.get();
                  List favs = List.from(doc.data()?['favDirectors'] ?? []);
                  favs.removeWhere((item) {
                    if (item is Map) return item['id'] == widget.directorId;
                    return item == widget.directorName;
                  });
                  await userRef.update({'favDirectors': favs});
                } else {
                  // Eskiden favori değildi, şimdi ekliyoruz
                  await userRef.set({
                    'favDirectors': FieldValue.arrayUnion([directorData]),
                    'updatedAt': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));
                }

                // 3. Başarılı Snackbar'ı göster
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        !wasFavorited
                            ? '${widget.directorName} favorilere eklendi!'
                            : '${widget.directorName} favorilerden çıkarıldı!',
                      ),
                      backgroundColor: !wasFavorited
                          ? Colors.green.shade700
                          : Colors.redAccent,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(
                        seconds: 1,
                      ), // Çok ekranda kalmasın
                    ),
                  );
                }
              } catch (e) {
                // 4. HATA DURUMU: Eğer internet kopuksa vs. işlemi geri al (Revert)
                if (mounted) {
                  setState(() {
                    _isFavorited = wasFavorited;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Hata oluştu, geri alındı: $e')),
                  );
                }
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _directorDetails == null
          ? const Center(child: Text('Veri bulunamadı.'))
          : CustomScrollView(
              slivers: [
                // --- ÜST KISIM: FOTOĞRAF VE BİLGİLER ---
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Yönetmen Fotoğrafı
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _directorDetails!['profile_path'] != null
                              ? CachedNetworkImage(
                                  imageUrl:
                                      'https://image.tmdb.org/t/p/w500${_directorDetails!['profile_path']}',
                                  width: 120,
                                  height: 180,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  width: 120,
                                  height: 180,
                                  color: cs.surfaceContainerHighest,
                                  child: const Icon(
                                    Icons.person,
                                    size: 50,
                                    color: Colors.grey,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 16),
                        // Kişisel Bilgiler
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.directorName,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (_directorDetails!['birthday'] != null)
                                _buildInfoRow(
                                  'Doğum',
                                  _directorDetails!['birthday'],
                                ),
                              if (_directorDetails!['place_of_birth'] != null)
                                _buildInfoRow(
                                  'Yer',
                                  _directorDetails!['place_of_birth'],
                                ),
                              if (_directorDetails!['deathday'] != null)
                                _buildInfoRow(
                                  'Ölüm',
                                  _directorDetails!['deathday'],
                                ),

                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF2E7D32,
                                  ).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Yönetmen',
                                  style: TextStyle(
                                    color: Color(0xFF2E7D32),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // --- BİYOGRAFİ ---
                if (_directorDetails!['biography'] != null &&
                    _directorDetails!['biography'].toString().isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Biyografi',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _directorDetails!['biography'],
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // --- YÖNETTİĞİ FİLMLER BAŞLIĞI ---
                if (_directedMovies.isNotEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                      child: Text(
                        'Yönettiği Filmler',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                // --- FİLMLER GRID LİSTESİ ---
                if (_directedMovies.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.65, // Afiş oranı
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final movie = _directedMovies[index];
                        final posterPath = movie['poster_path'];
                        final fullPosterUrl = posterPath != null
                            ? 'https://image.tmdb.org/t/p/w500$posterPath'
                            : '';

                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MovieDetailScreen(
                                  tmdbId: movie['id'],
                                  title: movie['title'],
                                  posterUrl: fullPosterUrl,
                                ),
                              ),
                            );
                          },
                          child: Column(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: PosterImage(
                                    posterUrl: fullPosterUrl,
                                    title: movie['title'],
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                movie['title'] ?? 'Film',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        );
                      }, childCount: _directedMovies.length),
                    ),
                  ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 40),
                ), // En alta boşluk
              ],
            ),
    );
  }

  Widget _buildInfoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title: ',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          Expanded(
            child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
