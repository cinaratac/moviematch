// Dosya: lib/widgets/background_3d_posters.dart

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

class Background3DPosters extends StatefulWidget {
  const Background3DPosters({super.key});

  @override
  State<Background3DPosters> createState() => _Background3DPostersState();
}

// Global cache: Uygulama açık kaldığı sürece veriyi hafızada tutar
List<String> _globalCachedPosters = []; 

class _Background3DPostersState extends State<Background3DPosters> with SingleTickerProviderStateMixin {
  List<String> _posterUrls = [];
  bool _isLoading = true;

  final ScrollController _scrollController1 = ScrollController();
  final ScrollController _scrollController2 = ScrollController();
  final ScrollController _scrollController3 = ScrollController();
  
  // --- YENİ EKLENEN ANİMASYON DEĞİŞKENLERİ ---
  late AnimationController _entranceController;
  late Animation<Offset> _entranceAnimation;

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    
    // 1. Giriş Animasyonu Tanımları
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800), // 1.8 saniyede yavaşça gelsin
    );

    // Aşağıdan (y ekseni 1.0) -> Yukarıya (y ekseni 0.0)
    _entranceAnimation = Tween<Offset>(
      begin: const Offset(0, 1.0), // Tamamen ekranın altından başla
      end: Offset.zero,            // Kendi yerine otur
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutQuart,  // Sonlara doğru yavaşlayan yumuşak bir fizik
    ));

    _fetchPosters();
  }

  Future<void> _fetchPosters() async {
    // A) HAFİZA KONTROLÜ
    if (_globalCachedPosters.isNotEmpty) {
      if (mounted) {
        setState(() {
          _posterUrls = List.from(_globalCachedPosters)..shuffle(Random());
          _isLoading = false;
        });
        _startAutoScroll();
        _entranceController.forward(); // Veri hazır, animasyonu başlat!
      }
      return;
    }

    // B) İLK YÜKLEME (Firebase'den çek)
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

      // Listeyi karıştır
      urls.shuffle(Random());

      if (mounted) {
        setState(() {
          _posterUrls = urls;
          _isLoading = false;
        });
        _startAutoScroll();
        _entranceController.forward(); // Veri geldi, sahneye alalım!
      }
    } catch (e) {
      debugPrint("Poster fetch error: $e");
      // Hata olsa bile loading'i kapat ki sonsuz döngüde kalmasın
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startAutoScroll() {
    _timer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      if (!mounted) return;
      _scroll(_scrollController1, 1.0);
      _scroll(_scrollController2, 1.5);
      _scroll(_scrollController3, 0.8);
    });
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
    _timer?.cancel();
    _entranceController.dispose(); // Controller'ı temizlemeyi unutmayalım
    _scrollController1.dispose();
    _scrollController2.dispose();
    _scrollController3.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Veri yokken siyah ekran göster (Animasyon siyah ekranın üstüne çıkacak)
    if (_isLoading || _posterUrls.isEmpty) {
      return Container(color: Colors.black); 
    }

    // --- ANİMASYONLU GÖSTERİM ---
    // SlideTransition ile tüm Row'u aşağıdan yukarı kaydırıyoruz
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