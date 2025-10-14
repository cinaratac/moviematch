import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../screens/public_profile_screen.dart';
import '../services/follow_system_service.dart';
import '../screens/chat_room_screen.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';

import 'dart:async';

// simple in-memory future cache so multiple PostTile instances don't refetch the same user doc repeatedly
final Map<String, Future<String?>> _lbHandleCache = {};

Future<String?> _lbHandleFor(String uid) {
  if (_lbHandleCache.containsKey(uid)) return _lbHandleCache[uid]!;
  _lbHandleCache[uid] = FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .get()
      .then((snap) {
        if (!snap.exists) return null;
        final m = snap.data();
        if (m == null) return null;
        final lb = (m['letterboxdUsername'] ?? '') as String;
        return lb.isNotEmpty ? lb : null;
      })
      .catchError((_) => null);
  return _lbHandleCache[uid]!;
}

class PostTile extends StatelessWidget {
  final String postId;
  final String authorId;
  final String displayName;
  final String handle; // '@lbHandle' ya da ''
  final String photoURL;
  final String timeLabel;
  final String text;
  final int likeCount;
  final int replyCount;
  final int repostCount;
  final String? movieTitle;
  final String? moviePoster;

  // Parent’tan gelen aksiyonlar (FeedPage optimize kalsın)
  final Future<void> Function(String postId, bool like) onToggleLike;
  final Future<void> Function(String otherUid) onStartChat;
  final Future<void> Function(String otherUid) onFollow;
  final Future<void> Function(String postId) onReport;

  const PostTile({
    super.key,
    required this.postId,
    required this.authorId,
    required this.displayName,
    required this.handle,
    required this.photoURL,
    required this.timeLabel,
    required this.text,
    required this.likeCount,
    required this.replyCount,
    required this.repostCount,
    this.movieTitle,
    this.moviePoster,
    required this.onToggleLike,
    required this.onStartChat,
    required this.onFollow,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final me = FirebaseAuth.instance.currentUser?.uid;
    final isOwner = me == authorId;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar, name, handle, follow/menu row replaced with StreamBuilder:
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(authorId)
                        .snapshots(includeMetadataChanges: false),
                    builder: (context, uSnap) {
                      String effName = displayName;
                      String effHandle = handle; // may be like '@lb'
                      String effPhoto = photoURL;

                      if (uSnap.hasData && uSnap.data!.exists) {
                        final u = uSnap.data!.data()!;
                        final username = (u['username'] ?? '') as String;
                        final disp = (u['displayName'] ?? '') as String;
                        final lb = (u['letterboxdUsername'] ?? '') as String;
                        final p = (u['photoURL'] ?? '') as String;
                        if (disp.isNotEmpty) effName = disp;
                        // prefer username, else letterboxd
                        if (username.isNotEmpty) {
                          effHandle = '@$username';
                        } else if (lb.isNotEmpty) {
                          effHandle = '@$lb';
                        }
                        if (p.isNotEmpty) effPhoto = p;
                      }

                      return Row(
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      PublicProfileScreen(uid: authorId),
                                ),
                              );
                            },
                            child: CircleAvatar(
                              radius: 20,
                              backgroundImage: effPhoto.isNotEmpty
                                  ? NetworkImage(effPhoto)
                                  : null,
                              child: effPhoto.isEmpty
                                  ? const Icon(Icons.person)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        PublicProfileScreen(uid: authorId),
                                  ),
                                );
                              },
                              child: Text(
                                effName.isEmpty ? 'Kullanıcı' : effName,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              (effHandle.isNotEmpty ? '$effHandle · ' : '') +
                                  timeLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Spacer(),
                          if (!isOwner)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: _FollowButton(authorId: authorId),
                            ),
                          _PostMenu(
                            authorId: authorId,
                            postId: postId,
                            onStartChat: onStartChat,
                            onFollow: onFollow,
                            onReport: onReport,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(text),
                  const SizedBox(height: 8),

                  // Movie attachment (optional)
                  if ((moviePoster != null && moviePoster!.isNotEmpty) ||
                      (movieTitle != null && movieTitle!.isNotEmpty))
                    _MovieAttachment(
                      posterUrl: moviePoster ?? '',
                      title: movieTitle ?? '',
                    ),
                  if ((moviePoster != null && moviePoster!.isNotEmpty) ||
                      (movieTitle != null && movieTitle!.isNotEmpty))
                    const SizedBox(height: 8),

                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: () {
                      final uid = FirebaseAuth.instance.currentUser?.uid;
                      if (uid == null) {
                        return const Stream.empty()
                            .cast<DocumentSnapshot<Map<String, dynamic>>>();
                      }
                      return FirebaseFirestore.instance
                          .collection('posts')
                          .doc(postId)
                          .collection('likes')
                          .doc(uid)
                          .snapshots();
                    }(),
                    builder: (context, snap) {
                      final initialLiked = snap.hasData && snap.data!.exists;
                      return _ActionBar(
                        postId: postId,
                        likeCount: likeCount,
                        replyCount: replyCount,
                        repostCount: repostCount,
                        isLiked: initialLiked,
                        onToggleLike: (id, like) async {
                          await onToggleLike(id, like);
                        },
                      );
                    },
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

class _MovieAttachment extends StatelessWidget {
  final String posterUrl;
  final String title;
  const _MovieAttachment({required this.posterUrl, required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (posterUrl.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 120, // smaller thumbnail
              height: 180, // keep 2:3 ratio
              child: PosterImage(
                posterUrl: posterUrl,
                title: title,
                fit: BoxFit.cover,
              ),
            ),
          ),
        if (posterUrl.isNotEmpty) const SizedBox(height: 8),
        if (title.isNotEmpty)
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

class _FollowButton extends StatefulWidget {
  final String authorId;
  const _FollowButton({required this.authorId});

  @override
  State<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<_FollowButton> {
  bool _busy = false;
  bool _isFollowing = false;
  StreamSubscription<FollowEvent>? _sub;

  String? get _me => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    // Event bus ile sayfa yenilemeden güncelle
    _sub = FollowSystemService.I.events.listen((e) {
      if (_me == null) return;
      if (e.actorUid != _me) return; // sadece benim aksiyonlarım bizi etkiler
      if (e.targetUid != widget.authorId) return;
      if (!mounted) return;
      setState(() => _isFollowing = e.followed);
    });
  }

  Future<void> _bootstrap() async {
    final me = _me;
    if (me == null || me == widget.authorId) return;
    try {
      final exists =
          (await FirebaseFirestore.instance
                  .collection('users')
                  .doc(me)
                  .collection('following')
                  .doc(widget.authorId)
                  .get(const GetOptions(source: Source.serverAndCache)))
              .exists;
      if (!mounted) return;
      setState(() => _isFollowing = exists);
    } catch (_) {}
  }

  Future<void> _doFollow() async {
    setState(() => _busy = true);
    try {
      await FollowSystemService.I.followUser(widget.authorId);
      if (mounted) setState(() => _isFollowing = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Takip edilemedi: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doUnfollow() async {
    setState(() => _busy = true);
    try {
      await FollowSystemService.I.unfollowUser(widget.authorId);
      if (mounted) setState(() => _isFollowing = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Takipten çıkılamadı: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Kendi profilimse buton gösterme
    if (_me == widget.authorId) return const SizedBox.shrink();

    if (_isFollowing) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 6),
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 0),
            ),
            onPressed: _busy ? null : _doUnfollow,
            child: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Takipten çık'),
          ),
        ],
      );
    }

    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        side: BorderSide(color: cs.outlineVariant),
        minimumSize: const Size(0, 0),
      ),
      onPressed: _busy ? null : _doFollow,
      child: _busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Takip et'),
    );
  }
}

class _PostMenu extends StatelessWidget {
  final String authorId;
  final String postId;
  final Future<void> Function(String otherUid) onStartChat;
  final Future<void> Function(String otherUid) onFollow;
  final Future<void> Function(String postId) onReport;

  const _PostMenu({
    required this.authorId,
    required this.postId,
    required this.onStartChat,
    required this.onFollow,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser?.uid;
    final owner = me == authorId;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (v) async {
        switch (v) {
          case 'follow':
            try {
              final me = FirebaseAuth.instance.currentUser?.uid;
              if (me == null || me == authorId) break;
              final folDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(me)
                  .collection('following')
                  .doc(authorId)
                  .get(const GetOptions(source: Source.serverAndCache));
              final isFollowing = folDoc.exists;
              if (isFollowing) {
                await FollowSystemService.I.unfollowUser(authorId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Takipten çıkıldı')),
                  );
                }
              } else {
                await FollowSystemService.I.followUser(authorId);
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Takip edildi')));
                }
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('İşlem başarısız: $e')));
              }
            }
            break;
          case 'dm':
            await _startDm(context);
            break;
          case 'report':
            await onReport(postId);
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Şikayet gönderildi')));
            break;
          case 'delete':
            await FirebaseFirestore.instance
                .collection('posts')
                .doc(postId)
                .delete();
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Gönderi silindi')));
            break;
        }
      },
      itemBuilder: (context) => [
        if (!owner)
          const PopupMenuItem(value: 'dm', child: Text('Mesaj gönder')),
        const PopupMenuItem(value: 'report', child: Text('Şikayet et')),
        if (owner) const PopupMenuItem(value: 'delete', child: Text('Sil')),
      ],
    );
  }

  Future<void> _startDm(BuildContext context) async {
    try {
      final me = FirebaseAuth.instance.currentUser?.uid;
      if (me == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Önce giriş yapmalısınız.')),
          );
        }
        return;
      }

      final fs = FirebaseFirestore.instance;

      // 1) Var olan DM odasını bul (array-contains ile önce "me" yi bulup, client-side diğerini filtrele)
      final qs = await fs
          .collection('chats')
          .where('participants', arrayContains: me)
          .limit(20)
          .get(const GetOptions(source: Source.serverAndCache));

      String? chatId;
      for (final d in qs.docs) {
        final data = d.data();
        final parts =
            (data['participants'] as List?)?.cast<String>() ?? const <String>[];
        final type = (data['type'] ?? '') as String;
        if (parts.contains(authorId) && (type == 'dm' || parts.length == 2)) {
          chatId = d.id;
          break;
        }
      }

      // 2) Yoksa oluştur
      chatId ??= (await fs.collection('chats').add({
        'type': 'dm',
        'participants': [me, authorId],
        'createdAt': FieldValue.serverTimestamp(),
      })).id;

      // 3) Sohbete git — doğrudan ChatRoomScreen'e yönlendir
      if (context.mounted && chatId != null) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatRoomScreen(chatId: chatId!, otherUid: authorId),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Mesaj başlatılamadı: $e')));
      }
    }
  }
}

class _ActionBar extends StatefulWidget {
  final String postId;
  final int likeCount;
  final int replyCount;
  final int repostCount;
  final bool isLiked;
  final Future<void> Function(String postId, bool like) onToggleLike;

  const _ActionBar({
    required this.postId,
    required this.likeCount,
    required this.replyCount,
    required this.repostCount,
    required this.isLiked,
    required this.onToggleLike,
  });

  @override
  State<_ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends State<_ActionBar> {
  late bool _liked;
  late int _likeCount;
  late int _replyCount;

  bool _likeBusy = false; // prevent double-taps spamming writes
  DateTime? _lastLikeAt;
  static const Duration _minLikeInterval = Duration(milliseconds: 800);
  // When user toggles like locally, do not let late-arriving remote values overwrite UI
  bool _userMutatedLike = false;

  @override
  void initState() {
    super.initState();
    _liked = widget.isLiked;
    _likeCount = widget.likeCount;
    _replyCount = widget.replyCount;
  }

  @override
  void didUpdateWidget(covariant _ActionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only accept remote liked/likeCount updates if user hasn't interacted locally.
    if (!_userMutatedLike) {
      if (oldWidget.isLiked != widget.isLiked) {
        _liked = widget.isLiked;
      }
      if (oldWidget.likeCount != widget.likeCount) {
        _likeCount = widget.likeCount;
      }
    }
    // Reply count can still sync from parent
    if (oldWidget.replyCount != widget.replyCount) {
      _replyCount = widget.replyCount;
    }
  }

  Future<void> _toggleLike() async {
    if (_likeBusy) return; // already processing a tap
    final now = DateTime.now();
    if (_lastLikeAt != null &&
        now.difference(_lastLikeAt!) < _minLikeInterval) {
      return; // too soon; ignore rapid double taps
    }
    _lastLikeAt = now;
    _likeBusy = true;

    _userMutatedLike = true;
    final next = !_liked;
    final prevCount = _likeCount;
    setState(() {
      _liked = next;
      _likeCount = (prevCount + (next ? 1 : -1)).clamp(0, 1 << 31);
    });

    try {
      await widget.onToggleLike(widget.postId, next);
    } catch (e) {
      // revert on failure
      if (mounted) {
        setState(() {
          _liked = !next;
          _likeCount = prevCount;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Beğeni güncellenemedi. Tekrar deneyin.'),
          ),
        );
      }
      _userMutatedLike = false;
    } finally {
      _userMutatedLike = false;
      _likeBusy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget btn(
      IconData icon,
      int count,
      VoidCallback onTap, {
      bool highlighted = false,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: highlighted ? Colors.red : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text('$count'),
            ],
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        btn(Icons.mode_comment_outlined, _replyCount, () async {
          await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => _ReplySheet(
              postId: widget.postId,
              onAdded: () {
                if (!mounted) return;
                setState(() {
                  _replyCount++;
                });
              },
            ),
          );
        }),
        const SizedBox(width: 8),
        btn(
          _liked ? Icons.favorite : Icons.favorite_border,
          _likeCount,
          () {
            _toggleLike();
          },
          highlighted: _liked,
        ),
      ],
    );
  }
}

class _ReplySheet extends StatefulWidget {
  final String postId;
  final VoidCallback? onAdded;
  const _ReplySheet({required this.postId, this.onAdded});

  @override
  State<_ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends State<_ReplySheet> {
  final TextEditingController _tc = TextEditingController();
  bool _sending = false;

  // One-shot paginated reads while the sheet is open
  final List<Map<String, dynamic>> _replies = <Map<String, dynamic>>[];
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  DateTime? _lastSendAt;
  static const Duration _minSendInterval = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _initialLoading = true;
      _replies.clear();
      _lastDoc = null;
      _hasMore = true;
    });
    try {
      final qs = await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .collection('replies')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get(const GetOptions(source: Source.serverAndCache));
      if (!mounted) return;
      setState(() {
        _replies.addAll(qs.docs.map((d) => {'__id': d.id, ...d.data()}));
        if (qs.docs.isNotEmpty) {
          _lastDoc = qs.docs.last;
        }
        _hasMore = qs.docs.length == 20;
        _initialLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _initialLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .collection('replies')
          .orderBy('createdAt', descending: true)
          .limit(20);
      if (_lastDoc != null) {
        q = q.startAfterDocument(_lastDoc!);
      }
      final qs = await q.get(const GetOptions(source: Source.serverAndCache));
      if (!mounted) return;
      setState(() {
        _replies.addAll(qs.docs.map((d) => {'__id': d.id, ...d.data()}));
        if (qs.docs.isNotEmpty) {
          _lastDoc = qs.docs.last;
        }
        _hasMore = qs.docs.length == 20;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _send() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final text = _tc.text.trim();
    if (text.isEmpty) return;
    if (_sending) return;

    final now = DateTime.now();
    if (_lastSendAt != null &&
        now.difference(_lastSendAt!) < _minSendInterval) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lütfen biraz bekleyin. Çok hızlı gönderiyorsunuz.'),
          ),
        );
      }
      return;
    }
    _lastSendAt = now;

    setState(() => _sending = true);

    final fs = FirebaseFirestore.instance;
    final postRef = fs.collection('posts').doc(widget.postId);
    final repliesRef = postRef.collection('replies');

    // VERİYİ KESİNLİKLE YAZ: önce sadece reply dokümanını yaz. Sayaç ayrı (opsiyonel)
    try {
      final payload = {
        'authorId': user.uid,
        'displayName': user.displayName ?? '',
        'photoURL': user.photoURL ?? '',
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
        'likeCount': 0,
      };

      final ref = await repliesRef.add(payload);

      // Parent UI sayacini aninda arttir
      try {
        widget.onAdded?.call();
      } catch (_) {}

      // Optimistic UI: hemen listeye ekle
      _tc.clear();
      if (mounted) {
        setState(() {
          _replies.insert(0, {
            '__id': ref.id,
            ...payload,
            'createdAt': Timestamp.now(), // UI'da anında göster
          });
          _sending = false;
        });
      }

      // Sayaç güncellemesi başarısız olsa bile yorum yazılmış olsun
      try {
        await postRef.update({
          'replyCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // Kural/izin hatası olabilir: görmezden gel
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Yorum gönderilemedi: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            Text('Yorumlar', style: Theme.of(context).textTheme.titleMedium),
            const Divider(),
            Expanded(
              child: _initialLoading
                  ? const Center(child: CircularProgressIndicator())
                  : (_replies.isEmpty
                        ? const Center(child: Text('Henüz yorum yok'))
                        : NotificationListener<ScrollNotification>(
                            onNotification: (n) {
                              if (n is ScrollEndNotification) {
                                final m = n.metrics;
                                if (m.pixels >= m.maxScrollExtent - 80) {
                                  _loadMore();
                                }
                              }
                              return false;
                            },
                            child: ListView.builder(
                              itemCount: _replies.length + (_hasMore ? 1 : 0),
                              itemBuilder: (_, i) {
                                if (i == _replies.length) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    child: Center(
                                      child: _loadingMore
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : TextButton(
                                              onPressed: _loadMore,
                                              child: const Text(
                                                'Daha fazla yükle',
                                              ),
                                            ),
                                    ),
                                  );
                                }
                                final m = _replies[i];
                                final photo = (m['photoURL'] ?? '').toString();

                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundImage: photo.isNotEmpty
                                        ? NetworkImage(photo)
                                        : null,
                                    child: photo.isEmpty
                                        ? const Icon(Icons.person)
                                        : null,
                                  ),
                                  title: Text(
                                    (m['displayName'] ?? '').toString(),
                                  ),
                                  subtitle: Text((m['text'] ?? '').toString()),
                                );
                              },
                            ),
                          )),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tc,
                      decoration: const InputDecoration(
                        hintText: 'Yanıt yaz...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sending ? null : _send,
                    child: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Gönder'),
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
