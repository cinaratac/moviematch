import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;
import 'dart:convert'; // EKLENDİ: JSON decode için
import 'package:http/http.dart' as http; // EKLENDİ: API isteği için
import 'package:fluttergirdi/secrets.dart'; // EKLENDİ: Token için

import 'package:fluttergirdi/services/match_service.dart' as global_match;
import 'package:fluttergirdi/services/like_service.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:fluttergirdi/screens/likes_page.dart'; 
import 'package:fluttergirdi/screens/passes_page.dart'; 
import 'package:swipe_cards/swipe_cards.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';
import 'package:fluttergirdi/widgets/green_characters.dart';
// FilmItem sınıfı burada tanımlı olduğu varsayılarak import ediliyor.
import 'package:fluttergirdi/widgets/match_card.dart'; 
import 'package:fluttergirdi/screens/movie_detail_screen.dart';

// Simple in-memory cache to persist match list within app session
class _MatchListSessionCache {
  static List<global_match.MatchResult>? results;
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

  final ValueNotifier<bool> _showGuideNotifier = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  @override
  void dispose() {
    _showGuideNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadMatches() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

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

    try {
      final results =
          await global_match.MatchService.instance.findMatches(me.uid);
      if (!mounted) return;

      _all = results;
      _MatchListSessionCache.results = results;

      _buildSwipeItems();

      setState(() {
        _matchEngine = MatchEngine(swipeItems: _swipeItems);
        _loading = false;
      });

      if (_swipeItems.isEmpty) {
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
      Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _showGuideNotifier.value = true;
      });

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Eşleşmeler alınamadı: $e')));
    }
  }

  void _removeUserFromLocalCache(String otherUid) {
    if (_MatchListSessionCache.results != null) {
      _MatchListSessionCache.results!.removeWhere((m) => m.uid == otherUid);
    }
    
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
          await LikeService.instance.likeUser(
            m.uid,
            commonFavoritesCount: m.commonFavCount,
            commonFiveStarsCount: m.commonFiveCount,
          );
          _removeUserFromLocalCache(m.uid);
        },
        nopeAction: () async {
          await LikeService.instance.passUser(m.uid);
          _removeUserFromLocalCache(m.uid);
        },
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;

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
          backgroundColor: cs.surface,
          appBar: AppBar(
            backgroundColor: cs.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: true,
            toolbarHeight: 65,
            titleSpacing: 16,
            title: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TabBar(
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      indicator: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      labelColor: cs.onSurface,
                      unselectedLabelColor: cs.onSurfaceVariant,
                      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                      overlayColor: WidgetStateProperty.all(Colors.transparent),
                      tabs: const [
                        Tab(text: 'Geçilenler'),
                        Tab(text: 'Eşleşmeler'),
                        Tab(text: 'Beğenilenler'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _LikesIndicatorHeart(onPressed: _openIncomingLikes),
                ),
              ],
            ),
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: TabBarView(
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        const PassesListBody(), 
                        
                        _loading
                            ? const Center(child: CircularProgressIndicator())
                            : (_swipeItems.isEmpty || _finished
                                ? const _NoMatchesCharacter()
                                : Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                                    child: SwipeCards(
                                      matchEngine: _matchEngine,
                                      itemBuilder: (context, index) {
                                        final m = _swipeItems[index].content
                                            as global_match.MatchResult;
                                        return MatchCard(
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
                                        _showGuideNotifier.value = true;
                                      },
                                      upSwipeAllowed: false,
                                      fillSpace: true,
                                    ),
                                  )),
      
                        const LikesListBody(), 
                      ],
                    ),
                  ),
                  const SizedBox(height: 56),
                ],
              ),

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
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => _IncomingLikesSheet(items: items));
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

  // YENİ EKLENEN FONKSİYON: TMDB ID'si yoksa arayıp bulur
  Future<void> _handleFilmTap(BuildContext context, FilmItem film) async {
    int? id = film.tmdbId;

    if (id == null) {
      // ID yok, arama yapmamız lazım. Kullanıcıya bir loading gösterelim.
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => const Center(child: CircularProgressIndicator()),
      );

      try {
        final searchUrl = Uri.parse(
          'https://api.themoviedb.org/3/search/movie?query=${Uri.encodeComponent(film.title)}&language=tr-TR&include_adult=false'
        );
        final res = await http.get(searchUrl, headers: Secrets.tmdbHeaders);
        
        // HATA DÜZELTME: Async işlemden sonra mounted kontrolü
        if (!mounted) return;
        Navigator.pop(context); // Loading'i kapat

        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          final results = data['results'] as List?;
          if (results != null && results.isNotEmpty) {
            id = results[0]['id'];
            
            // Gelecekte tekrar aramayalım diye Firestore'a kaydedelim
            if (film.id.isNotEmpty && id != null) {
              FirebaseFirestore.instance
                  .collection('catalog_films')
                  .doc(film.id)
                  .set({'tmdbId': id}, SetOptions(merge: true));
            }
          } else {
             ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Film detayları bulunamadı.'))
            );
            return;
          }
        } else {
           // HTTP Hata durumu
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Bağlantı hatası oluştu.'))
           );
           return;
        }
      } catch (e) {
        // HATA DÜZELTME: Catch bloğunda mounted kontrolü
        if (!mounted) return;
        Navigator.pop(context); // Loading'i kapat (eğer açıksa)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bağlantı hatası oluştu.'))
        );
        return;
      }
    }

    if (id != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MovieDetailScreen(
            tmdbId: id!,
            title: film.title,
            posterUrl: film.posterUrl,
          ),
        ),
      );
    }
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
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              
              final data = snap.data ?? const _Resolved();

              return SliverMainAxisGroup(
                slivers: [
                  if (data.fiveStars.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                        child: Text('Ortak 5 Yıldız', 
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3, 
                          childAspectRatio: 0.64,
                          crossAxisSpacing: 8, 
                          mainAxisSpacing: 8,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) {
                            final film = data.fiveStars[i];
                            return GestureDetector( 
                              onTap: () => _handleFilmTap(context, film), 
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: PosterImage(
                                  posterUrl: film.posterUrl, 
                                  title: film.title
                                ),
                              ),
                            );
                          },
                          childCount: data.fiveStars.length,
                        ),
                      ),
                    ),
                  ],

                  if (data.favorites.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                        child: Text('Ortak Favoriler', 
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3, 
                          childAspectRatio: 0.64,
                          crossAxisSpacing: 8, 
                          mainAxisSpacing: 8,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) {
                            final film = data.favorites[i];
                            return GestureDetector( 
                              onTap: () => _handleFilmTap(context, film), 
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: PosterImage(
                                  posterUrl: film.posterUrl, 
                                  title: film.title
                                ),
                              ),
                            );
                          },
                          childCount: data.favorites.length,
                        ),
                      ),
                    ),
                  ],

                  if (data.watchlist.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                        child: Text('Ortak İzleme Listesi', 
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3, 
                          childAspectRatio: 0.64,
                          crossAxisSpacing: 8, 
                          mainAxisSpacing: 8,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) {
                            final film = data.watchlist[i];
                            return GestureDetector( 
                              onTap: () => _handleFilmTap(context, film),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: PosterImage(
                                  posterUrl: film.posterUrl, 
                                  title: film.title
                                ),
                              ),
                            );
                          },
                          childCount: data.watchlist.length,
                        ),
                      ),
                    ),
                  ],

                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              );
            },
          ),
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

class _Resolved {
  final List<FilmItem> favorites;
  final List<FilmItem> fiveStars;
  final List<FilmItem> watchlist;
  const _Resolved({this.favorites = const [], this.fiveStars = const [], this.watchlist = const []});
}

Future<_Resolved> _resolveCommonFilms(global_match.MatchResult m) async {
  final db = FirebaseFirestore.instance;
  
  Future<List<FilmItem>> readChunk(List<String> keys) async {
    if (keys.isEmpty) return const [];
    final cleanKeys = keys.where((k) => k.trim().isNotEmpty).toList();
    if (cleanKeys.isEmpty) return const [];
    
    final items = <FilmItem>[];
    const chunkSize = 10;
    
    for (var i = 0; i < cleanKeys.length; i += chunkSize) {
      await Future.delayed(const Duration(milliseconds: 5));
      final chunk = cleanKeys.sublist(i, math.min(i + chunkSize, cleanKeys.length));
      
      var qs = await db.collection('catalog_films').where(FieldPath.documentId, whereIn: chunk).get();
      
      if (qs.docs.isEmpty) {
        qs = await db.collection('catalog_films').where('key', whereIn: chunk).get();
      }

      for (final doc in qs.docs) {
        final d = doc.data();
        final t = (d['title'] ?? d['name'] ?? '').toString();
        final p = (d['posterUrl'] ?? d['poster'] ?? d['poster_path'] ?? '').toString();
        // TMDB ID'yi de çekiyoruz
        final tmdbId = d['tmdbId'] as int?;

        items.add(FilmItem(
          id: doc.id, 
          title: t.isNotEmpty ? t : 'İsimsiz', 
          posterUrl: p,
          tmdbId: tmdbId 
        ));
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

// ... (_IncomingLikesSheet ve diğer widgetlar aynı kalıyor) ...
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
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(item.otherUid).get(),
      builder: (context, snapshot) {
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

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d);
    
    if (diff.inMinutes < 60) return '${diff.inMinutes}dk önce';
    if (diff.inHours < 24) return '${diff.inHours}sa önce';
    return '${d.day}.${d.month}.${d.year}';
  }
}

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
              iconSize: 26, 
              padding: EdgeInsets.zero,
              icon: Icon(
                hasUnread ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: hasUnread ? Colors.red : null, 
              ),
            ),
            if (hasUnread)
              Positioned(
                right: 10,
                top: 10,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
                  ),
                ),
              )
          ],
        );
      },
    );
  }
}