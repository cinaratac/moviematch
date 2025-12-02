import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluttergirdi/services/poster_fallback_service.dart'; 

class PosterImage extends StatefulWidget {
  final String? posterUrl;
  final String? title; // Fallback için gerekli
  final int? tmdbId;   // Fallback için gerekli (daha kesin sonuç sağlar)
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

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.posterUrl;
    
    // URL boşsa ve elimizde Title varsa hemen fallback dene
    if (_isEmpty(_currentUrl) && !_isEmpty(widget.title)) {
      _tryFallback();
    }
  }

  @override
  void didUpdateWidget(covariant PosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // URL, Title veya ID değişirse durumu sıfırla
    if (oldWidget.posterUrl != widget.posterUrl || 
        oldWidget.title != widget.title || 
        oldWidget.tmdbId != widget.tmdbId) {
      
      setState(() {
        _currentUrl = widget.posterUrl;
        _failed = false;
        _isLoadingFallback = false;
      });

      if (_isEmpty(_currentUrl) && !_isEmpty(widget.title)) {
        _tryFallback();
      }
    }
  }

  bool _isEmpty(String? s) => s == null || s.trim().isEmpty;

  Future<void> _tryFallback() async {
    // Eğer zaten aranıyorsa veya başlık yoksa işlem yapma
    if (_isLoadingFallback || _isEmpty(widget.title)) return;
    
    if (!mounted) return;
    setState(() => _isLoadingFallback = true);

    try {
      // --- DÜZELTME BURADA YAPILDI ---
      // fetchPoster yerine resolvePosterUrl kullanıyoruz.
      // Ayrıca tmdbId'yi de gönderiyoruz ki kesin sonuç bulsun.
      final newUrl = await PosterFallbackService.instance.resolvePosterUrl(
        title: widget.title,
        tmdbId: widget.tmdbId,
        existing: widget.posterUrl, // Mevcut bozuk URL'i de kontrol etsin
      );
      
      if (mounted) {
        if (newUrl != null && newUrl.isNotEmpty) {
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
    // 1. Hata durumu veya URL yoksa placeholder göster
    if (_failed || (_isEmpty(_currentUrl) && !_isLoadingFallback)) {
      return _buildPlaceholder();
    }

    // 2. Fallback aranıyorsa loading göster
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

    // 3. Resmi göster
    return CachedNetworkImage(
      imageUrl: _currentUrl!,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorWidget: (context, url, error) {
        // Resim yüklenemedi (404), Fallback mekanizmasını tetikle!
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_isLoadingFallback && !_failed) {
            _tryFallback();
          }
        });
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