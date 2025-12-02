import 'package:flutter/material.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';
import 'package:fluttergirdi/screens/profilescreen.dart'; // UserShelfCache için

class ComposePostPage extends StatefulWidget {
  final int maxChars;
  final Future<void> Function(String text, Map<String, String>? movie) onSend;

  const ComposePostPage({
    super.key,
    required this.maxChars,
    required this.onSend,
  });

  @override
  State<ComposePostPage> createState() => _ComposePostPageState();
}

class _ComposePostPageState extends State<ComposePostPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Map<String, String>? _selectedMovie;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _pickMovie() async {
    // Film seçme menüsü
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        // Profildeki filmleri al
        final merged = <Map<String, String>>[
          ...UserShelfCache.fiveStar,
          ...UserShelfCache.favorites,
          ...UserShelfCache.watchlist,
          ...UserShelfCache.disliked,
        ];
        
        // Tekrar edenleri temizle
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
      // Filmi seçince otomatik başlığı metne ekle (opsiyonel)
      if (_controller.text.isEmpty) {
        _controller.text = '';
      }
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
          final isEmpty = text.trim().isEmpty;

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(radius: 20, child: Icon(Icons.person)),
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
                          // --- FİLM KUTUCUĞU (ESKİ TASARIM) ---
                          if (_selectedMovie != null) ...[
                            const SizedBox(height: 8),
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
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              IconButton(
                                onPressed: () {},
                                icon: const Icon(Icons.image_outlined),
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
                                onPressed: isEmpty || remaining < 0
                                    ? null
                                    : () => widget.onSend(text, _selectedMovie),
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