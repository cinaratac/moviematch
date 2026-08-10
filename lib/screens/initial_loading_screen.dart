import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/shell.dart';
import 'package:fluttergirdi/services/app_popular_movies_service.dart';
import 'package:fluttergirdi/services/global_data_service.dart';
import 'package:fluttergirdi/services/notification_service.dart';
import 'package:fluttergirdi/services/push_token_service.dart';
import 'package:fluttergirdi/services/user_cache_service.dart';
import 'package:fluttergirdi/controllers/feed_controller.dart';
import 'package:fluttergirdi/widgets/branded_splash.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';

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
      _waitForCriticalData(),
    ]);

    if (!mounted) return;
    await _precacheFirstViewportImages();

    // Animasyon bittikten sonra kısa yumuşatma
    await Future.delayed(const Duration(milliseconds: 120));

    if (mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, _, _) => const HomeShell(),
          transitionsBuilder: (_, animation, _, child) =>
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
    await Future.wait([
      FeedController.instance.init(),
      FeedController.instance.initFollowing(),
      AppPopularMoviesService.instance.preload(),
      _waitForProfile(),
    ]);
  }

  Future<void> _waitForProfile() async {
    try {
      await GlobalDataService.instance.profileReady.timeout(
        const Duration(seconds: 3),
      );
    } catch (_) {
      debugPrint("Profil yüklemesi zaman aşımına uğradı, devam ediliyor.");
    }
  }

  Future<void> _precacheFirstViewportImages() async {
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final providers = <ImageProvider>[];
    final seenUrls = <String>{};

    void addImage(
      Object? rawUrl, {
      required int cacheWidth,
      bool isPoster = false,
    }) {
      final url = rawUrl?.toString().trim() ?? '';
      if (url.isEmpty ||
          (!url.startsWith('http://') && !url.startsWith('https://')) ||
          !seenUrls.add(url)) {
        return;
      }
      if (isPoster && url.contains('ltrbxd.com')) return;

      final provider = CachedNetworkImageProvider(
        url,
        cacheKey: isPoster ? url.split('?').first : null,
        cacheManager: isPoster ? customCacheManager : null,
      );
      providers.add(ResizeImage(provider, width: cacheWidth));
    }

    final popularMovies =
        AppPopularMoviesService.instance.cachedMovies ?? const [];
    for (final movie in popularMovies) {
      addImage(movie.posterUrl, cacheWidth: 312, isPoster: true);
    }

    final feed = FeedController.instance;
    for (final post in feed.posts.take(4)) {
      final data = post.data() ?? const <String, dynamic>{};
      final authorId = (data['authorId'] ?? '').toString();
      final cachedUser = UserCacheService.instance.getFromCache(authorId);
      addImage(
        cachedUser?.photoURL ?? data['photoURL'],
        cacheWidth: (40 * devicePixelRatio).round(),
      );

      final photoUrls = data['photoURLs'];
      final firstPostImage = photoUrls is List && photoUrls.isNotEmpty
          ? photoUrls.first
          : data['postImage'];
      addImage(
        firstPostImage,
        cacheWidth: (screenWidth * devicePixelRatio).round(),
      );

      final movie = data['movie'] is Map ? data['movie'] as Map : null;
      addImage(
        data['moviePoster'] ?? movie?['poster'] ?? movie?['posterUrl'],
        cacheWidth: (54 * devicePixelRatio).round(),
        isPoster: true,
      );
    }

    await Future.wait(
      providers.map((provider) async {
        try {
          await precacheImage(
            provider,
            context,
            onError: (_, _) {},
          ).timeout(const Duration(seconds: 8));
        } catch (_) {
          // Bozuk bir görsel uygulamanın açılmasını engellememeli.
        }
      }),
    );
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
