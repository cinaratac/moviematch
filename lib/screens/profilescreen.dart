import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/widgets/green_characters.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluttergirdi/services/letterboxd_service.dart';

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
import 'package:fluttergirdi/screens/post_detail_screen.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart'; 

import 'package:fluttergirdi/services/custom_list_service.dart';
import 'package:fluttergirdi/models/custom_list.dart';
import 'package:fluttergirdi/screens/custom_list_detail_screen.dart';

import 'package:fluttergirdi/models/gamification.dart';
import 'package:fluttergirdi/services/gamification_service.dart';

// --- MODEL SINIFLARI ---

/// Diğer sayfaların (Chat, Search vb.) erişebilmesi için gerekli önbellek sınıfı.
/// Veri sızıntısını önlemek için sayfa kapandığında temizlenir.
class UserShelfCache {
  static List<Map<String, String>> favorites = [];
  static List<Map<String, String>> fiveStar = [];
  static List<Map<String, String>> disliked = [];
  static List<Map<String, String>> watchlist = [];

  static void setFavorites(List<LetterboxdFilm> items) {
    favorites = items.map((e) => {'title': e.title, 'poster': e.posterUrl}).toList();
  }
  static void setFiveStar(List<LetterboxdFilm> items) {
    fiveStar = items.map((e) => {'title': e.title, 'poster': e.posterUrl}).toList();
  }
  static void setDisliked(List<LetterboxdFilm> items) {
    disliked = items.map((e) => {'title': e.title, 'poster': e.posterUrl}).toList();
  }
  static void setWatchlistFromMaps(List<Map<String, dynamic>> items) {
    watchlist = items.map((m) => {
      'title': (m['title'] ?? '').toString(),
      'poster': (m['poster'] ?? m['posterUrl'] ?? m['image'] ?? '').toString(),
    }).toList();
  }
  
  /// Verileri temizler
  static void clear() {
    favorites = [];
    fiveStar = [];
    disliked = [];
    watchlist = [];
  }
}

// Aktivite verisi için model
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
    final textStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white24, width: 1),
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
            child: Center(
              child: Image.network(imageUrl, fit: BoxFit.contain),
            ),
          ),
        );
      },
    );
  }

  void showUserList(String title, String collection) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (_) => _UserListSheet(title: title, uid: user.uid, collection: collection),
    );
  }

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => showEnlargedImage(user.photoURL),
          child: CircleAvatar(
            radius: 36,
            backgroundImage: user.photoURL != null && user.photoURL!.isNotEmpty
                ? NetworkImage(user.photoURL!)
                : null,
            child: (user.photoURL == null || user.photoURL!.isEmpty)
                ? Text(
                    shownName(user).isNotEmpty ? shownName(user)[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 24),
                  )
                : null,
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
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              
              // --- ROZET ALANI ---
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData || !snap.data!.exists) return const SizedBox.shrink();
                  final userData = snap.data!.data() as Map<String, dynamic>?;
                  final badges = List<String>.from(userData?['badges'] ?? []);
                  if (badges.isEmpty) return const SizedBox.shrink();

                  return Padding(
                    padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: badges.map((badgeId) {
                        final badge = AppBadge.allBadges.firstWhere(
                          (b) => b.id == badgeId, 
                          orElse: () => AppBadge.allBadges.first
                        );
                        return Tooltip(
                          message: '${badge.name}: ${badge.description}',
                          triggerMode: TooltipTriggerMode.tap,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: badge.color.withOpacity(0.15),
                              shape: BoxShape.circle,
                              border: Border.all(color: badge.color.withOpacity(0.6), width: 1),
                            ),
                            child: Icon(badge.icon, size: 12, color: badge.color),
                          ),
                        );
                      }).toList(),
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 6),
              (followers == null || following == null)
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
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
                          onTap: () => showUserList('Takip Edilenler', 'following'),
                        ),
                      ],
                    ),
              const SizedBox(height: 5),
              if (lbUsername != null && lbUsername.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Letterboxd: @$lbUsername',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
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
  
  // Set to avoid duplicate requests during same session
  final Map<String, Future<List<Map<String, dynamic>?>>> _watchlistFutureCache = {};

  int? _followersCount;
  int? _followingCount;
  StreamSubscription<FollowEvent>? _followSub;
  final ValueNotifier<bool> _showGuideNotifier = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    // Cache'i temizleyerek başla (Güvenlik)
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

      // Sadece değerler değişmişse Firestore'a yaz (Optimization)
      if (f1 != currentStoredFollowers || f2 != currentStoredFollowing) {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
           'followersCount': f1,
           'followingCount': f2,
           'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await GamificationService.instance.checkAndAwardBadges();

    } catch (_) {}

    _followSub?.cancel();
    _followSub = svc.events.listen((e) {
      if (!mounted) return;
      if (e.targetUid == uid) {
        setState(() => _followersCount = (_followersCount ?? 0) + (e.followed ? 1 : -1));
      }
      if (e.actorUid == uid) {
        setState(() => _followingCount = (_followingCount ?? 0) + (e.followed ? 1 : -1));
      }
    });
  }

  Future<void> _primeShelfCache() async {
    try {
      if (_futureFavs != null) {
        final favs = await _futureFavs!;
        // Hem local cache'i hem de statik cache'i güncelle
        UserShelfCache.setFavorites(favs);
      }
      if (_futureFiveStar != null) {
        final five = await _futureFiveStar!;
        UserShelfCache.setFiveStar(five);
      }
      if (_futureDisliked != null) {
        final dis = await _futureDisliked!;
        UserShelfCache.setDisliked(dis);
      }
    } catch (_) {}
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
    final hasFirestoreFiveStar = (fiveStarKeys is List && fiveStarKeys.isNotEmpty);
    
    // Cache dolu mu?
    final hasCacheFavs = UserShelfCache.favorites.isNotEmpty;
    final hasCacheFiveStar = UserShelfCache.fiveStar.isNotEmpty;

    if (hasFirestoreFavs || hasCacheFavs || hasFirestoreFiveStar || hasCacheFiveStar) {
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
    final u = uid != null ? sp.getString('lb_username_$uid') : sp.getString('lb_username');
    setState(() {
      _lbUsername = u;
      _futureFavs = (u == null || u.isEmpty) ? null : LetterboxdService.fetchFavorites(u);
      _futureFiveStar = (u == null || u.isEmpty) ? null : LetterboxdService.fetchFiveStar(u);
      _futureDisliked = (u == null || u.isEmpty) ? null : LetterboxdService.fetchDisliked(u);
    });
    _primeShelfCache().then((_) { _checkGuideVisibility(); });
    _forceWriteLbUsernameIfMissing();
  }

  void _bindLbFromFirestore() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _userSub?.cancel();
    _userSub = FirebaseFirestore.instance.collection('users').doc(uid).snapshots().listen((snap) async {
          if (!snap.exists) return;
          final data = snap.data() ?? const {};
          _lastUserData = Map<String, dynamic>.from(data);
          final lb = (data['letterboxdUsername'] ?? '').toString().trim();
          final appU = (data['username'] ?? data['handle'] ?? data['appUsername'] ?? '').toString().trim();
          if (appU.isNotEmpty && appU != (_appUsername ?? '')) {
            if (mounted) setState(() => _appUsername = appU);
          }
          if (lb.isNotEmpty && lb != _lbUsername) {
             if (mounted) setState(() => _lbUsername = lb);
             _refreshFavorites(); 
          }
          _checkGuideVisibility();
        });
  }

  // Sadece ekranda görünenleri yeniler, veritabanına sync yapmaz.
  Future<void> _refreshFavorites() async {
    if (_lbUsername == null || _lbUsername!.isEmpty) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        try {
          final ref = FirebaseFirestore.instance.collection('users').doc(uid);
          var snap = await ref.get(const GetOptions(source: Source.cache));
          if (!snap.exists) snap = await ref.get(const GetOptions(source: Source.server));
          final lb = (snap.data()?['letterboxdUsername'] ?? '').toString();
          if (lb.isNotEmpty) setState(() => _lbUsername = lb);
        } catch (_) {}
      }
      if (_lbUsername == null || _lbUsername!.isEmpty) return;
    }

    // Cache temizliği ve yeniden çekme (Sadece Read)
    final sp = await SharedPreferences.getInstance();
    final key = 'lb_cache_${_lbUsername?.toLowerCase()}';
    await sp.remove(key);
    await sp.remove('${key}_time');
    await sp.remove('${key}_watchlist');

    setState(() {
      if(_lbUsername != null) {
        _futureFavs = LetterboxdService.fetchFavorites(_lbUsername!);
        _futureFiveStar = LetterboxdService.fetchFiveStar(_lbUsername!);
        _futureDisliked = LetterboxdService.fetchDisliked(_lbUsername!);
      }
    });

    _primeShelfCache();
  }

  String _noYear(String t) => t.replaceAll(RegExp(r'\s*\(\d{4}\)$'), '');

  @override
  void dispose() {
    _userSub?.cancel();
    _followSub?.cancel();
    _showGuideNotifier.dispose();
    // Cache'i temizle ki diğer kullanıcılar görmesin (Güvenlik)
    UserShelfCache.clear();
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
                child: PosterImage(posterUrl: url, title: list.first.title, fit: BoxFit.cover),
              ),
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xE6000000), Color(0xCC000000), Color(0x99000000)],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- Watchlist Section ---
  Widget _watchlistSectionFromKeys(List<String> keys, {int maxItems = 30}) {
    void onReturnFromSearch() {
      setState(() => _watchlistFutureCache.clear());
    }
    if (keys.isEmpty) {
      return SizedBox(
        height: 140,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 1,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) => AspectRatio(
            aspectRatio: 2 / 3,
            child: _AddPosterTile(target: ShelfTarget.watchlist, onRefresh: onReturnFromSearch),
          ),
        ),
      );
    }
    final limited = keys.take(maxItems).toList();
    final hash = limited.join('|');
    final future = _watchlistFutureCache[hash] ??= Future.wait(
      limited.map((k) async {
        final col = FirebaseFirestore.instance.collection('catalog_films').doc(k);
        try { final c = await col.get(const GetOptions(source: Source.cache)); if (c.exists) { final d = c.data(); d?['docId'] = k; return d; } } catch (_) {}
        try { final s = await col.get(const GetOptions(source: Source.server)); if (s.exists) { final d = s.data(); d?['docId'] = k; return d; } } catch (_) {}
        return null;
      }),
    );
    return FutureBuilder<List<Map<String, dynamic>?>>(
      future: future,
      builder: (context, filmSnap) {
        if (filmSnap.connectionState == ConnectionState.waiting && !(filmSnap.hasData && (filmSnap.data?.isNotEmpty ?? false))) {
          return const SizedBox(height: 140, child: Center(child: CircularProgressIndicator()));
        }
        final films = (filmSnap.data ?? []).where((m) => m != null).map((m) => m!).toList();
        
        // Cache'i doldur (Diğer ekranlar için)
        UserShelfCache.setWatchlistFromMaps(films);
        
        return SizedBox(
          height: 140,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: films.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              if (i == films.length) return AspectRatio(aspectRatio: 2 / 3, child: _AddPosterTile(target: ShelfTarget.watchlist, onRefresh: onReturnFromSearch));
              
              final film = films[i];
              final poster = (film['poster'] ?? film['posterUrl'] ?? film['image'] ?? '').toString();
              final title = (film['title'] ?? '') as String;
              final docId = (film['docId'] ?? '').toString();
             
             return GestureDetector(
                onTap: () {
                  if (title.isNotEmpty) MovieActionHelper.show(context, title: title, posterUrl: poster, docId: docId, target: ShelfTarget.watchlist, onItemDeleted: () => setState(() => _watchlistFutureCache.clear()));
                },
                child: AspectRatio(aspectRatio: 2 / 3, child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Stack(fit: StackFit.expand, children: [poster.isNotEmpty ? PosterImage(posterUrl: poster, title: title, fit: BoxFit.cover) : Container(color: Colors.grey.shade800), if (title.isNotEmpty) Align(alignment: Alignment.bottomCenter, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), color: Colors.black54, child: Text(_noYear(title), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white), textAlign: TextAlign.center)))]))),
              );
            },
          ),
        );
      },
    );
  }

  Widget _shelfSectionFromUserField(String fieldName, {int maxItems = 30, String emptyText = 'Film bulunamadı.'}) {
    void onReturnFromSearch() {
      setState(() => _watchlistFutureCache.clear());
    }
    final keys = List<dynamic>.from((_lastUserData?[fieldName] ?? const [])).map((e) => e.toString()).toList();
    final ShelfTarget target = fieldName == 'favoritesKeys' ? ShelfTarget.favorites : fieldName == 'fiveStarKeys' ? ShelfTarget.fiveStar : ShelfTarget.disliked;
    if (keys.isEmpty) {
      return SizedBox(
        height: 140,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 1,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, i) => AspectRatio(aspectRatio: 2 / 3, child: _AddPosterTile(target: target, onRefresh: onReturnFromSearch)),
        ),
      );
    }
    final limited = keys.take(maxItems).toList();
    final hash = '$fieldName:' + limited.join('|');
    final future = _watchlistFutureCache[hash] ??= Future.wait(
      limited.map((k) async {
        final col = FirebaseFirestore.instance.collection('catalog_films').doc(k);
        try { final c = await col.get(const GetOptions(source: Source.cache)); if (c.exists) { final d = c.data(); d?['docId'] = k; return d; } } catch (_) {}
        try { final s = await col.get(const GetOptions(source: Source.server)); if (s.exists) { final d = s.data(); d?['docId'] = k; return d; } } catch (_) {}
        return null;
      }),
    );
    return FutureBuilder<List<Map<String, dynamic>?>>(
      future: future,
      builder: (context, filmSnap) {
        if (filmSnap.connectionState == ConnectionState.waiting && !(filmSnap.hasData && (filmSnap.data?.isNotEmpty ?? false))) {
          return const SizedBox(height: 140, child: Center(child: CircularProgressIndicator()));
        }
        final films = (filmSnap.data ?? []).where((m) => m != null).map((m) => m!).toList();
        return SizedBox(
          height: 140,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: films.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              if (i == films.length) return AspectRatio(aspectRatio: 2 / 3, child: _AddPosterTile(target: target, onRefresh: onReturnFromSearch));
              final film = films[i];
              final poster = (film['poster'] ?? film['posterUrl'] ?? film['image'] ?? '').toString();
              final title = (film['title'] ?? '') as String;
              final docId = (film['docId'] ?? '').toString();
              return GestureDetector(
                onTap: () {
                  if (title.isNotEmpty) MovieActionHelper.show(context, title: title, posterUrl: poster, docId: docId, target: target, onItemDeleted: () => setState(() => _watchlistFutureCache.clear()));
                },
                child: AspectRatio(aspectRatio: 2 / 3, child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Stack(fit: StackFit.expand, children: [poster.isNotEmpty ? PosterImage(posterUrl: poster, title: title, fit: BoxFit.cover) : Container(color: Colors.grey.shade800), if (title.isNotEmpty) Align(alignment: Alignment.bottomCenter, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), color: Colors.black54, child: Text(_noYear(title), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white), textAlign: TextAlign.center)))]))),
              );
            },
          ),
        );
      },
    );
  }

  // --- 1. SEKME: FİLMLER ---
  // RefreshIndicator kaldırıldı, sadece ListView
   Widget _buildProfileContentAfterHeader() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (_lbUsername == null) Padding(padding: const EdgeInsets.only(bottom: 8.0), child: Row(children: const [Icon(Icons.alternate_email), SizedBox(width: 8), Text('Letterboxd bağlı değil')])),
        const SizedBox(height: 12),
        Builder(builder: (context) {
           final bio = (_lastUserData?['bio'] ?? '').toString();
           if(bio.isNotEmpty) return Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(bio, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4)));
           return const SizedBox.shrink();
        }),
        Builder(builder: (context) {
           final age = _lastUserData?['age'];
           final genres = List<String>.from(_lastUserData?['favGenres'] ?? []);
           final dirs = List<String>.from(_lastUserData?['favDirectors'] ?? []);
           final acts = List<String>.from(_lastUserData?['favActors'] ?? []);
           if((age==null || age<=0) && genres.isEmpty && dirs.isEmpty && acts.isEmpty) return const SizedBox.shrink();

           Widget cw(String t, List<String> i) {
             if(i.isEmpty) return const SizedBox.shrink();
             return Padding(padding: const EdgeInsets.only(top: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: Theme.of(context).textTheme.titleSmall), const SizedBox(height: 8), Wrap(spacing: 8, runSpacing: 8, children: i.map((e)=>Chip(label: Text(e))).toList())]));
           }
           return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
             if(age is int && age > 0) Padding(padding: const EdgeInsets.only(top:8), child: Row(children: [const Icon(Icons.cake, size: 18), const SizedBox(width: 6), Text('Yaş: $age')])),
             cw('Sevdiğin türler', genres), cw('Sevdiğin yönetmenler', dirs), cw('Sevdiğin oyuncular', acts)
           ]);
        }),
        const SizedBox(height: 16),
        Padding(padding: const EdgeInsets.only(bottom: 8.0), child: Text('Favori Filmler', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
        const SizedBox(height: 8),
        _shelfSectionFromUserField('favoritesKeys', emptyText: 'Favori film bulunamadı.', maxItems: 30),
        Padding(padding: const EdgeInsets.only(top: 20.0, bottom: 8.0), child: Text('Sevdiği Filmler', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
        const SizedBox(height: 8),
        _shelfSectionFromUserField('fiveStarKeys', emptyText: '5★ film bulunamadı.', maxItems: 30),
        Padding(padding: const EdgeInsets.only(top: 20.0, bottom: 8.0), child: Text('Sevmediği Filmler', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
        const SizedBox(height: 8),
        _shelfSectionFromUserField('dislikedKeys', emptyText: 'Sevmediği film bulunamadı.', maxItems: 30),
        Padding(padding: const EdgeInsets.only(top: 20.0, bottom: 8.0), child: Text('Watchlist', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
        const SizedBox(height: 8),
        _watchlistSectionFromKeys(List<dynamic>.from((_lastUserData?['watchlistKeys'] ?? const [])).map((e) => e.toString()).toList(), maxItems: 30),

        const SizedBox(height: 52),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final user = snap.data;
        if (user == null) return const Scaffold(body: Center(child: Text('Oturum açılmadı')));

        return DefaultTabController(
          length: 3, 
          child: Scaffold(
            extendBodyBehindAppBar: true,
            body: Stack(
              children: [
                NestedScrollView(
                  headerSliverBuilder: (context, innerBoxIsScrolled) {
                    return [
                      SliverAppBar(
                        floating: true, snap: true, backgroundColor: Colors.black, elevation: 0, scrolledUnderElevation: 0, surfaceTintColor: Colors.transparent, automaticallyImplyLeading: false,
                        actions: [
                          IconButton(tooltip: 'Düzenle', icon: const Icon(Icons.edit_outlined), onPressed: () { Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditProfilePage(initialUserData: _lastUserData))); }),
                          // Yenile butonu kaldırıldı.
                          IconButton(tooltip: 'Ayarlar', icon: const Icon(Icons.settings_outlined), onPressed: () { Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage())); }),
                        ],
                      ),
                      SliverToBoxAdapter(
                        child: Stack(
                          children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.28, child: _blurBackdrop()),
                            Column(
                              children: [
                                SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight),
                                _profileHeaderSection(context: context, user: user, followers: _followersCount, following: _followingCount, lbUsername: _lbUsername, shownName: _shownName),
                                const SizedBox(height: 12),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: TabBar(
                                    isScrollable: false,
                                    indicator: UnderlineTabIndicator(borderSide: BorderSide(width: 2, color: Theme.of(context).colorScheme.primary)),
                                    indicatorSize: TabBarIndicatorSize.tab,
                                    overlayColor: WidgetStateProperty.all(Colors.transparent),
                                    labelPadding: const EdgeInsets.symmetric(vertical: 6),
                                    labelStyle: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                    unselectedLabelStyle: Theme.of(context).textTheme.titleSmall,
                                    labelColor: Theme.of(context).colorScheme.onSurface,
                                    unselectedLabelColor: Colors.white70,
                                    tabs: const [
                                      Tab(text: 'Filmler'),
                                      Tab(text: 'Aktiviteler'),
                                      Tab(text: 'Listeler'), 
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
                      _ActivitiesTab(uid: user.uid),
                      _ListsTab(uid: user.uid),
                    ],
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: _showGuideNotifier,
                  builder: (context, isVisible, child) {
                    if (!isVisible) return const SizedBox.shrink();
                    return GuideCharacterOverlay(message: "Profilin çok boş görünüyor! Hadi artı butonuna basıp favori filmlerini ekle.", isVisible: isVisible, onClose: () { _showGuideNotifier.value = false; });
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

// --- 2. SEKME: AKTİVİTELER ---
class _ActivitiesTab extends StatefulWidget {
  final String uid;
  const _ActivitiesTab({required this.uid});

  @override
  State<_ActivitiesTab> createState() => _ActivitiesTabState();
}

class _ActivitiesTabState extends State<_ActivitiesTab> with AutomaticKeepAliveClientMixin {
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
      final q = db.collection('posts').where('authorId', isEqualTo: widget.uid).orderBy('createdAt', descending: true).limit(30);
      final qs = await q.get();
      for (final d in qs.docs) {
        final m = d.data();
        final ts = m['createdAt'];
        final poster = (m['moviePoster'] ?? m['moviePosterUrl'] ?? m['poster'] ?? (m['movie'] is Map ? (m['movie']['poster'] ?? m['movie']['posterUrl']) : '') ?? '').toString();
        final title = (m['movieTitle'] ?? m['title'] ?? (m['movie'] is Map ? (m['movie']['title'] ?? '') : '') ?? '').toString();
        
        final tmdbId = (m['movie'] is Map ? m['movie']['id'] : null) ?? m['tmdbId'];

        items.add(_ActivityItemData(
          id: d.id,
          text: (m['text'] ?? '').toString(),
          createdAt: ts is Timestamp ? ts.toDate() : null,
          posterUrl: poster,
          title: title,
          likeCount: ((m['likeCount'] ?? 0) as num).toInt(),
          replyCount: ((m['replyCount'] ?? 0) as num).toInt(),
          tmdbId: (tmdbId is int) ? tmdbId : null,
        ));
      }
    } catch (_) {}
    
    items.sort((a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(a.createdAt?.millisecondsSinceEpoch ?? 0));

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

  // RefreshIndicator kaldırıldı.
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(children: [Text('Aktiviteler', style: Theme.of(context).textTheme.titleMedium)]),
        const SizedBox(height: 10),
        if (_loadingActivities)
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: CircularProgressIndicator()))
        else if (_activities.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Henüz aktivite yok.'))
        else
          ListView.separated(
            itemCount: _activities.length,
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            separatorBuilder: (_, __) => const Divider(height: 0.5, thickness: 0.5),
            itemBuilder: (context, i) {
              final a = _activities[i];
              final when = a.createdAt;
              String timeLabel = '';
              if (when != null) {
                timeLabel = _timeAgo(when);
              }
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
    final theme = Theme.of(context);
   

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PostDetailScreen(postId: item.id),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color.fromARGB(3, 255, 255, 255), width: 1)),
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
                  fit: BoxFit.cover
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
                      Expanded(child: Text(FirebaseAuth.instance.currentUser?.displayName ?? 'Kullanıcı', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                      const SizedBox(width: 8),
                      Text(' Paylaştı', style: Theme.of(context).textTheme.labelSmall),
                      if (timeLabel.isNotEmpty) ...[const SizedBox(width: 6), Text(timeLabel, style: Theme.of(context).textTheme.labelSmall)],
                    ],
                  ),
                  if (item.text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4.0), child: Text(item.text, maxLines: 4, overflow: TextOverflow.ellipsis)),
                  if (item.title.isNotEmpty && item.posterUrl.isEmpty && item.tmdbId == null)
                    Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [const Icon(Icons.local_movies, size: 16), const SizedBox(width: 6), Expanded(child: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall))])),
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0),
                    child: Row(children: [const Icon(Icons.favorite_border, size: 16), const SizedBox(width: 4), Text('${item.likeCount}'), const SizedBox(width: 12), const Icon(Icons.mode_comment_outlined, size: 16), const SizedBox(width: 4), Text('${item.replyCount}'), const SizedBox(width: 12), const Icon(Icons.repeat, size: 16)]),
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

class _ListsTabState extends State<_ListsTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if(uid == null) return const SizedBox.shrink();

    // RefreshIndicator kaldırıldı
    return StreamBuilder<List<CustomList>>(
      stream: CustomListService.instance.getUserLists(uid),
      builder: (context, snapshot) {
         if(snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
         final lists = snapshot.data ?? [];
         
         if (lists.isEmpty) {
           return ListView(
             padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
             children: [
               _CreateListTile(onTap: () => _showCreateListDialog(context)),
               const SizedBox(height: 20),
               const Center(child: Text("Henüz liste oluşturmadın.")),
             ],
           );
         }

         return ListView.builder(
           padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
           itemCount: lists.length + 1,
           itemBuilder: (context, index) {
             if(index == 0) {
               return _CreateListTile(onTap: () => _showCreateListDialog(context));
             }
             final list = lists[index - 1];
             return _CustomListCard(list: list, isMine: true);
           }
         );
      }
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 24, left: 24, right: 24, top: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Yeni Liste Oluştur", style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              TextField(controller: titleCtrl, autofocus: true, decoration: InputDecoration(labelText: "Liste Adı", hintText: "Örn: En İyi Korku Filmleri", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), prefixIcon: const Icon(Icons.format_list_bulleted))),
              const SizedBox(height: 16),
              TextField(controller: descCtrl, decoration: InputDecoration(labelText: "Açıklama (İsteğe bağlı)", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), prefixIcon: const Icon(Icons.description_outlined)), maxLines: 2),
              const SizedBox(height: 16),
              SwitchListTile(title: const Text("Herkese Açık"), subtitle: Text(isPublic ? "Herkes profilinizde görebilir" : "Sadece siz görebilirsiniz", style: const TextStyle(fontSize: 12, color: Colors.grey)), value: isPublic, contentPadding: EdgeInsets.zero, activeColor: Theme.of(ctx).colorScheme.primary, onChanged: (val) => setSheetState(() => isPublic = val)),
              const SizedBox(height: 24),
              SizedBox(width: double.infinity, height: 50, child: FilledButton(onPressed: isLoading ? null : () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) return;
                setSheetState(() => isLoading = true);
                try {
                  await CustomListService.instance.createList(title, descCtrl.text.trim(), isPublic: isPublic);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {} finally { if (ctx.mounted) setSheetState(() => isLoading = false); }
              }, style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: isLoading ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text("Oluştur", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.5)), borderRadius: BorderRadius.circular(12), color: Colors.white.withOpacity(0.05)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.add_circle_outline), SizedBox(width: 8), Text("Yeni Liste Oluştur", style: TextStyle(fontWeight: FontWeight.bold))]),
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
    return GestureDetector(
      onTap: () { Navigator.push(context, MaterialPageRoute(builder: (_) => CustomListDetailScreen(list: list, isMyList: isMine))); },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 100,
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          ClipRRect(borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)), child: SizedBox(width: 70, height: double.infinity, child: list.coverImageUrl != null ? PosterImage(posterUrl: list.coverImageUrl!, title: list.title, fit: BoxFit.cover) : Container(color: Colors.grey.shade800, child: const Icon(Icons.list, color: Colors.white24)))),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(list.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis), const SizedBox(height: 4), Text('${list.movieCount} film', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)), if (!list.isPublic) const Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.lock, size: 12, color: Colors.grey))])),
          const Icon(Icons.chevron_right, color: Colors.grey), const SizedBox(width: 12),
        ]),
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
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => SearchMoviePage(target: target)));
        if (result == true) { onRefresh?.call(); }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: colorScheme.onSurface.withOpacity(0.1),
          alignment: Alignment.center,
          child: Icon(
            Icons.add, 
            size: 40, 
            color: colorScheme.onSurface.withOpacity(0.6), 
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
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
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

// --- KULLANICI LİSTESİ PENCERESİ (Takipçi/Takip edilenler için) ---
class _UserListSheet extends StatelessWidget {
  final String title;
  final String uid;
  final String collection; // 'followers' or 'following'

  const _UserListSheet({required this.title, required this.uid, required this.collection});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
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
                      future: FirebaseFirestore.instance.collection('users').doc(docId).get(),
                      builder: (context, userSnap) {
                        if (!userSnap.hasData) return const ListTile(title: Text('Yükleniyor...'));
                        final data = userSnap.data!.data() as Map<String, dynamic>?;
                        final name = data?['displayName'] ?? data?['username'] ?? 'Kullanıcı';
                        final photo = data?['photoURL'];
                        
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: (photo != null) ? NetworkImage(photo) : null,
                            child: photo == null ? const Icon(Icons.person) : null,
                          ),
                          title: Text(name),
                          onTap: () {
                            Navigator.push(
                              context, 
                              MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: docId))
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