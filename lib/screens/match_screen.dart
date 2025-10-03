import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttergirdi/screens/settings_page.dart';
import 'dart:math' as math;
import 'package:fluttergirdi/services/match_service.dart'
    as global_match; // uses services/match_service.dart
import 'package:fluttergirdi/services/like_service.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:fluttergirdi/screens/likes_page.dart';
import 'package:fluttergirdi/screens/passes_page.dart';
import 'package:swipe_cards/swipe_cards.dart';

// Simple in-memory cache to persist match list within app session
class _MatchListSessionCache {
  static List<global_match.MatchResult>? results;
  static DateTime? ts;
}

/// Lists other users ordered by computed match score using `MatchService().findMatches(...)`.
class MatchListScreen extends StatefulWidget {
  const MatchListScreen({super.key});

  @override
  State<MatchListScreen> createState() => _MatchListScreenState();
}

class _MatchListScreenState extends State<MatchListScreen> {
  List<global_match.MatchResult> _all = const [];
  final List<SwipeItem> _swipeItems = [];
  late MatchEngine _matchEngine;
  bool _loading = true;
  // Persist scroll/child states across tab switches and route pops within this session
  static final PageStorageBucket _bucket = PageStorageBucket();

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _openIncomingLikes() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;
    final db = FirebaseFirestore.instance;

    List<_IncomingLike> items = [];

    try {
      // Query by participant only; filter client-side to avoid composite indexes
      final qa = await db.collection('likes').where('a', isEqualTo: me).get();
      final qb = await db.collection('likes').where('b', isEqualTo: me).get();

      void pushFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
        final m = d.data();
        final String a = (m['a'] ?? '') as String;
        final String b = (m['b'] ?? '') as String;
        if (a.isEmpty || b.isEmpty) return;
        final bool meIsA = a == me;
        // include only if OTHER side liked me
        final bool otherLiked = meIsA
            ? (m['bLiked'] == true)
            : (m['aLiked'] == true);
        if (!otherLiked) return;
        final otherUid = meIsA ? b : a;
        final wasUnseen = meIsA ? (m['aSeen'] != true) : (m['bSeen'] != true);
        final ts =
            (m['updatedAt'] as Timestamp?)?.toDate() ??
            (m['createdAt'] as Timestamp?)?.toDate() ??
            DateTime.fromMillisecondsSinceEpoch(0);
        items.add(
          _IncomingLike(
            docId: d.id,
            otherUid: otherUid,
            wasUnseen: wasUnseen,
            when: ts,
            seenField: meIsA ? 'aSeen' : 'bSeen',
          ),
        );
      }

      for (final d in qa.docs) pushFromDoc(d);
      for (final d in qb.docs) pushFromDoc(d);

      items.sort((a, b) => b.when.compareTo(a.when));

      // Mark only unseen as seen (best-effort)
      if (items.isNotEmpty) {
        final batch = db.batch();
        for (final it in items) {
          if (!it.wasUnseen) continue;
          batch.set(db.collection('likes').doc(it.docId), {
            it.seenField: true,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        try {
          await batch.commit();
        } catch (_) {}
      }
      try {
        await LikeService.instance.markIncomingLikesSeen(me);
      } catch (_) {}
    } catch (e) {
      debugPrint('incomingLikes error: $e');
      items = [];
    }

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.favorite_outline,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Beni beğenenler',
                        style: theme.textTheme.titleMedium,
                      ),
                      const Spacer(),
                      if (items.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${items.length}',
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: items.isEmpty
                      ? const Center(child: Text('Henüz beğeni yok'))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) =>
                              _IncomingLikeTile(item: items[i]),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadMatches() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      setState(() {
        _loading = false;
        _all = const [];
        _swipeItems.clear();
      });
      return;
    }

    // 1) If we have session cache, use it (no Firestore call)
    if (_MatchListSessionCache.results != null &&
        _MatchListSessionCache.results!.isNotEmpty) {
      _all = _MatchListSessionCache.results!;
      _swipeItems
        ..clear()
        ..addAll(
          _all.map(
            (m) => SwipeItem(
              content: m,
              likeAction: () async {
                await LikeService.instance.likeUser(
                  m.uid,
                  commonFavoritesCount: m.commonFavCount,
                  commonFiveStarsCount: m.commonFiveCount,
                );
                // switch to Likes tab
                DefaultTabController.of(context).animateTo(2);
              },
              nopeAction: () async {
                await LikeService.instance.passUser(m.uid);
                // switch to Passes tab
                DefaultTabController.of(context).animateTo(1);
              },
            ),
          ),
        );
      setState(() {
        _matchEngine = MatchEngine(swipeItems: _swipeItems);
        _loading = false;
      });
      return;
    }

    // 2) Otherwise fetch once and cache for the session
    try {
      final results = await global_match.MatchService().findMatches(me.uid);
      if (!mounted) return;

      _all = results;
      _MatchListSessionCache.results = results;
      _MatchListSessionCache.ts = DateTime.now();

      _swipeItems
        ..clear()
        ..addAll(
          _all.map(
            (m) => SwipeItem(
              content: m,
              likeAction: () async {
                await LikeService.instance.likeUser(
                  m.uid,
                  commonFavoritesCount: m.commonFavCount,
                  commonFiveStarsCount: m.commonFiveCount,
                );
                DefaultTabController.of(context).animateTo(2);
              },
              nopeAction: () async {
                await LikeService.instance.passUser(m.uid);
                DefaultTabController.of(context).animateTo(1);
              },
            ),
          ),
        );

      setState(() {
        _matchEngine = MatchEngine(swipeItems: _swipeItems);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _all = const [];
        _swipeItems.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Eşleşmeler alınamadı: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      return const Scaffold(
        body: Center(child: Text('Oturum açmanız gerekiyor')),
      );
    }

    return DefaultTabController(
      initialIndex: 1,
      length: 3,
      child: PageStorage(
        bucket: _bucket,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Eşleşmeler'),
            bottom: TabBar(
              tabs: [
                const Tab(text: 'Geçilenler'),
                const Tab(text: 'Eşleşmeler'),

                const Tab(text: 'Beğenilenler'),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Beni beğenenler',
                icon: const Icon(Icons.favorite_outline),
                onPressed: _openIncomingLikes,
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'settings') {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    );
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'settings',
                    child: ListTile(
                      leading: Icon(Icons.settings_outlined),
                      title: Text('Ayarlar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: TabBarView(
            physics: const NeverScrollableScrollPhysics(),
            children: [
              // --- Tab 2: Geçilenler ---
              const PassesListBody(),
              // --- Tab 1: mevcut eşleşme listesi ---
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : (_swipeItems.isEmpty
                        ? const Center(child: Text('Şu an eşleşme yok.'))
                        : Padding(
                            padding: const EdgeInsets.all(16),
                            child: SwipeCards(
                              matchEngine: _matchEngine,
                              // allow inner vertical scroll by disabling up-swipe capture
                              upSwipeAllowed: false,
                              fillSpace: true,
                              onStackFinished: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Hepsi bu kadar 👋'),
                                  ),
                                );
                              },
                              itemBuilder: (context, index) {
                                final m =
                                    _swipeItems[index].content
                                        as global_match.MatchResult;
                                return _MatchCard(
                                  key: ValueKey(m.uid),
                                  result: m,
                                  onOpen: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => MatchScreen(result: m),
                                      ),
                                    );
                                  },
                                  onLike: () {
                                    // Right swipe (LIKE): service is executed via SwipeItem.likeAction
                                    _matchEngine.currentItem?.like();
                                  },
                                  onPass: () {
                                    // Left swipe (PASS): service is executed via SwipeItem.nopeAction
                                    _matchEngine.currentItem?.nope();
                                  },
                                );
                              },
                            ),
                          )),

              // --- Tab 3: Beğenilenler ---
              const LikesListBody(),
            ],
          ),
        ),
      ),
    );
  }
}

class _MatchCard extends StatefulWidget {
  final global_match.MatchResult result;
  final VoidCallback onOpen;
  final VoidCallback onLike;
  final VoidCallback onPass;
  const _MatchCard({
    required this.result,
    required this.onOpen,
    required this.onLike,
    required this.onPass,
    super.key,
  });

  @override
  State<_MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends State<_MatchCard>
    with AutomaticKeepAliveClientMixin {
  late final Future<_CardData> _future; // cached once per card

  @override
  void initState() {
    super.initState();
    _future = _loadCardData(widget.result);
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // keep-alive
    final m = widget.result;
    final theme = Theme.of(context);
    final pct = m.score.clamp(0, 100).toStringAsFixed(1);
    final title = (m.displayName != null && m.displayName!.isNotEmpty)
        ? m.displayName!
        : (m.letterboxdUsername != null && m.letterboxdUsername!.isNotEmpty
              ? '@${m.letterboxdUsername}'
              : m.uid);

    return Card(
      key: PageStorageKey('match_card_${m.uid}'),
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: m.uid)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: FutureBuilder<_CardData>(
            future: _future,
            builder: (context, snap) {
              final cd = snap.data;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Scrollable content
                  Expanded(
                    child: SingleChildScrollView(
                      key: PageStorageKey('match_card_scroll_${m.uid}'),
                      padding: EdgeInsets.zero,
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header row
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 40,
                                backgroundImage:
                                    (m.photoURL != null &&
                                        m.photoURL!.isNotEmpty)
                                    ? NetworkImage(m.photoURL!)
                                    : null,
                                child:
                                    (m.photoURL == null || m.photoURL!.isEmpty)
                                    ? const Icon(Icons.person, size: 40)
                                    : null,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          _Pill(
                                            icon: Icons.percent,
                                            text: '%$pct uyum',
                                          ),
                                          _Pill(
                                            icon: Icons.star_rate_rounded,
                                            text:
                                                'Ortak 5★: ${m.commonFiveCount}',
                                          ),
                                          _Pill(
                                            icon: Icons.favorite_outline,
                                            text:
                                                'Ortak fav: ${m.commonFavCount}',
                                          ),
                                          if (m.commonWatchCount > 0)
                                            _Pill(
                                              icon: Icons.visibility_outlined,
                                              text:
                                                  'Ortak watchlist: ${m.commonWatchCount}',
                                            ),
                                          if (cd?.age != null)
                                            _Pill(
                                              icon: Icons.cake_outlined,
                                              text: 'Yaş: ${cd!.age}',
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Favorite genres / directors / actors chips (limited)
                          if (cd != null) ...[
                            if (cd.genres.isNotEmpty)
                              _ChipsRow(
                                label: 'Sevdiği Türler',
                                values: cd.genres.take(6).toList(),
                              ),
                            if (cd.directors.isNotEmpty)
                              _ChipsRow(
                                label: 'Sevdiği Yönetmenler',
                                values: cd.directors.take(4).toList(),
                              ),
                            if (cd.actors.isNotEmpty)
                              _ChipsRow(
                                label: 'Sevdiği Oyuncular',
                                values: cd.actors.take(4).toList(),
                              ),
                            const SizedBox(height: 8),
                          ] else ...[
                            const _SkeletonLine(),
                            const SizedBox(height: 8),
                          ],

                          // Common film posters preview (five★, favorites, watchlist)
                          if (cd != null &&
                              (cd.favPosters.isNotEmpty ||
                                  cd.fivePosters.isNotEmpty ||
                                  cd.watchPosters.isNotEmpty)) ...[
                            if (cd.fivePosters.isNotEmpty) ...[
                              const _SectionLabel(text: 'Ortak 5★ Filmler'),
                              const SizedBox(height: 8),
                              _PosterStrip(urls: cd.fivePosters),
                              const SizedBox(height: 12),
                            ],
                            if (cd.favPosters.isNotEmpty) ...[
                              const _SectionLabel(text: 'Ortak Favoriler'),
                              const SizedBox(height: 8),
                              _PosterStrip(urls: cd.favPosters),
                              const SizedBox(height: 12),
                            ],
                            if (cd.watchPosters.isNotEmpty) ...[
                              const _SectionLabel(text: 'Ortak Watchlist'),
                              const SizedBox(height: 8),
                              _PosterStrip(urls: cd.watchPosters),
                              const SizedBox(height: 12),
                            ],
                          ] else ...[
                            if (snap.connectionState == ConnectionState.waiting)
                              const _SkeletonPosters(),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Fixed bottom action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: widget.onPass,
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('Geç'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: widget.onLike,
                          icon: const Icon(Icons.favorite_rounded),
                          label: const Text('Beğen'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Pill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(text, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class FilmItem {
  final String title;
  final String posterUrl;
  const FilmItem({required this.title, required this.posterUrl});
}

/// Shows details for a single match, resolving posters/titles from `catalog_films/{filmKey}`.
class MatchScreen extends StatefulWidget {
  final global_match.MatchResult result;
  const MatchScreen({super.key, required this.result});

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen>
    with AutomaticKeepAliveClientMixin {
  late final Future<_Resolved> _future; // cache once per screen

  @override
  void initState() {
    super.initState();
    _future = _resolveCommonFilms(widget.result);
  }

  Future<void> _openIncomingLikes() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;
    final db = FirebaseFirestore.instance;

    List<_IncomingLike> items = [];

    try {
      // Query by participant only; filter client-side to avoid composite indexes
      final qa = await db.collection('likes').where('a', isEqualTo: me).get();
      final qb = await db.collection('likes').where('b', isEqualTo: me).get();

      void pushFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
        final m = d.data();
        final String a = (m['a'] ?? '') as String;
        final String b = (m['b'] ?? '') as String;
        if (a.isEmpty || b.isEmpty) return;
        final bool meIsA = a == me;
        // include only if OTHER side liked me
        final bool otherLiked = meIsA
            ? (m['bLiked'] == true)
            : (m['aLiked'] == true);
        if (!otherLiked) return;
        final otherUid = meIsA ? b : a;
        final wasUnseen = meIsA ? (m['aSeen'] != true) : (m['bSeen'] != true);
        final ts =
            (m['updatedAt'] as Timestamp?)?.toDate() ??
            (m['createdAt'] as Timestamp?)?.toDate() ??
            DateTime.fromMillisecondsSinceEpoch(0);
        items.add(
          _IncomingLike(
            docId: d.id,
            otherUid: otherUid,
            wasUnseen: wasUnseen,
            when: ts,
            seenField: meIsA ? 'aSeen' : 'bSeen',
          ),
        );
      }

      for (final d in qa.docs) pushFromDoc(d);
      for (final d in qb.docs) pushFromDoc(d);

      items.sort((a, b) => b.when.compareTo(a.when));

      // Mark only unseen as seen (best-effort)
      if (items.isNotEmpty) {
        final batch = db.batch();
        for (final it in items) {
          if (!it.wasUnseen) continue;
          batch.set(db.collection('likes').doc(it.docId), {
            it.seenField: true,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        try {
          await batch.commit();
        } catch (_) {}
      }
      try {
        await LikeService.instance.markIncomingLikesSeen(me);
      } catch (_) {}
    } catch (e) {
      debugPrint('incomingLikes error: $e');
      items = [];
    }

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.favorite_outline,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Beni beğenenler',
                        style: theme.textTheme.titleMedium,
                      ),
                      const Spacer(),
                      if (items.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${items.length}',
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: items.isEmpty
                      ? const Center(child: Text('Henüz beğeni yok'))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) =>
                              _IncomingLikeTile(item: items[i]),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Normalize possible nulls from MatchResult for new common fields
    final commonGenres = widget.result.commonGenres;
    final commonDirectors = widget.result.commonDirectors;
    final commonActors = widget.result.commonActors;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          (widget.result.displayName != null &&
                  widget.result.displayName!.isNotEmpty)
              ? widget.result.displayName!
              : (widget.result.letterboxdUsername != null &&
                        widget.result.letterboxdUsername!.isNotEmpty
                    ? '${widget.result.letterboxdUsername}'
                    : widget.result.uid),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        actions: [
          IconButton(
            tooltip: 'Beni beğenenler',
            icon: const Icon(Icons.favorite_outline),
            onPressed: _openIncomingLikes,
          ),
          IconButton(
            tooltip: 'Geç',
            icon: const Icon(Icons.close_rounded),
            onPressed: () async {
              try {
                await LikeService.instance.passUser(widget.result.uid);
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Geçildi')));
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Geç hatası: $e')));
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<_Resolved>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Detay yüklenemedi: ${snap.error}'));
          }
          final data = snap.data ?? const _Resolved();
          final pct = widget.result.score.clamp(0, 100).toStringAsFixed(1);

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        '%$pct uyum',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _StatChip(
                            label: 'Ortak 5★',
                            value: data.fiveStars.length,
                          ),
                          _StatChip(
                            label: 'Ortak favori',
                            value: data.favorites.length,
                          ),
                          _StatChip(
                            label: 'Ortak watchlist',
                            value: data.watchlist.length,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (commonGenres.isNotEmpty)
                        _ChipsRow(
                          label: 'Ortak Türler',
                          values: commonGenres.take(8).toList(),
                        ),
                      if (commonDirectors.isNotEmpty)
                        _ChipsRow(
                          label: 'Ortak Yönetmenler',
                          values: commonDirectors.take(6).toList(),
                        ),
                      if (commonActors.isNotEmpty)
                        _ChipsRow(
                          label: 'Ortak Oyuncular',
                          values: commonActors.take(6).toList(),
                        ),
                    ],
                  ),
                ),
              ),
              _SectionGrid(title: 'Ortak 5★', films: data.fiveStars),
              _SectionGrid(title: 'Ortak Favoriler', films: data.favorites),
              _SectionGrid(title: 'Ortak Watchlist', films: data.watchlist),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          try {
            await LikeService.instance.likeUser(
              widget.result.uid,
              commonFavoritesCount: widget.result.commonFavCount,
              commonFiveStarsCount: widget.result.commonFiveCount,
            );
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Beğenildi')));
          } catch (e) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Beğenme hatası: $e')));
          }
        },
        icon: const Icon(Icons.favorite_rounded),
        label: const Text('Beğen'),
      ),
    );
  }

  Future<_Resolved> _resolveCommonFilms(global_match.MatchResult m) async {
    final db = FirebaseFirestore.instance;

    Future<List<FilmItem>> readChunk(List<String> keys) async {
      if (keys.isEmpty) return const [];
      final items = <FilmItem>[];
      const chunkSize = 10; // Firestore whereIn max 10

      for (var i = 0; i < keys.length; i += chunkSize) {
        final chunk = keys.sublist(i, math.min(i + chunkSize, keys.length));
        final qs = await db
            .collection('catalog_films')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in qs.docs) {
          final d = doc.data();
          final t =
              (d['title'] ?? d['name'] ?? d['originalTitle'] ?? d['t'] ?? '')
                  as String;
          items.add(
            FilmItem(
              title: t.isNotEmpty ? t : 'İsimsiz',
              posterUrl:
                  (d['posterUrl'] ?? d['poster'] ?? d['image'] ?? '') as String,
            ),
          );
        }
      }
      return items;
    }

    // Fetch all three groups in parallel
    final favF = readChunk(m.commonFavorites);
    final fiveF = readChunk(m.commonFiveStars);
    final watchF = readChunk(m.commonWatchlist);

    final favs = await favF;
    final fives = await fiveF;
    final watch = await watchF;
    return _Resolved(favorites: favs, fiveStars: fives, watchlist: watch);
  }
}

class _IncomingLike {
  final String docId; // likes/{pairId} document id
  final String otherUid; // karşı tarafın uid'i
  final bool wasUnseen; // captured before we marked seen
  final DateTime when;
  final String seenField; // 'aSeen' or 'bSeen'
  _IncomingLike({
    required this.docId,
    required this.otherUid,
    required this.wasUnseen,
    required this.when,
    required this.seenField,
  });
}

class _IncomingLikeTile extends StatelessWidget {
  final _IncomingLike item;
  const _IncomingLikeTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = item.wasUnseen
        ? theme
              .colorScheme
              .primaryContainer // mavi ton (ilk kez görülen)
        : theme
              .colorScheme
              .surfaceContainerHighest; // gri ton (daha önce görülen)

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PublicProfileScreen(uid: item.otherUid),
          ),
        );
      },
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _IncomingAvatar(uid: item.otherUid),
            const SizedBox(width: 12),
            Expanded(child: _IncomingName(uid: item.otherUid)),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _IncomingAvatar extends StatelessWidget {
  final String uid;
  const _IncomingAvatar({required this.uid});
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snap) {
        String? url;
        if (snap.hasData && snap.data!.exists) {
          url = (snap.data!.data()!['photoURL'] ?? '') as String;
        }
        return CircleAvatar(
          radius: 20,
          backgroundImage: (url != null && url.isNotEmpty)
              ? NetworkImage(url)
              : null,
          child: (url == null || url.isEmpty) ? const Icon(Icons.person) : null,
        );
      },
    );
  }
}

class _IncomingName extends StatelessWidget {
  final String uid;
  const _IncomingName({required this.uid});
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snap) {
        String title = uid;
        if (snap.hasData && snap.data!.exists) {
          final u = snap.data!.data()!;
          final username = (u['username'] ?? '') as String;
          final lb = (u['letterboxdUsername'] ?? '') as String;
          if (username.isNotEmpty)
            title = username;
          else if (lb.isNotEmpty)
            title = '@$lb';
        }
        return Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      },
    );
  }
}

class _Resolved {
  final List<FilmItem> favorites;
  final List<FilmItem> fiveStars;
  final List<FilmItem> watchlist;
  const _Resolved({
    this.favorites = const [],
    this.fiveStars = const [],
    this.watchlist = const [],
  });
}

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  const _StatChip({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Chip(avatar: const Icon(Icons.movie), label: Text('$label: $value'));
  }
}

class _SectionGrid extends StatelessWidget {
  final String title;
  final List<FilmItem> films;
  const _SectionGrid({required this.title, required this.films});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (films.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(width: 8),
              Text('—', style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            _Grid(films: films),
          ],
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  final List<FilmItem> films;
  const _Grid({required this.films});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 110).floor().clamp(3, 6);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: films.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            // Space for a one-line caption under the poster (outside the image)
            childAspectRatio: 0.64,
          ),
          itemBuilder: (context, index) {
            final film = films[index];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 2 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      film.posterUrl,
                      fit: BoxFit.cover,
                      cacheWidth: 300, // ~2x of 150px width
                      filterQuality: FilterQuality.low,
                      errorBuilder: (_, __, ___) => Container(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        child: const Center(
                          child: Icon(Icons.image_not_supported),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    film.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Convenience entry screen
class MatchesEntry extends StatelessWidget {
  const MatchesEntry({super.key});
  @override
  Widget build(BuildContext context) => const MatchListScreen();
}

// --- CardData and helpers for match card preview ---

class _CardData {
  final int? age;
  final List<String> genres;
  final List<String> directors;
  final List<String> actors;
  final List<String> favPosters; // from commonFavorites
  final List<String> fivePosters; // from commonFiveStars
  final List<String> watchPosters; // from commonWatchlist
  const _CardData({
    this.age,
    this.genres = const [],
    this.directors = const [],
    this.actors = const [],
    this.favPosters = const [],
    this.fivePosters = const [],
    this.watchPosters = const [],
  });
}

Future<_CardData> _loadCardData(global_match.MatchResult m) async {
  final db = FirebaseFirestore.instance;

  // 1) Read profile prefs from users/{uid}
  final u = await db.collection('users').doc(m.uid).get();
  int? age;
  List<String> genres = const [];
  List<String> directors = const [];
  List<String> actors = const [];
  if (u.exists) {
    final d = u.data() ?? {};
    final a = d['age'];
    if (a is int) age = a; // nullable
    genres = List<String>.from(d['favGenres'] ?? const []);
    directors = List<String>.from(d['favDirectors'] ?? const []);
    actors = List<String>.from(d['favActors'] ?? const []);
  }

  // 2) Resolve a few poster URLs from catalog for common films
  Future<List<String>> readPosters(List<String> keys, {int limit = 8}) async {
    if (keys.isEmpty) return const [];
    final pick = keys.take(limit).toList();
    final posters = <String>[];
    const chunk = 10;
    for (var i = 0; i < pick.length; i += chunk) {
      final sub = pick.sublist(i, math.min(i + chunk, pick.length));
      // Try with documentId first
      final qs = await db
          .collection('catalog_films')
          .where(FieldPath.documentId, whereIn: sub)
          .get();
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = qs.docs;
      // Fallback: if no docs, try with 'key' field
      if (docs.isEmpty) {
        final altQs = await db
            .collection('catalog_films')
            .where('key', whereIn: sub)
            .get();
        docs = altQs.docs;
      }
      for (final doc in docs) {
        final d = doc.data();
        final p =
            (d['posterUrl'] ??
                    d['poster'] ??
                    d['image'] ??
                    d['poster_path'] ??
                    '')
                as String;
        if (p.isNotEmpty) posters.add(p);
      }
      // Optionally add debugPrint to aid diagnosis
      debugPrint(
        'readPosters: sub=${sub.length}, posters=${posters.length} (this chunk: ${docs.length})',
      );
    }
    return posters;
  }

  final favPosters = await readPosters(m.commonFavorites, limit: 8);
  final fivePosters = await readPosters(m.commonFiveStars, limit: 8);
  final watchPosters = await readPosters(m.commonWatchlist, limit: 8);

  return _CardData(
    age: age,
    genres: genres,
    directors: directors,
    actors: actors,
    favPosters: favPosters,
    fivePosters: fivePosters,
    watchPosters: watchPosters,
  );
}

class _ChipsRow extends StatelessWidget {
  final String label;
  final List<String> values;
  const _ChipsRow({required this.label, required this.values});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in values)
                  Chip(label: Text(v, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});
  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.bodyLarge);
  }
}

class _PosterStrip extends StatelessWidget {
  final List<String> urls;
  const _PosterStrip({required this.urls});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final u = urls[i];
          return AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                u,
                fit: BoxFit.cover,
                cacheWidth: 240, // ~120px * 2 devicePixelRatio
                filterQuality: FilterQuality.low,
                errorBuilder: (_, __, ___) => Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Center(child: Icon(Icons.image_not_supported)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 16,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _SkeletonPosters extends StatelessWidget {
  const _SkeletonPosters();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: Row(
        children: List.generate(
          4,
          (i) => Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == 3 ? 0 : 8),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
