import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluttergirdi/services/poster_fallback_service.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

final customCacheManager = CacheManager(
  Config(
    'moviePosterCache',
    stalePeriod: const Duration(days: 7),
    maxNrOfCacheObjects: 200,
  ),
);

class PosterImage extends StatefulWidget {
  final String? posterUrl;
  final String? title;
  final int? tmdbId;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? cacheWidth;

  const PosterImage({
    super.key,
    required this.posterUrl,
    required this.title,
    this.tmdbId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.cacheWidth,
  });

  @override
  State<PosterImage> createState() => _PosterImageState();
}

class _PosterImageState extends State<PosterImage> {
  String? _currentUrl;
  bool _isLoadingFallback = false;
  bool _failed = false;
  int _retryCount = 0;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.posterUrl;

    // Eğer URL baştan boşsa hemen fallback dene
    if (_isEmpty(_currentUrl) && !_isEmpty(widget.title)) {
      _tryFallback(force: true);
    }
  }

  @override
  void didUpdateWidget(covariant PosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.posterUrl != widget.posterUrl ||
        oldWidget.title != widget.title ||
        oldWidget.tmdbId != widget.tmdbId) {
      setState(() {
        _currentUrl = widget.posterUrl;
        _failed = false;
        _isLoadingFallback = false;
        _retryCount = 0;
      });

      if (_isEmpty(_currentUrl) && !_isEmpty(widget.title)) {
        _tryFallback(force: true);
      }
    }
  }

  bool _isEmpty(String? s) => s == null || s.trim().isEmpty;

  // force: true ise mevcut URL'yi kontrol etmeden direkt TMDB'ye gider
  Future<void> _tryFallback({bool force = false}) async {
    if (_isLoadingFallback || _isEmpty(widget.title) || _retryCount >= 3) {
      if (mounted && _retryCount >= 3) setState(() => _failed = true);
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoadingFallback = true;
      _retryCount++;
    });

    try {
      final newUrl = await PosterFallbackService.instance.resolvePosterUrl(
        title: widget.title,
        tmdbId: widget.tmdbId,
        existing: widget.posterUrl,
        ignoreExisting: force, // KRİTİK DEĞİŞİKLİK
      );

      if (mounted) {
        if (newUrl != null && newUrl.isNotEmpty && newUrl != _currentUrl) {
          setState(() {
            _currentUrl = newUrl;
            _failed = false;
          });
        } else {
          setState(() => _failed = true);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _isLoadingFallback = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || (_isEmpty(_currentUrl) && !_isLoadingFallback)) {
      return _buildPlaceholder();
    }

    if (_isLoadingFallback && _isEmpty(_currentUrl)) {
      return _buildLoading();
    }

    final int? optimalMemCacheWidth =
        widget.cacheWidth ??
        (widget.width != null &&
                !widget.width!.isInfinite &&
                !widget.width!.isNaN
            ? (widget.width! * 2.5).toInt()
            : 300); // Sonsuzluk gelirse varsayılan olarak 300 kullan

    return CachedNetworkImage(
      imageUrl: _currentUrl!,
      httpHeaders: const {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
  },
      cacheManager: customCacheManager,
      memCacheWidth: optimalMemCacheWidth,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorWidget: (context, url, error) {
        // CachedNetworkImage yükleyemediyse URL bozuktur.
        // Bu yüzden force: true ile çağırıyoruz.
        if (!_isLoadingFallback && !_failed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _tryFallback(force: true);
          });
        }
        return _buildPlaceholder();
      },
      placeholder: (context, url) => _buildLoading(),
    );
  }

  Widget _buildLoading() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey[900],
      child: Center(
        child: SizedBox(
          width: (widget.width ?? 50) * 0.3,
          height: (widget.width ?? 50) * 0.3,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey[900],
      child: Center(
        child: Icon(
          Icons.movie_creation_outlined,
          color: Colors.white24,
          size: (widget.width ?? 50) * 0.4,
        ),
      ),
    );
  }
}
