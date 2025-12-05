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
import 'package:fluttergirdi/screens/post_detail_screen.dart';

// --- İMPORTLAR ---
import 'package:fluttergirdi/services/custom_list_service.dart';
import 'package:fluttergirdi/models/custom_list.dart';
import 'package:fluttergirdi/screens/custom_list_detail_screen.dart';
import 'package:fluttergirdi/widgets/movie_action_helper.dart';
import 'package:fluttergirdi/models/shelf_target.dart';
import 'package:fluttergirdi/models/gamification.dart'; // Rozetler için

// Aktivite Verisi Modeli
class _ActivityItemData {
  final String id; 
  final String text;
  final DateTime? createdAt;
  final String posterUrl; 
  final String title; 
  final int likeCount;
  final int replyCount;
  final int repostCount;
  final int? tmdbId; 

  const _ActivityItemData({
    required this.id,
    required this.text,
    required this.createdAt,
    this.posterUrl = '',
    this.title = '',
    this.likeCount = 0,
    this.replyCount = 0,
    this.repostCount = 0,
    this.tmdbId,
  });
}

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

  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream;

  // Katalog önbelleği
  final Map<String, Future<List<Map<String, dynamic>?>>> _catalogFutureCache = {};

  int? _extractTmdbId(Map<String, dynamic> m) {
    final val = m['tmdbId'];
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val);
    return null;
  }

  // --- PROFİL RESMİ BÜYÜTME ---
  void _showEnlargedImage(String imageUrl) {
    if (imageUrl.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: true, 
      barrierColor: Colors.black.withOpacity(0.9), 
      builder: (ctx) {
        return GestureDetector(
          onTap: () => Navigator.pop(ctx), 
          child: InteractiveViewer(
            child: Center(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
              ),
            ),
          ),
        );
      },
    );
  }

  // --- TAKİP LİSTESİ GÖSTERME ---
  void _showUserList(String title, String collection) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (_) => _UserListSheet(title: title, uid: widget.uid, collection: collection),
    );
  }

  Widget _blurBackdropFromKeys(List<String> favKeys) {
    if (favKeys.isEmpty) return const SizedBox.shrink();
    final firstKey = favKeys.first.trim();
    if (firstKey.isEmpty) return const SizedBox.shrink();
    final cacheKey = 'backdrop:$firstKey';
    return FutureBuilder<List<Map<String, dynamic>?>>(
      future: (_catalogFutureCache[cacheKey] ??= _fetchCatalogForKeys([firstKey])),
      builder: (context, snap) {
        final m = (snap.data != null && snap.data!.isNotEmpty) ? snap.data!.first : null;
        if (m == null) return const SizedBox.shrink();

        final url = (m['poster'] ?? m['posterUrl'] ?? m['image'] ?? '') as String;
        final tmdbId = _extractTmdbId(m);
        final title = _catalogTitle(m);

        if (url.isEmpty && tmdbId == null) return const SizedBox.shrink();

        return Positioned.fill(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: PosterImage(
                  posterUrl: url,
                  tmdbId: tmdbId,
                  title: title,
                  fit: BoxFit.cover,
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Color(0x99000000), Color(0x66000000)],
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

  Widget _shelfSectionFromKeys(String title, List<String> keys, {int maxItems = 30}) {
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
              return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()));
            }
            final films = (snap.data ?? []).where((m) => m != null).map((m) => m!).toList();
            if (films.isEmpty) {
              return Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('$title bulunamadı.'));
            }
            return SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: films.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final m = films[i];
                  final poster = (m['poster'] ?? m['posterUrl'] ?? m['image'] ?? '') as String;
                  final t = _catalogTitle(m);
                  final tmdbId = _extractTmdbId(m);

                  return AspectRatio(
                    aspectRatio: 2 / 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          PosterImage(posterUrl: poster, tmdbId: tmdbId, title: t, fit: BoxFit.cover),
                          if (t.isNotEmpty)
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                color: Colors.black54,
                                child: Text(
                                  t,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, color: Colors.white),
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

  final Map<String, Future<List<Map<String, dynamic>?>>> _watchlistFutureCache = {};

  Future<List<Map<String, dynamic>?>> _fetchCatalogForKeys(List<String> keys) async {
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
      final part = clean.sublist(i, i + chunk > clean.length ? clean.length : i + chunk);
      if (part.isEmpty) continue;
      try {
        final qs = await fs.collection('catalog_films').where(FieldPath.documentId, whereIn: part).get();
        for (final d in qs.docs) found[d.id] = d.data();
      } catch (_) {}
    }
    final missing = ordered.where((id) => !found.containsKey(id)).toList();
    for (final id in missing) {
      try {
        final snap = await fs.collection('catalog_films').doc(id).get();
        if (snap.exists) found[id] = snap.data()!;
      } catch (_) {}
    }
    final out = <Map<String, dynamic>?>[];
    for (final id in ordered) out.add(found[id]);
    return out;
  }

  @override
  void initState() {
    super.initState();
    _userStream = FirebaseFirestore.instance.collection('users').doc(widget.uid).snapshots(includeMetadataChanges: false);
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
      if ((newFollowers != _followersCount) || (newIsFollowing != _isFollowing)) {
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
    if (myUid == null || myUid == widget.uid) return;
    final score = await MatchService.instance.calculateMatchScore(myUid, widget.uid);
    if (mounted) setState(() => _matchScore = score);
  }

  Future<void> _loadFollowing() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || myUid == widget.uid) {
      if (_isFollowing != null) setState(() => _isFollowing = null);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(myUid).collection('following').doc(widget.uid).get(const GetOptions(source: Source.server));
      if (!mounted) return;
      final v = snap.exists;
      if (_isFollowing != v) setState(() => _isFollowing = v);
    } catch (_) {
      try {
        final snap = await FirebaseFirestore.instance.collection('users').doc(myUid).collection('following').doc(widget.uid).get(const GetOptions(source: Source.cache));
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
      final followers = await FollowSystemService.I.fetchFollowerCountOnce(widget.uid);
      final following = await FollowSystemService.I.fetchFollowingCountOnce(widget.uid);
      if (!mounted) return;
      if (_followersCount != followers || _followingCount != following) {
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
      final meBlocked = await fs.collection('users').doc(myUid).collection('blocked').doc(other).get(const GetOptions(source: Source.server));
      final heBlocked = await fs.collection('users').doc(other).collection('blocked').doc(myUid).get(const GetOptions(source: Source.server));
      if (!mounted) return;
      setState(() {
        _isBlocked = meBlocked.exists;
        _hasBlockedMe = heBlocked.exists;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _followSub?.cancel();
    super.dispose();
  }

  void _showReportDialog(String myUid, String targetUid) {
    String selectedReason = 'Spam';
    final TextEditingController detailsCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Kullanıcıyı Bildir'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Bu kullanıcıyı neden bildiriyorsunuz?'),
                  const SizedBox(height: 10),
                  RadioListTile<String>(title: const Text('Spam veya Yanıltıcı'), value: 'Spam', groupValue: selectedReason, onChanged: (v) => setDialogState(() => selectedReason = v!)),
                  RadioListTile<String>(title: const Text('Hakaret / Zorbalık'), value: 'Harassment', groupValue: selectedReason, onChanged: (v) => setDialogState(() => selectedReason = v!)),
                  RadioListTile<String>(title: const Text('Uygunsuz İçerik'), value: 'Inappropriate', groupValue: selectedReason, onChanged: (v) => setDialogState(() => selectedReason = v!)),
                  RadioListTile<String>(title: const Text('Diğer'), value: 'Other', groupValue: selectedReason, onChanged: (v) => setDialogState(() => selectedReason = v!)),
                  if (selectedReason == 'Other')
                    TextField(
                      controller: detailsCtrl,
                      decoration: const InputDecoration(hintText: 'Lütfen açıklayın...', labelText: 'Açıklama', border: OutlineInputBorder()),
                      maxLines: 3,
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('İptal')),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  UserProfileService.instance.reportUser(
                    reporterId: myUid, reportedId: targetUid, reason: selectedReason, details: detailsCtrl.text.trim(),
                  ).then((_) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bildirim için teşekkürler.')));
                  });
                },
                child: const Text('Bildir'),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3, // 3 SEKME
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) async {
                final myUid = FirebaseAuth.instance.currentUser?.uid;
                if (myUid == null) return;
                if (value == 'report') _showReportDialog(myUid, widget.uid);
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem(value: 'report', child: ListTile(leading: Icon(Icons.flag_outlined), title: Text('Kişiyi bildir'), contentPadding: EdgeInsets.zero)),
              ],
            ),
          ],
        ),
        extendBodyBehindAppBar: true,
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _userStream,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snap.hasData || !snap.data!.exists) return const Center(child: Text('Kullanıcı bulunamadı'));
            
            final data = snap.data!.data()!;
            final displayName = (data['displayName'] ?? '') as String;
            final lb = (data['letterboxdUsername'] ?? '') as String;
            final photoURL = (data['photoURL'] ?? '') as String;
            final appUsername = (data['username'] ?? '') as String;

            final titleText = appUsername.isNotEmpty ? appUsername : (displayName.isNotEmpty ? displayName : (lb.isNotEmpty ? '@$lb' : '(İsimsiz)'));

            return NestedScrollView(
              headerSliverBuilder: (context, inner) {
                return [
                  SliverToBoxAdapter(
                    child: Stack(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).padding.top + kToolbarHeight + 165,
                          child: Stack(
                            children: [_blurBackdropFromKeys(List<String>.from((data['favoritesKeys'] ?? const [])))],
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + kToolbarHeight + 12, 16, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => _showEnlargedImage(photoURL),
                                    child: CircleAvatar(
                                      radius: 36,
                                      backgroundImage: photoURL.isNotEmpty ? NetworkImage(photoURL) : null,
                                      child: photoURL.isEmpty
                                          ? Text(
                                              displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
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
                                        Text(titleText, style: Theme.of(context).textTheme.titleLarge, overflow: TextOverflow.ellipsis),
                                        if (displayName.isNotEmpty && titleText != displayName)
                                          Text(displayName, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
                                        
                                        // --- YENİ: ROZET ALANI ---
                                        StreamBuilder<DocumentSnapshot>(
                                          stream: FirebaseFirestore.instance.collection('users').doc(widget.uid).snapshots(),
                                          builder: (context, snap) {
                                            if (!snap.hasData || !snap.data!.exists) return const SizedBox.shrink();
                                            final uData = snap.data!.data() as Map<String, dynamic>?;
                                            final badges = List<String>.from(uData?['badges'] ?? []);
                                            if (badges.isEmpty) return const SizedBox.shrink();

                                            return Padding(
                                              padding: const EdgeInsets.only(top: 4.0),
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
                                    border: Border.all(color: Theme.of(context).colorScheme.error.withOpacity(0.4)),
                                  ),
                                  child: Row(children: const [Icon(Icons.block, size: 16), SizedBox(width: 8), Expanded(child: Text('Bu kullanıcıyla etkileşim engellendi.'))]),
                                ),
                              Row(
                                children: [
                                  _StatContainer(
                                    icon: Icons.groups, 
                                    label: 'Takipçi', 
                                    count: _followersCount ?? 0,
                                    onTap: () => _showUserList('Takipçiler', 'followers'),
                                  ),
                                  const SizedBox(width: 8),
                                  _StatContainer(
                                    icon: Icons.person_add_alt, 
                                    label: 'Takip', 
                                    count: _followingCount ?? 0,
                                    onTap: () => _showUserList('Takip Edilenler', 'following'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 17),
                              if (lb.isNotEmpty)
                                Padding(padding: const EdgeInsets.only(bottom: 10.0), child: Text('Letterboxd: @$lb', style: Theme.of(context).textTheme.bodyMedium)),
                              
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12.0),
                                child: Row(
                                  children: [
                                    if (!_isBlocked && !_hasBlockedMe && FirebaseAuth.instance.currentUser?.uid != widget.uid) ...[
                                      Expanded(
                                        child: FilledButton.tonalIcon(
                                          onPressed: () async {
                                            final myUid = FirebaseAuth.instance.currentUser?.uid;
                                            if (myUid == null) return;
                                            final chatId = await ChatService.instance.getOrCreateChat(myUid, widget.uid);
                                            if (!context.mounted) return;
                                            Navigator.push(context, MaterialPageRoute(builder: (_) => ChatRoomScreen(chatId: chatId, otherUid: widget.uid)));
                                          },
                                          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                          icon: const Icon(Icons.message_rounded, size: 20),
                                          label: const Text('Mesaj'),
                                        ),
                                      ),
                                      if (FirebaseAuth.instance.currentUser?.uid != null && FirebaseAuth.instance.currentUser!.uid != widget.uid)
                                        const SizedBox(width: 10),
                                    ],
                                    if (FirebaseAuth.instance.currentUser?.uid != null && FirebaseAuth.instance.currentUser!.uid != widget.uid)
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed: _followBusy ? null : _toggleFollow,
                                          style: FilledButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          icon: _followBusy
                                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                              : Icon(_isFollowing == true ? Icons.check : Icons.person_add_alt_1, size: 20),
                                          label: Text(_isFollowing == true ? 'Takiptesin' : 'Takip et'),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              TabBar(
                                indicator: UnderlineTabIndicator(borderSide: BorderSide(width: 2, color: Theme.of(context).colorScheme.primary)),
                                indicatorSize: TabBarIndicatorSize.tab,
                                overlayColor: WidgetStateProperty.all(Colors.transparent),
                                labelPadding: const EdgeInsets.symmetric(vertical: 6),
                                labelStyle: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                                unselectedLabelStyle: Theme.of(context).textTheme.titleSmall,
                                labelColor: Theme.of(context).colorScheme.onSurface,
                                unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                tabs: const [
                                  Tab(text: 'Filmler'),
                                  Tab(text: 'Aktiviteler'),
                                  Tab(text: 'Listeler'),
                                ],
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                        if (_matchScore != null && _matchScore! > 0)
                          Positioned(
                            top: MediaQuery.of(context).padding.top + kToolbarHeight + 10,
                            right: 16,
                            child: Container(
                              width: 60, height: 60,
                              decoration: BoxDecoration(
                                color: Colors.green.shade600,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 3))],
                              ),
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('%$_matchScore', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, height: 1.0)),
                                  const Text('UYUM', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w500, height: 1.0)),
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
                  _ActivitiesTab(uid: widget.uid),
                  _PublicListsTab(uid: widget.uid),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProfileTabBody(Map<String, dynamic> data) {
    final favKeys = List<String>.from(data['favoritesKeys'] ?? const []);
    final fiveKeys = List<String>.from(data['fiveStarKeys'] ?? const []);
    final disKeys = List<String>.from(data['dislikedKeys'] ?? const []);
    final bio = (data['bio'] ?? '').toString();
    final age = data['age'];
    final genres = List<String>.from(data['favGenres'] ?? const []);
    final directors = List<String>.from(data['favDirectors'] ?? const []);
    final actors = List<String>.from(data['favActors'] ?? const []);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (bio.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 16.0), child: Text(bio, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4))),
        if (age != null || genres.isNotEmpty || directors.isNotEmpty || actors.isNotEmpty)
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (age is int && age > 0) Padding(padding: const EdgeInsets.only(bottom: 8.0), child: Row(children: [const Icon(Icons.cake, size: 18), const SizedBox(width: 6), Text('Yaş: $age')])),
            if (genres.isNotEmpty) _ChipsSection(title: 'Sevdiği türler', items: genres),
            if (directors.isNotEmpty) _ChipsSection(title: 'Sevdiği yönetmenler', items: directors),
            if (actors.isNotEmpty) _ChipsSection(title: 'Sevdiği oyuncular', items: actors),
            const SizedBox(height: 12),
          ]),
        if (favKeys.isNotEmpty) ...[_shelfSectionFromKeys('Favori Filmler', favKeys, maxItems: 30), const SizedBox(height: 16)],
        if (fiveKeys.isNotEmpty) ...[_shelfSectionFromKeys('Sevdiği Filmler', fiveKeys, maxItems: 30), const SizedBox(height: 16)],
        if (disKeys.isNotEmpty) ...[_shelfSectionFromKeys('Sevmediği Filmler', disKeys, maxItems: 30), const SizedBox(height: 16)],
        Text('Watchlist', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _WatchlistSection(data: data, watchlistFutureCache: _watchlistFutureCache, fetchCatalog: _fetchCatalogForKeys),
      ],
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _loadActivities,
      child: ListView(
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
      ),
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
    final cs = theme.colorScheme;

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
                  if (item.text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4.0), child: Text(item.text, maxLines: 4, overflow: TextOverflow.ellipsis)),
                  if (item.title.isNotEmpty && item.posterUrl.isEmpty && item.tmdbId == null)
                    Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [const Icon(Icons.local_movies, size: 16), const SizedBox(width: 6), Expanded(child: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall))])),
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0),
                    child: Row(children: [
                      const Icon(Icons.favorite_border, size: 16), const SizedBox(width: 4), Text('${item.likeCount}'), 
                      const SizedBox(width: 12), 
                      const Icon(Icons.mode_comment_outlined, size: 16), const SizedBox(width: 4), Text('${item.replyCount}'), 
                      const SizedBox(width: 12), 
                      const Icon(Icons.repeat, size: 16),
                      const Spacer(),
                      if (timeLabel.isNotEmpty) Text('Paylaştı  $timeLabel', style: Theme.of(context).textTheme.labelSmall),
                    ]),
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
class _PublicListsTab extends StatefulWidget {
  final String uid;
  const _PublicListsTab({required this.uid});

  @override
  State<_PublicListsTab> createState() => _PublicListsTabState();
}

class _PublicListsTabState extends State<_PublicListsTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 500));
        setState((){});
      },
      child: StreamBuilder<List<CustomList>>(
        stream: CustomListService.instance.getUserLists(widget.uid),
        builder: (context, snapshot) {
           if(snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
           final lists = snapshot.data ?? [];
           
           // Sadece herkese açık listeler
           final publicLists = lists.where((l) => l.isPublic).toList();

           if (publicLists.isEmpty) {
             return const Center(child: Text("Henüz liste oluşturulmamış."));
           }

           return ListView.builder(
             padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
             itemCount: publicLists.length,
             itemBuilder: (context, index) {
               final list = publicLists[index];
               return _CustomListCard(list: list);
             }
           );
        }
      )
    );
  }
}

class _CustomListCard extends StatelessWidget {
  final CustomList list;
  const _CustomListCard({required this.list});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => CustomListDetailScreen(list: list, isMyList: false)));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 100,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
              child: SizedBox(
                width: 70,
                height: double.infinity,
                child: list.coverImageUrl != null
                    ? PosterImage(posterUrl: list.coverImageUrl!, title: list.title, fit: BoxFit.cover)
                    : Container(color: Colors.grey.shade800, child: const Icon(Icons.list, color: Colors.white24)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(list.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text('${list.movieCount} film', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
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

class _StatContainer extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final VoidCallback? onTap; // Tıklanabilir yapıldı

  const _StatContainer({required this.icon, required this.label, required this.count, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 0.6),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Text(count.toString(), style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ChipsSection extends StatelessWidget {
  final String title;
  final List<String> items;
  const _ChipsSection({required this.title, required this.items});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: items.map((e) => Chip(label: Text(e))).toList()),
        ],
      ),
    );
  }
}

class _WatchlistSection extends StatelessWidget {
  final Map<String, dynamic> data;
  final Map<String, Future<List<Map<String, dynamic>?>>> watchlistFutureCache;
  final Future<List<Map<String, dynamic>?>> Function(List<String>) fetchCatalog;

  const _WatchlistSection({required this.data, required this.watchlistFutureCache, required this.fetchCatalog});

  int? _extractTmdbId(Map<String, dynamic> m) {
    final val = m['tmdbId'];
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final List<dynamic> keysDyn = (data['watchlistKeys'] ?? []) as List<dynamic>;
    final keys = keysDyn.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    final limited = keys.take(30).toList();
    final hash = limited.join('|');
    
    return FutureBuilder<List<Map<String, dynamic>?>>(
      future: limited.isEmpty ? Future.value([]) : (watchlistFutureCache[hash] ??= fetchCatalog(limited)),
      builder: (context, fsnap) {
        if (fsnap.connectionState == ConnectionState.waiting) return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()));
        final films = (fsnap.data ?? []).where((m) => m != null).map((m) => m!).toList();
        if (films.isEmpty) return const Text('Watchlist boş.');
        return SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: films.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final film = films[i];
              final poster = (film['poster'] ?? film['posterUrl'] ?? '') as String;
              final title = (film['title'] ?? '') as String;
              final tmdbId = _extractTmdbId(film);
              return AspectRatio(
                aspectRatio: 2 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PosterImage(posterUrl: poster, tmdbId: tmdbId, title: title, fit: BoxFit.cover),
                      if (title.isNotEmpty)
                        Align(alignment: Alignment.bottomCenter, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), color: Colors.black54, child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white), textAlign: TextAlign.center))),
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
}

// --- KULLANICI LİSTESİ PENCERESİ (YENİ) ---
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
                    final docId = docs[index].id; // docId = user UID
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