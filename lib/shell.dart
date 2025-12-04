import 'dart:async'; // StreamSubscription için gerekli
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:app_links/app_links.dart'; // <-- Deep Link paketi
import 'package:fluttergirdi/services/chat_service.dart';
import 'package:fluttergirdi/screens/feed_screens.dart';
import 'package:fluttergirdi/screens/match_screen.dart';
import 'package:fluttergirdi/screens/messagesscreen.dart';
import 'package:fluttergirdi/screens/profilescreen.dart';
import 'package:fluttergirdi/services/announcement_service.dart';
import 'package:fluttergirdi/screens/post_detail_screen.dart'; // <-- Detay sayfası

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  late final AppLinks _appLinks; // <-- Link yakalayıcı
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    
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
    super.dispose();
  }

  // Linkleri dinleyen fonksiyon
  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // 1. Uygulama kapalıyken linke tıklandıysa (Cold Start)
    try {
      final Uri? initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    } catch (e) {
      debugPrint('Link hatası: $e');
    }

    // 2. Uygulama arkaplandayken linke tıklandıysa (Background/Foreground)
    _linkSubscription = _appLinks.uriLinkStream.listen((Uri? uri) {
      if (uri != null) {
        _handleDeepLink(uri);
      }
    });
  }

  // Linki analiz edip sayfayı açan fonksiyon
  void _handleDeepLink(Uri uri) {
    // Link formatı: cinematch://app/post?id=POST_ID
    // Veya: https://cinematch.web.app/post?id=POST_ID
    if (uri.path.contains('/post')) {
      final String? postId = uri.queryParameters['id'];
      
      if (postId != null && mounted) {
        debugPrint("Link yakalandı! Post ID: $postId");
        
        // İlgili posta git
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
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: _buildBottomBar(context),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.14),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
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
                color: selected ? cs.primary : cs.onSurfaceVariant,
              );
            }),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final selected = states.contains(WidgetState.selected);
              return TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              );
            }),
          ),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.view_list_outlined),
                selectedIcon: Icon(Icons.view_list),
                label: 'Feed',
              ),
              const NavigationDestination(
                icon: Icon(Icons.favorite_border),
                selectedIcon: Icon(Icons.favorite),
                label: 'Match',
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