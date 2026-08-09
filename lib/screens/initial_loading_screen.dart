import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/shell.dart';
import 'package:fluttergirdi/services/global_data_service.dart';
import 'package:fluttergirdi/services/notification_service.dart';
import 'package:fluttergirdi/services/push_token_service.dart';
import 'package:fluttergirdi/controllers/feed_controller.dart';
import 'package:fluttergirdi/widgets/branded_splash.dart';

class InitialLoadingScreen extends StatefulWidget {
  const InitialLoadingScreen({super.key});

  @override
  State<InitialLoadingScreen> createState() => _InitialLoadingScreenState();
}

class _InitialLoadingScreenState extends State<InitialLoadingScreen> {
  @override
  void initState() {
    super.initState();
    _preloadAndGo();
  }

  Future<void> _preloadAndGo() async {
    // Bu ekran yalnızca AuthGate kayıt durumunu sunucudan doğruladıktan sonra
    // açılır. Kullanıcıya özel servisleri yarım kayıtlar için başlatma.
    unawaited(_startNotificationServices());

    // Preloading zaten main.dart'ta başladı ama shell'de de çağrılıyor.
    // Burada tekrar çağırmak zararlı değil — ??= guard var içeride.
    GlobalDataService.instance.startPreloading();

    await Future.wait([
      Future.delayed(const Duration(milliseconds: 700)),
      _waitForCriticalData().timeout(
        const Duration(milliseconds: 2500),
        onTimeout: () {
          debugPrint(
            "Başlangıç verisi gecikti, uygulama açılışı sürdürülüyor.",
          );
        },
      ),
    ]);

    // Animasyon bittikten sonra kısa yumuşatma
    await Future.delayed(const Duration(milliseconds: 200));

    if (mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const HomeShell(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  Future<void> _startNotificationServices() async {
    await NotificationService.I.start();
    await NotificationService.I.requestPermissions();
    await PushTokenService.I.start();
  }

  Future<void> _waitForCriticalData() async {
    // 1. Önce sadece ana akış yüklensin
    await FeedController.instance.init();

    // Yığılmayı önlemek için araya çeyrek saniyelik nefes payı koyuyoruz
    await Future.delayed(const Duration(milliseconds: 250));

    // 2. Takip edilenler akışı yüklensin
    await FeedController.instance.initFollowing();

    // 3. Profil ve diğer global veriler yüklensin (Zaman aşımı korumalı)
    try {
      await GlobalDataService.instance.profileReady.timeout(
        const Duration(seconds: 3),
      );
    } catch (_) {
      debugPrint("Profil yüklemesi zaman aşımına uğradı, devam ediliyor.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 40.0),
          child: BrandedSplash(),
        ),
      ),
    );
  }
}