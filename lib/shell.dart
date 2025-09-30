import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/feed_screens.dart';
import 'package:fluttergirdi/screens/match_screen.dart';

import 'package:fluttergirdi/screens/messagesscreen.dart';
import 'package:fluttergirdi/screens/profilescreen.dart';
import 'package:fluttergirdi/screens/search_profiles_screen.dart';
import 'package:fluttergirdi/services/chat_service.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  final Map<String, StreamSubscription<int>> _chatSubs = {};
  final Map<String, int> _chatCounts = {};

  final List<Widget> _pages = [
    const FeedPage(),
    const MatchListScreen(),
    const ProfilePage(),
    const MessagesPage(),
    const SearchProfilesScreen(),
  ];

  void _syncChatListeners(List<String> chatIds, String uid) {
    // Remove obsolete listeners
    final obsolete = _chatSubs.keys.where((k) => !chatIds.contains(k)).toList();
    for (final id in obsolete) {
      _chatSubs.remove(id)?.cancel();
      _chatCounts.remove(id);
    }
    // Add new listeners
    for (final id in chatIds) {
      if (_chatSubs.containsKey(id)) continue;
      final sub = ChatService.instance.unreadCountForChat(id, uid).listen((
        count,
      ) {
        if (!mounted) return;
        _chatCounts[id] = count;
        setState(() {}); // total will be recalculated in build
      });
      _chatSubs[id] = sub;
    }
  }

  @override
  void dispose() {
    for (final s in _chatSubs.values) {
      s.cancel();
    }
    _chatSubs.clear();
    _chatCounts.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return _scaffoldWithBadge(0);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: uid)
          .snapshots(),
      builder: (context, snap) {
        final ids = <String>[];
        if (snap.hasData) {
          for (final d in snap.data!.docs) {
            ids.add(d.id);
          }
        }
        // Sync listeners to current chat ids
        _syncChatListeners(ids, uid);

        // Sum latest counts coming from per-chat streams
        int total = 0;
        for (final v in _chatCounts.values) {
          total += (v is int) ? v : 0;
        }
        return _scaffoldWithBadge(total);
      },
    );
  }

  Widget _scaffoldWithBadge(int total) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
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
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
          NavigationDestination(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.chat_bubble_outline),
                if (total > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 14,
                      ),
                      child: Text(
                        total > 99 ? '99+' : total.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            selectedIcon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.chat_bubble),
                if (total > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.all(Radius.circular(999)),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 14,
                      ),
                      child: Text(
                        total > 99 ? '99+' : total.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            label: 'Messages',
          ),
          const NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Search',
          ),
        ],
      ),
    );
  }
}
