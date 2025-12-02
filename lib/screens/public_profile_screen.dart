import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/services/user_profile_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/services/chat_service.dart';
import 'package:fluttergirdi/screens/chat_room_screen.dart';
import 'package:fluttergirdi/services/follow_system_service.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:fluttergirdi/services/match_service.dart';


class PublicProfileScreen extends StatefulWidget {
  final String uid;
  const PublicProfileScreen({super.key, required this.uid});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  bool? _isFollowing;
  bool _followBusy = false;
  int? _followersCount;
  int? _followingCount;
  StreamSubscription<FollowEvent>? _followSub;
  bool _isBlocked = false;
  bool _hasBlockedMe = false;
  int? _matchScore;

  // Ekran titremesini önleyen Stream
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream;

  // Katalog önbelleği
  final Map<String, Future<List<Map<String, dynamic>?>>> _catalogFutureCache =
      {};

  // Yardımcı: Güvenli ID çıkarma
  int? _extractTmdbId(Map<String, dynamic> m) {
    final val = m['tmdbId'];
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val);
    return null;
  }

  /// Arka plan bulanık poster
  Widget _blurBackdropFromKeys(List<String> favKeys) {
    if (favKeys.isEmpty) return const SizedBox.shrink();
    final firstKey = favKeys.first.trim();
    if (firstKey.isEmpty) return const SizedBox.shrink();
    final cacheKey = 'backdrop:$firstKey';
    return FutureBuilder<List<Map<String, dynamic>?>>(
      future: (_catalogFutureCache[cacheKey] ??= _fetchCatalogForKeys([
        firstKey,
      ])),
      builder: (context, snap) {
        final m = (snap.data != null && snap.data!.isNotEmpty)
            ? snap.data!.first
            : null;
        if (m == null) return const SizedBox.shrink();

        final url =
            (m['poster'] ?? m['posterUrl'] ?? m['image'] ?? '') as String;
        final tmdbId = _extractTmdbId(m);
        final title = _catalogTitle(m);

        // URL boş olsa bile TMDB ID varsa PosterImage onu bulur
        if (url.isEmpty && tmdbId == null) return const SizedBox.shrink();

        return Positioned.fill(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: PosterImage(
                  posterUrl: url,
                  tmdbId: tmdbId, // <--- EKLENDİ
                  title: title,
                  fit: BoxFit.cover,
                ),
              ),
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

  String _catalogTitle(Map<String, dynamic> m) {
    return (m['title'] ?? m['name'] ?? m['t'] ?? '') as String;
  }

  // Raf bölümü (Favoriler, 5 Yıldız vb.)
  Widget _shelfSectionFromKeys(
    String title,
    List<String> keys, {
    int maxItems = 30,
  }) {
    if (keys.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('$title bulunamadı.'),
      );
    }
    final limited = keys.take(maxItems).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, dynamic>?>>(
          future: (() {
            final k = 'shelf:${title.toLowerCase()}:${limited.join('|')}';
            return _catalogFutureCache[k] ??= _fetchCatalogForKeys(limited);
          })(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final films = (snap.data ?? const [])
                .where((m) => m != null)
                .map((m) => m!)
                .toList();
            if (films.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('$title bulunamadı.'),
              );
            }
            return SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: films.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final m = films[i];
                  final poster =
                      (m['poster'] ?? m['posterUrl'] ?? m['image'] ?? '')
                          as String;
                  final t = _catalogTitle(m);
                  final tmdbId = _extractTmdbId(m); // <--- EKLENDİ

                  return AspectRatio(
                    aspectRatio: 2 / 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          PosterImage(
                            posterUrl: poster,
                            tmdbId: tmdbId, // <--- EKLENDİ
                            title: t,
                            fit: BoxFit.cover,
                          ),
                          if (t.isNotEmpty)
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                color: Colors.black54,
                                child: Text(
                                  t,
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
        ),
      ],
    );
  }

  final Map<String, Future<List<Map<String, dynamic>?>>> _watchlistFutureCache =
      {};

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _futureActivities;

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _fetchActivities() async {
    final fs = FirebaseFirestore.instance;
    final base = fs
        .collection('posts')
        .where('authorId', isEqualTo: widget.uid);

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> sortAndLimitFrom(
      QuerySnapshot<Map<String, dynamic>> qs,
    ) async {
      final docs = qs.docs.toList();
      docs.sort((a, b) {
        final ta = (a.data()['createdAt'] as Timestamp?);
        final tb = (b.data()['createdAt'] as Timestamp?);
        final ma = ta?.millisecondsSinceEpoch ?? 0;
        final mb = tb?.millisecondsSinceEpoch ?? 0;
        return mb.compareTo(ma);
      });
      return docs.take(50).toList();
    }

    try {
      final qs = await base
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get(const GetOptions(source: Source.server));
      return qs.docs;
    } on FirebaseException catch (e) {
      final isIndexIssue =
          e.code == 'failed-precondition' ||
          (e.message?.toLowerCase().contains('index') ?? false);

      if (isIndexIssue) {
        try {
          final qs = await base
              .limit(200)
              .get(const GetOptions(source: Source.server));
          return await sortAndLimitFrom(qs);
        } catch (_) {}
      }

      try {
        final qs = await base
            .orderBy('createdAt', descending: true)
            .limit(50)
            .get(const GetOptions(source: Source.cache));
        return qs.docs;
      } catch (_) {
        final qs = await base
            .limit(200)
            .get(const GetOptions(source: Source.cache));
        return await sortAndLimitFrom(qs);
      }
    } catch (_) {
      final qs = await base
          .limit(200)
          .get(const GetOptions(source: Source.cache));
      return await sortAndLimitFrom(qs);
    }
  }

  String _timeAgo(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}g';
    final months = diff.inDays ~/ 30;
    if (months < 12) return '${months}a';
    final years = diff.inDays ~/ 365;
    return '${years}y';
  }

  Future<List<Map<String, dynamic>?>> _fetchCatalogForKeys(
    List<String> keys,
  ) async {
    final fs = FirebaseFirestore.instance;
    final ordered = <String>[];
    final clean = <String>[];
    for (final raw in keys) {
      final s = raw.trim();
      if (s.isEmpty) continue;
      ordered.add(s);
      clean.add(s);
    }

    final found = <String, Map<String, dynamic>>{};
    const int chunk = 10;

    for (int i = 0; i < clean.length; i += chunk) {
      final part = clean.sublist(
        i,
        i + chunk > clean.length ? clean.length : i + chunk,
      );
      if (part.isEmpty) continue;
      try {
        final qs = await fs
            .collection('catalog_films')
            .where(FieldPath.documentId, whereIn: part)
            .get();
        for (final d in qs.docs) {
          found[d.id] = d.data();
        }
      } catch (_) {}
    }

    final missing = ordered.where((id) => !found.containsKey(id)).toList();
    for (final id in missing) {
      try {
        final snap = await fs.collection('catalog_films').doc(id).get();
        if (snap.exists) {
          found[id] = snap.data()!;
        }
      } catch (_) {}
    }

    final out = <Map<String, dynamic>?>[];
    for (final id in ordered) {
      out.add(found[id]);
    }
    return out;
  }


  @override
  void initState() {
    super.initState();
    // STREAM BURADA BAŞLATILIYOR (Sadece 1 kere)
    _userStream = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .snapshots(includeMetadataChanges: false);

    _futureActivities = _fetchActivities();
    _loadFollowing();
    _bootstrapFollowCounts();
    _loadBlockStatus();

    _followSub = FollowSystemService.I.events.listen((e) {
      if (e.targetUid != widget.uid) return;
      if (!mounted) return;
      int? newFollowers = _followersCount;
      bool? newIsFollowing = _isFollowing;

      if (newFollowers != null) {
        newFollowers = (newFollowers + (e.followed ? 1 : -1));
        if (newFollowers < 0) newFollowers = 0;
      }
      if (FirebaseAuth.instance.currentUser?.uid == e.actorUid) {
        newIsFollowing = e.followed;
      }
      if ((newFollowers != _followersCount) ||
          (newIsFollowing != _isFollowing)) {
        setState(() {
          _followersCount = newFollowers;
          _isFollowing = newIsFollowing;
        });
      }
    });
    _calcScore();
  }
  Future<void> _calcScore() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    // Kendi profilimizse hesaplamaya gerek yok
    if (myUid == null || myUid == widget.uid) return; 

    final score = await MatchService.instance.calculateMatchScore(myUid, widget.uid);
    if (mounted) {
      setState(() {
        _matchScore = score;
      });
    }
  }

  Future<void> _loadFollowing() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || myUid == widget.uid) {
      if (_isFollowing != null) setState(() => _isFollowing = null);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(myUid)
          .collection('following')
          .doc(widget.uid)
          .get(const GetOptions(source: Source.server));
      if (!mounted) return;
      final v = snap.exists;
      if (_isFollowing != v) setState(() => _isFollowing = v);
    } catch (_) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(myUid)
            .collection('following')
            .doc(widget.uid)
            .get(const GetOptions(source: Source.cache));
        if (!mounted) return;
        final v = snap.exists;
        if (_isFollowing != v) setState(() => _isFollowing = v);
      } catch (_) {
        if (!mounted) return;
        if (_isFollowing != null) setState(() => _isFollowing = null);
      }
    }
  }

  Future<void> _toggleFollow() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || myUid == widget.uid) return;
    if (_followBusy) return;
    setState(() => _followBusy = true);
    try {
      if (_isFollowing == true) {
        await FollowSystemService.I.unfollowUser(widget.uid);
      } else {
        await FollowSystemService.I.followUser(widget.uid);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _bootstrapFollowCounts() async {
    try {
      final followers = await FollowSystemService.I.fetchFollowerCountOnce(
        widget.uid,
      );
      final following = await FollowSystemService.I.fetchFollowingCountOnce(
        widget.uid,
      );
      if (!mounted) return;
      final changeFollowers = _followersCount != followers;
      final changeFollowing = _followingCount != following;
      if (changeFollowers || changeFollowing) {
        setState(() {
          _followersCount = followers;
          _followingCount = following;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadBlockStatus() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;
    final other = widget.uid;
    try {
      final fs = FirebaseFirestore.instance;
      final meBlocked = await fs
          .collection('users')
          .doc(myUid)
          .collection('blocked')
          .doc(other)
          .get(const GetOptions(source: Source.server));
      final heBlocked = await fs
          .collection('users')
          .doc(other)
          .collection('blocked')
          .doc(myUid)
          .get(const GetOptions(source: Source.server));
      if (!mounted) return;
      setState(() {
        _isBlocked = meBlocked.exists;
        _hasBlockedMe = heBlocked.exists;
      });
    } catch (_) {
      try {
        final fs = FirebaseFirestore.instance;
        final meBlocked = await fs
            .collection('users')
            .doc(myUid)
            .collection('blocked')
            .doc(other)
            .get(const GetOptions(source: Source.cache));
        final heBlocked = await fs
            .collection('users')
            .doc(other)
            .collection('blocked')
            .doc(myUid)
            .get(const GetOptions(source: Source.cache));
        if (!mounted) return;
        setState(() {
          _isBlocked = meBlocked.exists;
          _hasBlockedMe = heBlocked.exists;
        });
      } catch (_) {}
    }
  }


  @override
  void dispose() {
    _followSub?.cancel();
    super.dispose();
  }

  Widget _buildProfileTabBody(Map<String, dynamic> data) {
    final favKeys = List<String>.from(data['favoritesKeys'] ?? const []);
    final fiveKeys = List<String>.from(data['fiveStarKeys'] ?? const []);
    final disKeys = List<String>.from(data['dislikedKeys'] ?? const []);

    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _futureActivities = _fetchActivities();
        });
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          () {
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
          }(),
          // ---------------------------

          () {
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
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: items.map((e) => Chip(label: Text(e))).toList(),
                    ),
                  ],
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (age is int && age > 0) const SizedBox(height: 8),
                if (age is int && age > 0)
                  Row(
                    children: [
                      const Icon(Icons.cake, size: 18),
                      const SizedBox(width: 6),
                      Text('Yaş: $age'),
                    ],
                  ),
                chipWrap('Sevdiği türler', genres),
                chipWrap('Sevdiği yönetmenler', directors),
                chipWrap('Sevdiği oyuncular', actors),
                const SizedBox(height: 12),
              ],
            );
          }(),

          if (favKeys.isNotEmpty) ...[
            _shelfSectionFromKeys('Favori Filmler', favKeys, maxItems: 30),
            const SizedBox(height: 16),
          ],
          if (fiveKeys.isNotEmpty) ...[
            _shelfSectionFromKeys('Sevdiği Filmler', fiveKeys, maxItems: 30),
            const SizedBox(height: 16),
          ],
          if (disKeys.isNotEmpty) ...[
            _shelfSectionFromKeys('Sevmediği Filmler', disKeys, maxItems: 30),
            const SizedBox(height: 16),
          ],

          Text('Watchlist', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final List<dynamic> keysDyn =
                  (data['watchlistKeys'] ??
                          data['watchlist_keys'] ??
                          data['watchlistIds'] ??
                          data['watchlist_ids'] ??
                          [])
                      as List<dynamic>;
              final keys = keysDyn
                  .map((e) => e.toString())
                  .where((e) => e.isNotEmpty)
                  .toList();
              final List<dynamic> inlineDyn =
                  (data['watchlistFilms'] ?? data['watchlist'] ?? [])
                      as List<dynamic>;
              final List<Map<String, dynamic>> inlineFilms = inlineDyn
                  .whereType<Map<String, dynamic>>()
                  .toList();
              if (keys.isEmpty && inlineFilms.isEmpty)
                return const Text('Watchlist boş.');
              final limited = keys.take(30).toList();
              final hash = limited.join('|');
              return FutureBuilder<List<Map<String, dynamic>?>>(
                future: limited.isEmpty
                    ? Future.value(const <Map<String, dynamic>?>[])
                    : (_watchlistFutureCache[hash] ??= _fetchCatalogForKeys(
                        limited,
                      )),
                builder: (context, fsnap) {
                  List<Map<String, dynamic>> films = const [];
                  if (fsnap.connectionState == ConnectionState.waiting &&
                      inlineFilms.isEmpty) {
                    return const SizedBox(
                      height: 180,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (fsnap.hasData && fsnap.data != null) {
                    films = fsnap.data!
                        .where((m) => m != null)
                        .map((m) => m!)
                        .toList();
                  }
                  if (films.isEmpty && inlineFilms.isNotEmpty)
                    films = inlineFilms;
                  if (films.isEmpty) return const Text('Watchlist boş.');
                  return SizedBox(
                    height: 180,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: films.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, i) {
                        final film = films[i];
                        final poster =
                            (film['poster'] ??
                                    film['posterUrl'] ??
                                    film['image'] ??
                                    '')
                                as String;
                        final title =
                            (film['title'] ?? film['name'] ?? film['t'] ?? '')
                                as String;
                        // Watchlist de ID ile düzeltilsin
                        final tmdbId = _extractTmdbId(film); // <--- EKLENDİ

                        return AspectRatio(
                          aspectRatio: 2 / 3,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                PosterImage(
                                  posterUrl: poster,
                                  tmdbId: tmdbId, // <--- EKLENDİ
                                  title: title,
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
                                        title,
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
          ),
        ],
      ),
    );
  }

  Widget _buildActivitiesTabBody() {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _futureActivities = _fetchActivities();
        });
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          Row(
            children: [
              Text(
                'Aktiviteler',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Yenile',
                onPressed: () {
                  setState(() => _futureActivities = _fetchActivities());
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
            future: _futureActivities,
            builder: (context, asnap) {
              if (asnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (asnap.hasError) {
                return Text(
                  'Aktiviteler yüklenemedi: ${asnap.error}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.redAccent),
                );
              }
              final docs = asnap.data ?? const [];
              if (docs.isEmpty) return const Text('Henüz aktivite yok.');
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                padding: EdgeInsets.zero,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final m = docs[i].data();
                  final dt = (m['createdAt'] as Timestamp?)?.toDate();
                  final time = dt == null ? '' : _timeAgo(dt);
                  final poster =
                      (m['moviePoster'] ?? m['moviePosterUrl'] ?? '') as String;
                  final title = (m['movieTitle'] ?? '') as String;
                  
                  // Aktivite öğelerinde genelde ID saklanmaz ama varsa kullan
                  // m['movie'] içinde tmdbId olabilir mi? Şemaya bağlı. 
                  // Şimdilik basit bırakıyoruz.

                  return _ActivityItem(
                    displayName: (m['displayName'] ?? '') as String,
                    text: (m['text'] ?? '') as String,
                    timeLabel: time,
                    likeCount: (m['likeCount'] ?? 0) is int
                        ? m['likeCount'] as int
                        : ((m['likeCount'] ?? 0) as num).toInt(),
                    replyCount: (m['replyCount'] ?? 0) is int
                        ? m['replyCount'] as int
                        : ((m['replyCount'] ?? 0) as num).toInt(),
                    repostCount: (m['repostCount'] ?? 0) is int
                        ? m['repostCount'] as int
                        : ((m['repostCount'] ?? 0) as num).toInt(),
                    posterUrl: poster,
                    movieTitle: title,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }


 void _showReportDialog(String myUid, String targetUid) {
    String selectedReason = 'Spam'; // Varsayılan
    final TextEditingController detailsCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Kullanıcıyı Bildir'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Bu kullanıcıyı neden bildiriyorsunuz?'),
                    const SizedBox(height: 10),
                    
                    RadioListTile<String>(
                      title: const Text('Spam veya Yanıltıcı'),
                      value: 'Spam',
                      groupValue: selectedReason,
                      onChanged: (v) => setDialogState(() => selectedReason = v!),
                    ),
                    RadioListTile<String>(
                      title: const Text('Hakaret / Zorbalık'),
                      value: 'Harassment',
                      groupValue: selectedReason,
                      onChanged: (v) => setDialogState(() => selectedReason = v!),
                    ),
                    RadioListTile<String>(
                      title: const Text('Uygunsuz İçerik'),
                      value: 'Inappropriate',
                      groupValue: selectedReason,
                      onChanged: (v) => setDialogState(() => selectedReason = v!),
                    ),
                    RadioListTile<String>(
                      title: const Text('Diğer'),
                      value: 'Other',
                      groupValue: selectedReason,
                      onChanged: (v) => setDialogState(() => selectedReason = v!),
                    ),

                    if (selectedReason == 'Other')
                      TextField(
                        controller: detailsCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Lütfen açıklayın...',
                          labelText: 'Açıklama',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('İptal'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    // Servis çağrısı
                    UserProfileService.instance.reportUser(
                      reporterId: myUid,
                      reportedId: targetUid,
                      reason: selectedReason,
                      details: detailsCtrl.text.trim(),
                    ).then((_) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          // İstenen mesaj değişikliği:
                          const SnackBar(content: Text('Bildirim için teşekkürler.')),
                        );
                      }
                    });
                  },
                  child: const Text('Bildir'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          actions: [
            // Mevcut kodunuzdaki actions: [ PopupMenuButton... ] kısmını bulun ve şöyle değiştirin:

PopupMenuButton<String>(
  icon: const Icon(Icons.more_vert),
  onSelected: (value) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    if (value == 'report') {
      // ESKİ KODU SİLİN -> YENİ DİYALOĞU ÇAĞIRIN
      _showReportDialog(myUid, widget.uid); 
      
    } 
  },
  itemBuilder: (ctx) => const [
    PopupMenuItem(
      value: 'report',
      child: ListTile(
        leading: Icon(Icons.flag_outlined),
        title: Text('Kişiyi bildir'),
        contentPadding: EdgeInsets.zero,
      ),
    ),
  ],
),
          ],
        ),
        extendBodyBehindAppBar: true,
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _userStream,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snap.hasData || !snap.data!.exists) {
              return const Center(child: Text('Kullanıcı bulunamadı'));
            }
            final data = snap.data!.data()!;
            final displayName = (data['displayName'] ?? '') as String;
            final lb = (data['letterboxdUsername'] ?? '') as String;
            final photoURL = (data['photoURL'] ?? '') as String;
            final appUsername = (data['username'] ?? '') as String;

            final titleText = appUsername.isNotEmpty
                ? appUsername
                : (displayName.isNotEmpty
                      ? displayName
                      : (lb.isNotEmpty ? '@$lb' : '(İsimsiz)'));

            return NestedScrollView(
              headerSliverBuilder: (context, inner) {
                return [
                  SliverToBoxAdapter(
                    child: Stack(
                      children: [
                        SizedBox(
                          height:
                              MediaQuery.of(context).padding.top +
                              kToolbarHeight +
                              165,
                          child: Stack(
                            children: [
                              _blurBackdropFromKeys(
                                List<String>.from(
                                  (data['favoritesKeys'] ?? const []),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            MediaQuery.of(context).padding.top +
                                kToolbarHeight +
                                12,
                            16,
                            0,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 36,
                                    backgroundImage: photoURL.isNotEmpty
                                        ? NetworkImage(photoURL)
                                        : null,
                                    child: photoURL.isEmpty
                                        ? Text(
                                            displayName.isNotEmpty
                                                ? displayName[0].toUpperCase()
                                                : '?',
                                            style: const TextStyle(
                                              fontSize: 24,
                                            ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          titleText,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleLarge,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (displayName.isNotEmpty &&
                                            titleText != displayName)
                                          Text(
                                            displayName,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (_isBlocked || _hasBlockedMe)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error.withOpacity(0.4),
                                    ),
                                  ),
                                  child: Row(
                                    children: const [
                                      Icon(Icons.block, size: 16),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Bu kullanıcıyla etkileşim engellendi.',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outlineVariant,
                                        width: 0.6,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.groups, size: 16),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Takipçi',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          (_followersCount ?? 0).toString(),
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outlineVariant,
                                        width: 0.6,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.person_add_alt,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Takip',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          (_followingCount ?? 0).toString(),
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 17),
                              if (lb.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10.0),
                                  child: Text(
                                    'Letterboxd: @$lb',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                ),
                              // --- BUTONLARIN BAŞLANGICI ---
Padding(
  padding: const EdgeInsets.symmetric(vertical: 12.0),
  child: Row(
    children: [
      // 1. MESAJ GÖNDER BUTONU (Varsa)
      if (!_isBlocked &&
          !_hasBlockedMe &&
          FirebaseAuth.instance.currentUser?.uid != widget.uid) ...[
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: () async {
              final myUid = FirebaseAuth.instance.currentUser?.uid;
              if (myUid == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Giriş yapmalısın.')),
                );
                return;
              }
              final chatId =
                  await ChatService.instance.getOrCreateChat(myUid, widget.uid);
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatRoomScreen(
                    chatId: chatId,
                    otherUid: widget.uid,
                  ),
                ),
              );
            },
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.message_rounded, size: 20),
            label: const Text('Mesaj'),
          ),
        ),
        // Eğer takip butonu da gösterilecekse araya boşluk koy
        if (FirebaseAuth.instance.currentUser?.uid != null &&
            FirebaseAuth.instance.currentUser!.uid != widget.uid)
          const SizedBox(width: 10),
      ],

      // 2. TAKİP ET BUTONU (Varsa)
      if (FirebaseAuth.instance.currentUser?.uid != null &&
          FirebaseAuth.instance.currentUser!.uid != widget.uid)
        Expanded(
          child: FilledButton.icon(
            onPressed: _followBusy ? null : _toggleFollow,
            style: FilledButton.styleFrom(
              // İstenilen YEŞİL renk ayarı:
              backgroundColor: Colors.green,
              foregroundColor: Colors.white, // Yazı ve ikon rengi
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: _followBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    _isFollowing == true
                        ? Icons.check
                        : Icons.person_add_alt_1,
                    size: 20,
                  ),
            label: Text(
              _isFollowing == true ? 'Takiptesin' : 'Takip et',
            ),
          ),
        ),
    ],
  ),
),
// --- BUTONLARIN BİTİŞİ ---
                              const SizedBox(height: 12),
                              TabBar(
                                indicator: UnderlineTabIndicator(
                                  borderSide: BorderSide(
                                    width: 2,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
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
                                unselectedLabelStyle: Theme.of(
                                  context,
                                ).textTheme.titleSmall,
                                labelColor: Theme.of(
                                  context,
                                ).colorScheme.onSurface,
                                unselectedLabelColor: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.7),
                                tabs: const [
                                  Tab(text: 'Filmler'),
                                  Tab(text: 'Aktiviteler'),
                                ],
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                        // --- YEŞİL UYUM DAİRESİ (AppBar'ın Altında, Sağ Üstte) ---
      if (_matchScore != null && _matchScore! > 0)
        Positioned(
          // AppBar boyutu + Status bar + biraz boşluk (10px) kadar aşağıya itiyoruz
          top: MediaQuery.of(context).padding.top + kToolbarHeight + 10,
          right: 16, // Sağdan boşluk
          child: Container(
            width: 60, // Biraz daha belirgin olsun diye büyüttük
            height: 60,
            decoration: BoxDecoration(
              color: Colors.green.shade600,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '%$_matchScore',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
                const Text(
                  'UYUM',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w500,
                    height: 1.0,
                  ),
                ),
              ],
            ),
          ),
        ),
                      ],
                    ),
                  ),
                ];
              },
              body: TabBarView(
                children: [
                  _buildProfileTabBody(data),
                  _buildActivitiesTabBody(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  final String displayName;
  final String text;
  final String timeLabel;
  final int likeCount;
  final int replyCount;
  final int repostCount;
  final String posterUrl; // boş olabilir
  final String movieTitle; // boş olabilir

  const _ActivityItem({
    required this.displayName,
    required this.text,
    required this.timeLabel,
    required this.likeCount,
    required this.replyCount,
    required this.repostCount,
    required this.posterUrl,
    required this.movieTitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Row stats() {
      Text stat(IconData icon, int n) => Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(icon, size: 14, color: cs.onSurfaceVariant),
            ),
            const WidgetSpan(child: SizedBox(width: 6)),
            TextSpan(text: '$n', style: theme.textTheme.bodySmall),
          ],
        ),
      );
      return Row(
        children: [
          stat(Icons.favorite_border, likeCount),
          const SizedBox(width: 16),
          stat(Icons.mode_comment_outlined, replyCount),
          const SizedBox(width: 16),
          stat(Icons.repeat_outlined, repostCount),
        ],
      );
    }

    final hasPoster = posterUrl.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant, width: 0.6),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPoster)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: PosterImage(
                posterUrl: posterUrl,
                title: movieTitle,
                width: 56,
                height: 84,
                fit: BoxFit.cover,
              ),
            ),
          if (hasPoster) const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName.isNotEmpty ? displayName : 'Kullanıcı',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                if (text.isNotEmpty)
                  Text(text, style: theme.textTheme.bodyMedium),
                if (movieTitle.isNotEmpty && !hasPoster)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.local_movies, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            movieTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    stats(),
                    const Spacer(),
                    if (timeLabel.isNotEmpty)
                      Text(
                        'Paylaştı  $timeLabel',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}