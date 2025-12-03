import 'dart:io'; // Dosya işlemleri için
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; // Resim seçici
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';
import 'package:fluttergirdi/screens/profilescreen.dart';

class ComposePostPage extends StatefulWidget {
  final int maxChars;
  final Map<String, String>? initialMovie;
  // onSend fonksiyonunun imzasını değiştiriyoruz: Artık File? image de alacak
  final Future<void> Function(String text, Map<String, String>? movie, File? image) onSend;

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
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _picker = ImagePicker(); // Picker tanımla
  
  Map<String, String>? _selectedMovie;
  File? _selectedImage; // Seçilen resmi tutacak değişken

  @override
  void initState() {
    super.initState();
    if (widget.initialMovie != null) {
      _selectedMovie = widget.initialMovie;
    }
  }
  
  // Resim seçme fonksiyonu
  Future<void> _pickImage() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080, // Aşırı büyük olmaması için
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
    _focusNode.dispose();
    super.dispose();
  }

  // ... _pickMovie fonksiyonu aynen kalsın ...
  Future<void> _pickMovie() async {
     // (Mevcut kodunuzdaki _pickMovie içeriği buraya gelecek)
     // ...
     // Kısaca: Profildeki filmleri listeleme mantığınız aynı kalsın.
      final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        final merged = <Map<String, String>>[
          ...UserShelfCache.fiveStar,
          ...UserShelfCache.favorites,
          ...UserShelfCache.watchlist,
          ...UserShelfCache.disliked,
        ];
        
        final seen = <String>{};
        final items = <Map<String, String>>[];
        for (final m in merged) {
          final t = (m['title'] ?? '').trim();
          if (t.isEmpty) continue;
          final key = t.toLowerCase();
          if (seen.add(key)) {
            items.add({
              'title': t,
              'poster': (m['poster'] ?? '').toString(),
            });
          }
        }

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
                    ? const Center(child: Text('Listen boş. Profilinden senkronize et.'))
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

    if (result != null && mounted) {
      setState(() {
        _selectedMovie = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Yeni Gönderi')),
      body: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _controller,
        builder: (context, value, _) {
          final text = value.text;
          final remaining = widget.maxChars - text.characters.length;
          // Resim varsa da gönderilebilir olsun
          final hasContent = text.trim().isNotEmpty || _selectedImage != null || _selectedMovie != null;

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profil fotosu
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
                          TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            maxLines: null,
                            minLines: 1,
                            decoration: const InputDecoration(
                              hintText: 'Neler oluyor?',
                              border: InputBorder.none,
                            ),
                          ),
                          
                          // --- 1. RESİM ÖNİZLEME ALANI ---
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
                                      // Resmin çok uzamaması için maks yükseklik
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
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.close, color: Colors.white, size: 20),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // --- 2. FİLM KUTUCUĞU ---
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
                                        posterUrl: _selectedMovie!['poster']!,
                                        title: _selectedMovie!['title'],
                                        width: 44,
                                        height: 66,
                                        fit: BoxFit.cover,
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
                                    onPressed: () => setState(() => _selectedMovie = null),
                                    icon: const Icon(Icons.close),
                                    tooltip: 'Kaldır',
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          
                          // --- 3. ALT BUTONLAR ---
                          Row(
                            children: [
                              // Resim Seçme Butonu
                              IconButton(
                                onPressed: _pickImage,
                                icon: const Icon(Icons.image_outlined),
                                tooltip: 'Resim ekle',
                                color: cs.onSurfaceVariant,
                              ),
                              // Film Seçme Butonu
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
                                    : () => widget.onSend(text, _selectedMovie, _selectedImage),
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