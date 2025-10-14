// lib/widgets/poster_image.dart
import 'package:flutter/material.dart';
import '../services/poster_fallback_service.dart';

class PosterImage extends StatelessWidget {
  final String? posterUrl; // mevcut (boş da olabilir)
  final int? tmdbId;
  final String? imdbId;
  final String? title;
  final int? year;

  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const PosterImage({
    super.key,
    required this.posterUrl,
    this.tmdbId,
    this.imdbId,
    this.title,
    this.year,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: PosterFallbackService.instance.resolvePosterUrl(
        existing: posterUrl,
        tmdbId: tmdbId,
        imdbId: imdbId,
        title: title,
        year: year,
        writeBackToCatalog: true,
      ),
      builder: (context, snap) {
        final url = snap.data ?? posterUrl;
        final child = (url != null && url.isNotEmpty)
            ? Image.network(
                url,
                width: width,
                height: height,
                fit: fit,
                errorBuilder: (_, __, ___) => _placeholder(),
              )
            : _placeholder();
        if (borderRadius != null) {
          return ClipRRect(borderRadius: borderRadius!, child: child);
        }
        return child;
      },
    );
  }

  Widget _placeholder() {
    return Container(
      width: width,
      height: height,
      color: Colors.black12,
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image_outlined),
    );
  }
}
