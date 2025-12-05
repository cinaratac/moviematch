import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/widgets/green_characters.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluttergirdi/services/letterboxd_service.dart';
import 'package:fluttergirdi/services/match_service.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui' as ui;

import 'package:fluttergirdi/screens/edit_profile_page.dart';
import 'package:fluttergirdi/screens/settings_page.dart';
import 'package:fluttergirdi/services/follow_system_service.dart';
import 'package:fluttergirdi/screens/search_movie.dart';
import 'package:fluttergirdi/models/shelf_target.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';
import 'package:fluttergirdi/widgets/movie_action_helper.dart';

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
  final String text;
  final DateTime? createdAt;
  final String posterUrl; // optional movie poster
  final String title; // optional movie title
  final int likeCount;
  final int replyCount;

  const _ActivityItem({
    required this.id,
    required this.text,
    required this.createdAt,
    this.posterUrl = '',
    this.title = '',
    this.likeCount = 0,
    this.replyCount = 0,
  });
}

class _CountPill extends StatelessWidget {
  final String label;
  final int value;
  const _CountPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );
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

/// Compact profile header section (avatar, name, follower/following)
Widget _profileHeaderSection({
  required BuildContext context,
  required User user,
  required int? followers,
  required int? following,
  required String? lbUsername,
  required String Function(User) shownName,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 36,
          backgroundImage: user.photoURL != null && user.photoURL!.isNotEmpty
              ? NetworkImage(user.photoURL!)
              : null,
          child: (user.photoURL == null || user.photoURL!.isEmpty)
              ? Text(
                  shownName(user).isNotEmpty
                      ? shownName(user)[0].toUpperCase()
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
                shownName(user),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              (followers == null || following == null)
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _CountPill(label: 'Takipçi', value: followers),
                        _CountPill(label: 'Takip', value: following),
                      ],
                    ),
              const SizedBox(height: 5),
              if (lbUsername != null && lbUsername.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Letterboxd: @$lbUsername',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
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
  
  final Set<String> _catalogUpsertedKeys = <String>{};
  
  final Map<String, Future<List<Map<String, dynamic>?>>> _watchlistFutureCache =
      {};
  
  bool _loadingActivities = false;
  List<_ActivityItem> _activities = <_ActivityItem>[];

  int? _followers;
  int? _following;
  StreamSubscription<FollowEvent>? _followSub;

  bool _initialSyncTriggered = false; 
  
  final ValueNotifier<bool> _showGuideNotifier = ValueNotifier<bool>(false);

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

  Map<String, String> _extractMovieInfo(Map<String, dynamic> m) {
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
    }
  }

  Future<void> _forceWriteLbUsernameIfMissing() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final lb = (_lbUsername ?? '').trim();
    if (uid == null || lb.isEmpty) return;
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      Map<String, dynamic>? data;
      try {
        final c = await ref.get(const GetOptions(source: Source.cache));
        if (c.exists) data = c.data();
      } catch (_) {}
      data ??= (await ref.get(const GetOptions(source: Source.server))).data();
      final current = (data?['letterboxdUsername'] ?? '').toString().trim();
      if (current.isEmpty) {
        await ref.set({
          'letterboxdUsername': lb,
          'letterboxdUsername_lc': lb.toLowerCase(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  Future<void> _ensureInitialSyncIfNeeded() async {
    if (_initialSyncTriggered) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final lb = (_lbUsername ?? '').trim();
    if (uid == null || lb.isEmpty) return;

    try {
      final db = FirebaseFirestore.instance;
      Map<String, dynamic>? userData;
      try {
        final c = await db
            .collection('users')
            .doc(uid)
            .get(const GetOptions(source: Source.cache));
        if (c.exists) userData = c.data();
      } catch (_) {}
      if (userData == null) {
        try {
          final s = await db
              .collection('users')
              .doc(uid)
              .get(const GetOptions(source: Source.server));
          if (s.exists) userData = s.data();
        } catch (_) {}
      }

      final favKeys = List<String>.from(
        (userData?['favoritesKeys'] ?? const []),
      );
      final fiveKeys = List<String>.from(
        (userData?['fiveStarKeys'] ?? const []),
      );

      Map<String, dynamic>? tasteData;
      try {
        final t = await db
            .collection('userTasteProfiles')
            .doc(uid)
            .get(const GetOptions(source: Source.cache));
        if (t.exists) tasteData = t.data();
      } catch (_) {}
      if (tasteData == null) {
        try {
          final t2 = await db
              .collection('userTasteProfiles')
              .doc(uid)
              .get(const GetOptions(source: Source.server));
          if (t2.exists) tasteData = t2.data();
        } catch (_) {}
      }

      final missing =
          favKeys.isEmpty || fiveKeys.isEmpty || (tasteData == null);
      if (missing) {
        _initialSyncTriggered = true; 
        await _syncLetterboxdToFirestore(lb);
      }
    } catch (_) {
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

  void _checkGuideVisibility() {
    if (!mounted) return;

    final favKeys = _lastUserData?['favoritesKeys'];
    final hasFirestoreFavs = (favKeys is List && favKeys.isNotEmpty);
    
    final fiveStarKeys = _lastUserData?['fiveStarKeys'];
    final hasFirestoreFiveStar = (fiveStarKeys is List && fiveStarKeys.isNotEmpty);

    final hasCacheFavs = UserShelfCache.favorites.isNotEmpty;
    
    final hasCacheFiveStar = UserShelfCache.fiveStar.isNotEmpty;

    if (hasFirestoreFavs || hasCacheFavs || hasFirestoreFiveStar || hasCacheFiveStar) {
      _showGuideNotifier.value = false;
    } else {
      _showGuideNotifier.value = true;
    }
  }

  Future<void> _loadActivities() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (mounted) setState(() => _loadingActivities = true);

    final db = FirebaseFirestore.instance;
    final List<_ActivityItem> items = [];

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
          ),
        );
      }
    } catch (_) {}

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

    _primeShelfCache().then((_) {
      _checkGuideVisibility(); 
    });

    _forceWriteLbUsernameIfMissing();
    _ensureInitialSyncIfNeeded();
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

          if (appU.isNotEmpty && appU != (_appUsername ?? '')) {
            if (mounted) {
              setState(() => _appUsername = appU);
            }
          }

          _checkGuideVisibility();
        });
  }

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
        continue; 
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
      return; 
    }

    await doc.set({
      'fiveStars': newFive,
      'lowRatings': newLow,
      'profile': newProfile,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _syncLetterboxdToFirestore(String lbUsername) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || lbUsername.isEmpty) return;

    final db = FirebaseFirestore.instance;
    final userRef = db.collection('users').doc(uid);

    try {
      await userRef.set({
        'letterboxdUsername': lbUsername,
        'letterboxdUsername_lc': lbUsername.toLowerCase(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('users upsert letterboxdUsername error: $e');
    }

    List<LetterboxdFilm> favs = const [];
    List<LetterboxdFilm> five = const [];
    List<LetterboxdFilm> low = const [];
    try {
      favs = await LetterboxdService.fetchFavorites(lbUsername);
    } catch (e) {
      debugPrint('fetchFavorites error: $e');
    }
    try {
      five = await LetterboxdService.fetchFiveStar(lbUsername);
    } catch (e) {
      debugPrint('fetchFiveStar error: $e');
    }
    try {
      low = await LetterboxdService.fetchDisliked(lbUsername);
    } catch (e) {
      debugPrint('fetchDisliked error: $e');
    }

    try {
      await LetterboxdService.syncFavoritesToFirestore(lbUsername: lbUsername);
    } catch (e) {
      debugPrint('syncFavoritesToFirestore error: $e');
    }
    try {
      await LetterboxdService.syncWatchlistToFirestore(lbUsername: lbUsername);
    } catch (e) {
      debugPrint('syncWatchlistToFirestore error: $e');
    }
    try {
      await LetterboxdService.syncDislikedToFirestore(lbUsername: lbUsername);
    } catch (e) {
      debugPrint('syncDislikedToFirestore error: $e');
    }

    try {
      await _upsertCatalogFromList(favs);
    } catch (_) {}
    try {
      await _upsertCatalogFromList(five);
    } catch (_) {}
    try {
      await _upsertCatalogFromList(low);
    } catch (_) {}

    try {
      final newFavKeys = favs
          .map((e) => e.key)
          .where((k) => k.isNotEmpty)
          .toList();
      final newFiveKeys = five
          .map((e) => e.key)
          .where((k) => k.isNotEmpty)
          .toList();
      final newLowKeys = low
          .map((e) => e.key)
          .where((k) => k.isNotEmpty)
          .toList();

      await userRef.set({
        if (newFavKeys.isNotEmpty) 'favoritesKeys': newFavKeys,
        if (newFiveKeys.isNotEmpty) 'fiveStarKeys': newFiveKeys,
        if (newLowKeys.isNotEmpty) 'dislikedKeys': newLowKeys,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('users mirror arrays error: $e');
    }

    try {
      await _writeTasteProfile(
        uid: uid,
        lbUsername: lbUsername,
        fiveStars: five,
        lowRatings: low,
      );
    } catch (e) {
      debugPrint('writeTasteProfile error: $e');
    }

    try {
     await MatchService.instance.autoCreateMatchesFiveOnly(uid, minCommonFive: 1);
    } catch (e) {
      debugPrint('autoCreateMatchesFiveOnly error: $e');
    }
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _followSub?.cancel();
    _showGuideNotifier.dispose();
    super.dispose();
  }

  String _shownName(User user) {
    final local = (_appUsername ?? '').trim();
    if (local.isNotEmpty) {
      return local; 
    }
    final dn = (user.displayName ?? '').trim();
    if (dn.isNotEmpty) return dn; 
    final email = user.email ?? '';
    return email.contains('@') ? email.split('@').first : 'Kullanıcı';
  }

 Widget _blurBackdrop() {
    const Widget baseBlack = SizedBox.expand(child: ColoredBox(color: Colors.black));

    if (_futureFavs == null) return baseBlack;

    return FutureBuilder<List<LetterboxdFilm>>(
      future: _futureFavs,
      builder: (context, snap) {
        final list = snap.data ?? const <LetterboxdFilm>[];
        final hasPoster = list.isNotEmpty && (list.first.posterUrl).isNotEmpty;
        
        if (!hasPoster) return baseBlack;

        final url = list.first.posterUrl;
        return SizedBox.expand(
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: PosterImage(
                  posterUrl: url,
                  title: list.first.title,
                  fit: BoxFit.cover,
                ),
              ),
              
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xE6000000), 
                      Color(0xCC000000), 
                      Color(0x99000000), 
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
    final sp = await SharedPreferences.getInstance();
    final key = 'lb_cache_${_lbUsername!.toLowerCase()}';
    await sp.remove(key);
    await sp.remove('${key}_time');
    setState(() {
      _futureFavs = LetterboxdService.fetchFavorites(_lbUsername!);
      _futureFiveStar = LetterboxdService.fetchFiveStar(_lbUsername!);
      _futureDisliked = LetterboxdService.fetchDisliked(_lbUsername!);
    });
    _primeShelfCache();
  }

  String _noYear(String t) {
    return t.replaceAll(RegExp(r'\s*\(\d{4}\)$'), '');
  }

  Widget _watchlistSectionFromKeys(List<String> keys, {int maxItems = 30}) {
    void onReturnFromSearch() {
      setState(() {
        _watchlistFutureCache.clear();
      });
    }

    if (keys.isEmpty) {
      return SizedBox(
        height: 180,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 1,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) => AspectRatio(
            aspectRatio: 2 / 3,
            child: _AddPosterTile(
              target: ShelfTarget.watchlist,
              onRefresh: onReturnFromSearch, 
            ),
          ),
        ),
      );
    }

    final limited = keys.take(maxItems).toList();
    final hash = limited.join('|');

    final future = _watchlistFutureCache[hash] ??= Future.wait(
      limited.map((k) async {
        final col = FirebaseFirestore.instance
            .collection('catalog_films')
            .doc(k);
        try {
          final c = await col.get(const GetOptions(source: Source.cache));
          if (c.exists) {
            final data = c.data();
            data?['docId'] = k; // ID EKLENDI
            return data;
          }
        } catch (_) {}
        try {
          final s = await col.get(const GetOptions(source: Source.server));
          if (s.exists) {
            final data = s.data();
            data?['docId'] = k; // ID EKLENDI
            return data;
          }
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
        if (!filmSnap.hasData) {
          return SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 1,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => AspectRatio(
                aspectRatio: 2 / 3,
                child: _AddPosterTile(
                  target: ShelfTarget.watchlist,
                  onRefresh: onReturnFromSearch,
                ),
              ),
            ),
          );
        }
        final films = filmSnap.data!
            .where((m) => m != null)
            .map((m) => m!)
            .toList();

        UserShelfCache.setWatchlistFromMaps(films);

        if (films.isEmpty) {
          return SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 1,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => AspectRatio(
                aspectRatio: 2 / 3,
                child: _AddPosterTile(
                  target: ShelfTarget.watchlist,
                  onRefresh: onReturnFromSearch,
                ),
              ),
            ),
          );
        }

        return SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: films.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              if (i == films.length) {
                return AspectRatio(
                  aspectRatio: 2 / 3,
                  child: _AddPosterTile(
                    target: ShelfTarget.watchlist,
                    onRefresh: onReturnFromSearch,
                  ),
                );
              }
              final film = films[i];
              final poster =
                  (film['poster'] ?? film['posterUrl'] ?? film['image'] ?? '')
                      as String;
              final title = (film['title'] ?? '') as String;
              final docId = (film['docId'] ?? '').toString();

             return GestureDetector(
                onTap: () {
                  if (title.isNotEmpty) {
                    MovieActionHelper.show(
                      context,
                      title: title,
                      posterUrl: poster,
                      docId: docId,
                      target: ShelfTarget.watchlist,
                      onItemDeleted: () {
                        setState(() {
                          _watchlistFutureCache.clear();
                        });
                      },
                    );
                  }
                },
                child: AspectRatio(
                aspectRatio: 2 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      poster.isNotEmpty
                          ? PosterImage(
                              posterUrl: poster,
                              title: title,
                              fit: BoxFit.cover,
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
                ),)
              );
            },
          ),
        );
      },
    );
  }

  Widget _shelfSectionFromUserField(
    String fieldName, {
    int maxItems = 30,
    String emptyText = 'Film bulunamadı.',
  }) {
    void onReturnFromSearch() {
      setState(() {
        _watchlistFutureCache.clear();
      });
    }

    final keys = List<dynamic>.from(
      (_lastUserData?[fieldName] ?? const []),
    ).map((e) => e.toString()).toList();

    final ShelfTarget target = fieldName == 'favoritesKeys'
        ? ShelfTarget.favorites
        : fieldName == 'fiveStarKeys'
        ? ShelfTarget.fiveStar
        : ShelfTarget.disliked;

    if (keys.isEmpty) {
      return SizedBox(
        height: 180,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 1,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) => AspectRatio(
            aspectRatio: 2 / 3,
            child: _AddPosterTile(
              target: target,
              onRefresh: onReturnFromSearch,
            ),
          ),
        ),
      );
    }

    final limited = keys.take(maxItems).toList();
    final hash = '$fieldName:' + limited.join('|');

    final future = _watchlistFutureCache[hash] ??= Future.wait(
      limited.map((k) async {
        final col = FirebaseFirestore.instance
            .collection('catalog_films')
            .doc(k);
        try {
          final c = await col.get(const GetOptions(source: Source.cache));
          if (c.exists) {
            final data = c.data();
            data?['docId'] = k; // ID EKLENDI
            return data;
          }
        } catch (_) {}
        try {
          final s = await col.get(const GetOptions(source: Source.server));
          if (s.exists) {
            final data = s.data();
            data?['docId'] = k; // ID EKLENDI
            return data;
          }
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
        if (!filmSnap.hasData) {
          return SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 1,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => AspectRatio(
                aspectRatio: 2 / 3,
                child: _AddPosterTile(
                  target: target,
                  onRefresh: onReturnFromSearch, 
                ),
              ),
            ),
          );
        }
        final films = filmSnap.data!
            .where((m) => m != null)
            .map((m) => m!)
            .toList();

        if (films.isEmpty) {
          return SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 1,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => AspectRatio(
                aspectRatio: 2 / 3,
                child: _AddPosterTile(
                  target: target,
                  onRefresh: onReturnFromSearch,
                ),
              ),
            ),
          );
        }

        return SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: films.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              if (i == films.length) {
                return AspectRatio(
                  aspectRatio: 2 / 3,
                  child: _AddPosterTile(
                    target: target,
                    onRefresh: onReturnFromSearch, 
                  ),
                );
              }
              final film = films[i];
              final poster =
                  (film['poster'] ?? film['posterUrl'] ?? film['image'] ?? '')
                      as String;
              final title = (film['title'] ?? '') as String;
              final docId = (film['docId'] ?? '').toString();

              return GestureDetector(
                onTap: () {
                  if (title.isNotEmpty) {
                    MovieActionHelper.show(
                      context,
                      title: title,
                      posterUrl: poster,
                      docId: docId,
                      target: target,
                      onItemDeleted: () {
                        setState(() {
                          _watchlistFutureCache.clear();
                        });
                      },
                    );
                  }
                },
                child: AspectRatio(
                aspectRatio: 2 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      poster.isNotEmpty
                          ? PosterImage(
                              posterUrl: poster,
                              title: title,
                              fit: BoxFit.cover,
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
                )
              );
            },
          ),
        );
      },
    );
  }

  // --- BEGIN: Profile & Activities Tabs ---
  // Widget _buildProfileTab(User user) {
  //   // Deprecated/unused: see _buildProfileContentAfterHeader().
  //   // If you want to use it, uncomment and use in TabBarView.
  // }
  /// Builds the Five Star shelf with an "add film" button at the start.
  

  Widget _buildActivitiesTab() {
    return RefreshIndicator(
      onRefresh: () async {
        await _loadActivities();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            children: [
              Text(
                'Aktiviteler',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 10),
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
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color.fromARGB(3, 255, 255, 255),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((a.posterUrl).isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: PosterImage(
                            posterUrl: a.posterUrl,
                            title: a.title,
                            width: 44,
                            height: 66,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _shownName(
                                      FirebaseAuth.instance.currentUser!,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                const SizedBox(width: 8),
                               Text(
                                  ' Paylaştı',
                                style: Theme.of(context).textTheme.labelSmall,
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
                            if (a.text.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Text(
                                  a.text,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Row(
                                children: [
                                  const Icon(Icons.favorite_border, size: 16),
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
    );
  }

  Widget _buildProfileContentAfterHeader() {
    return RefreshIndicator(
      onRefresh: () async {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) await user.reload();
        if (_lbUsername != null && _lbUsername!.isNotEmpty) {
          setState(() {
            _futureFavs = LetterboxdService.fetchFavorites(_lbUsername!);
            _futureFiveStar = LetterboxdService.fetchFiveStar(_lbUsername!);
            _futureDisliked = LetterboxdService.fetchDisliked(_lbUsername!);
          });
        }
        await _bootstrapCounts();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
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
            ),
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final data = _lastUserData ?? const <String, dynamic>{};
              final bio = (data['bio'] ?? '').toString();

              if (bio.isNotEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    bio,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.4, 
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          Builder(
            builder: (context) {
              final data = _lastUserData ?? const <String, dynamic>{};
              final age = data['age'];
              final genres = List<String>.from(data['favGenres'] ?? const []);
              final directors = List<String>.from(
                data['favDirectors'] ?? const [],
              );
              final actors = List<String>.from(data['favActors'] ?? const []);

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
          
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                'Favori Filmler',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            _shelfSectionFromUserField(
              'favoritesKeys',
              emptyText: 'Favori film bulunamadı.',
              maxItems: 30,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 20.0, bottom: 8.0),
              child: Text(
                'Sevdiği Filmler',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            _shelfSectionFromUserField(
              'fiveStarKeys',
              emptyText: '5★ film bulunamadı.',
              maxItems: 30,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 20.0, bottom: 8.0),
              child: Text(
                'Sevmediği Filmler',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            _shelfSectionFromUserField(
              'dislikedKeys',
              emptyText: 'Sevmediği film bulunamadı.',
              maxItems: 30,
            ),
          
          Padding(
            padding: const EdgeInsets.only(top: 20.0, bottom: 8.0),
            child: Text(
              'Watchlist',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          _watchlistSectionFromKeys(
            List<dynamic>.from(
              (_lastUserData?['watchlistKeys'] ?? const []),
            ).map((e) => e.toString()).toList(),
            maxItems: 30,
          ),
        ],
      ),
    );
  }

 @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
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

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            extendBodyBehindAppBar: true,
            body: Stack(
              children: [
                NestedScrollView(
                  headerSliverBuilder: (context, innerBoxIsScrolled) {
                    return [
                      SliverAppBar(
                        floating: true,
                        snap: true,
                        backgroundColor: Colors.black,
                        elevation: 0,
                        scrolledUnderElevation: 0,
                        surfaceTintColor: Colors.transparent,
                        automaticallyImplyLeading: false,
                        actions: [
                          IconButton(
                            tooltip: 'Düzenle',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => EditProfilePage(
                                    initialUserData: _lastUserData,
                                  ),
                                ),
                              );
                            },
                          ),
                          
                          IconButton(
                            tooltip: 'Yenile',
                            icon: const Icon(Icons.refresh),
                            onPressed: () async {
                              await _refreshFavorites();
                              await _loadActivities();
                              await _bootstrapCounts();
                            },
                          ),
                          
                          IconButton(
                            tooltip: 'Ayarlar',
                            icon: const Icon(Icons.settings_outlined),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const SettingsPage(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      SliverToBoxAdapter(
                        child: Stack(
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.28,
                              child: _blurBackdrop(),
                            ),
                            Column(
                              children: [
                                SizedBox(
                                  height:
                                      MediaQuery.of(context).padding.top +
                                      kToolbarHeight,
                                ),
                                _profileHeaderSection(
                                  context: context,
                                  user: user,
                                  followers: _followers,
                                  following: _following,
                                  lbUsername: _lbUsername,
                                  shownName: _shownName,
                                ),
                                const SizedBox(height: 12),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: TabBar(
                                    isScrollable: false,
                                    indicator: UnderlineTabIndicator(
                                      borderSide: BorderSide(
                                        width: 2,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                    ),
                                    indicatorSize: TabBarIndicatorSize.tab,
                                    overlayColor: WidgetStateProperty.all(
                                      Colors.transparent,
                                    ),
                                    labelPadding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                    labelStyle: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                    unselectedLabelStyle: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                    labelColor: Theme.of(context).colorScheme.onSurface,
                                    unselectedLabelColor: Colors.white70,
                                    tabs: const [
                                      Tab(text: 'Filmler'),
                                      Tab(text: 'Aktiviteler'),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ];
                  },
                  body: TabBarView(
                    children: [
                      _buildProfileContentAfterHeader(),
                      _buildActivitiesTab(),
                    ],
                  ),
                ),

                ValueListenableBuilder<bool>(
                  valueListenable: _showGuideNotifier,
                  builder: (context, isVisible, child) {
                    if (!isVisible) return const SizedBox.shrink();
                    
                    return GuideCharacterOverlay(
                      message: "Profilin çok boş görünüyor! Hadi artı butonuna basıp favori filmlerini ekle.",
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
        );
      },
    );
  }
 
}

class _AddPosterTile extends StatelessWidget {
  final ShelfTarget target;
  final VoidCallback? onRefresh; 

  const _AddPosterTile({
    required this.target, 
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SearchMoviePage(target: target)),
        );
        
        if (result == true) {
          onRefresh?.call();
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: Colors.white10, 
          alignment: Alignment.center,
          child: const Icon(Icons.add, size: 40, color: Colors.white70),
        ),
      ),
    );
  }
}

class _AddFilmDialog extends StatefulWidget {
  @override
  State<_AddFilmDialog> createState() => _AddFilmDialogState();
}

class _AddFilmDialogState extends State<_AddFilmDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _submitting = false;
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Yeni Film Ekle'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Film adı'),
        onSubmitted: _submit,
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : () => _submit(_controller.text),
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Ekle'),
        ),
      ],
    );
  }

  void _submit(String value) async {
    final filmName = value.trim();
    if (filmName.isEmpty) return;
    setState(() => _submitting = true);
    await Future.delayed(const Duration(milliseconds: 200));
    Navigator.of(context).pop(filmName);
  }
}