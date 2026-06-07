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
import 'package:fluttergirdi/services/tab_service.dart'; // EKLENDİ: TabService Importu

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0; // Sizin değişkeniniz bu
  late final AppLinks _appLinks; 
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    
    // --- TAB SERVICE DİNLEYİCİSİ (EKLENDİ) ---
    // Drawer'dan veya başka yerden sekme değiştirme isteği gelirse burası çalışır
    TabService.instance.indexNotifier.addListener(() {
      if (mounted) {
        final newIndex = TabService.instance.indexNotifier.value;
        setState(() {
          _index = newIndex; // DÜZELTME: _selectedIndex yerine _index kullanıldı
        });
      }
    });

    // Duyuru kontrolü
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AnnouncementService.instance.checkAndShowAnnouncement(context);
    });

    // --- DEEP LINK BAŞLATMA ---
    _initDeepLinks();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    // TabService dinleyicisini kaldırmaya gerek yok çünkü singleton, 
    // ama best practice olarak dispose edilebilir. Şimdilik gerek yok.
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

  final List<Widget> _pages = [
    const FeedPage(),
    const MatchListScreen(),
    const MessagesPage(),
    const ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    // PopScope: Telefonun fiziksel geri tuşunu dinler ve kontrol eder
    return PopScope(
      // Sadece Feed sekmesindeyken (index == 0) uygulamadan çıkışa izin ver
      canPop: _index == 0, 
      onPopInvokedWithResult: (bool didPop, Object? result) {
        // Eğer sistem zaten geri gittiyse (uygulamadan çıktıysa) hiçbir şey yapma
        if (didPop) {
          return;
        }
        
        // Eğer Feed (Ana) ekranda değilsek, çıkmak yerine Feed ekranına dön
        if (_index != 0) {
          setState(() {
            _index = 0;
          });
          TabService.instance.changeTab(0); 
        }
      },
      child: Scaffold( 
        extendBody: true,
        body: IndexedStack(index: _index, children: _pages),
        bottomNavigationBar: _buildBottomBar(context),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6), // Saydamlık için opacity ayarı
        boxShadow: const [], 
      ),
      child: SafeArea(
        top: false, 
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            height: 52,
            backgroundColor: Colors.transparent, // Arka planı saydam yap
            indicatorColor: cs.primary.withOpacity(0.14),
            indicatorShape: const StadiumBorder(),
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            iconTheme: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return IconThemeData(
                size: 20,
                color: selected ?const Color.fromARGB(253, 97, 202, 101)  : Colors.white70,
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
              setState(() => _index = i);
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