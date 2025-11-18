import 'package:flutter/material.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';

/// Feed'deki post paylaşma bileşeninin taşınmış/yeniden kullanılabilir hali.
/// FEED ekranında `_Composer` olarak kullanılan widget ile aynı API'yi korur.
class FeedComposer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final int maxChars;
  final void Function(String)? onSend;
  final Map<String, String>? selectedMovie;
  final VoidCallback onPickMovie;
  final VoidCallback onClearMovie;

  const FeedComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.maxChars,
    required this.selectedMovie,
    required this.onPickMovie,
    required this.onClearMovie,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final text = value.text;
        final remaining = maxChars - text.characters.length;
        final isEmpty = text.trim().isEmpty;

        return Padding(
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
                      controller: controller,
                      focusNode: focusNode,
                      maxLines: null,
                      minLines: 1,
                      decoration: const InputDecoration(
                        hintText: 'Neler oluyor?',
                        border: InputBorder.none,
                      ),
                    ),
                    if (selectedMovie != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: cs.outlineVariant),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            if ((selectedMovie!['poster'] ?? '').isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: PosterImage(
                                  posterUrl: (() {
                                    final raw =
                                        (selectedMovie!['poster'] ??
                                                selectedMovie!['posterUrl'] ??
                                                '')
                                            as String;
                                    if (raw.isEmpty) return '';
                                    if (raw.startsWith('http'))
                                      return raw; // absolute URL already
                                    // TMDB relative path like "/abc.jpg"
                                    return 'https://image.tmdb.org/t/p/w185$raw';
                                  })(),
                                  title: selectedMovie!['title'],
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
                                selectedMovie!['title'] ?? 'Seçili film',
                                style: theme.textTheme.titleSmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              onPressed: onClearMovie,
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
                          tooltip: 'Medya',
                          color: cs.onSurfaceVariant,
                        ),
                        IconButton(
                          onPressed: onPickMovie,
                          icon: const Icon(Icons.movie),
                          tooltip: 'Film seç',
                          color: cs.onSurfaceVariant,
                        ),
                        const Spacer(),
                        if (remaining <= 40)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Text(
                              remaining.toString(),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: remaining < 0
                                    ? cs.error
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        FilledButton(
                          onPressed: isEmpty || remaining < 0
                              ? null
                              : () {
                                  onSend?.call(text);
                                  if (context.mounted) {
                                    Navigator.of(
                                      context,
                                    ).pop(); // return to Feed
                                  }
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
        );
      },
    );
  }
}
