import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluttergirdi/services/poster_fallback_service.dart'; 
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

// CacheManager global olarak tanımlı
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
  // Optimize için yeni parametre: İstenilen bellek önbellek boyutu
  final int? cacheWidth;

  const PosterImage({
    super.key,
    required this.posterUrl,
    required this.title,
    this.tmdbId, 
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.cacheWidth, // Yeni parametre
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
    
    if (_isEmpty(_currentUrl) && !_isEmpty(widget.title)) {
      _tryFallback();
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
        _tryFallback();
      }
    }
  }

  bool _isEmpty(String? s) => s == null || s.trim().isEmpty;

  Future<void> _tryFallback() async {
    if (_isLoadingFallback || _isEmpty(widget.title) || _retryCount >= 2) {
      if (mounted && _retryCount >= 2) setState(() => _failed = true);
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

    // OPTİMİZASYON: Bellek boyutunu hesapla
    // Eğer dışarıdan cacheWidth verilmişse onu kullan.
    // Verilmemişse ama widget.width belliyse onun 2.5 katını kullan (Retina ekranlar için).
    // Hiçbiri yoksa varsayılan 200 kullan (Eski 300'den daha güvenli).
    final int? optimalMemCacheWidth = widget.cacheWidth ?? 
        (widget.width != null ? (widget.width! * 2.5).toInt() : 200);

    return CachedNetworkImage(
      imageUrl: _currentUrl!,
      cacheManager: customCacheManager,
      
      // ÖNEMLİ: Sadece RAM'deki boyutu kısıtlıyoruz. 
      // Disktekini orijinal boyutta tutabiliriz, böylece detay sayfasına geçince tekrar indirmeyiz.
      memCacheWidth: optimalMemCacheWidth,
      
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorWidget: (context, url, error) {
        if (!_isLoadingFallback && !_failed) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _tryFallback();
            });
        }
        return _buildPlaceholder();
      },
      placeholder: (context, url) => Container(
        width: widget.width,
        height: widget.height,
        color: Colors.grey[850],
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