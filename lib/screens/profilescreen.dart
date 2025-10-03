import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluttergirdi/services/letterboxd_service.dart';
import 'package:fluttergirdi/services/match_service.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui' as ui;
import 'package:fluttergirdi/screens/edit_profile_page.dart';
import 'package:fluttergirdi/screens/settings_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  String? _lbUsername;
  String? _appUsername;
  Future<List<LetterboxdFilm>>? _futureFavs;
  Future<List<LetterboxdFilm>>? _futureFiveStar;
  Future<List<LetterboxdFilm>>? _futureDisliked;
  bool _autoSynced = false;
  // Cache for watchlist catalog fetches to avoid refetch on repeated snapshots
  final Map<String, Future<List<Map<String, dynamic>?>>> _watchlistFutureCache =
      {};

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _bindLbFromFirestore();
  }

  Future<void> _loadPrefs() async {
    final sp = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;

    // Eski global anahtar -> kullanıcıya özel anahtara tek seferlik taşıma
    final oldGlobal = sp.getString('lb_username');
    if (uid != null && oldGlobal != null) {
      await sp.setString('lb_username_$uid', oldGlobal);
      await sp.remove('lb_username');
    }

    final u = uid != null
        ? sp.getString('lb_username_$uid')
        : sp.getString('lb_username');
    setState(() {
      _lbUsername = u;
      _futureFavs = (u == null || u.isEmpty)
          ? null
          : LetterboxdService.fetchFavorites(u);
      _futureFiveStar = (u == null || u.isEmpty)
          ? null
          : LetterboxdService.fetchFiveStar(u);
      _futureDisliked = (u == null || u.isEmpty)
          ? null
          : LetterboxdService.fetchDisliked(u);
    });
    // Auto-sync once per session if LB username exists
    if (!_autoSynced && u != null && u.isNotEmpty && uid != null) {
      try {
        // Trigger full sync on next frame (avoid setState conflicts)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _syncLetterboxdToFirestore(u);
        });
        _autoSynced = true;
      } catch (_) {
        // ignore; manual refresh or next open will try again
      }
    }
  }

  void _bindLbFromFirestore() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _userSub?.cancel();
    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) async {
          if (!snap.exists) return;
          final data = snap.data() ?? const {};
          final lb = (data['letterboxdUsername'] ?? '').toString().trim();
          final appU =
              (data['username'] ?? data['handle'] ?? data['appUsername'] ?? '')
                  .toString()
                  .trim();

          // 1) Propagate app username immediately if changed
          if (appU.isNotEmpty && appU != (_appUsername ?? '')) {
            if (mounted) {
              setState(() => _appUsername = appU);
            }
          }

          // 2) Handle Letterboxd username changes (avoid early return so appU still updates)
          if (lb.isNotEmpty && lb != (_lbUsername ?? '')) {
            // persist to SharedPreferences for next app launch
            try {
              final sp = await SharedPreferences.getInstance();
              await sp.setString('lb_username_$uid', lb);
            } catch (_) {}

            // update state & futures
            if (mounted) {
              setState(() {
                _lbUsername = lb;
                _futureFavs = LetterboxdService.fetchFavorites(lb);
                _futureFiveStar = LetterboxdService.fetchFiveStar(lb);
                _futureDisliked = LetterboxdService.fetchDisliked(lb);
                _autoSynced = false; // force re-sync once for new username
              });
            }

            // auto-sync once for this new username
            if (!_autoSynced) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _syncLetterboxdToFirestore(lb);
              });
              _autoSynced = true;
            }
          }
        });
  }

  /// Upsert film docs into `catalog_films/{filmKey}` so posters/titles resolve in UI
  Future<void> _upsertCatalogFromList(List<LetterboxdFilm> films) async {
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    for (final f in films) {
      if ((f.key).isEmpty) continue;
      final ref = db.collection('catalog_films').doc(f.key);
      batch.set(ref, {
        'title': f.title,
        'url': f.url,
        'posterUrl': f.posterUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  /// Writes fiveStars and lowRatings into `userTasteProfiles/{uid}`
  Future<void> _writeTasteProfile({
    required String uid,
    required String lbUsername,
    required List<LetterboxdFilm> fiveStars,
    required List<LetterboxdFilm> lowRatings,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final db = FirebaseFirestore.instance;
    final doc = db.collection('userTasteProfiles').doc(uid);
    await doc.set({
      'fiveStars': fiveStars
          .map((e) => e.key)
          .where((k) => k.isNotEmpty)
          .toList(),
      'lowRatings': lowRatings
          .map((e) => e.key)
          .where((k) => k.isNotEmpty)
          .toList(),
      'profile': {
        'displayName': user?.displayName,
        'letterboxdUsername': lbUsername,
        'avatarUrl': user?.photoURL,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Full sync: favorites -> users/{uid}.favoritesKeys, fiveStars/lowRatings -> userTasteProfiles/{uid}
  Future<void> _syncLetterboxdToFirestore(String lbUsername) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || lbUsername.isEmpty) return;

    // 1) Favorites: fills users/{uid}.favoritesKeys and catalog
    await LetterboxdService.syncFavoritesToFirestore(lbUsername: lbUsername);
    // 1.1) WATCHLIST: users/{uid}.watchlistKeys + catalog_films upsert
    try {
      await LetterboxdService.syncWatchlistToFirestore(lbUsername: lbUsername);
    } catch (e) {
      debugPrint('syncWatchlistToFirestore error: $e');
    }

    // 2) Five stars & low ratings; also upsert catalogs so posters resolve
    final five = await LetterboxdService.fetchFiveStar(lbUsername);
    final low = await LetterboxdService.fetchDisliked(lbUsername);
    await _upsertCatalogFromList(five);
    await _upsertCatalogFromList(low);

    // Mirror 5★ into users/{uid}.fiveStarKeys as well (MatchService this field reads)
    try {
      final db = FirebaseFirestore.instance;
      await db.collection('users').doc(uid).set({
        'fiveStarKeys': five
            .map((e) => e.key)
            .where((k) => k.isNotEmpty)
            .toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // optional: ignore if fails; taste profile still written below
    }

    // 3) Mirror disliked into users/{uid}.dislikedKeys as well (and catalog already upserted above)
    try {
      await LetterboxdService.syncDislikedToFirestore(lbUsername: lbUsername);
    } catch (_) {
      // optional: ignore if not available
    }

    // 4) Write taste profile for 5★ and low ratings
    await _writeTasteProfile(
      uid: uid,
      lbUsername: lbUsername,
      fiveStars: five,
      lowRatings: low,
    );

    // 5) Sync bitti: sadece ortak 5★ olanlar için otomatik eşleşme oluştur
    try {
      await MatchService().autoCreateMatchesFiveOnly(uid, minCommonFive: 1);
    } catch (e) {
      debugPrint('autoCreateMatchesFiveOnly error: $e');
    }
  }

  @override
  void dispose() {
    _userSub?.cancel();
    super.dispose();
  }

  String _shownName(User user) {
    final local = (_appUsername ?? '').trim();
    if (local.isNotEmpty)
      return local; // Firestore'daki uygulama kullanıcı adı öncelikli
    final dn = (user.displayName ?? '').trim();
    if (dn.isNotEmpty) return dn; // sonra Firebase Auth displayName
    final email = user.email ?? '';
    return email.contains('@') ? email.split('@').first : 'Kullanıcı';
  }

  Widget _posterTile(LetterboxdFilm f) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            f.posterUrl,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            headers: LetterboxdService.imageHeaders,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                color: Colors.black12,
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            },
            errorBuilder: (_, __, ___) => Container(
              color: Colors.grey.shade800,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    _noYear(f.title),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              color: Colors.black54,
              child: Text(
                _noYear(f.title),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Blurred header using the first favorite film poster as a fullscreen background
  Widget _blurBackdrop() {
    if (_futureFavs == null) return const SizedBox.shrink();
    return FutureBuilder<List<LetterboxdFilm>>(
      future: _futureFavs,
      builder: (context, snap) {
        final list = snap.data ?? const <LetterboxdFilm>[];
        final hasPoster = list.isNotEmpty && (list.first.posterUrl).isNotEmpty;
        if (!hasPoster) return const SizedBox.shrink();
        final url = list.first.posterUrl;
        return Positioned.fill(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  headers: LetterboxdService.imageHeaders,
                  errorBuilder: (_, __, ___) => Container(color: Colors.black),
                ),
              ),
              // dark scrim for contrast
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xCC000000),
                      Color(0x99000000),
                      Color(0x66000000),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Zorla yenile: cache'i temizleyip tekrar çekmek için
  Future<void> _refreshFavorites() async {
    if (_lbUsername == null || _lbUsername!.isEmpty) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();
          final lb = (snap.data()?['letterboxdUsername'] ?? '').toString();
          if (lb.isNotEmpty) {
            setState(() {
              _lbUsername = lb;
            });
          }
        } catch (_) {}
      }
      if (_lbUsername == null || _lbUsername!.isEmpty) return;
    }
    // Cache temizle
    final sp = await SharedPreferences.getInstance();
    final key = 'lb_cache_${_lbUsername!.toLowerCase()}';
    await sp.remove(key);
    await sp.remove('${key}_time');
    // Yeniden çek
    setState(() {
      _futureFavs = LetterboxdService.fetchFavorites(_lbUsername!);
      _futureFiveStar = LetterboxdService.fetchFiveStar(_lbUsername!);
      _futureDisliked = LetterboxdService.fetchDisliked(_lbUsername!);
    });
  }

  String _noYear(String t) {
    // "Movie Title (1999)" -> "Movie Title"
    return t.replaceAll(RegExp(r'\s*\(\d{4}\)$'), '');
  }

  // --- WATCHLIST SECTION ---
  Widget _watchlistSection(String uid, {int maxItems = 30}) {
    final fs = FirebaseFirestore.instance;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: fs.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const SizedBox.shrink();
        }
        final data = snap.data!.data()!;
        final List<dynamic> keysDyn =
            (data['watchlistKeys'] ?? []) as List<dynamic>;
        final keys = keysDyn.map((e) => e.toString()).toList();
        if (keys.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Watchlist boş.'),
          );
        }
        final limited = keys.take(maxItems).toList();
        // Build a stable cache key based on limited keys
        final hash = limited.join('|');
        final future = _watchlistFutureCache[hash] ??= Future.wait(
          limited.map((k) async {
            final d = await fs.collection('catalog_films').doc(k).get();
            return d.data();
          }),
        );

        return FutureBuilder<List<Map<String, dynamic>?>>(
          future: future,
          builder: (context, filmSnap) {
            if (filmSnap.connectionState == ConnectionState.waiting &&
                !(filmSnap.hasData && (filmSnap.data?.isNotEmpty ?? false))) {
              return const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (!filmSnap.hasData) return const SizedBox.shrink();
            final films = filmSnap.data!
                .where((m) => m != null)
                .map((m) => m!)
                .toList();
            if (films.isEmpty) return const SizedBox.shrink();

            return SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: films.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final film = films[i];
                  final poster =
                      (film['poster'] ??
                              film['posterUrl'] ??
                              film['image'] ??
                              '')
                          as String;
                  final title = (film['title'] ?? '') as String;
                  return AspectRatio(
                    aspectRatio: 2 / 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          poster.isNotEmpty
                              ? Image.network(
                                  poster,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                  headers: LetterboxdService.imageHeaders,
                                  errorBuilder: (_, __, ___) =>
                                      Container(color: Colors.grey.shade800),
                                )
                              : Container(color: Colors.grey.shade800),
                          if (title.isNotEmpty)
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                color: Colors.black54,
                                child: Text(
                                  _noYear(title),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(), // canlı dinle
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snap.data;
        if (user == null) {
          return const Scaffold(body: Center(child: Text('Oturum açılmadı')));
        }

        // Removed unused local variables

        return Scaffold(
          appBar: AppBar(
            title: const Text('Profil'),
            backgroundColor: Colors.black.withValues(
              alpha: 0.20,
            ), // semi‑transparent
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            actions: [
              IconButton(
                tooltip: 'Düzenle',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const EditProfilePage()),
                  );
                },
              ),
              IconButton(
                tooltip: 'Yenile',
                icon: const Icon(Icons.refresh),
                onPressed: _refreshFavorites,
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
          extendBodyBehindAppBar: true,
          body: Stack(
            children: [
              _blurBackdrop(),
              RefreshIndicator(
                onRefresh: () async {
                  await user.reload();
                  if (_lbUsername != null && _lbUsername!.isNotEmpty) {
                    setState(() {
                      _futureFavs = LetterboxdService.fetchFavorites(
                        _lbUsername!,
                      );
                      _futureFiveStar = LetterboxdService.fetchFiveStar(
                        _lbUsername!,
                      );
                      _futureDisliked = LetterboxdService.fetchDisliked(
                        _lbUsername!,
                      );
                    });
                  }
                },
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    MediaQuery.of(context).padding.top + kToolbarHeight + 12,
                    16,
                    16,
                  ),
                  children: [
                    // Header
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundImage:
                              user.photoURL != null && user.photoURL!.isNotEmpty
                              ? NetworkImage(user.photoURL!)
                              : null,
                          child:
                              (user.photoURL == null || user.photoURL!.isEmpty)
                              ? Text(
                                  _shownName(user).isNotEmpty
                                      ? _shownName(user)[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(fontSize: 24),
                                )
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _shownName(user),
                                style: Theme.of(context).textTheme.titleLarge,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                user.email ?? '—',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              if (!user.emailVerified)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6.0),
                                  child: Row(
                                    children: const [
                                      Icon(Icons.info_outline, size: 16),
                                      SizedBox(width: 6),
                                      Text('E-posta doğrulanmadı'),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    if (_lbUsername == null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: const [
                            Icon(Icons.alternate_email),
                            SizedBox(width: 8),
                            Text('Letterboxd bağlı değil'),
                          ],
                        ),
                      )
                    else
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Chip(label: Text('Letterboxd: @$_lbUsername')),
                      ),

                    // Kullanıcı profili tercihleri (yaş, türler, yönetmenler, oyuncular)
                    const SizedBox(height: 12),
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .snapshots(),
                      builder: (context, usnap) {
                        if (!usnap.hasData || !usnap.data!.exists) {
                          return const SizedBox.shrink();
                        }
                        final data = usnap.data!.data()!;
                        final age = data['age'];
                        final genres = List<String>.from(
                          data['favGenres'] ?? const [],
                        );
                        final directors = List<String>.from(
                          data['favDirectors'] ?? const [],
                        );
                        final actors = List<String>.from(
                          data['favActors'] ?? const [],
                        );

                        if ((age == null || (age is int && age <= 0)) &&
                            genres.isEmpty &&
                            directors.isEmpty &&
                            actors.isEmpty) {
                          return const SizedBox.shrink();
                        }

                        Widget chipWrap(String title, List<String> items) {
                          if (items.isEmpty) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: items
                                      .map((e) => Chip(label: Text(e)))
                                      .toList(),
                                ),
                              ],
                            ),
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (age is int && age > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Row(
                                  children: [
                                    const Icon(Icons.cake, size: 18),
                                    const SizedBox(width: 6),
                                    Text('Yaş: $age'),
                                  ],
                                ),
                              ),
                            chipWrap('Sevdiğin türler', genres),
                            chipWrap('Sevdiğin yönetmenler', directors),
                            chipWrap('Sevdiğin oyuncular', actors),
                          ],
                        );
                      },
                    ),

                    if (_lbUsername != null) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text(
                            'Favori Filmler',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      FutureBuilder<List<LetterboxdFilm>>(
                        future: _futureFavs,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const SizedBox(
                              height: 180,
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          if (snapshot.hasError) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Favoriler alınamadı: ${snapshot.error}',
                                  ),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: FilledButton.icon(
                                      onPressed: _refreshFavorites,
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('Tekrar dene'),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          final items = snapshot.data ?? [];
                          if (items.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('Favori film bulunamadı.'),
                            );
                          }
                          return SizedBox(
                            height: 180,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, i) {
                                final f = items[i];
                                return AspectRatio(
                                  aspectRatio: 2 / 3,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: _posterTile(f),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text(
                            'Sevdiği Filmler',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      FutureBuilder<List<LetterboxdFilm>>(
                        future: _futureFiveStar,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const SizedBox(
                              height: 180,
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          if (snapshot.hasError) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('5★ film bulunamadı.'),
                            );
                          }
                          final items = snapshot.data ?? [];
                          if (items.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('5★ film bulunamadı.'),
                            );
                          }
                          return SizedBox(
                            height: 180,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, i) {
                                final f = items[i];
                                return AspectRatio(
                                  aspectRatio: 2 / 3,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: _posterTile(f),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text(
                            'Sevmediği Filmler',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      FutureBuilder<List<LetterboxdFilm>>(
                        future: _futureDisliked,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const SizedBox(
                              height: 180,
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          if (snapshot.hasError) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Sevmediği filmler alınamadı: ${snapshot.error}',
                                  ),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: FilledButton.icon(
                                      onPressed: _refreshFavorites,
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('Tekrar dene'),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          final items = snapshot.data ?? [];
                          if (items.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('Sevmediği film bulunamadı.'),
                            );
                          }
                          return SizedBox(
                            height: 180,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, i) {
                                final f = items[i];
                                return AspectRatio(
                                  aspectRatio: 2 / 3,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: _posterTile(f),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ],

                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          'Watchlist',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    _watchlistSection(user.uid, maxItems: 30),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
