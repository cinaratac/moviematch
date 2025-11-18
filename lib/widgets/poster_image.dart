import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/poster_fallback_service.dart';

class PosterImage extends StatelessWidget {
  final String? posterUrl; 
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
    // Eğer hiç veri yoksa direkt placeholder dön
    if ((posterUrl == null || posterUrl!.isEmpty) && 
        tmdbId == null && 
        (title == null || title!.isEmpty)) {
      return _buildClip(_placeholder());
    }

    return FutureBuilder<String?>(
      // Poster URL'yi doğrula veya TMDB'den bul
      future: PosterFallbackService.instance.resolvePosterUrl(
        existing: posterUrl,
        tmdbId: tmdbId,
        imdbId: imdbId,
        title: title,
        year: year,
        writeBackToCatalog: true, // Bulursa DB'ye kaydet ki sonraki sefer hızlı olsun
      ),
      builder: (context, snap) {
        // Veri henüz gelmediyse veya yükleniyorsa
        if (snap.connectionState == ConnectionState.waiting && posterUrl == null) {
          return _buildClip(_placeholder());
        }

        // Servis bir URL buldu mu? Yoksa eskisiyle mi devam edelim?
        final url = snap.data ?? posterUrl;

        if (url != null && url.isNotEmpty) {
          return _buildClip(
            CachedNetworkImage(
              imageUrl: url,
              width: width,
              height: height,
              fit: fit,
              // Cache yönetimi: Disk ve Ram kullanımı optimize edilir
              memCacheWidth: (width != null && width! > 0) ? (width! * 2).toInt() : 400,
              fadeInDuration: const Duration(milliseconds: 300),
              placeholder: (context, url) => _placeholder(),
              errorWidget: (context, url, error) {
                // URL geldi ama yüklenirken hata oldu (403 vs), placeholder göster
                return _placeholder(isError: true);
              },
            ),
          );
        }

        return _buildClip(_placeholder());
      },
    );
  }

  Widget _buildClip(Widget child) {
    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: child);
    }
    return child;
  }

  Widget _placeholder({bool isError = false}) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[900], // Daha şık bir dark mode placeholder rengi
      alignment: Alignment.center,
      child: Icon(
        isError ? Icons.broken_image_rounded : Icons.movie_creation_outlined,
        color: Colors.white24,
        size: (width != null && width! < 50) ? 20 : 32,
      ),
    );
  }
}