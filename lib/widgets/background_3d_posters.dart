// Dosya: lib/widgets/background_3d_posters.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/scheduler.dart'; // Ticker için EKLENDİ

class Background3DPosters extends StatefulWidget {
  const Background3DPosters({super.key});

  @override
  State<Background3DPosters> createState() => _Background3DPostersState();
}

// Global cache: Uygulama açık kaldığı sürece veriyi hafızada tutar
List<String> _globalCachedPosters = []; 

// SingleTickerProviderStateMixin yerine TickerProviderStateMixin kullanıldı
// Çünkü artık hem AnimationController hem de kendi Ticker'ımız var.
class _Background3DPostersState extends State<Background3DPosters> with TickerProviderStateMixin {
  List<String> _posterUrls = [];
  bool _isLoading = true;

  final ScrollController _scrollController1 = ScrollController();
  final ScrollController _scrollController2 = ScrollController();
  final ScrollController _scrollController3 = ScrollController();
  
  late AnimationController _entranceController;
  late Animation<Offset> _entranceAnimation;

  // YENİ: Timer yerine Ticker kullanıyoruz (Sıfır kasma garantili)
  late Ticker _ticker;

  @override
  void initState() {
    super.initState();
    
    // 1. Giriş Animasyonu Tanımları
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800), 
    );

    _entranceAnimation = Tween<Offset>(
      begin: const Offset(0, 1.0), 
      end: Offset.zero,            
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutQuart,  
    ));

    // 2. Ticker (Ekran yenileme hızına senkronize döngü)
    _ticker = createTicker((elapsed) {
      if (!mounted) return;
      // Timer (30ms) yerine Ticker (16ms) kullandığımız için hızları yarıya indirdik
      _scroll(_scrollController1, 0.5);
      _scroll(_scrollController2, 0.75);
      _scroll(_scrollController3, 0.4);
    });

    _fetchPosters();
  }

  Future<void> _fetchPosters() async {
    if (_globalCachedPosters.isNotEmpty) {
      if (mounted) {
        setState(() {
          _posterUrls = List.from(_globalCachedPosters)..shuffle(Random());
          _isLoading = false;
        });
        _startAutoScroll();
        _entranceController.forward(); 
      }
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('catalog_films')
          .where('posterUrl', isNull: false)
          .limit(50) 
          .get();

      List<String> urls = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['posterUrl'] != null) {
          urls.add(data['posterUrl']);
        }
      }

      if (urls.isNotEmpty) {
        _globalCachedPosters = urls;
      }

      urls.shuffle(Random());

      if (mounted) {
        setState(() {
          _posterUrls = urls;
          _isLoading = false;
        });
        _startAutoScroll();
        _entranceController.forward(); 
      }
    } catch (e) {
      debugPrint("Poster fetch error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startAutoScroll() {
    // Ticker çalışmıyorsa başlat
    if (!_ticker.isTicking) {
      _ticker.start();
    }
  }

  void _scroll(ScrollController controller, double speed) {
    if (controller.hasClients) {
      double maxScroll = controller.position.maxScrollExtent;
      double currentScroll = controller.offset;
      
      if (currentScroll >= maxScroll * 0.9) {
         controller.jumpTo(0);
      } else {
        controller.jumpTo(currentScroll + speed);
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose(); // Timer.cancel() yerine Ticker'ı yok ediyoruz
    _entranceController.dispose(); 
    _scrollController1.dispose();
    _scrollController2.dispose();
    _scrollController3.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _posterUrls.isEmpty) {
      return Container(color: Colors.black); 
    }

    return SlideTransition(
      position: _entranceAnimation,
      child: Row(
        children: [
          Expanded(child: _buildInfiniteColumn(_scrollController1, 0)),
          Expanded(child: _buildInfiniteColumn(_scrollController2, 1)),
          Expanded(child: _buildInfiniteColumn(_scrollController3, 2)),
        ],
      ),
    );
  }

  Widget _buildInfiniteColumn(ScrollController controller, int offsetIndex) {
    return ListView.builder(
      controller: controller,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 10000, 
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) {
        final realIndex = (index + (offsetIndex * 5)) % _posterUrls.length;
        final url = _posterUrls[realIndex];

        return Container(
          height: 180, 
          margin: const EdgeInsets.all(4), 
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            image: DecorationImage(
              image: CachedNetworkImageProvider(url, maxWidth: 300),
              fit: BoxFit.cover,
            ),
          ),
        );
      },
    );
  }
}