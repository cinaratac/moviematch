import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/screens/actors_screen.dart';
import 'package:fluttergirdi/widgets/green_characters.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluttergirdi/services/catalog_service.dart';
import 'package:fluttergirdi/services/letterboxd_service.dart';
import 'package:fluttergirdi/screens/full_shelf_screen.dart';
import 'dart:async';
import 'package:fluttergirdi/services/streak_service.dart'; // STREAK SERVISI
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttergirdi/screens/director_screen.dart';
import 'package:fluttergirdi/screens/edit_profile_page.dart';
import 'package:fluttergirdi/screens/settings_page.dart';
import 'package:fluttergirdi/services/follow_system_service.dart';
import 'package:fluttergirdi/screens/search_movie.dart';
import 'package:fluttergirdi/models/shelf_target.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';
import 'package:fluttergirdi/widgets/movie_action_helper.dart';
import 'package:fluttergirdi/widgets/follow_user_list_dialog.dart';
import 'package:fluttergirdi/widgets/recent_watched_movies.dart';
import 'package:fluttergirdi/screens/post_detail_screen.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';

import 'package:fluttergirdi/services/custom_list_service.dart';
import 'package:fluttergirdi/models/custom_list.dart';
import 'package:fluttergirdi/screens/custom_list_detail_screen.dart';
import 'package:fluttergirdi/services/global_data_service.dart';
import 'package:fluttergirdi/models/gamification.dart';
import 'package:fluttergirdi/services/gamification_service.dart';

// --- MODEL SINIFLARI ---

class UserShelfCache {
  static List<Map<String, String>> favorites = [];
  static List<Map<String, String>> fiveStar = [];
  static List<Map<String, String>> disliked = [];
  static List<Map<String, String>> watchlist = [];

  static void setFavorites(List<LetterboxdFilm> items) {
    favorites = items
        .map((e) => {'title': e.title, 'poster': e.posterUrl})
        .toList();
  }

  static void setFiveStar(List<LetterboxdFilm> items) {
    fiveStar = items
        .map((e) => {'title': e.title, 'poster': e.posterUrl})
        .toList();
  }

  static void setDisliked(List<LetterboxdFilm> items) {
    disliked = items
        .map((e) => {'title': e.title, 'poster': e.posterUrl})
        .toList();
  }

  static List<Map<String, String>> _mapsFromFilmDocs(
    List<Map<String, dynamic>> items,
  ) {
    return items
        .map(
          (m) => {
            'title': (m['title'] ?? '').toString(),
            'poster': (m['poster'] ?? m['posterUrl'] ?? m['image'] ?? '')
                .toString(),
          },
        )
        .toList();
  }

  static void setShelfFromMaps(
    ShelfTarget target,
    List<Map<String, dynamic>> items,
  ) {
    final mapped = _mapsFromFilmDocs(items);
    switch (target) {
      case ShelfTarget.favorites:
        favorites = mapped;
        break;
      case ShelfTarget.fiveStar:
        fiveStar = mapped;
        break;
      case ShelfTarget.disliked:
        disliked = mapped;
        break;
      case ShelfTarget.watchlist:
        watchlist = mapped;
        break;
    }
  }

  static void setWatchlistFromMaps(List<Map<String, dynamic>> items) {
    watchlist = _mapsFromFilmDocs(items);
  }

  static void clear() {
    favorites = [];
    fiveStar = [];
    disliked = [];
    watchlist = [];
  }
}

class _ActivityItemData {
  final String id;
  final String text;
  final DateTime? createdAt;
  final String posterUrl;
  final String title;
  final int likeCount;
  final int replyCount;
  final int? tmdbId;

  const _ActivityItemData({
    required this.id,
    required this.text,
    required this.createdAt,
    this.posterUrl = '',
    this.title = '',
    this.likeCount = 0,
    this.replyCount = 0,
    this.tmdbId,
  });
}

// --- WIDGETLAR ---

class _CountPill extends StatelessWidget {
  final String label;
  final int value;
  final VoidCallback? onTap;

  const _CountPill({required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Açık temada siyah, koyu temada beyaz yazı
    final textColor = isDark ? Colors.white : Colors.black87;
    // Açık temada gri çerçeve, koyu temada beyazımsı çerçeve
    final borderColor = isDark ? Colors.white24 : Colors.black12;
    // Açık temada çok hafif siyah dolgu, koyu temada çok hafif beyaz dolgu
    final bgColor = isDark ? Colors.white10 : Colors.black.withOpacity(0.05);

    final textStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: textColor,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Text('$label: $value', style: textStyle),
      ),
    );
  }
}

Widget _profileHeaderSection({
  required BuildContext context,
  required User user,
  required int? followers,
  required int? following,
  required String? lbUsername,
  required String Function(User) shownName,
}) {
  void showEnlargedImage(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (ctx) {
        return GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: InteractiveViewer(
            child: Center(child: Image.network(imageUrl, fit: BoxFit.contain)),
          ),
        );
      },
    );
  }

  final isDark = Theme.of(context).brightness == Brightness.dark;
  void showUserList(String title, String collection) {
    showDialog(
      context: context,
      builder: (_) => FollowUserListDialog(
        title: title,
        uid: user.uid,
        collection: collection,
        onOpenProfile: (uid) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: uid)),
          );
        },
      ),
    );
  }

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => showEnlargedImage(user.photoURL),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF2E7D32),
                width: 2,
              ), // Yeşil çerçeve
            ),
            child: CircleAvatar(
              radius: 36,
              backgroundImage:
                  user.photoURL != null && user.photoURL!.isNotEmpty
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
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                shownName(user),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: isDark
                      ? const Color.fromARGB(255, 255, 255, 255)
                      : const Color.fromARGB(255, 0, 0, 0),
                  fontWeight: FontWeight.w600,
                  shadows: [
                    Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 4),
                  ],
                ),
                overflow: TextOverflow.ellipsis,
              ),

              // --- ROZET VE STREAK ALANI ---
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData || !snap.data!.exists)
                    return const SizedBox.shrink();
                  final userData = snap.data!.data() as Map<String, dynamic>?;
                  final badges = List<String>.from(userData?['badges'] ?? []);
                  // DÜZELTME BURADA: 'currentStreak' yerine 'streakCount' yazıldı
                  final int streakCount =
                      (userData?['streakCount'] ?? 0) as int;

                  if (badges.isEmpty && streakCount <= 0)
                    return const SizedBox.shrink();

                  return Padding(
                    padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // STREAK (SERİ) ATEŞİ
                        if (streakCount > 0)
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.orangeAccent,
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.orange.withOpacity(0.1),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.local_fire_department_rounded,
                                  color: Colors.orangeAccent,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$streakCount Gün Serisi',
                                  style: const TextStyle(
                                    color: Colors.orangeAccent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // MEVCUT ROZETLER
                        if (badges.isNotEmpty)
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: badges.map((badgeId) {
                              final badge = AppBadge.allBadges.firstWhere(
                                (b) => b.id == badgeId,
                                orElse: () => AppBadge.allBadges.first,
                              );
                              return Tooltip(
                                message: '${badge.name}: ${badge.description}',
                                triggerMode: TooltipTriggerMode.tap,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: badge.color.withOpacity(0.15),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: badge.color.withOpacity(0.6),
                                      width: 1,
                                    ),
                                  ),
                                  child: Icon(
                                    badge.icon,
                                    size: 12,
                                    color: badge.color,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 6),
              (followers == null || following == null)
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _CountPill(
                          label: 'Takipçi',
                          value: followers,
                          onTap: () => showUserList('Takipçiler', 'followers'),
                        ),
                        _CountPill(
                          label: 'Takip',
                          value: following,
                          onTap: () =>
                              showUserList('Takip Edilenler', 'following'),
                        ),
                      ],
                    ),
              const SizedBox(height: 5),
              if (lbUsername != null && lbUsername.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Letterboxd: @$lbUsername',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                      shadows: [
                        Shadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 2,
                        ),
                      ],
                    ),
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

  final Map<String, Future<List<Map<String, dynamic>?>>> _watchlistFutureCache =
      {};

  int? _followersCount;
  int? _followingCount;
  StreamSubscription<FollowEvent>? _followSub;
  final ValueNotifier<bool> _showGuideNotifier = ValueNotifier<bool>(false);

  late Stream<User?> _userStream;

  @override
  void initState() {
    super.initState();
    _userStream = FirebaseAuth.instance.userChanges();

    UserShelfCache.clear();
    _loadPrefs();
    _bindLbFromFirestore();
    _bootstrapCounts();
  }

  Future<void> _bootstrapCounts() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final svc = FollowSystemService.I;
    try {
      final f1 = await svc.fetchFollowerCountOnce(uid);
      final f2 = await svc.fetchFollowingCountOnce(uid);

      if (mounted) {
        setState(() {
          _followersCount = f1;
          _followingCount = f2;
        });
      }

      final int? currentStoredFollowers = _lastUserData?['followersCount'];
      final int? currentStoredFollowing = _lastUserData?['followingCount'];

      if (f1 != currentStoredFollowers || f2 != currentStoredFollowing) {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'followersCount': f1,
          'followingCount': f2,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {}

    _followSub?.cancel();
    _followSub = svc.events.listen((e) {
      if (!mounted) return;
      if (e.targetUid == uid) {
        setState(
          () =>
              _followersCount = (_followersCount ?? 0) + (e.followed ? 1 : -1),
        );
      }
      if (e.actorUid == uid) {
        setState(
          () =>
              _followingCount = (_followingCount ?? 0) + (e.followed ? 1 : -1),
        );
      }
    });
    final prefs = await SharedPreferences.getInstance();
    final lastCheck = prefs.getString('last_badge_check') ?? '';
    final today = DateTime.now().toIso8601String().substring(0, 10);

    if (lastCheck != today) {
      await GamificationService.instance.checkAndAwardBadges();
      await prefs.setString('last_badge_check', today);
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

  void _checkGuideVisibility() {
    if (!mounted) return;
    final favKeys = _lastUserData?['favoritesKeys'];
    final hasFirestoreFavs = (favKeys is List && favKeys.isNotEmpty);
    final fiveStarKeys = _lastUserData?['fiveStarKeys'];
    final hasFirestoreFiveStar =
        (fiveStarKeys is List && fiveStarKeys.isNotEmpty);

    final hasCacheFavs = UserShelfCache.favorites.isNotEmpty;
    final hasCacheFiveStar = UserShelfCache.fiveStar.isNotEmpty;

    if (hasFirestoreFavs ||
        hasCacheFavs ||
        hasFirestoreFiveStar ||
        hasCacheFiveStar) {
      _showGuideNotifier.value = false;
    } else {
      _showGuideNotifier.value = true;
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
    });
    _checkGuideVisibility();
    _forceWriteLbUsernameIfMissing();
  }

  void _bindLbFromFirestore() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    void updateProfileState(Map<String, dynamic> data) {
      if (mounted) {
        setState(() {
          _lastUserData = Map<String, dynamic>.from(data);
          final lb = (data['letterboxdUsername'] ?? '').toString().trim();
          final appU =
              (data['displayName'] ??
                      data['username'] ??
                      data['handle'] ??
                      data['appUsername'] ??
                      '')
                  .toString()
                  .trim();
          if (appU.isNotEmpty && appU != (_appUsername ?? '')) {
            _appUsername = appU;
          }
          if (lb.isNotEmpty && lb != _lbUsername) {
            _lbUsername = lb;
          }
        });
      }
      _checkGuideVisibility();
    }

    // --- KESİN ÇÖZÜM: ARKAPLANDA İNEN VERİ VARSA ANINDA GÖSTER ---
    if (GlobalDataService.instance.myProfileData != null) {
      updateProfileState(GlobalDataService.instance.myProfileData!);
    }

    _userSub?.cancel();
    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) async {
          if (!snap.exists) return;
          updateProfileState(snap.data() ?? const {});
        });
  }

  String _noYear(String t) => t.replaceAll(RegExp(r'\s*\(\d{4}\)$'), '');

  int? _extractTmdbId(Map<String, dynamic> m) {
    final val = m['tmdbId'];
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val);
    return null;
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _followSub?.cancel();
    _showGuideNotifier.dispose();
    UserShelfCache.clear();
    _userSub?.cancel();
    super.dispose();
  }

  String _shownName(User user) {
    final local = (_appUsername ?? '').trim();
    if (local.isNotEmpty) return local;
    final dn = (user.displayName ?? '').trim();
    if (dn.isNotEmpty) return dn;
    final email = user.email ?? '';
    return email.contains('@') ? email.split('@').first : 'Kullanıcı';
  }

  Widget _watchlistSectionFromKeys(List<String> keys, {int maxItems = 30}) {
    void onReturnFromSearch() {
      setState(() => _watchlistFutureCache.clear());
    }

    if (keys.isEmpty) {
      return SizedBox(
        height: 140,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: _AddPosterTile(
                  target: ShelfTarget.watchlist,
                  onRefresh: onReturnFromSearch,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final limited = keys.take(maxItems).toList();
    final hash = limited.join('|');
    final future = _watchlistFutureCache[hash] ??= CatalogService()
        .getFilmsByKeys(limited)
        .then(
          (films) => films.map<Map<String, dynamic>?>((film) => film).toList(),
        );
    return FutureBuilder<List<Map<String, dynamic>?>>(
      future: future,
      builder: (context, filmSnap) {
        if (filmSnap.connectionState == ConnectionState.waiting &&
            !(filmSnap.hasData && (filmSnap.data?.isNotEmpty ?? false))) {
          return const SizedBox(
            height: 140,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        // EKSİK OLAN SATIRLAR BURADAYDI (films değişkeni tanımlanıyor)
        final films = (filmSnap.data ?? [])
            .where((m) => m != null)
            .map((m) => m!)
            .toList();
        UserShelfCache.setWatchlistFromMaps(films);

        return SizedBox(
          height: 140,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < films.length; i++) ...[
                  Builder(
                    builder: (context) {
                      final film = films[i];
                      final poster =
                          (film['poster'] ??
                                  film['posterUrl'] ??
                                  film['image'] ??
                                  '')
                              .toString();
                      final title = (film['title'] ?? '') as String;
                      final docId = (film['docId'] ?? '').toString();
                      final tmdbId = _extractTmdbId(film);

                      return GestureDetector(
                        onTap: () {
                          if (title.isNotEmpty) {
                            MovieActionHelper.show(
                              context,
                              title: title,
                              posterUrl: poster,
                              docId: docId,
                              tmdbId: tmdbId,
                              target: ShelfTarget.watchlist,
                              onItemDeleted: () =>
                                  setState(() => _watchlistFutureCache.clear()),
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
                                PosterImage(
                                  posterUrl: poster,
                                  title: title,
                                  tmdbId: tmdbId,
                                  fit: BoxFit.cover,
                                ),
                                if (title.isNotEmpty)
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 4,
                                      ),
                                      color: Colors.black54,
                                      width: double.infinity,
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
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                ],
                // Ekleme Butonu
                AspectRatio(
                  aspectRatio: 2 / 3,
                  child: _AddPosterTile(
                    target: ShelfTarget.watchlist,
                    onRefresh: onReturnFromSearch,
                  ),
                ),
              ],
            ),
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
      setState(() => _watchlistFutureCache.clear());
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
        height: 140,
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
    final future = _watchlistFutureCache[hash] ??= CatalogService()
        .getFilmsByKeys(limited)
        .then(
          (films) => films.map<Map<String, dynamic>?>((film) => film).toList(),
        );
    return FutureBuilder<List<Map<String, dynamic>?>>(
      future: future,
      builder: (context, filmSnap) {
        if (filmSnap.connectionState == ConnectionState.waiting &&
            !(filmSnap.hasData && (filmSnap.data?.isNotEmpty ?? false))) {
          return const SizedBox(
            height: 140,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final films = (filmSnap.data ?? [])
            .where((m) => m != null)
            .map((m) => m!)
            .toList();
        UserShelfCache.setShelfFromMaps(target, films);
        return SizedBox(
          height: 140,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: films.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              if (i == films.length)
                return AspectRatio(
                  aspectRatio: 2 / 3,
                  child: _AddPosterTile(
                    target: target,
                    onRefresh: onReturnFromSearch,
                  ),
                );
              final film = films[i];
              final poster =
                  (film['poster'] ?? film['posterUrl'] ?? film['image'] ?? '')
                      .toString();
              final title = (film['title'] ?? '') as String;
              final docId = (film['docId'] ?? '').toString();
              final tmdbId = _extractTmdbId(film);

              return GestureDetector(
                onTap: () {
                  if (title.isNotEmpty)
                    MovieActionHelper.show(
                      context,
                      title: title,
                      posterUrl: poster,
                      docId: docId,
                      tmdbId: tmdbId, // <-- TMDB ID BURAYA EKLENDİ
                      target: target,
                      onItemDeleted: () =>
                          setState(() => _watchlistFutureCache.clear()),
                    );
                },
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        PosterImage(
                          posterUrl: poster,
                          title: title,
                          tmdbId: tmdbId,
                          fit: BoxFit.cover,
                        ),
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
                ),
              );
            },
          ),
        );
      },
    );
  }

  // --- 1. SEKME: FİLMLER ---

  Widget _buildSectionHeader(
    String title,
    List<String> keys,
    ShelfTarget target,
  ) {
    // target eklendi
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return Padding(
      padding: const EdgeInsets.only(top: 20.0, bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          if (keys.isNotEmpty)
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FullShelfScreen(
                      title: title,
                      filmKeys: keys,
                      target: target,
                    ),
                  ),
                );
              },
              child: const Text(
                'Tümü',
                style: TextStyle(
                  color: Color(0xFF2E7D32),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProfileContentAfterHeader() {
    final favKeys = List<String>.from(
      (_lastUserData?['favoritesKeys'] ?? []).map((e) => e.toString()),
    );
    final fiveStarKeys = List<String>.from(
      (_lastUserData?['fiveStarKeys'] ?? []).map((e) => e.toString()),
    );
    final dislikedKeys = List<String>.from(
      (_lastUserData?['dislikedKeys'] ?? []).map((e) => e.toString()),
    );
    final watchlistKeys = List<String>.from(
      (_lastUserData?['watchlistKeys'] ?? []).map((e) => e.toString()),
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (_lbUsername == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              children: [
                Icon(Icons.alternate_email, color: textColor),
                const SizedBox(width: 8),
                Text(
                  'Letterboxd bağlı değil',
                  style: TextStyle(color: textColor),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Builder(
          builder: (context) {
            final bio = (_lastUserData?['bio'] ?? '').toString();
            if (bio.isNotEmpty)
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  bio,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.4,
                    color: textColor,
                  ),
                ),
              );
            return const SizedBox.shrink();
          },
        ),
        Builder(
          builder: (context) {
            final age = _lastUserData?['age'];
            final genres = List<dynamic>.from(
              _lastUserData?['favGenres'] ?? [],
            );
            final dirs = List<dynamic>.from(
              _lastUserData?['favDirectors'] ?? [],
            );
            // Burayı List<dynamic> yapıyoruz çünkü hem String hem Map gelebilir
            final acts = List<dynamic>.from(_lastUserData?['favActors'] ?? []);

            if ((age == null || age <= 0) &&
                genres.isEmpty &&
                dirs.isEmpty &&
                acts.isEmpty)
              return const SizedBox.shrink();

            // EKLENDİ: isDirector parametresi
            Widget cw(
              String t,
              List<dynamic> i, {
              bool isActor = false,
              bool isDirector = false,
            }) {
              if (i.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t,
                      style: Theme.of(
                        context,
                      ).textTheme.titleSmall?.copyWith(color: textColor),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: i.map((item) {
                        String name;
                        int id = 0;
                        if (item is Map) {
                          name = item['name'] ?? '';
                          id = item['id'] ?? 0;
                        } else {
                          name = item.toString();
                        }

                        return ActionChip(
                          label: Text(
                            name,
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: isDark
                              ? Colors.grey[800]
                              : Colors.grey[200],
                          side: BorderSide.none,
                          padding: EdgeInsets.zero,
                          // EKLENDİ: Yönetmen ekranı yönlendirmesi
                          onPressed: isActor
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ActorScreen(
                                        actorId: id,
                                        actorName: name,
                                      ),
                                    ),
                                  );
                                }
                              : isDirector
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DirectorScreen(
                                        directorId: id,
                                        directorName: name,
                                      ),
                                    ),
                                  );
                                }
                              : null,
                        );
                      }).toList(),
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
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Icon(Icons.cake, size: 18, color: textColor),
                        const SizedBox(width: 6),
                        Text('Yaş: $age', style: TextStyle(color: textColor)),
                      ],
                    ),
                  ),
                cw('Sevdiğin türler', genres),
                cw('Sevdiğin yönetmenler', dirs, isDirector: true),
                cw('Sevdiğin oyuncular', acts, isActor: true),
              ],
            );
          },
        ),
        RecentWatchedMovies(
          uid: FirebaseAuth.instance.currentUser?.uid ?? '',
          fallbackMovieKeys: [...fiveStarKeys, ...favKeys, ...dislikedKeys],
        ),

        const SizedBox(height: 16),

        // --- BÖLÜMLER ---
        _buildSectionHeader(
          'Favori Filmler',
          favKeys,
          ShelfTarget.favorites,
        ), // ShelfTarget.favorites eklendi
        _shelfSectionFromUserField(
          'favoritesKeys',
          emptyText: 'Favori film bulunamadı.',
          maxItems: 20,
        ),

        // Sevdiği Filmler
        _buildSectionHeader(
          'Sevdiği Filmler',
          fiveStarKeys,
          ShelfTarget.fiveStar,
        ), // ShelfTarget.fiveStar eklendi
        _shelfSectionFromUserField(
          'fiveStarKeys',
          emptyText: '5★ film bulunamadı.',
          maxItems: 20,
        ),

        // Sevmediği Filmler
        _buildSectionHeader(
          'Sevmediği Filmler',
          dislikedKeys,
          ShelfTarget.disliked,
        ), // ShelfTarget.disliked eklendi
        _shelfSectionFromUserField(
          'dislikedKeys',
          emptyText: 'Sevmediği film bulunamadı.',
          maxItems: 20,
        ),

        // Watchlist
        _buildSectionHeader(
          'Watchlist',
          watchlistKeys,
          ShelfTarget.watchlist,
        ), // ShelfTarget.watchlist eklendi
        _watchlistSectionFromKeys(watchlistKeys, maxItems: 20),

        const SizedBox(height: 52),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // --- TEMA VE RENKLER ---
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryGreen = const Color(0xFF2E7D32);
    final bgGradientStart = isDark
        ? const Color(0xFF0D2410)
        : const Color(0xFFE8F5E9);
    final bgGradientEnd = isDark ? const Color(0xFF000000) : Colors.white;

    return StreamBuilder<User?>(
      stream: _userStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [bgGradientStart, bgGradientEnd],
                ),
              ),
              child: const Center(
                child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
              ),
            ),
          );
        }
        final user = snap.data;
        if (user == null)
          return const Scaffold(body: Center(child: Text('Oturum açılmadı')));

        return DefaultTabController(
          length: 3,
          child: Scaffold(
            extendBodyBehindAppBar: true,
            // Gradient Arka Planı
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [bgGradientStart, bgGradientEnd],
                  stops: const [0.0, 0.4],
                ),
              ),
              child: Stack(
                children: [
                  NestedScrollView(
                    headerSliverBuilder: (context, innerBoxIsScrolled) {
                      return [
                        SliverAppBar(
                          floating: true,
                          snap: true,
                          backgroundColor:
                              Colors.transparent, // Gradient görünsün
                          elevation: 0,
                          scrolledUnderElevation: 0,
                          surfaceTintColor: Colors.transparent,
                          automaticallyImplyLeading: false,
                          actions: [
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),

                              child: IconButton(
                                tooltip: 'Düzenle',
                                icon: Icon(
                                  Icons.edit_outlined,
                                  color: isDark
                                      ? const Color.fromARGB(255, 255, 255, 255)
                                      : const Color.fromARGB(255, 0, 0, 0),
                                ),
                                onPressed: () async {
                                  final bool? result =
                                      await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => EditProfilePage(
                                            initialUserData: _lastUserData,
                                          ),
                                        ),
                                      );

                                  if (result == true && mounted) {
                                    setState(() {});

                                    final uid =
                                        FirebaseAuth.instance.currentUser?.uid;
                                    if (uid != null) {
                                      try {
                                        final doc = await FirebaseFirestore
                                            .instance
                                            .collection('users')
                                            .doc(uid)
                                            .get();
                                        if (doc.exists && mounted) {
                                          final data = doc.data()!;
                                          setState(() {
                                            _lastUserData = data;
                                            _appUsername =
                                                (data['displayName'] ??
                                                        data['username'] ??
                                                        '')
                                                    .toString();
                                            _lbUsername =
                                                (data['letterboxdUsername'] ??
                                                        '')
                                                    .toString();
                                          });
                                        }
                                      } catch (_) {}
                                    }
                                  }
                                },
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.only(right: 12, left: 4),

                              child: IconButton(
                                tooltip: 'Ayarlar',
                                icon: Icon(
                                  Icons.settings_outlined,
                                  color: isDark
                                      ? const Color.fromARGB(255, 255, 255, 255)
                                      : const Color.fromARGB(255, 0, 0, 0),
                                ),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const SettingsPage(),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        SliverToBoxAdapter(
                          child: Stack(
                            children: [
                              Column(
                                children: [
                                  _profileHeaderSection(
                                    context: context,
                                    user: user,
                                    followers: _followersCount,
                                    following: _followingCount,
                                    lbUsername: _lbUsername,
                                    shownName: _shownName,
                                  ),
                                  const SizedBox(height: 35),
                                  // Tab Bar
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Container(
                                      height: 40, // Yükseklik sınırlandırıldı
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.black45
                                            : Colors.white.withOpacity(0.5),
                                        borderRadius: BorderRadius.circular(
                                          20,
                                        ), // Daha oval köşeler
                                      ),
                                      child: TabBar(
                                        isScrollable: false,
                                        indicator: BoxDecoration(
                                          color: primaryGreen,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: primaryGreen.withOpacity(
                                                0.4,
                                              ),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        indicatorSize: TabBarIndicatorSize.tab,
                                        dividerColor: Colors.transparent,
                                        labelPadding: EdgeInsets
                                            .zero, // İç boşluk sıfırlandı
                                        labelStyle: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ), // Yazı boyutu dengelendi
                                        unselectedLabelStyle: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 13,
                                        ),
                                        labelColor: Colors.white,
                                        unselectedLabelColor: isDark
                                            ? Colors.white60
                                            : Colors.black54,
                                        overlayColor: WidgetStateProperty.all(
                                          Colors.transparent,
                                        ),
                                        tabs: const [
                                          Tab(text: 'Filmler', height: 40),
                                          Tab(text: 'Aktiviteler', height: 40),
                                          Tab(text: 'Listeler', height: 40),
                                        ],
                                      ),
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
                        _ActivitiesTab(uid: user.uid),
                        _ListsTab(uid: user.uid),
                      ],
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: _showGuideNotifier,
                    builder: (context, isVisible, child) {
                      if (!isVisible) return const SizedBox.shrink();
                      return GuideCharacterOverlay(
                        message:
                            "Profilin çok boş görünüyor! Hadi artı butonuna basıp favori filmlerini ekle.",
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
      },
    );
  }
}

// --- 2. SEKME: AKTİVİTELER ---
class _ActivitiesTab extends StatefulWidget {
  final String uid;
  const _ActivitiesTab({required this.uid});

  @override
  State<_ActivitiesTab> createState() => _ActivitiesTabState();
}

class _ActivitiesTabState extends State<_ActivitiesTab>
    with AutomaticKeepAliveClientMixin {
  bool _loadingActivities = false;
  List<_ActivityItemData> _activities = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (mounted) setState(() => _loadingActivities = true);
    final db = FirebaseFirestore.instance;
    final List<_ActivityItemData> items = [];
    try {
      final q = db
          .collection('posts')
          .where('authorId', isEqualTo: widget.uid)
          .orderBy('createdAt', descending: true)
          .limit(30);
      final qs = await q.get();
      for (final d in qs.docs) {
        final m = d.data();
        final ts = m['createdAt'];
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
        final tmdbId =
            (m['movie'] is Map ? m['movie']['id'] : null) ?? m['tmdbId'];

        items.add(
          _ActivityItemData(
            id: d.id,
            text: (m['text'] ?? '').toString(),
            createdAt: ts is Timestamp ? ts.toDate() : null,
            posterUrl: poster,
            title: title,
            likeCount: ((m['likeCount'] ?? 0) as num).toInt(),
            replyCount: ((m['replyCount'] ?? 0) as num).toInt(),
            tmdbId: (tmdbId is int) ? tmdbId : null,
          ),
        );
      }
    } catch (_) {}
    items.sort(
      (a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
        a.createdAt?.millisecondsSinceEpoch ?? 0,
      ),
    );
    if (mounted) {
      setState(() {
        _activities = items;
        _loadingActivities = false;
      });
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}g';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(
          children: [
            Text(
              'Aktiviteler',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.bold,
              ),
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Henüz aktivite yok.',
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
            ),
          )
        else
          ListView.separated(
            itemCount: _activities.length,
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            separatorBuilder: (_, __) =>
                const SizedBox(height: 12), // Kartlar arası boşluk
            itemBuilder: (context, i) {
              final a = _activities[i];
              final when = a.createdAt;
              String timeLabel = '';
              if (when != null) timeLabel = _timeAgo(when);
              return _ActivityWidget(item: a, timeLabel: timeLabel);
            },
          ),
      ],
    );
  }
}

class _ActivityWidget extends StatelessWidget {
  final _ActivityItemData item;
  final String timeLabel;
  const _ActivityWidget({required this.item, required this.timeLabel});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PostDetailScreen(postId: item.id)),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((item.posterUrl).isNotEmpty || item.tmdbId != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: PosterImage(
                  posterUrl: item.posterUrl,
                  title: item.title,
                  tmdbId: item.tmdbId,
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
                          FirebaseAuth.instance.currentUser?.displayName ??
                              'Kullanıcı',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: textColor,
                              ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Paylaştı',
                        style: TextStyle(fontSize: 12, color: subTextColor),
                      ),
                      if (timeLabel.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          '• $timeLabel',
                          style: TextStyle(fontSize: 12, color: subTextColor),
                        ),
                      ],
                    ],
                  ),
                  if (item.text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        item.text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: textColor),
                      ),
                    ),
                  if (item.title.isNotEmpty &&
                      item.posterUrl.isEmpty &&
                      item.tmdbId == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.local_movies,
                            size: 16,
                            color: subTextColor,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: subTextColor,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.favorite_border,
                          size: 16,
                          color: subTextColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${item.likeCount}',
                          style: TextStyle(fontSize: 12, color: subTextColor),
                        ),
                        const SizedBox(width: 16),
                        Icon(
                          Icons.mode_comment_outlined,
                          size: 16,
                          color: subTextColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${item.replyCount}',
                          style: TextStyle(fontSize: 12, color: subTextColor),
                        ),
                        const SizedBox(width: 16),
                        Icon(Icons.repeat, size: 16, color: subTextColor),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- 3. SEKME: LİSTELER ---
class _ListsTab extends StatefulWidget {
  final String uid;
  const _ListsTab({required this.uid});

  @override
  State<_ListsTab> createState() => _ListsTabState();
}

class _ListsTabState extends State<_ListsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return const SizedBox.shrink();

    // Bu profile bakan kişi, profilin sahibi mi?
    final isMe = widget.uid == currentUid;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ==========================================
          // 1. BÖLÜM: KENDİ OLUŞTURDUĞU LİSTELER
          // ==========================================
          StreamBuilder<List<CustomList>>(
            stream: CustomListService.instance.getUserLists(widget.uid),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final lists = snapshot.data ?? [];

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // En üstte "Yeni Liste Oluştur" butonu (Sadece kendi profilinde)
                  if (isMe)
                    _CreateListTile(
                      onTap: () => _showCreateListDialog(context),
                    ),

                  // Eğer hiç listesi yoksa
                  if (lists.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          isMe
                              ? "Henüz liste oluşturmadın."
                              : "Kullanıcı henüz liste oluşturmamış.",
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ),
                    )
                  // Listeler varsa göster
                  else
                    ListView.builder(
                      shrinkWrap:
                          true, // Listenin sayfa içinde taşmaması için kritik
                      physics:
                          const NeverScrollableScrollPhysics(), // Kaydırmayı ana sayfaya devreder
                      padding: EdgeInsets.zero,
                      itemCount: lists.length,
                      itemBuilder: (context, index) {
                        return _CustomListCard(
                          list: lists[index],
                          isMine: isMe,
                        );
                      },
                    ),
                ],
              );
            },
          ),

          // ==========================================
          // 2. BÖLÜM: KAYDEDİLENLER (SADECE KENDİ PROFİLİNDEYSE GÖZÜKÜR)
          // ==========================================
          if (isMe) ...[
            const SizedBox(height: 24),
            // Ufak "Kaydedilenler" Başlığı
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 12),
              child: Text(
                "Kaydedilenler",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
            ),

            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(widget.uid)
                  .collection('saved_lists')
                  .orderBy('savedAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text(
                        "Henüz kaydedilmiş listen yok.",
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap:
                      true, // Listenin sayfa içinde taşmaması için kritik
                  physics:
                      const NeverScrollableScrollPhysics(), // Kaydırmayı ana sayfaya devreder
                  padding: EdgeInsets.zero,
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;

                    final customList = CustomList(
                      id: data['listId'],
                      ownerId: data['ownerId'] ?? '',
                      ownerName: data['ownerName'] ?? 'Bilinmiyor',
                      title: data['title'] ?? 'İsimsiz',
                      description: data['description'] ?? '',
                      coverImageUrl: data['coverImageUrl'],
                      isPublic: data['isPublic'] ?? true,
                      movieCount: data['movieCount'] ?? 0,
                      createdAt: DateTime.now(),
                    );

                    return _CustomListCard(list: customList, isMine: false);
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  void _showCreateListDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    bool isPublic = true;
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Yeni Liste Oluştur",
                style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: "Liste Adı",
                  hintText: "Örn: En İyi Korku Filmleri",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.format_list_bulleted),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descCtrl,
                decoration: InputDecoration(
                  labelText: "Açıklama (İsteğe bağlı)",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.description_outlined),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text("Herkese Açık"),
                subtitle: Text(
                  isPublic
                      ? "Herkes profilinizde görebilir"
                      : "Sadece siz görebilirsiniz",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                value: isPublic,
                contentPadding: EdgeInsets.zero,
                activeColor: Theme.of(ctx).colorScheme.primary,
                onChanged: (val) => setSheetState(() => isPublic = val),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          final title = titleCtrl.text.trim();
                          if (title.isEmpty) return;
                          setSheetState(() => isLoading = true);
                          try {
                            await CustomListService.instance.createList(
                              title,
                              descCtrl.text.trim(),
                              isPublic: isPublic,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                          } catch (e) {
                          } finally {
                            if (ctx.mounted)
                              setSheetState(() => isLoading = false);
                          }
                        },
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: const Color(0xFF2E7D32),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          "Oluştur",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateListTile extends StatelessWidget {
  final VoidCallback onTap;
  const _CreateListTile({required this.onTap});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryGreen = const Color(0xFF2E7D32);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: primaryGreen.withOpacity(0.5), width: 1.5),
          borderRadius: BorderRadius.circular(12),
          color: isDark
              ? primaryGreen.withOpacity(0.1)
              : Colors.white.withOpacity(0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, color: primaryGreen),
            const SizedBox(width: 8),
            Text(
              "Yeni Liste Oluştur",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: primaryGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomListCard extends StatelessWidget {
  final CustomList list;
  final bool isMine;
  const _CustomListCard({required this.list, this.isMine = false});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                CustomListDetailScreen(list: list, isMyList: isMine),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 100,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(12),
              ),
              child: SizedBox(
                width: 70,
                height: double.infinity,
                child: list.coverImageUrl != null
                    ? PosterImage(
                        posterUrl: list.coverImageUrl!,
                        title: list.title,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: Colors.grey.shade800,
                        child: const Icon(Icons.list, color: Colors.white24),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    list.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${list.movieCount} film',
                    style: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                  if (!list.isPublic)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(Icons.lock, size: 12, color: Colors.grey),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

class _AddPosterTile extends StatelessWidget {
  final ShelfTarget target;
  final VoidCallback? onRefresh;
  const _AddPosterTile({required this.target, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryGreen = const Color(0xFF2E7D32);

    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SearchMoviePage(target: target)),
        );
        // Arama ekranından başarıyla film eklendiyse result döner
        if (result == true) {
          // --- ÇÖKME KORUMASI BURADA ---
          if (!context.mounted) return;

          onRefresh?.call();

          if (target != ShelfTarget.watchlist) {
            StreakService.instance.triggerAction(context);
          }
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
            border: Border.all(color: primaryGreen.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.add,
            size: 40,
            color: primaryGreen.withOpacity(0.7),
          ),
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

class _UserListSheet extends StatefulWidget {
  final String title;
  final String uid;
  final String collection;

  const _UserListSheet({
    required this.title,
    required this.uid,
    required this.collection,
  });

  @override
  State<_UserListSheet> createState() => _UserListSheetState();
}

class _UserListSheetState extends State<_UserListSheet> {
  final Map<String, Future<DocumentSnapshot>> _userFutureCache = {};
  final Map<String, DocumentSnapshot> _userSnapshotCache = {};

  Future<DocumentSnapshot> _loadUser(String uid) {
    return _userFutureCache.putIfAbsent(uid, () async {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      _userSnapshotCache[uid] = snap;
      return snap;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final uid = widget.uid;
    final collection = widget.collection;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection(collection)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('Liste boş.'));
                }
                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final docId = docs[index].id;
                    return FutureBuilder<DocumentSnapshot>(
                      future: _loadUser(docId),
                      initialData: _userSnapshotCache[docId],
                      builder: (context, userSnap) {
                        if (!userSnap.hasData)
                          return const ListTile(title: Text('Yükleniyor...'));
                        if (!userSnap.data!.exists) {
                          return const SizedBox.shrink();
                        }
                        final data =
                            userSnap.data!.data() as Map<String, dynamic>?;
                        final name =
                            data?['displayName'] ??
                            data?['username'] ??
                            'Kullanıcı';
                        final photo = data?['photoURL'];

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: (photo != null)
                                ? NetworkImage(photo)
                                : null,
                            child: photo == null
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          title: Text(name, style: TextStyle(color: textColor)),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PublicProfileScreen(uid: docId),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileListsView extends StatefulWidget {
  final String profileUid; // Profiline bakılan kişinin UID'si
  final bool isMe; // Kendi profilimiz mi?

  const ProfileListsView({
    Key? key,
    required this.profileUid,
    required this.isMe,
  }) : super(key: key);

  @override
  State<ProfileListsView> createState() => _ProfileListsViewState();
}

class _ProfileListsViewState extends State<ProfileListsView> {
  bool _showSaved = false; // false: Kendi Listelerim, true: Kaydedilenler

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // SADECE KENDİ PROFİLİMİZSE TOGGLE (GEÇİŞ) BUTONLARINI GÖSTER
        if (widget.isMe)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _showSaved = false),
                      child: Container(
                        decoration: BoxDecoration(
                          color: !_showSaved
                              ? Colors.green
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          "Oluşturduklarım",
                          style: TextStyle(
                            color: !_showSaved ? Colors.white : Colors.white54,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _showSaved = true),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _showSaved ? Colors.green : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          "Kaydedilenler",
                          style: TextStyle(
                            color: _showSaved ? Colors.white : Colors.white54,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // LİSTELERİN GÖSTERİLDİĞİ ALAN
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _showSaved
                // KAYDEDİLENLER SORGUSU
                ? FirebaseFirestore.instance
                      .collection('users')
                      .doc(widget.profileUid)
                      .collection('saved_lists')
                      .orderBy('savedAt', descending: true)
                      .snapshots()
                // OLUŞTURDUKLARIM SORGUSU
                : FirebaseFirestore.instance
                      .collection('custom_lists')
                      .where('ownerId', isEqualTo: widget.profileUid)
                      .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.green),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Text(
                    _showSaved
                        ? "Henüz hiç liste kaydetmedin."
                        : "Henüz bir liste oluşturulmadı.",
                    style: const TextStyle(color: Colors.white54),
                  ),
                );
              }

              final docs = snapshot.data!.docs;

              return ListView.builder(
                padding: const EdgeInsets.only(top: 8, bottom: 80),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;

                  // Firebase'den gelen veriyi CustomList modeline çeviriyoruz
                  // (Senin CustomList.fromMap() fonksiyonun varsa onu da kullanabilirsin)
                  final customList = CustomList(
                    id: _showSaved ? data['listId'] : docs[index].id,
                    ownerId: data['ownerId'] ?? '',
                    ownerName: data['ownerName'] ?? 'Bilinmiyor',
                    title: data['title'] ?? 'İsimsiz',
                    description: data['description'] ?? '',
                    coverImageUrl: data['coverImageUrl'],
                    isPublic: data['isPublic'] ?? true,
                    movieCount: data['movieCount'] ?? 0,
                    createdAt: data['createdAt']?.toDate() ?? DateTime.now(),
                  );

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    color: Colors.white10,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(12),
                      leading:
                          (customList.coverImageUrl != null &&
                              customList.coverImageUrl!.startsWith('http'))
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                customList.coverImageUrl!,
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Container(
                                      width: 50,
                                      height: 50,
                                      color: Colors.black26,
                                      child: const Icon(
                                        Icons.error,
                                        color: Colors.white54,
                                      ),
                                    ),
                              ),
                            )
                          : Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.list,
                                color: Colors.white54,
                              ),
                            ),
                      title: Text(
                        customList.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          "${customList.movieCount} Film • Hazırlayan: ${customList.ownerName}",
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Colors.white54,
                      ),
                      onTap: () {
                        // Tıklandığında yazdığımız detay ekranına yönlendir!
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CustomListDetailScreen(
                              list: customList,
                              isMyList:
                                  customList.ownerId ==
                                  FirebaseAuth.instance.currentUser?.uid,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
