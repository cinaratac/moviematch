import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
// YENİ: Cloud Functions paketi
import 'package:cloud_functions/cloud_functions.dart'; 

// "import '../secrets.dart';"  <-- BU SATIRI SİLİN, ARTIK GEREK YOK
import '../models/shelf_target.dart';
import '../widgets/poster_image.dart'; 
import '../screens/profilescreen.dart';

extension ShelfTargetXLocal on ShelfTarget {
  String get userArrayField {
    switch (this) {
      case ShelfTarget.fiveStar: return 'fiveStarKeys';
      case ShelfTarget.disliked: return 'dislikedKeys';
      case ShelfTarget.favorites: return 'favoritesKeys';
      case ShelfTarget.watchlist: return 'watchlistKeys';
    }
  }
}

// BU FONKSİYONU DEĞİŞTİRİYORUZ
Future<List<dynamic>> _tmdbSearchMovies(String query) async {
  final q = query.trim();
  if (q.isEmpty) return [];

  // ARTIK TOKEN YOK, SUNUCUYA SORUYORUZ
  try {
    final result = await FirebaseFunctions.instance
        .httpsCallable('searchMovies') // Backend'deki fonksiyon adı
        .call({'query': q});
    
    // Backend { results: [...] } formatında dönüyor
    final data = result.data as Map<String, dynamic>;
    return (data['results'] as List?) ?? [];
  } catch (e) {
    print("Arama Hatası: $e");
    // Hata durumunda boş liste dönebilir veya hatayı yukarı fırlatabilirsiniz
    throw Exception("Arama sırasında hata oluştu: $e");
  }
}

class SearchMoviePage extends StatefulWidget {
  final ShelfTarget? target; 
  final bool isSelectionMode; 

  const SearchMoviePage({
    super.key, 
    this.target, 
    this.isSelectionMode = false
  });

  @override
  State<SearchMoviePage> createState() => _SearchMoviePageState();
}

class _SearchMoviePageState extends State<SearchMoviePage> {
  // ... (Geri kalan kodlarınız aynı kalıyor, sadece build metodunda değişiklik yok) ...
  // ... Copy-Paste yaparken SearchMoviePage class'ının altındaki _searchMovies metodunun
  // ... yukarıdaki global _tmdbSearchMovies'i çağırdığından emin olun.
  
  // (Kodun devamını buraya kopyalamıyorum, sadece üstteki _tmdbSearchMovies değişimi yeterli. 
  // Sınıfın geri kalanı aynı çalışır.)
  
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _movies = [];
  bool _isLoading = false;
  String? _error;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String get _hintText {
     if (widget.isSelectionMode) return 'Listeye eklemek için film ara...';
     if (widget.target == null) return 'Film ara...';
     switch (widget.target!) {
       case ShelfTarget.fiveStar: return 'Sevdiğin filmi ara...';
       case ShelfTarget.disliked: return 'Sevmediğin filmi ara...';
       case ShelfTarget.favorites: return 'Favori filmini ara...';
       case ShelfTarget.watchlist: return 'İzlemek istediğin filmi ara...';
     }
   }

  Future<void> _searchMovies(String query) async {
    if (query.isEmpty) {
      setState(() { _movies = []; _error = null; });
      return;
    }
    setState(() { _isLoading = true; _error = null; });
    try {
      // YENİ FONKSİYONU ÇAĞIRIYOR
      final results = await _tmdbSearchMovies(query);
      setState(() => _movies = results);
    } catch (e) {
      setState(() => _error = 'Hata: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _slugify(String s) {
    var slug = s.toLowerCase();
    slug = slug
      .replaceAll('ı', 'i')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ş', 's')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c');
    slug = slug.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    slug = slug.replaceAll(RegExp(r'^-+|-+$'), '');
    return slug;
  }

  void _showMovieDetails(dynamic movie) {
    // ... (Mevcut _showMovieDetails kodunuz aynı kalacak) ...
    // Kodu buraya tekrar yapıştırıp kalabalık yapmıyorum, bu kısımda değişiklik yok.
    final theme = Theme.of(context);
    final posterPath = movie['poster_path'];
    final posterUrl = (posterPath is String && posterPath.isNotEmpty)
        ? 'https://image.tmdb.org/t/p/w500$posterPath'
        : '';
    final String title = (movie['title'] ?? 'Başlık yok').toString();
    final String originalTitle = (movie['original_title'] ?? '').toString(); 
    final String release = (movie['release_date'] ?? '').toString();
    final String year = release.length >= 4 ? release.substring(0, 4) : '';
    final String overview = (movie['overview'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 60,
            left: 20, right: 20, top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: PosterImage(posterUrl: posterUrl, title: title, width: 100, height: 150, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, fontSize: 20), maxLines: 3, overflow: TextOverflow.ellipsis),
                        if (year.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(6)),
                            child: Text(year, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                          ),
                        ],
                         Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Orijinal: $originalTitle', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (overview.isNotEmpty) ...[
                 Text(overview, maxLines: 4, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                 const SizedBox(height: 24),
              ],
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  icon: const Icon(Icons.add_rounded),
                  label: Text(widget.isSelectionMode ? 'Bu Filmi Seç' : 'Listeye Ekle', style: const TextStyle(fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () async {
                    if (widget.isSelectionMode) {
                      final selectedMovie = {
                        'id': movie['id'],
                        'title': title,
                        'poster': posterUrl,
                        'releaseDate': release,
                      };
                      Navigator.of(context).pop(); 
                      Navigator.of(context).pop(selectedMovie);
                      return;
                    }

                    try {
                      final uid = FirebaseAuth.instance.currentUser?.uid;
                      if (uid == null) { if (mounted) Navigator.of(context).pop(); return; }

                      final int tmdbId = (movie['id'] as num).toInt();
                      final int yearInt = int.tryParse(year) ?? 0;
                      
                      final db = FirebaseFirestore.instance;
                      
                      final sourceForSlug = originalTitle.isNotEmpty ? originalTitle : title;
                      final String guessLbSlug = _slugify(sourceForSlug);
                      final String primaryKey = 'film:$guessLbSlug';
                      
                      await db.collection('catalog_films').doc(primaryKey).set({
                        'title': title,           
                        'originalTitle': originalTitle,
                        'posterUrl': posterUrl, 
                        'tmdbId': tmdbId, 
                        'year': yearInt,
                        'titleLc': title.toLowerCase(),
                        'aliases': FieldValue.arrayUnion(['tmdb:$tmdbId']), 
                        'source': 'tmdb', 
                        'updatedAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));

                      if (widget.target != null) {
                        final String field = widget.target!.userArrayField;
                        await db.collection('users').doc(uid).set({
                          field: FieldValue.arrayUnion([primaryKey]),
                          'updatedAt': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));
                        
                        if (widget.target == ShelfTarget.fiveStar) {
                           await db.collection('userTasteProfiles').doc(uid).set({'fiveStars': FieldValue.arrayUnion([primaryKey])}, SetOptions(merge: true));
                        } else if (widget.target == ShelfTarget.disliked) {
                           await db.collection('userTasteProfiles').doc(uid).set({'lowRatings': FieldValue.arrayUnion([primaryKey])}, SetOptions(merge: true));
                        }
                        
                        final Map<String, String> newLocalItem = {'title': title, 'poster': posterUrl, 'posterUrl': posterUrl};
                        switch (widget.target!) {
                          case ShelfTarget.fiveStar: UserShelfCache.fiveStar = List.from(UserShelfCache.fiveStar)..add(newLocalItem); break;
                          case ShelfTarget.favorites: UserShelfCache.favorites = List.from(UserShelfCache.favorites)..add(newLocalItem); break;
                          case ShelfTarget.watchlist: UserShelfCache.watchlist = List.from(UserShelfCache.watchlist)..add(newLocalItem); break;
                          case ShelfTarget.disliked: UserShelfCache.disliked = List.from(UserShelfCache.disliked)..add(newLocalItem); break;
                        }
                      }

                      if (mounted) {
                        Navigator.of(context).pop(); 
                        Navigator.of(context).pop(true);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$title listene eklendi (ID: $primaryKey)'), backgroundColor: theme.colorScheme.primary));
                      }
                    } catch (e) {
                      print('HATA: $e');
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
     // ... (Build metodu aynı kalıyor) ...
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => Navigator.of(context).pop()),
        title: Container(
          height: 45,
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            textAlignVertical: TextAlignVertical.center,
            style: theme.textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: _hintText,
              hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7)),
              border: InputBorder.none,
              prefixIcon: Icon(Icons.search, color: theme.colorScheme.onSurfaceVariant),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              suffixIcon: _searchController.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 20), onPressed: () { _searchController.clear(); _searchMovies(''); }) : null,
            ),
            onChanged: (value) {
              if (_debounce?.isActive ?? false) _debounce!.cancel();
              _debounce = Timer(const Duration(milliseconds: 800), () { 
                _searchMovies(value);
              });
            },
          ),
        ),
      ),
      body: _buildBody(),
    );
  }
  
  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text(_error!, textAlign: TextAlign.center)));
    if (_movies.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.movie, size: 80, color: Colors.grey.withOpacity(0.3)), const SizedBox(height: 16), Text('Aradığınız filmi yukarı yazın.', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey))]));
    
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.67, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemCount: _movies.length,
      itemBuilder: (context, index) => _buildGridItem(_movies[index]),
    );
  }

  Widget _buildGridItem(dynamic movie) {
      // ... (Grid Item kodu aynı kalıyor) ...
    final posterPath = movie['poster_path'];
    final posterUrl = (posterPath is String && posterPath.isNotEmpty) ? 'https://image.tmdb.org/t/p/w500$posterPath' : '';
    final title = movie['title'] ?? '';
    final tmdbId = (movie['id'] is int) ? movie['id'] as int : null;

    return InkWell(
      onTap: () => _showMovieDetails(movie),
      borderRadius: BorderRadius.circular(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            PosterImage(posterUrl: posterUrl, title: title, tmdbId: tmdbId, fit: BoxFit.cover),
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent])),
                child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black, blurRadius: 2)])),
              ),
            ),
          ],
        ),
      ),
    );
  }
}