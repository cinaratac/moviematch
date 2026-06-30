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
import 'package:fluttergirdi/screens/news_detail_page.dart';
import 'package:fluttergirdi/screens/news_list_page.dart';
import 'package:fluttergirdi/screens/post_detail_screen.dart';
import 'package:fluttergirdi/services/tab_service.dart';
import 'package:fluttergirdi/services/global_data_service.dart';
import 'package:fluttergirdi/services/notification_service.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  Timer? _smartLoadingTimer;

  final List<Widget> _pages = [
    const FeedPage(),
    const MatchListScreen(),
    const MessagesPage(),
    const ProfilePage(),
  ];

  // Sadece Feed açık başlar, diğerleri akıllı sistemle yüklenecek.
  final List<bool> _loadedPages = [true, false, false, false];

  @override
  void initState() {
    super.initState();

    TabService.instance.indexNotifier.addListener(_onTabServiceIndexChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      AnnouncementService.instance.checkAndShowAnnouncement(context);
      GlobalDataService.instance.startPreloading();
      NotificationService.I.flushPendingNavigation();
      _startSmartLoading();
    });

    _initDeepLinks();

    // Uygulama açıldıktan sonra akıllı yüklemeyi başlat
  }

  void _onTabServiceIndexChanged() {
    if (mounted) {
      final newIndex = TabService.instance.indexNotifier.value;
      if (_index != newIndex) {
        _switchToTab(newIndex);
      }
    }
  }

  void _switchToTab(int targetIndex) {
    if (_index == targetIndex) return;

    // Geçiş yapılırken anlık duraksamayı önlemek için timer'ı sıfırla

    setState(() {
      _index = targetIndex;
      _loadedPages[targetIndex] = true;
    });

    // Sekme geçişi bitince arka plan yüklemelerine kaldığı yerden devam et
  }

  // --- İŞTE SİHİRLİ KISIM (AKILLI YÜKLEME) ---
  void _startSmartLoading() {
    // Feed (0) zaten yüklü. Diğer sekmeleri aralarına yarım saniye
    // koyarak arka planda yüklüyoruz. Hepsini aynı anda yüklemek
    // uygulamanın ilk açılışta kasmasına sebep olur.

    _smartLoadingTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && !_loadedPages[3]) {
        setState(() => _loadedPages[3] = true); // 1. Öncelik: Profil Sayfası
      }

      _smartLoadingTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted && !_loadedPages[2]) {
          setState(() => _loadedPages[2] = true); // 2. Öncelik: Mesajlar
        }

        _smartLoadingTimer = Timer(const Duration(milliseconds: 500), () {
          if (mounted && !_loadedPages[1]) {
            setState(() => _loadedPages[1] = true); // 3. Öncelik: Cinephiles
          }
        });
      });
    });
  }

  @override
  void dispose() {
    _smartLoadingTimer?.cancel();
    _linkSubscription?.cancel();
    TabService.instance.indexNotifier.removeListener(_onTabServiceIndexChanged);
    super.dispose();
  }

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
    final path = uri.path.toLowerCase();

    if (path.contains('/news-detail')) {
      final String? articleId = uri.queryParameters['id'];

      if (articleId != null && articleId.isNotEmpty && mounted) {
        debugPrint("Haber linki yakalandı! Article ID: $articleId");
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => NewsDetailPage(articleId: articleId),
          ),
        );
      }
      return;
    }

    if (path.contains('/news')) {
      if (mounted) {
        debugPrint("Haber listesi linki yakalandı!");
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const NewsListPage()));
      }
      return;
    }

    if (path.contains('/post')) {
      final String? postId = uri.queryParameters['id'];

      if (postId != null && mounted) {
        debugPrint("Link yakalandı! Post ID: $postId");
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PostDetailScreen(postId: postId)),
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
            return _loadedPages[index]
                ? _pages[index]
                : const SizedBox.shrink();
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
        color: Colors.black.withValues(alpha: 0.6),
        boxShadow: const [],
      ),
      child: SafeArea(
        top: false,
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            height: 52,
            backgroundColor: Colors.transparent,
            indicatorColor: cs.primary.withValues(alpha: 0.14),
            indicatorShape: const StadiumBorder(),
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            iconTheme: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return IconThemeData(
                size: 20,
                color: selected
                    ? const Color.fromARGB(253, 97, 202, 101)
                    : Colors.white70,
              );
            }),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected
                    ? const Color.fromARGB(253, 97, 202, 101)
                    : Colors.white70,
              );
            }),
          ),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) {
              _switchToTab(i);
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
