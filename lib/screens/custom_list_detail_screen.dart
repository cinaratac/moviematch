import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/models/custom_list.dart';
import 'package:fluttergirdi/services/custom_list_service.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';
import 'package:fluttergirdi/screens/search_movie.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';

class CustomListDetailScreen extends StatelessWidget {
  final CustomList list;
  final bool isMyList;

  const CustomListDetailScreen({
    super.key, 
    required this.list, 
    this.isMyList = false
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // --- 1. Kapak, Başlık ve Açıklama ---
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 16, bottom: 12, right: 16), // Hizalama ayarı
              title: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    list.title, 
                    style: const TextStyle(
                      fontSize: 16, 
                      fontWeight: FontWeight.bold, 
                      color: Colors.white, 
                      shadows: [Shadow(color: Colors.black, blurRadius: 10)]
                    )
                  ),
                  if (list.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0), // Başlık ile açıklama arası boşluk
                      child: Text(
                        list.description,
                        maxLines: 2, // Çok uzunsa 2 satırla sınırla
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10, // Daha küçük font
                          fontWeight: FontWeight.normal,
                          color: Colors.white, // Hafif silik beyaz
                          shadows: [Shadow(color: Colors.black, blurRadius: 8)]
                        ),
                      ),
                    ),
                ],
              ),
              background: list.coverImageUrl != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(list.coverImageUrl!, fit: BoxFit.cover),
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter, end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                            ),
                          ),
                        ), 
                      ],
                    )
                  : Container(
                      color: Colors.grey.shade900, 
                      child: const Center(
                        child: Icon(Icons.movie_filter, size: 64, color: Colors.white24)
                      )
                    ),
            ),
            actions: [
              if (isMyList)
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Film Ekle',
                  onPressed: () => _navigateToAddMovie(context),
                ),
              if (isMyList)
                IconButton(
                   icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                   onPressed: () => _confirmDelete(context),
                ),
            ],
          ),

          // --- 2. Liste Bilgileri ve Hazırlayan ---
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // LİSTE SAHİBİ
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PublicProfileScreen(uid: list.ownerId),
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: Colors.grey.shade300,
                          child: const Icon(Icons.person, size: 14, color: Colors.black54),
                        ),
                        const SizedBox(width: 6),
                        RichText(
                          text: TextSpan(
                          
                            children: [
                              const TextSpan(
                                text: "Hazırlayan: ", 
                                style: TextStyle(color: Colors.grey)
                              ),
                              TextSpan(
                                text: list.ownerName,
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // İstatistikler (Film Sayısı, Gizlilik vb.)
                  Row(
                    children: [
                      Icon(Icons.movie, size: 16, color: Colors.grey.shade400),
                      const SizedBox(width: 4),
                      Text('${list.movieCount} Film', style: TextStyle(color: Colors.grey.shade400)),
                      const SizedBox(width: 16),
                      if (!list.isPublic) ...[
                         Icon(Icons.lock, size: 16, color: Colors.grey.shade400),
                         const SizedBox(width: 4),
                         Text('Gizli Liste', style: TextStyle(color: Colors.grey.shade400)),
                      ]
                    ],
                  ),
                ],
              ),
            ),
          ),

          // --- 3. Filmler Grid ---
          StreamBuilder<QuerySnapshot>(
            stream: CustomListService.instance.getListItems(list.id),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SliverFillRemaining(child: Center(child: CircularProgressIndicator()));
              
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                 return SliverFillRemaining(
                   hasScrollBody: false,
                   child: Center(
                     child: Column(
                       mainAxisAlignment: MainAxisAlignment.center,
                       children: [
                         Icon(Icons.format_list_bulleted, size: 64, color: Colors.grey.shade300),
                         const SizedBox(height: 16),
                         const Text("Bu listede henüz film yok.", style: TextStyle(color: Colors.grey)),
                         if (isMyList) 
                           TextButton(onPressed: () => _navigateToAddMovie(context), child: const Text("Film Ekle"))
                       ],
                     ),
                   ),
                 );
              }

              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      
                      int tmdbId = 0;
                      if (data['id'] is int) {
                        tmdbId = data['id'];
                      } else if (data['id'] != null) {
                        tmdbId = int.tryParse(data['id'].toString()) ?? 0;
                      }

                      return GestureDetector(
                        onTap: () {
                          if (tmdbId != 0) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MovieDetailScreen(
                                  tmdbId: tmdbId,
                                  title: data['title'],
                                  posterUrl: data['poster'],
                                ),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Film detayları yüklenemedi."))
                            );
                          }
                        },
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: PosterImage(
                                  posterUrl: data['poster'] ?? '',
                                  title: data['title'] ?? '',
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            
                            if (data['poster'] == null)
                               Center(child: Text(data['title'] ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10))),

                            if (isMyList)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: InkWell(
                                  onTap: () => CustomListService.instance.removeMovieFromList(list.id, docs[index].id),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                    child: const Icon(Icons.close, color: Colors.white, size: 16),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                    childCount: docs.length,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.67,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Future<void> _navigateToAddMovie(BuildContext context) async {
    final selectedMovie = await Navigator.push(
      context, 
      MaterialPageRoute(builder: (_) => const SearchMoviePage(isSelectionMode: true))
    );

    if (selectedMovie != null && selectedMovie is Map<String, dynamic>) {
       await CustomListService.instance.addMovieToList(list.id, selectedMovie);
       if (context.mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${selectedMovie['title']} eklendi.")));
       }
    }
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Listeyi Sil"),
        content: const Text("Bu listeyi silmek istediğinize emin misiniz? Bu işlem geri alınamaz."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("İptal")),
          TextButton(
            onPressed: () async {
               Navigator.pop(ctx); 
               await CustomListService.instance.deleteList(list.id);
               if (context.mounted) Navigator.pop(context); 
            },
            child: const Text("Sil", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}