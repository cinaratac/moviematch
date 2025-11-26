import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttergirdi/screens/settings_page.dart';
import 'dart:math' as math;
import 'package:fluttergirdi/services/match_service.dart'
    as global_match; // services/match_service.dart kullanılıyor
import 'package:fluttergirdi/services/like_service.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:fluttergirdi/screens/likes_page.dart';
import 'package:fluttergirdi/screens/passes_page.dart';
import 'package:swipe_cards/swipe_cards.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';
import 'package:fluttergirdi/widgets/green_characters.dart';

// Simple in-memory cache to persist match list within app session
class _MatchListSessionCache {
  static List<global_match.MatchResult>? results;
  static DateTime? ts;
}

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
  bool _finished = false;
  static final PageStorageBucket _bucket = PageStorageBucket();

  // 1. Karakterin görünürlüğünü yönetecek Notifier
  final ValueNotifier<bool> _showGuideNotifier = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  @override
  void dispose() {
    _showGuideNotifier.dispose(); // Bellek sızıntısını önlemek için dispose ediyoruz
    super.dispose();
  }

  Future<void> _loadMatches() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    // 1) Cache kontrolü
    if (_MatchListSessionCache.results != null &&
        _MatchListSessionCache.results!.isNotEmpty) {
      _all = _MatchListSessionCache.results!;
      _buildSwipeItems();
      if (mounted) {
        setState(() {
          _matchEngine = MatchEngine(swipeItems: _swipeItems);
          _loading = false;
        });
      }
      return;
    }

    // 2) Servisten çekme
    try {
      final results =
          await global_match.MatchService.instance.findMatches(me.uid);
      if (!mounted) return;

      _all = results;
      _MatchListSessionCache.results = results;
      _MatchListSessionCache.ts = DateTime.now();

      _buildSwipeItems();

      setState(() {
        _matchEngine = MatchEngine(swipeItems: _swipeItems);
        _loading = false;
      });

      // EĞER LİSTE BOŞSA KARAKTERİ TETİKLE
      if (_swipeItems.isEmpty) {
        // Küçük bir gecikme ekleyerek sayfa geçişinin bitmesini bekleyelim
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _showGuideNotifier.value = true;
        });
      }

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _all = const [];
      });
      // Hata durumunda da liste boş kalacağı için karakteri gösterebiliriz
      Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _showGuideNotifier.value = true;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Eşleşmeler alınamadı: $e')));
    }
  }
  // [YENİ] Kart kaydırılınca o kişiyi hafızadan silen fonksiyon
  void _removeUserFromLocalCache(String otherUid) {
    // 1. Ekrandaki geçici listeden sil (Hot Reload yapınca gelmesin diye)
    if (_MatchListSessionCache.results != null) {
      _MatchListSessionCache.results!.removeWhere((m) => m.uid == otherUid);
    }
    
    // 2. Arka plandaki Servis Cache'inden sil (5 dk süresi dolmadan gelmesin diye)
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me != null) {
      global_match.MatchService.instance.removeUserFromCache(me, otherUid);
    }
  }

  void _buildSwipeItems() {
    _swipeItems.clear();
    for (final m in _all) {
      _swipeItems.add(SwipeItem(
        content: m,
        likeAction: () async {
          // Firebase'e gönder
          await LikeService.instance.likeUser(
            m.uid,
            commonFavoritesCount: m.commonFavCount,
            commonFiveStarsCount: m.commonFiveCount,
          );
          // [GÜNCELLEME] Hafızadan sil
          _removeUserFromLocalCache(m.uid);
        },
        nopeAction: () async {
          // Firebase'e gönder
          await LikeService.instance.passUser(m.uid);
          // [GÜNCELLEME] Hafızadan sil
          _removeUserFromLocalCache(m.uid);
        },
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      return const Scaffold(
          body: Center(child: Text('Oturum açmanız gerekiyor')));
    }

    return DefaultTabController(
      initialIndex: 1,
      length: 3,
      child: PageStorage(
        bucket: _bucket,
        child: Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          appBar: AppBar(
            title: const Text('Matchs',
                style: TextStyle(fontWeight: FontWeight.bold)),
            centerTitle: true,
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Geçilenler'),
                Tab(text: 'Eşleşmeler'),
                Tab(text: 'Beğenilenler'),
              ],
            ),
            actions: [
              _LikesIndicatorHeart(onPressed: _openIncomingLikes),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  );
                },
              ),
            ],
          ),
          // BURASI GÜNCELLENDİ: TabBarView Stack içine alındı
          body: Stack(
            children: [
              // 1. KATMAN: Tab İçerikleri
              TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  // --- Tab 1: Geçilenler ---
                  const PassesListBody(),

                  // --- Tab 2: Eşleşme Kartları ---
                  _loading
                      ? const Center(child: CircularProgressIndicator())
                      : (_swipeItems.isEmpty || _finished
                          ? const _NoMatchesCharacter()
                          : Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 16, 16, 24),
                              child: SwipeCards(
                                matchEngine: _matchEngine,
                                itemBuilder: (context, index) {
                                  final m = _swipeItems[index].content
                                      as global_match.MatchResult;
                                  return _MatchCard(
                                    key: ValueKey(m.uid),
                                    result: m,
                                    onOpen: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              MatchScreen(result: m),
                                        ),
                                      );
                                    },
                                    onLike: () {
                                      _matchEngine.currentItem?.like();
                                    },
                                    onPass: () {
                                      _matchEngine.currentItem?.nope();
                                    },
                                  );
                                },
                                onStackFinished: () {
                                  setState(() => _finished = true);
                                  // KARTLAR BİTİNCE KARAKTERİ TETİKLE
                                  _showGuideNotifier.value = true;
                                },
                                upSwipeAllowed: false,
                                fillSpace: true,
                              ),
                            )),

                  // --- Tab 3: Beğenilenler ---
                  const LikesListBody(),
                ],
              ),

              // 2. KATMAN: REHBER KARAKTER
              ValueListenableBuilder<bool>(
                valueListenable: _showGuideNotifier,
                builder: (context, isVisible, child) {
                  if (!isVisible) return const SizedBox.shrink();

                  return GuideCharacterOverlay(
                    message: "Daha fazla film izlemelisin",
                    isVisible: isVisible,
                    onClose: () {
                      _showGuideNotifier.value = false;
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openIncomingLikes() async {
    // (Orijinal incoming likes logic'i korundu)
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;
    final db = FirebaseFirestore.instance;
    List<_IncomingLike> items = [];
    try {
      final qa = await db.collection('likes').where('a', isEqualTo: me).get();
      final qb = await db.collection('likes').where('b', isEqualTo: me).get();

      void pushFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
        final m = d.data();
        final String a = (m['a'] ?? '') as String;
        final String b = (m['b'] ?? '') as String;
        if (a.isEmpty || b.isEmpty) return;
        final bool meIsA = a == me;
        final bool otherLiked =
            meIsA ? (m['bLiked'] == true) : (m['aLiked'] == true);
        if (!otherLiked) return;
        final otherUid = meIsA ? b : a;
        final wasUnseen = meIsA ? (m['aSeen'] != true) : (m['bSeen'] != true);
        final ts = (m['updatedAt'] as Timestamp?)?.toDate() ??
            (m['createdAt'] as Timestamp?)?.toDate() ??
            DateTime.fromMillisecondsSinceEpoch(0);
        items.add(_IncomingLike(
          docId: d.id,
          otherUid: otherUid,
          wasUnseen: wasUnseen,
          when: ts,
          seenField: meIsA ? 'aSeen' : 'bSeen',
        ));
      }

      for (final d in qa.docs) pushFromDoc(d);
      for (final d in qb.docs) pushFromDoc(d);
      items.sort((a, b) => b.when.compareTo(a.when));

      // Mark seen logic...
      if (items.isNotEmpty) {
        final batch = db.batch();
        for (final it in items) {
          if (!it.wasUnseen) continue;
          batch.set(
              db.collection('likes').doc(it.docId),
              {it.seenField: true, 'updatedAt': FieldValue.serverTimestamp()},
              SetOptions(merge: true));
        }
        await batch.commit();
      }
      LikeService.instance.markIncomingLikesSeen(me);
    } catch (_) {}

    if (!mounted) return;
    // Bottom Sheet UI
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => _IncomingLikesSheet(items: items));
  }
}

// --- Modern Match Card ---

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
  late final Future<_CardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadCardData(widget.result);
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final m = widget.result;
    final theme = Theme.of(context);
    final pct = m.score.clamp(0, 100).toStringAsFixed(0);

    final title = (m.displayName != null && m.displayName!.isNotEmpty)
        ? m.displayName!
        : (m.letterboxdUsername != null ? '@${m.letterboxdUsername}' : 'Kullanıcı');

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow, // Flutter 3.22+
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Content Scroll
          Positioned.fill(
            bottom: 80, // Space for buttons
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header: Photo & Name
                  Row(
  children: [
    // Fotoğraf ve İsim/Skor alanını tıklanabilir Expanded widget'ı ile sarıyoruz.
    Expanded( 
      child: InkWell(
        borderRadius: BorderRadius.circular(50), 
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              // Hedef: PublicProfileScreen(uid)
              builder: (_) => PublicProfileScreen(uid: m.uid),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0), // Tıklama alanını rahatlatmak için
          child: Row(
            children: [
              // Fotoğraf (Original Container)
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.colorScheme.primary, width: 2),
                  image: (m.photoURL != null && m.photoURL!.isNotEmpty)
                      ? DecorationImage(
                          image: NetworkImage(m.photoURL!),
                          fit: BoxFit.cover)
                      : null,
                ),
                child: (m.photoURL == null || m.photoURL!.isEmpty)
                    ? Icon(Icons.person, size: 40, color: theme.primaryColor)
                    : null,
              ),
              const SizedBox(width: 16),
              // İsim & Skor (Original Expanded Column)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold, fontSize: 22)),
                    const SizedBox(height: 4),
                    // Score Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '%$pct Uyum',
                        style: TextStyle(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold),
                      ),
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    // Detay butonu (Original IconButton) - Tıklanabilir alan dışında kalır.
    IconButton(
        onPressed: widget.onOpen,
        icon: const Icon(Icons.info_outline_rounded))
  ],
),
                  const SizedBox(height: 24),

                  // Stats Row
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        if (m.commonFiveCount > 0)
                          _StatBox(
                              icon: Icons.star_rounded,
                              val: '${m.commonFiveCount}',
                              label: '5★',
                              color: Colors.amber),
                        if (m.commonFavCount > 0)
                          _StatBox(
                              icon: Icons.favorite_rounded,
                              val: '${m.commonFavCount}',
                              label: 'Fav',
                              color: Colors.redAccent),
                        if (m.commonWatchCount > 0)
                          _StatBox(
                              icon: Icons.visibility_rounded,
                              val: '${m.commonWatchCount}',
                              label: 'Watch',
                              color: Colors.blueAccent),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Async Data: Genres & Posters
                  // Async Data: Genres & Posters
                  FutureBuilder<_CardData>(
                    future: _future,
                    builder: (context, snap) {
                      final cd = snap.data;
                      // Loading state for content
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const _SkeletonContent();
                      }
                      
                      final commonGenres = m.commonGenres;
                      final commonDirectors = m.commonDirectors;
                      // Veri var mı ve film listesi dolu mu kontrolü
                      final hasFilms = cd != null && cd.allFilms.isNotEmpty;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Common Genres / Directors
                          if (commonGenres.isNotEmpty || commonDirectors.isNotEmpty) ...[
                             Text('ORTAK ZEVKLER', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, color: theme.hintColor)),
                             const SizedBox(height: 8),
                             Wrap(
                               spacing: 8,
                               runSpacing: 8,
                               children: [
                                 ...commonGenres.take(4).map((g) => Chip(
                                   label: Text(g), 
                                   visualDensity: VisualDensity.compact,
                                   backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                   side: BorderSide.none,
                                 )),
                                 ...commonDirectors.take(2).map((d) => Chip(
                                   label: Text(d), 
                                   avatar: const Icon(Icons.movie_creation_outlined, size: 14),
                                   visualDensity: VisualDensity.compact,
                                   side: BorderSide.none,
                                 ))
                               ],
                             ),
                             const SizedBox(height: 20),
                          ],

                          // Posters
                          if (hasFilms) ...[
                            Text('ORTAK FİLMLER', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, color: theme.hintColor)),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 140,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: cd!.allFilms.length, // allPosters yerine allFilms
                                separatorBuilder: (_, __) => const SizedBox(width: 10),
                                itemBuilder: (ctx, i) {
                                  final film = cd.allFilms[i]; // Film objesini al
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: AspectRatio(
                                      aspectRatio: 2 / 3,
                                      child: PosterImage(
                                        posterUrl: film.posterUrl,
                                        title: film.title, // Title parametresi eklendi
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            )
                          ] else ...[
                            // Eğer film yoksa gösterilecek kutu (Spread operatörü ile listeye eklendi)
                            Container(
                               padding: const EdgeInsets.all(16),
                               width: double.infinity,
                               decoration: BoxDecoration(
                                 color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                                 borderRadius: BorderRadius.circular(12)
                               ),
                               child: const Text('Ortak film detayı yükleniyor veya yok...', textAlign: TextAlign.center, style: TextStyle(fontSize: 12))
                            )
                          ]
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Fixed Bottom Buttons
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: widget.onPass,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                        side: BorderSide(color: theme.colorScheme.error, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                      ),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Pas'),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: widget.onLike,
                       style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 4,
                        shadowColor: theme.colorScheme.primary.withOpacity(0.4),
                      ),
                      icon: const Icon(Icons.favorite_rounded),
                      label: const Text('Beğen'),
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final IconData icon;
  final String val;
  final String label;
  final Color color;
  const _StatBox(
      {required this.icon,
      required this.val,
      required this.label,
      required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(val, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(fontSize: 10, color: theme.hintColor)),
        ],
      ),
    );
  }
}

class _SkeletonContent extends StatelessWidget {
  const _SkeletonContent();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(width: 100, height: 12, color: Colors.black12),
        const SizedBox(height: 8),
        Container(width: double.infinity, height: 30, color: Colors.black12),
        const SizedBox(height: 20),
        Container(width: 100, height: 12, color: Colors.black12),
        const SizedBox(height: 8),
        Row(
          children: List.generate(3, (i) => Container(
            width: 80, height: 120, 
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(8)
            ),
          )),
        )
      ],
    );
  }
}

// --- Detail Screen (Common Films Grid) ---

class MatchScreen extends StatefulWidget {
  final global_match.MatchResult result;
  const MatchScreen({super.key, required this.result});

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  late final Future<_Resolved> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolveCommonFilms(widget.result);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.result;
    final pct = m.score.clamp(0, 100).toStringAsFixed(0);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 140,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(m.displayName ?? 'Kullanıcı'),
              centerTitle: false,
              titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
            ),
            actions: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: Text(
                    '%$pct', 
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)
                  ),
                ),
              )
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Semantic Tags
                  if (m.commonGenres.isNotEmpty)
                    _ChipsSection(label: 'Ortak Türler', values: m.commonGenres),
                  if (m.commonDirectors.isNotEmpty)
                    _ChipsSection(label: 'Ortak Yönetmenler', values: m.commonDirectors),
                  if (m.commonActors.isNotEmpty)
                    _ChipsSection(label: 'Ortak Oyuncular', values: m.commonActors),
                ],
              ),
            ),
          ),
          
          FutureBuilder<_Resolved>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const SliverFillRemaining(child: Center(child: CircularProgressIndicator()));
              }
              final data = snap.data ?? const _Resolved();
              return SliverList(delegate: SliverChildListDelegate([
                if(data.fiveStars.isNotEmpty) _SectionGrid(title: 'Ortak 5 Yıldız', films: data.fiveStars),
                if(data.favorites.isNotEmpty) _SectionGrid(title: 'Ortak Favoriler', films: data.favorites),
                if(data.watchlist.isNotEmpty) _SectionGrid(title: 'Ortak İzleme Listesi', films: data.watchlist),
                const SizedBox(height: 40),
              ]));
            },
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await LikeService.instance.likeUser(m.uid, commonFavoritesCount: m.commonFavCount, commonFiveStarsCount: m.commonFiveCount);
          if(mounted) Navigator.pop(context);
        },
        icon: const Icon(Icons.favorite),
        label: const Text('Beğen'),
      ),
    );
  }
}

class _ChipsSection extends StatelessWidget {
  final String label;
  final List<String> values;
  const _ChipsSection({required this.label, required this.values});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: values.map((v) => Chip(label: Text(v), visualDensity: VisualDensity.compact)).toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// --- Helper Classes & Functions ---

class FilmItem {
  final String title;
  final String posterUrl;
  const FilmItem({required this.title, required this.posterUrl});
}

class _Resolved {
  final List<FilmItem> favorites;
  final List<FilmItem> fiveStars;
  final List<FilmItem> watchlist;
  const _Resolved({this.favorites = const [], this.fiveStars = const [], this.watchlist = const []});
}

Future<_Resolved> _resolveCommonFilms(global_match.MatchResult m) async {
  final db = FirebaseFirestore.instance;
  
  // Robust Fetcher
  Future<List<FilmItem>> readChunk(List<String> keys) async {
    if (keys.isEmpty) return const [];
    final cleanKeys = keys.where((k) => k.trim().isNotEmpty).toList();
    if (cleanKeys.isEmpty) return const [];
    
    final items = <FilmItem>[];
    const chunkSize = 10;
    
    for (var i = 0; i < cleanKeys.length; i += chunkSize) {
      final chunk = cleanKeys.sublist(i, math.min(i + chunkSize, cleanKeys.length));
      
      // 1. Try by Doc ID
      var qs = await db.collection('catalog_films').where(FieldPath.documentId, whereIn: chunk).get();
      
      // 2. Fallback by 'key' field
      if (qs.docs.isEmpty) {
        qs = await db.collection('catalog_films').where('key', whereIn: chunk).get();
      }

      for (final doc in qs.docs) {
        final d = doc.data();
        final t = (d['title'] ?? d['name'] ?? '').toString();
        final p = (d['posterUrl'] ?? d['poster'] ?? d['poster_path'] ?? '').toString();
        items.add(FilmItem(title: t.isNotEmpty ? t : 'İsimsiz', posterUrl: p));
      }
    }
    return items;
  }

  final favF = readChunk(m.commonFavorites);
  final fiveF = readChunk(m.commonFiveStars);
  final watchF = readChunk(m.commonWatchlist);

  return _Resolved(
    favorites: await favF,
    fiveStars: await fiveF,
    watchlist: await watchF,
  );
}

// --- Card Data Fetcher for Swipe Card Preview ---

// --- GÜNCELLENMİŞ VERSİYON ---

class _CardData {
  // Artık sadece String listesi değil, FilmItem listesi tutuyoruz (Title + Poster)
  final List<FilmItem> allFilms; 
  const _CardData({this.allFilms = const []});
}

Future<_CardData> _loadCardData(global_match.MatchResult m) async {
  final db = FirebaseFirestore.instance;
  
  // Öncelik sırası: 5 yıldız -> favoriler -> watchlist
  final allKeys = <String>{
    ...m.commonFiveStars.take(4),
    ...m.commonFavorites.take(4),
    ...m.commonWatchlist.take(2)
  }.take(6).toList(); 

  if(allKeys.isEmpty) return const _CardData();

  final films = <FilmItem>[];
  
  try {
     // Doc ID ile ara
     var qs = await db.collection('catalog_films').where(FieldPath.documentId, whereIn: allKeys).get();
     
     // Bulamazsa 'key' alanı ile ara (Yedek)
     if (qs.docs.isEmpty) {
       qs = await db.collection('catalog_films').where('key', whereIn: allKeys).get();
     }

     for(final d in qs.docs) {
       final data = d.data();
       final p = (data['posterUrl'] ?? data['poster'] ?? '').toString();
       final t = (data['title'] ?? data['name'] ?? '').toString(); // Title'ı da alıyoruz!
       
       // Poster boş olsa bile listeye ekle, çünkü PosterImage widget'ı title ile bulacak.
       if (t.isNotEmpty) {
         films.add(FilmItem(title: t, posterUrl: p));
       }
     }
  } catch(_) {}

  return _CardData(allFilms: films);
}

// --- Components for Incoming Likes Bottom Sheet ---

class _IncomingLikesSheet extends StatelessWidget {
  final List<_IncomingLike> items;
  const _IncomingLikesSheet({required this.items});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Beni Beğenenler', style: Theme.of(context).textTheme.titleMedium),
            ),
            Expanded(
               child: items.isEmpty 
                 ? const Center(child: Text('Henüz kimse yok'))
                 : ListView.separated(
                     itemCount: items.length,
                     separatorBuilder: (_,__) => const Divider(height: 1),
                     itemBuilder: (ctx, i) => _IncomingLikeTile(item: items[i]),
                   ),
            )
          ],
        ),
      ),
    );
  }
}

class _IncomingLike {
  final String docId;
  final String otherUid;
  final bool wasUnseen;
  final DateTime when;
  final String seenField;
  _IncomingLike({required this.docId, required this.otherUid, required this.wasUnseen, required this.when, required this.seenField});
}

class _IncomingLikeTile extends StatelessWidget {
  final _IncomingLike item;
  const _IncomingLikeTile({required this.item});

  @override
  Widget build(BuildContext context) {
    // UID yerine gerçek kullanıcı verisini çekiyoruz
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(item.otherUid).get(),
      builder: (context, snapshot) {
        // Veri yüklenirken basit bir görünüm
        if (!snapshot.hasData) {
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person, color: Colors.grey)),
            title: Text('Yükleniyor...', style: TextStyle(color: Colors.grey[600])),
          );
        }

        final data = snapshot.data!.data();
        final name = data?['displayName'] ?? data?['username'] ?? 'Kullanıcı';
        final photo = data?['photoURL'] as String?;
        final lbUsername = data?['letterboxdUsername'] as String?;
        
        // Eğer isim yoksa Letterboxd adını, o da yoksa 'Kullanıcı'yı göster
        final displayName = (name != null && name.isNotEmpty) 
            ? name 
            : (lbUsername != null ? '@$lbUsername' : 'Kullanıcı');

        return ListTile(
          tileColor: item.wasUnseen 
              ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.2) 
              : null,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade300),
              image: (photo != null && photo.isNotEmpty)
                  ? DecorationImage(image: NetworkImage(photo), fit: BoxFit.cover)
                  : null,
            ),
            child: (photo == null || photo.isEmpty)
                ? const Icon(Icons.person, size: 20)
                : null,
          ),
          title: Text(displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            _formatDate(item.when),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
          onTap: () {
            Navigator.push(
              context, 
              MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: item.otherUid))
            );
          },
        );
      },
    );
  }

  // Tarihi daha okunaklı gösteren yardımcı metod
  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    
    if (diff.inMinutes < 60) return '${diff.inMinutes}dk önce';
    if (diff.inHours < 24) return '${diff.inHours}sa önce';
    return '${d.day}.${d.month}.${d.year}';
  }
}

// --- Empty State & Indicator ---

class _NoMatchesCharacter extends StatelessWidget {
  const _NoMatchesCharacter();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.theater_comedy_rounded, size: 100, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text('Şimdilik bu kadar!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Text('Daha fazla ortak zevk için filmlerini puanla.', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

class _LikesIndicatorHeart extends StatelessWidget {
  final VoidCallback onPressed;
  const _LikesIndicatorHeart({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    // LikeService üzerinden okunmamış beğeni sayısını dinliyoruz
    return StreamBuilder<int>(
      stream: LikeService.instance.incomingLikesUnreadCount(),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        final hasUnread = count > 0;

        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              onPressed: onPressed,
              icon: Icon(
                hasUnread ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: hasUnread ? Colors.red : null, // Okunmamış varsa Kırmızı
              ),
            ),
            // Opsiyonel: Kırmızı nokta (Badge) eklemek isterseniz
            if (hasUnread)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                  ),
                ),
              )
          ],
        );
      },
    );
  }
}

// Grid section helper for detail screen
class _SectionGrid extends StatelessWidget {
  final String title;
  final List<FilmItem> films;
  const _SectionGrid({required this.title, required this.films});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, 
              childAspectRatio: 0.64,
              crossAxisSpacing: 8, 
              mainAxisSpacing: 8
            ),
            itemCount: films.length,
            itemBuilder: (_, i) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: PosterImage(posterUrl: films[i].posterUrl, title: films[i].title),
            ),
          )
        ],
      ),
    );
  }
}