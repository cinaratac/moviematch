import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluttergirdi/services/poster_fallback_service.dart'; 
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

// CacheManager global olarak tanımlı (Doğru)
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

  const PosterImage({
    super.key,
    required this.posterUrl,
    required this.title,
    this.tmdbId, 
    this.width,
    this.height,
    this.fit = BoxFit.cover,
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
    // KORUMA 1: Eğer zaten yükleniyorsa, başlık yoksa veya 2 kereden fazla denendiyse dur.
    if (_isLoadingFallback || _isEmpty(widget.title) || _retryCount >= 2) {
      if (mounted && _retryCount >= 2) setState(() => _failed = true);
      return;
    }
    
    if (!mounted) return;
    setState(() {
      _isLoadingFallback = true;
      _retryCount++; // Deneme sayısını artır
    });

    try {
      final newUrl = await PosterFallbackService.instance.resolvePosterUrl(
        title: widget.title,
        tmdbId: widget.tmdbId,
        existing: widget.posterUrl,
      );
      
      if (mounted) {
        // KORUMA 2: Yeni URL geçerli mi ve eskisiyle farklı mı?
        if (newUrl != null && newUrl.isNotEmpty && newUrl != _currentUrl) {
          setState(() {
            _currentUrl = newUrl;
            _failed = false;
            // Başarılı olursa sayacı sıfırlama, çünkü bu yeni resim de bozuk olabilir.
            // Sayacı olduğu gibi bırakıyoruz ki sonsuz döngü olmasın.
          });
        } else {
          // Eğer aynı URL geldiyse veya null ise başarısız say.
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

    return CachedNetworkImage(
      imageUrl: _currentUrl!,
      cacheManager: customCacheManager,
      // DÜZELTME: maxWidthDiskCache KALDIRILDI.
      // Bu parametre bazı resimlerde işleme hatası verip infinite loop'a sokuyor olabilir.
      // Sadece RAM için memCacheWidth tutuyoruz, bu performans için yeterlidir.
      memCacheWidth: 300, 
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorWidget: (context, url, error) {
        // Döngü koruması: Sadece henüz fallback denenmediyse dene
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