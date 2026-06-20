import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/shell.dart';
import 'package:fluttergirdi/services/global_data_service.dart';
import 'package:fluttergirdi/widgets/green_characters.dart';
import 'package:fluttergirdi/controllers/feed_controller.dart';

class InitialLoadingScreen extends StatefulWidget {
  const InitialLoadingScreen({super.key});

  @override
  State<InitialLoadingScreen> createState() => _InitialLoadingScreenState();
}

class _InitialLoadingScreenState extends State<InitialLoadingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  String _randomFact = '';

  final List<String> _cinemaFacts = [
    'Matrix serisindeki ikonik yeşil kodlar aslında Japon suşi tariflerinden oluşur.',
    'Yüzüklerin Efendisi filminin bütçesi, gerçek Titanik gemisinin yapım maliyetinden daha yüksekti.',
    'Ucuz Roman (Pulp Fiction) filmindeki bütün saatler 4:20\'yi gösterir.',
    'İlk Star Wars filmi için tasarlanan Millennium Falcon uzay gemisi, bir hamburgerden ilham alınmıştır.',
    'Terminatör\'de Arnold Schwarzenegger, film boyunca sadece 74 kelime konuşmuştur.',
    'Rocky filmindeki ikonik koşu sahnesinde, pazar yerindeki insanların çoğu çekim yapıldığından habersiz gerçek halktı.',
    'Leon (Sevginin Gücü) filmindeki polis baskını sahnesi o kadar gerçekçiydi ki, civardaki bir soyguncu gerçek polis sanıp teslim olmuştur.',
  ];

  @override
  void initState() {
    super.initState();
    _randomFact = _cinemaFacts[Random().nextInt(_cinemaFacts.length)];

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    );

    _preloadAndGo();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _preloadAndGo() async {
    // Preloading zaten main.dart'ta başladı ama shell'de de çağrılıyor.
    // Burada tekrar çağırmak zararlı değil — ??= guard var içeride.
    GlobalDataService.instance.startPreloading();

    await Future.wait([
      _controller.forward(),       // Animasyonun tamamlanmasını bekle
      _waitForCriticalData(),      // Kritik verilerin gelmesini bekle
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

  Future<void> _waitForCriticalData() async {
    // Kritik sıra:
    // 1. Feed controller (kullanıcı açılınca feed boş görünmesin)
    // 2. Profil/shelf cache (film detayına girilince izlendi durumu görünsün)
    // 3. Chat + match için kısa tolerans (bunlar olmasa da ana akış çalışır)

    await Future.wait([
      FeedController.instance.init(),
      FeedController.instance.initFollowing(),
      // Profil datası ilk Firestore snapshot'ından geldiğinde resolve eder.
      // Firestore offline cache varsa ~50ms, yoksa ~500ms sürer.
      GlobalDataService.instance.profileReady
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () {}, // Timeout olursa takılma, devam et
          ),
    ]);

    // Chat ve match için maksimum 1 saniye daha bekle.
    // Gelmediyse zaten kademeli olarak gelecek — kullanıcıyı bekletme.
    await Future.any([
      Future.wait([
        _waitUntil(() => GlobalDataService.instance.myChats != null),
        _waitUntil(() => GlobalDataService.instance.myMatches != null),
      ]),
      Future.delayed(const Duration(seconds: 1)),
    ]);
  }

  /// Belirli bir koşul sağlanana kadar 50ms aralıklarla bekler.
  Future<void> _waitUntil(bool Function() condition) async {
    while (!condition()) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  @override
  Widget build(BuildContext context) {
    const double barWidth       = 260.0;
    const double characterSize  = 55.0;
    const double travelDistance = barWidth - characterSize;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final travel = _controller.value * travelDistance;
                  return Column(children: [
                    SizedBox(
                      width: barWidth,
                      height: characterSize,
                      child: Stack(children: [
                        Positioned(
                          left: travel,
                          bottom: 0,
                          child: Transform.rotate(
                            angle: _controller.value * 2 * pi * 3,
                            child: const GreenEyesCharacter(size: characterSize),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 5),
                    SizedBox(
                      width: barWidth,
                      height: 8,
                      child: Stack(children: [
                        Container(
                          width: barWidth, height: 8,
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        Container(
                          width: travel + characterSize, height: 8,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2E7D32),
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [BoxShadow(
                              color: const Color(0xFF2E7D32).withValues(alpha: 0.4),
                              blurRadius: 8, offset: const Offset(0, 2),
                            )],
                          ),
                        ),
                      ]),
                    ),
                  ]);
                },
              ),
              const SizedBox(height: 40),
              Text(
                'Biliyor muydunuz?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _randomFact,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.color
                      ?.withValues(alpha: 0.7),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}