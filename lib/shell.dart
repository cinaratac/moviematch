import 'dart:async'; 
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app_links/app_links.dart'; 
import 'package:fluttergirdi/services/chat_service.dart';
import 'package:fluttergirdi/screens/feed_screens.dart';
import 'package:fluttergirdi/screens/match_screen.dart';
import 'package:fluttergirdi/screens/messagesscreen.dart';
import 'package:fluttergirdi/screens/profilescreen.dart';
import 'package:fluttergirdi/services/announcement_service.dart';
import 'package:fluttergirdi/screens/post_detail_screen.dart';
import 'package:fluttergirdi/services/tab_service.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0; 
  late final AppLinks _appLinks; 
  StreamSubscription<Uri>? _linkSubscription;
  Timer? _idlePreloadTimer; // EKLENDİ: Arka plan akıllı yükleme zamanlayıcısı

  final List<Widget> _pages = [
    const FeedPage(),
    const MatchListScreen(),
    const MessagesPage(),
    const ProfilePage(),
  ];
  final List<bool> _loadedPages = [true, false, false, false];

  @override
  void initState() {
    super.initState();
    
    // TabService Dinleyicisi
    TabService.instance.indexNotifier.addListener(_onTabServiceIndexChanged);

    // Duyuru kontrolü
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AnnouncementService.instance.checkAndShowAnnouncement(context);
    });

    _initDeepLinks();
    
    // Uygulama açıldığında ilk ekran yüklendikten sonra diğerlerini arkada yüklemeye başla
    _startIdlePreloading();
  }

  // EKLENDİ: Drawer'dan vs. tetiklenen değişimleri yakalamak için
  void _onTabServiceIndexChanged() {
    if (mounted) {
      final newIndex = TabService.instance.indexNotifier.value;
      if (_index != newIndex) {
        _switchToTab(newIndex);
      }
    }
  }

  // EKLENDİ: Merkezi Sekme Değiştirme ve Yükleme Kontrolcüsü
  void _switchToTab(int targetIndex) {
    // 1. Kullanıcı sekmeye aniden bastığı için arka plandaki gizli yüklemeleri hemen iptal et
    _idlePreloadTimer?.cancel();

    // 2. Hedef sekmeyi anında aktif et ve yüklenmesi için izin ver
    setState(() {
      _index = targetIndex;
      _loadedPages[targetIndex] = true; 
    });
    
    // 3. Geçiş anındaki kasmanın geçmesi için biraz bekle ve kalan sayfaları arkada yüklemeye devam et
    _startIdlePreloading();
  }

  // EKLENDİ: Sistemi yormadan arka planda sayfaları teker teker yükleyen fonksiyon
  void _startIdlePreloading() {
    _idlePreloadTimer?.cancel();
    
    // Kullanıcının bulunduğu sayfayı rahatça görebilmesi için 1.5 saniye bekle
    _idlePreloadTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;

      // Yüklenmemiş olan ilk sekmeyi bul
      int nextToLoad = -1;
      for (int i = 0; i < _loadedPages.length; i++) {
        if (!_loadedPages[i]) {
          nextToLoad = i;
          break;
        }
      }

      // Eğer yüklenmemiş sayfa kaldıysa, sadece onu yükle
      if (nextToLoad != -1) {
        setState(() {
          _loadedPages[nextToLoad] = true;
        });
        
        // Bu sayfa yüklendikten sonra diğerine geçmek için döngüyü tekrar başlat (sistemi boğmamak için sırayla)
        _startIdlePreloading();
      }
    });
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _idlePreloadTimer?.cancel(); // Zamanlayıcıyı bellekten temizle
    TabService.instance.indexNotifier.removeListener(_onTabServiceIndexChanged);
    super.dispose();
  }

  // Linkleri dinleyen fonksiyon
  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    try {
      final Uri? initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } catch (e) {
      debugPrint('Link hatası: $e');
    }

    _linkSubscription = _appLinks.uriLinkStream.listen((Uri? uri) {
      if (uri != null) {
        _handleDeepLink(uri);
      }
    });
  }

  void _handleDeepLink(Uri uri) {
    if (uri.path.contains('/post')) {
      final String? postId = uri.queryParameters['id'];
      
      if (postId != null && mounted) {
        debugPrint("Link yakalandı! Post ID: $postId");
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PostDetailScreen(postId: postId),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _index == 0, 
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) {
          return;
        }
        
        if (_index != 0) {
          _switchToTab(0);
          TabService.instance.changeTab(0); 
        }
      },
      child: Scaffold( 
        extendBody: true,
        body: IndexedStack(
          index: _index,
          children: List.generate(_pages.length, (index) {
            return _loadedPages[index] ? _pages[index] : const SizedBox.shrink();
          }),
        ),
        bottomNavigationBar: _buildBottomBar(context),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        boxShadow: const [], 
      ),
      child: SafeArea(
        top: false, 
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            height: 52,
            backgroundColor: Colors.transparent, 
            indicatorColor: cs.primary.withOpacity(0.14),
            indicatorShape: const StadiumBorder(),
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            iconTheme: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return IconThemeData(
                size: 20,
                color: selected ? const Color.fromARGB(253, 97, 202, 101) : Colors.white70,
              );
            }),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? const Color.fromARGB(253, 97, 202, 101) : Colors.white70,
              );
            }),
          ),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) {
              _switchToTab(i); // EKLENDİ: Merkezi metodu çağır
              TabService.instance.changeTab(i); 
            },
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.view_list_outlined),
                selectedIcon: Icon(Icons.view_list),
                label: 'Feed',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_search_outlined),
                selectedIcon: Icon(Icons.person_search),
                label: 'Cinephiles',
              ),
              NavigationDestination(
                icon: _MessagesIcon(),
                selectedIcon: _MessagesIcon(selected: true),
                label: 'Messages',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessagesIcon extends StatelessWidget {
  final bool selected;
  const _MessagesIcon({this.selected = false});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final baseIcon = Icon(
      selected ? Icons.chat_bubble : Icons.chat_bubble_outline,
    );

    return StreamBuilder<int>(
      stream: ChatService.instance.totalUnreadMessagesFor(uid), 
      builder: (context, snap) {
        final count = snap.data ?? 0;
        if (count <= 0) return baseIcon;
        return Badge.count(
          count: count > 9 ? 9 : count, 
          smallSize: 16,
          backgroundColor: Theme.of(context).colorScheme.primary,
          textColor: Colors.white,
          child: baseIcon,
        );
      },
    );
  }
}