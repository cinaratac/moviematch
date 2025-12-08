import 'dart:io'; 
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; 
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:fluttergirdi/widgets/poster_image.dart';
import 'package:fluttergirdi/screens/profilescreen.dart';
import '../services/text_filter_service.dart';
import 'dart:math' as math; 

class ComposePostPage extends StatefulWidget {
  final int maxChars;
  // DİKKAT: Map<String, String> yerine Map<String, dynamic> yapıldı
  final Map<String, dynamic>? initialMovie;
  
  final Future<void> Function({
    required String text, 
    Map<String, dynamic>? movie, // DİKKAT: dynamic yapıldı
    File? image,
    double? rating,
    required bool isSpoiler,
    List<String>? tags,
    String? reviewTitle,
  }) onSend;

  const ComposePostPage({
    super.key,
    required this.maxChars,
    this.initialMovie,
    required this.onSend,
  });

  @override
  State<ComposePostPage> createState() => _ComposePostPageState();
}

class _ComposePostPageState extends State<ComposePostPage> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _tagsCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _picker = ImagePicker(); 
  
  // DİKKAT: String yerine dynamic
  Map<String, dynamic>? _selectedMovie;
  File? _selectedImage;
  
  double _rating = 0.0;
  bool _isSpoiler = false;
  bool _showReviewOptions = false; 

  @override
  void initState() {
    super.initState();
    if (widget.initialMovie != null) {
      _selectedMovie = widget.initialMovie;
      _showReviewOptions = true;
    }
  }
  
  Future<void> _pickImage() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080, 
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() {
          _selectedImage = File(picked.path);
        });
      }
    } catch (e) {
      debugPrint('Resim seçilemedi: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _titleCtrl.dispose();
    _tagsCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // --- GÜNCELLENMİŞ VERİ ÇEKME FONKSİYONU ---
  // DİKKAT: Dönüş tipi Map<String, dynamic> oldu
  Future<List<Map<String, dynamic>>> _fetchUserMovies() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!userDoc.exists) return [];
      
      final data = userDoc.data()!;
      final Set<String> allKeys = {};

      void addKeys(String field) {
        if (data[field] is List) {
          allKeys.addAll(List<String>.from(data[field]));
        }
      }

      addKeys('fiveStarKeys');
      addKeys('favoritesKeys');
      addKeys('watchlistKeys');
      addKeys('dislikedKeys');

      if (allKeys.isEmpty) return [];

      final List<Map<String, dynamic>> movies = [];
      final List<String> keysList = allKeys.toList();

      for (var i = 0; i < keysList.length; i += 10) {
        final chunk = keysList.sublist(i, math.min(i + 10, keysList.length));
        
        var qs = await FirebaseFirestore.instance
            .collection('catalog_films')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        if (qs.docs.isEmpty) {
           qs = await FirebaseFirestore.instance
            .collection('catalog_films')
            .where('key', whereIn: chunk)
            .get();
        }

        for (var doc in qs.docs) {
          final fd = doc.data();
          final title = (fd['title'] ?? '').toString();
          
          // DİKKAT: ID parse işlemi burada yapılıyor
          int? tmdbId;
          if (fd['tmdbId'] is int) {
            tmdbId = fd['tmdbId'];
          } else if (fd['tmdbId'] is String) {
            tmdbId = int.tryParse(fd['tmdbId']);
          } else if (fd['id'] is int) {
            tmdbId = fd['id'];
          }

          if (title.isNotEmpty) {
            movies.add({
              'title': title,
              'poster': (fd['posterUrl'] ?? fd['poster'] ?? '').toString(),
              'tmdbId': tmdbId, // Artık int (veya null) gönderiyoruz
            });
          }
        }
      }
      
      movies.sort((a, b) => (a['title'] ?? '').compareTo(b['title'] ?? ''));
      return movies;

    } catch (e) {
      debugPrint("Film listesi çekme hatası: $e");
      return [];
    }
  }

  Future<void> _pickMovie() async {
    // DİKKAT: Tür dynamic oldu
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _fetchUserMovies(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.5,
                child: const Center(child: CircularProgressIndicator()),
              );
            }

            final items = snapshot.data ?? [];
            
            return SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Filmlerim', style: Theme.of(ctx).textTheme.titleLarge),
                  ),
                  const Divider(),
                  Expanded(
                    child: items.isEmpty
                        ? const Center(child: Text('Listen boş veya yüklenemedi.'))
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final title = items[i]['title'] ?? '';
                              final poster = items[i]['poster'] ?? '';
                              return ListTile(
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    width: 40,
                                    height: 60,
                                    child: poster.isNotEmpty
                                        ? PosterImage(posterUrl: poster, title: title)
                                        : const ColoredBox(color: Colors.black12, child: Icon(Icons.movie)),
                                  ),
                                ),
                                title: Text(title),
                                onTap: () => Navigator.of(ctx).pop(items[i]),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      setState(() {
        _selectedMovie = result;
        _showReviewOptions = true; 
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Yeni Gönderi / İnceleme')),
      body: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _controller,
        builder: (context, value, _) {
          final text = value.text;
          final remaining = widget.maxChars - text.characters.length;
          final hasContent = text.trim().isNotEmpty || _selectedImage != null || _selectedMovie != null;

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundImage: FirebaseAuth.instance.currentUser?.photoURL != null
                          ? NetworkImage(FirebaseAuth.instance.currentUser!.photoURL!)
                          : null,
                      child: FirebaseAuth.instance.currentUser?.photoURL == null
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_selectedMovie != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: TextField(
                                controller: _titleCtrl,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                decoration: const InputDecoration(
                                  hintText: 'İnceleme Başlığı (İsteğe bağlı)',
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                              ),
                            ),

                          TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            maxLines: null,
                            minLines: 3,
                            decoration: const InputDecoration(
                              hintText: 'Düşüncelerini yaz...',
                              border: InputBorder.none,
                            ),
                          ),
                          
                          if (_selectedImage != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.file(
                                      _selectedImage!,
                                      width: double.infinity,
                                      height: 300, 
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: GestureDetector(
                                      onTap: () => setState(() => _selectedImage = null),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                        child: const Icon(Icons.close, color: Colors.white, size: 20),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          if (_selectedMovie != null) ...[
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: cs.outlineVariant),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: Row(
                                children: [
                                  if ((_selectedMovie!['poster'] ?? '').isNotEmpty)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: PosterImage(
                                        posterUrl: _selectedMovie!['poster'],
                                        title: _selectedMovie!['title'],
                                        width: 44, height: 66, fit: BoxFit.cover,
                                      ),
                                    )
                                  else
                                    const Icon(Icons.movie, size: 40),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _selectedMovie!['title'] ?? 'Seçili film',
                                      style: theme.textTheme.titleSmall,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => setState(() {
                                      _selectedMovie = null;
                                      _showReviewOptions = false;
                                      _rating = 0;
                                    }),
                                    icon: const Icon(Icons.close),
                                    tooltip: 'Kaldır',
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text("Puan:", style: TextStyle(fontWeight: FontWeight.bold)),
                                      const SizedBox(width: 8),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: List.generate(5, (index) {
                                          return GestureDetector(
                                            onTap: () => setState(() => _rating = index + 1.0),
                                            child: Icon(
                                              index < _rating ? Icons.star_rounded : Icons.star_border_rounded,
                                              color: Colors.amber,
                                              size: 32,
                                            ),
                                          );
                                        }),
                                      ),
                                      if (_rating > 0)
                                        IconButton(
                                          onPressed: () => setState(() => _rating = 0), 
                                          icon: const Icon(Icons.replay, size: 16, color: Colors.grey),
                                          tooltip: "Puanı sıfırla",
                                        )
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  
                                  TextField(
                                    controller: _tagsCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Etiketler (Virgülle ayır)',
                                      hintText: 'Örn: korku, klasik, 90lar',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.tag, size: 18),
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  SwitchListTile(
                                    title: const Text("Spoiler İçerir", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                    value: _isSpoiler,
                                    onChanged: (val) => setState(() => _isSpoiler = val),
                                    activeColor: Colors.redAccent,
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          
                          Row(
                            children: [
                              IconButton(
                                onPressed: _pickImage,
                                icon: const Icon(Icons.image_outlined),
                                tooltip: 'Resim ekle',
                                color: cs.onSurfaceVariant,
                              ),
                              IconButton(
                                onPressed: _pickMovie,
                                icon: const Icon(Icons.movie),
                                tooltip: 'Film seç',
                                color: cs.onSurfaceVariant,
                              ),
                              const Spacer(),
                              if (remaining <= 40)
                                Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: Text(
                                    '$remaining',
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      color: remaining < 0 ? cs.error : cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              FilledButton(
                                onPressed: !hasContent || remaining < 0
                                    ? null
                                    : () {
                                          if (TextFilterService.hasProfanity(text) || TextFilterService.hasProfanity(_titleCtrl.text)) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Uygunsuz içerik tespit edildi.'), backgroundColor: Colors.red),
                                            );
                                            return;
                                          }

                                          List<String> tagsList = [];
                                          if (_tagsCtrl.text.isNotEmpty) {
                                            tagsList = _tagsCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                                          }

                                          widget.onSend(
                                            text: text, 
                                            movie: _selectedMovie, 
                                            image: _selectedImage,
                                            rating: _rating > 0 ? _rating : null,
                                            isSpoiler: _isSpoiler,
                                            tags: tagsList,
                                            reviewTitle: _titleCtrl.text,
                                          );
                                        },
                                child: const Text('Gönder'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
            ],
          );
        },
      ),
    );
  }
}