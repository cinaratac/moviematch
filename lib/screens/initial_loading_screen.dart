import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/shell.dart';
import 'package:fluttergirdi/services/global_data_service.dart';
import 'package:fluttergirdi/widgets/green_characters.dart';

class InitialLoadingScreen extends StatefulWidget {
  const InitialLoadingScreen({super.key});

  @override
  State<InitialLoadingScreen> createState() => _InitialLoadingScreenState();
}

class _InitialLoadingScreenState extends State<InitialLoadingScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  String _randomFact = "";

  final List<String> _cinemaFacts = [
    "Matrix serisindeki ikonik yeşil kodlar aslında Japon suşi tariflerinden oluşur.",
    "Yüzüklerin Efendisi filminin bütçesi, gerçek Titanik gemisinin yapım maliyetinden daha yüksekti.",
    "Ucuz Roman (Pulp Fiction) filmindeki bütün saatler 4:20'yi gösterir.",
    "İlk Star Wars filmi için tasarlanan Millennium Falcon uzay gemisi, bir hamburgerden ilham alınmıştır.",
    "Terminatör'de Arnold Schwarzenegger, film boyunca sadece 74 kelime konuşmuştur.",
    "Rocky filmindeki ikonik koşu sahnesinde, pazar yerindeki insanların çoğu çekim yapıldığından habersiz gerçek halktı.",
    "Leon (Sevginin Gücü) filmindeki polis baskını sahnesi o kadar gerçekçiydi ki, civardaki bir soyguncu gerçek polis sanıp teslim olmuştur.",
  ];

  @override
  void initState() {
    super.initState();
    final random = Random();
    _randomFact = _cinemaFacts[random.nextInt(_cinemaFacts.length)];

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
    GlobalDataService.instance.startPreloading();

    Future<void> dataWait() async {
      int loop = 0;
      
      // 1. Match, Chat VE FEED verilerinin inmesini bekle
      while ((GlobalDataService.instance.myMatches == null || 
              GlobalDataService.instance.myChats == null || 
              GlobalDataService.instance.myFeed == null) && loop < 100) {
        await Future.delayed(const Duration(milliseconds: 100));
        loop++;
      }

      // 2. KESİN ÇÖZÜM: Sohbetlerdeki herkesin profil resmini cihaz belleğine (RAM) kaydet!
      // precacheImage bloğunu şu şekilde try-catch içine al ve kesinlikle await etme (bağımsız çalışsın)
if (mounted && GlobalDataService.instance.myChats != null) {
  for (var doc in GlobalDataService.instance.myChats!) {
    final photos = doc.data()['photos'] as Map?;
    if (photos != null) {
      for (var url in photos.values) {
        if (url is String && url.isNotEmpty && url.startsWith('http')) {
          // AWAIT ETME, SADECE TETİKLE VE UNUT
          precacheImage(NetworkImage(url), context).catchError((e) {
            debugPrint("Resim önbelleğe alınamadı (403 olabilir): $url");
            return null;
          });
        }
      }
    }
  }
}
    }

    await Future.wait([
      _controller.forward(),
      dataWait(),
    ]);

    await Future.delayed(const Duration(milliseconds: 300));

    if (mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const HomeShell(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const double barWidth = 260.0;
    const double characterSize = 55.0;
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
                builder: (context, child) {
                  final double currentTravel = _controller.value * travelDistance;
                  
                  return Column(
                    children: [
                      SizedBox(
                        width: barWidth,
                        height: characterSize,
                        child: Stack(
                          children: [
                            Positioned(
                              left: currentTravel,
                              bottom: 0,
                              child: Transform.rotate(
                                angle: _controller.value * 2 * pi * 3, 
                                child: const GreenEyesCharacter(
                                  size: characterSize,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 5),
                      SizedBox(
                        width: barWidth,
                        height: 8,
                        child: Stack(
                          children: [
                            Container(
                              width: barWidth,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.2), 
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            Container(
                              width: currentTravel + characterSize,
                              height: 8,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2E7D32),
                                borderRadius: BorderRadius.circular(4),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF2E7D32).withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
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
                  color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
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