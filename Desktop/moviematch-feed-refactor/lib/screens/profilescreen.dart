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
import 'package:fluttergirdi/services/follow_system_service.dart';

// --- In-memory shelf cache to avoid duplicate Firestore reads across screens ---
class UserShelfCache {
  static List<Map<String, String>> favorites = const [];
  static List<Map<String, String>> fiveStar = const [];
  static List<Map<String, String>> disliked = const [];
  static List<Map<String, String>> watchlist = const [];

  static void setFavorites(List<LetterboxdFilm> items) {
    favorites = items
        .map((e) => {'title': e.title, 'poster': e.posterUrl})
        .toList(growable: false);
  }

  static void setFiveStar(List<LetterboxdFilm> items) {
    fiveStar = items
        .map((e) => {'title': e.title, 'poster': e.posterUrl})
        .toList(growable: false);
  }

  static void setDisliked(List<LetterboxdFilm> items) {
    disliked = items
        .map((e) => {'title': e.title, 'poster': e.posterUrl})
        .toList(growable: false);
  }

  static void setWatchlistFromMaps(List<Map<String, dynamic>> items) {
    watchlist = items
        .map(
          (m) => {
            'title': (m['title'] ?? '').toString(),
            'poster': (m['poster'] ?? m['posterUrl'] ?? m['image'] ?? '')
                .toString(),
          },
        )
        .toList(growable: false);
  }
}

// Lightweight view model for profile activities (top-level)
class _ActivityItem {
  final String id; // postId
  final String type; // 'post' | 'repost'
  final String text;
  final DateTime? createdAt;
  final String posterUrl; // optional movie poster
  final String title; // optional movie title
  final int likeCount;
  final int replyCount;
  final int repostCount;

  const _ActivityItem({
    required this.id,
    required this.type,
    required this.text,
    required this.createdAt,
    this.posterUrl = '',
    this.title = '',
    this.likeCount = 0,
    this.replyCount = 0,
    this.repostCount = 0,
  });
}

class _CountPill extends StatelessWidget {
  final String label;
  final int value;
  const _CountPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Text('$label: $value', style: textStyle),
    );
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _lastUserData;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  String? _lbUsername;
  String? _appUsername;
  Future<List<LetterboxdFilm>>? _futureFavs;
  Future<List<LetterboxdFilm>>? _futureFiveStar;
  Future<List<LetterboxdFilm>>? _futureDisliked;
  String?
  _lastSyncedLbUsername; // same-session guard to avoid duplicate sync writes
  final Set<String> _catalogUpsertedKeys = <String>{};
  // Cache for watchlist catalog fetches to avoid refetch on repeated snapshots
  final Map<String, Future<List<Map<String, dynamic>?>>> _watchlistFutureCache =
      {};
  // --- Activity feed (posts & reposts) — single fetch, cache-first ---
  bool _loadingActivities = false;
  List<_ActivityItem> _activities = <_ActivityItem>[];

  int? _followers;
  int? _following;
  StreamSubscription<FollowEvent>? _followSub;

  Future<void> _bootstrapCounts() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final svc = FollowSystemService.I;
    try {
      final f1 = await svc.fetchFollowerCountOnce(uid);
      final f2 = await svc.fetchFollowingCountOnce(uid);
      if (mounted) {
        setState(() {
          _followers = f1;
          _following = f2;
        });
      }
    } catch (_) {}

    _followSub?.cancel();
    _followSub = svc.events.listen((e) {
      if (!mounted) return;
      if (e.targetUid == uid) {
        setState(() => _followers = (_followers ?? 0) + (e.followed ? 1 : -1));
      }
      if (e.actorUid == uid) {
        setState(() => _following = (_following ?? 0) + (e.followed ? 1 : -1));
      }
    });
  }

  // Helper to extract movie poster/title from post payloads
  Map<String, String> _extractMovieInfo(Map<String, dynamic> m) {
    // Try flattened fields
    final poster =
        (m['moviePoster'] ??
                m['moviePosterUrl'] ??
                m['poster'] ??
                (m['movie'] is Map
                    ? (m['movie']['poster'] ?? m['movie']['posterUrl'])
                    : '') ??
                '')
            .toString();
    final title =
        (m['movieTitle'] ??
                m['title'] ??
                (m['movie'] is Map ? (m['movie']['title'] ?? '') : '') ??
                '')
            .toString();
    return {'poster': poster, 'title': title};
  }

  // Fill in-memory cache for shelves when futures resolve
  Future<void> _primeShelfCache() async {
    try {
      if (_futureFavs != null) {
        final favs = await _futureFavs!;
        UserShelfCache.setFavorites(favs);
      }
      if (_futureFiveStar != null) {
        final five = await _futureFiveStar!;
        UserShelfCache.setFiveStar(five);
      }
      if (_futureDisliked != null) {
        final low = await _futureDisliked!;
        UserShelfCache.setDisliked(low);
      }
    } catch (_) {
      // ignore cache fill errors silently
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _bindLbFromFirestore();
    _loadActivities();
    _bootstrapCounts();
  }

  Future<void> _loadActivities() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (mounted) setState(() => _loadingActivities = true);

    final db = FirebaseFirestore.instance;
    final List<_ActivityItem> items = [];

    // 1) User's own posts (single fetch, cache-first, then server fallback)
    try {
      final q = db
          .collection('posts')
          .where('authorId', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(30);
      QuerySnapshot<Map<String, dynamic>> qs;
      try {
        qs = await q.get(const GetOptions(source: Source.cache));
      } catch (_) {
        qs = await q.get();
      }
      for (final d in qs.docs) {
        final m = d.data();
        final ts = m['createdAt'];
        final info = _extractMovieInfo(m);
        items.add(
          _ActivityItem(
            id: d.id,
            type: 'post',
            text: (m['text'] ?? '').toString(),
            createdAt: ts is Timestamp ? ts.toDate() : null,
            posterUrl: info['poster'] ?? '',
            title: info['title'] ?? '',
            likeCount: (m['likeCount'] ?? 0) is int
                ? (m['likeCount'] ?? 0) as int
                : ((m['likeCount'] ?? 0) as num).toInt(),
            replyCount: (m['replyCount'] ?? 0) is int
                ? (m['replyCount'] ?? 0) as int
                : ((m['replyCount'] ?? 0) as num).toInt(),
            repostCount: (m['repostCount'] ?? 0) is int
                ? (m['repostCount'] ?? 0) as int
                : ((m['repostCount'] ?? 0) as num).toInt(),
          ),
        );
      }
    } catch (_) {}

    // 2) Reposts by the user (best-effort via collectionGroup 'reposts' with doc == uid)
    // If your data model differs, feel free to rename 'reposts' or remove this block.
    try {
      final cg = db
          .collectionGroup('reposts')
          .where('userId', isEqualTo: uid) // use field, not documentId()
          .limit(50);
      final cgSnap = await cg.get();
      for (final rpDoc in cgSnap.docs) {
        final postRef = rpDoc.reference.parent.parent; // posts/{postId}
        if (postRef == null) continue;
        try {
          final p = await postRef.get(const GetOptions(source: Source.cache));
          final data =
              (p.exists ? p.data() : null) ??
              (await postRef.get(
                const GetOptions(source: Source.server),
              )).data();
          if (data == null) continue;
          final ts = data['createdAt'];
          final info = _extractMovieInfo(data);
          items.add(
            _ActivityItem(
              id: postRef.id,
              type: 'repost',
              text: (data['text'] ?? '').toString(),
              createdAt: ts is Timestamp ? ts.toDate() : null,
              posterUrl: info['poster'] ?? '',
              title: info['title'] ?? '',
              likeCount: (data['likeCount'] ?? 0) is int
                  ? (data['likeCount'] ?? 0) as int
                  : ((data['likeCount'] ?? 0) as num).toInt(),
              replyCount: (data['replyCount'] ?? 0) is int
                  ? (data['replyCount'] ?? 0) as int
                  : ((data['replyCount'] ?? 0) as num).toInt(),
              repostCount: (data['repostCount'] ?? 0) is int
                  ? (data['repostCount'] ?? 0) as int
                  : ((data['repostCount'] ?? 0) as num).toInt(),
            ),
          );
        } catch (_) {}
      }
    } catch (_) {
      // collectionGroup may be unavailable in rules; ignore silently
    }

    // Sort by time desc and publish
    items.sort((a, b) {
      final at = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });

    if (mounted) {
      setState(() {
        _activities = items;
        _loadingActivities = false;
      });
    }
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
    // Fill in-memory cache when futures complete (no extra Firestore reads)
    // ignore: discarded_futures
    _primeShelfCache();

    // Removed auto-sync trigger on every open
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
          _lastUserData = Map<String, dynamic>.from(data);
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
              });
            }
            // Refresh in-memory shelves as soon as new futures resolve
            // ignore: discarded_futures
            _primeShelfCache();

            // Auto-sync ONLY when LB username changes (write minimization)
            if (_lastSyncedLbUsername != lb) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _syncLetterboxdToFirestore(lb);
              });
              _lastSyncedLbUsername = lb;
            }
          }
        });
  }

  /// Upsert film docs into `catalog_films/{filmKey}` so posters/titles resolve in UI
  Future<void> _upsertCatalogFromList(List<LetterboxdFilm> films) async {
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    var queued = 0;
    for (final f in films) {
      final k = (f.key);
      if (k.isEmpty) {
        continue;
      }
      if (_catalogUpsertedKeys.contains(k)) {
        continue; // already done this session
      }
      _catalogUpsertedKeys.add(k);
      final ref = db.collection('catalog_films').doc(k);
      batch.set(ref, {
        'title': f.title,
        'url': f.url,
        'posterUrl': f.posterUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      queued++;
    }
    if (queued > 0) {
      await batch.commit();
    }
  }

  /// Writes fiveStars and lowRatings into `userTasteProfiles/{uid}` only if changed
  Future<void> _writeTasteProfile({
    required String uid,
    required String lbUsername,
    required List<LetterboxdFilm> fiveStars,
    required List<LetterboxdFilm> lowRatings,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final db = FirebaseFirestore.instance;
    final doc = db.collection('userTasteProfiles').doc(uid);

    final newFive = fiveStars
        .map((e) => e.key)
        .where((k) => k.isNotEmpty)
        .toList();
    final newLow = lowRatings
        .map((e) => e.key)
        .where((k) => k.isNotEmpty)
        .toList();

    // Read existing to avoid unnecessary writes
    Map<String, dynamic> old = const {};
    try {
      final snap = await doc.get(const GetOptions(source: Source.cache));
      if (snap.exists && snap.data() != null) old = snap.data()!;
    } catch (_) {}
    if (old.isEmpty) {
      try {
        final snap = await doc.get(const GetOptions(source: Source.server));
        if (snap.exists && snap.data() != null) old = snap.data()!;
      } catch (_) {}
    }

    bool sameLists(List a, List b) {
      if (identical(a, b)) return true;
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }

    final oldFive = List<String>.from((old['fiveStars'] ?? const []));
    final oldLow = List<String>.from((old['lowRatings'] ?? const []));
    final oldProfile = Map<String, dynamic>.from((old['profile'] ?? const {}));

    final newProfile = {
      'displayName': user?.displayName,
      'letterboxdUsername': lbUsername,
      'avatarUrl': user?.photoURL,
    };

    final listsSame = sameLists(oldFive, newFive) && sameLists(oldLow, newLow);
    final profileSame =
        oldProfile['displayName'] == newProfile['displayName'] &&
        oldProfile['letterboxdUsername'] == newProfile['letterboxdUsername'] &&
        oldProfile['avatarUrl'] == newProfile['avatarUrl'];

    if (listsSame && profileSame) {
      return; // Skip write: nothing changed
    }

    await doc.set({
      'fiveStars': newFive,
      'lowRatings': newLow,
      'profile': newProfile,
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

    // Mirror 5★ into users/{uid}.fiveStarKeys only if changed
    try {
      final db = FirebaseFirestore.instance;
      final userRef = db.collection('users').doc(uid);
      final currentSnap = await userRef.get(
        const GetOptions(source: Source.cache),
      );
      Map<String, dynamic>? cur = currentSnap.data();
      if (cur == null) {
        try {
          final s2 = await userRef.get(const GetOptions(source: Source.server));
          cur = s2.data();
        } catch (_) {}
      }
      final newFive = five
          .map((e) => e.key)
          .where((k) => k.isNotEmpty)
          .toList();
      final oldFive = List<String>.from((cur?['fiveStarKeys'] ?? const []));
      bool changed = newFive.length != oldFive.length;
      if (!changed) {
        for (var i = 0; i < newFive.length; i++) {
          if (newFive[i] != oldFive[i]) {
            changed = true;
            break;
          }
        }
      }
      if (changed) {
        await userRef.set({
          'fiveStarKeys': newFive,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {
      // ignore optional mirror errors
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
    _followSub?.cancel();
    super.dispose();
  }

  String _shownName(User user) {
    final local = (_appUsername ?? '').trim();
    if (local.isNotEmpty) {
      return local; // Firestore'daki uygulama kullanıcı adı öncelikli
    }
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
          final ref = FirebaseFirestore.instance.collection('users').doc(uid);
          var snap = await ref.get(const GetOptions(source: Source.cache));
          if (!snap.exists) {
            snap = await ref.get(const GetOptions(source: Source.server));
          }
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
    // Refresh the cache after manual refresh
    // ignore: discarded_futures
    _primeShelfCache();
  }

  String _noYear(String t) {
    // "Movie Title (1999)" -> "Movie Title"
    return t.replaceAll(RegExp(r'\s*\(\d{4}\)$'), '');
  }

  // --- WATCHLIST SECTION (cache‑first, single fetch; no extra user stream) ---
  Widget _watchlistSectionFromKeys(List<String> keys, {int maxItems = 30}) {
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
        final col = FirebaseFirestore.instance
            .collection('catalog_films')
            .doc(k);
        // cache‑first -> server fallback
        try {
          final c = await col.get(const GetOptions(source: Source.cache));
          if (c.exists) return c.data();
        } catch (_) {}
        try {
          final s = await col.get(const GetOptions(source: Source.server));
          if (s.exists) return s.data();
        } catch (_) {}
        return null;
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

        // Publish watchlist into in‑memory cache so other screens reuse it without extra reads
        UserShelfCache.setWatchlistFromMaps(films);

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
                  (film['poster'] ?? film['posterUrl'] ?? film['image'] ?? '')
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
                    MaterialPageRoute(
                      builder: (_) =>
                          EditProfilePage(initialUserData: _lastUserData),
                    ),
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
                  await _loadActivities();
                  await _bootstrapCounts();
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
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _shownName(user),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  (_followers == null || _following == null)
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            _CountPill(
                                              label: 'Takipçi',
                                              value: _followers!,
                                            ),
                                            _CountPill(
                                              label: 'Takip',
                                              value: _following!,
                                            ),
                                          ],
                                        ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 5),
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

                    // Kullanıcı profili tercihleri (yaş, türler, yönetmenler, oyuncular) — tek okunur, _lastUserData üzerinden
                    const SizedBox(height: 12),
                    Builder(
                      builder: (context) {
                        final data = _lastUserData ?? const <String, dynamic>{};
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
                    _watchlistSectionFromKeys(
                      List<dynamic>.from(
                        (_lastUserData?['watchlistKeys'] ?? const []),
                      ).map((e) => e.toString()).toList(),
                      maxItems: 30,
                    ),
                    const SizedBox(height: 17),
                    Row(
                      children: [
                        Text(
                          'Aktiviteler',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Yenile',
                          icon: const Icon(Icons.refresh),
                          onPressed: _loadingActivities
                              ? null
                              : _loadActivities,
                        ),
                      ],
                    ),
                    SizedBox(height: 5),
                    if (_loadingActivities)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_activities.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Henüz aktivite yok.'),
                      )
                    else
                      ListView.separated(
                        itemCount: _activities.length,
                        physics: const NeverScrollableScrollPhysics(),
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 0.5, thickness: 0.5),
                        itemBuilder: (context, i) {
                          final a = _activities[i];
                          final when = a.createdAt;
                          String timeLabel = '';
                          if (when != null) {
                            final diff = DateTime.now().difference(when);
                            if (diff.inMinutes < 60) {
                              timeLabel = '${diff.inMinutes}m';
                            } else if (diff.inHours < 24) {
                              timeLabel = '${diff.inHours}h';
                            } else {
                              timeLabel = '${diff.inDays}g';
                            }
                          }
                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white10, // semi-transparent card
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color.fromARGB(3, 255, 255, 255),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Poster yalnızca film eklenmişse gösterilsin (placeholder yok)
                                if ((a.posterUrl).isNotEmpty) ...[
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      a.posterUrl,
                                      width: 44,
                                      height: 66,
                                      fit: BoxFit.cover,
                                      headers: LetterboxdService.imageHeaders,
                                      errorBuilder: (_, __, ___) => Container(
                                        width: 44,
                                        height: 66,
                                        color: Colors.grey.shade800,
                                        child: const Icon(Icons.movie),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                // Metinler
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Kullanıcı adı (kalın) + aktivite tipi + zaman etiketi
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              _shownName(
                                                FirebaseAuth
                                                    .instance
                                                    .currentUser!,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            a.type == 'repost'
                                                ? 'Alıntıladı'
                                                : 'Paylaştı',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.labelSmall,
                                          ),
                                          if (timeLabel.isNotEmpty) ...[
                                            const SizedBox(width: 6),
                                            Text(
                                              timeLabel,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.labelSmall,
                                            ),
                                          ],
                                        ],
                                      ),
                                      // Gönderi metni (yalnızca bir kez)
                                      if (a.text.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 4.0,
                                          ),
                                          child: Text(
                                            a.text,
                                            maxLines: 4,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      // Metrikler
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 6.0,
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.favorite_border,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 4),
                                            Text('${a.likeCount}'),
                                            const SizedBox(width: 12),
                                            const Icon(
                                              Icons.mode_comment_outlined,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 4),
                                            Text('${a.replyCount}'),
                                            const SizedBox(width: 12),
                                            const Icon(Icons.repeat, size: 16),
                                            const SizedBox(width: 4),
                                            Text('${a.repostCount}'),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
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
