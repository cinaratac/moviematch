import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../screens/public_profile_screen.dart';

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

// caches remote like state per post to avoid repeated reads per session
final Map<String, Future<bool>> _likedFutureCache = {};

Future<bool> _isLikedRemotely(String postId) {
  if (_likedFutureCache.containsKey(postId)) return _likedFutureCache[postId]!;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    _likedFutureCache[postId] = Future.value(false);
    return _likedFutureCache[postId]!;
  }
  _likedFutureCache[postId] = FirebaseFirestore.instance
      .collection('posts')
      .doc(postId)
      .collection('likes')
      .doc(uid)
      .get()
      .then((d) => d.exists)
      .catchError((_) => false);
  return _likedFutureCache[postId]!;
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
    required this.onToggleLike,
    required this.onStartChat,
    required this.onFollow,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PublicProfileScreen(uid: authorId),
                  ),
                );
              },
              child: CircleAvatar(
                radius: 20,
                backgroundImage: photoURL.isNotEmpty
                    ? NetworkImage(photoURL)
                    : null,
                child: photoURL.isEmpty ? const Icon(Icons.person) : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
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
                            displayName.isEmpty ? 'Kullanıcı' : displayName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),

                      // fetch letterboxd handle once per author (cached future)
                      FutureBuilder<String?>(
                        future: _lbHandleFor(authorId),
                        builder: (context, snap) {
                          final lb = (snap.data ?? '').toString();
                          final showLb = lb.isNotEmpty;
                          return Flexible(
                            child: Text(
                              '${showLb ? '@$lb · ' : ''}$timeLabel',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      ),

                      const Spacer(),
                      _PostMenu(
                        authorId: authorId,
                        postId: postId,
                        onStartChat: onStartChat,
                        onFollow: onFollow,
                        onReport: onReport,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(text),
                  const SizedBox(height: 8),
                  FutureBuilder<bool>(
                    future: _isLikedRemotely(postId),
                    builder: (context, snap) {
                      final initialLiked =
                          snap.data ??
                          false; // fallback if remote like state not yet loaded
                      return _ActionBar(
                        postId: postId,
                        likeCount: likeCount,
                        replyCount: replyCount,
                        repostCount: repostCount,
                        isLiked: initialLiked,
                        onToggleLike: (id, like) async {
                          // update remote via parent callback
                          await onToggleLike(id, like);
                          // also refresh local cache so subsequent rebuilds use the new truth
                          _likedFutureCache[id] = Future.value(like);
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
            await onFollow(authorId);
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Takip edildi')));
            break;
          case 'dm':
            await onStartChat(authorId);
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
          const PopupMenuItem(value: 'follow', child: Text('Takip et')),
        if (!owner)
          const PopupMenuItem(value: 'dm', child: Text('Mesaj gönder')),
        const PopupMenuItem(value: 'report', child: Text('Şikayet et')),
        if (owner) const PopupMenuItem(value: 'delete', child: Text('Sil')),
      ],
    );
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
      if (oldWidget.isLiked != widget.isLiked) _liked = widget.isLiked;
      if (oldWidget.likeCount != widget.likeCount)
        _likeCount = widget.likeCount;
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
    } finally {
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
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
        btn(Icons.repeat_outlined, widget.repostCount, () {}),
        // LIKE button — red heart when liked, tap again to unlike
        btn(
          _liked ? Icons.favorite : Icons.favorite_border,
          _likeCount,
          () {
            _toggleLike();
          },
          highlighted: _liked,
        ),
        IconButton(
          icon: const Icon(Icons.share_outlined, size: 20),
          onPressed: () {},
          tooltip: 'Paylaş',
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

  // Local liked-state for replies to avoid FutureBuilder staleness
  final Map<String, bool> _replyLiked = <String, bool>{};

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
        if (qs.docs.isNotEmpty) _lastDoc = qs.docs.last;
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
        if (qs.docs.isNotEmpty) _lastDoc = qs.docs.last;
        _hasMore = qs.docs.length == 20;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _ensureReplyLikedLoaded(String replyId) async {
    if (_replyLiked.containsKey(replyId)) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _replyLiked[replyId] = false;
      return;
    }
    try {
      final liked = await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .collection('replies')
          .doc(replyId)
          .collection('likes')
          .doc(uid)
          .get()
          .then((d) => d.exists);
      if (!mounted) return;
      setState(() {
        _replyLiked[replyId] = liked;
      });
    } catch (_) {
      // default false on error
      _replyLiked[replyId] = false;
    }
  }

  Future<void> _toggleReplyLike({
    required String replyId,
    required bool like,
    required int index,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final fs = FirebaseFirestore.instance;
    final postRef = fs.collection('posts').doc(widget.postId);
    final replyRef = postRef.collection('replies').doc(replyId);
    final likeRef = replyRef.collection('likes').doc(uid);

    try {
      // Atomic + idempotent via transaction + FieldValue.increment
      final result = await fs.runTransaction<Map<String, dynamic>>((tx) async {
        final likeSnap = await tx.get(likeRef);
        final hasLike = likeSnap.exists;

        if (like && !hasLike) {
          tx.set(likeRef, {'createdAt': FieldValue.serverTimestamp()});
          tx.update(replyRef, {'likeCount': FieldValue.increment(1)});
          return {'liked': true, 'delta': 1};
        }
        if (!like && hasLike) {
          tx.delete(likeRef);
          tx.update(replyRef, {'likeCount': FieldValue.increment(-1)});
          return {'liked': false, 'delta': -1};
        }
        // No-op: already desired state
        return {'liked': hasLike, 'delta': 0};
      });

      // Sync local caches/UI based on delta
      final newLiked = (result['liked'] as bool?) ?? false;
      final delta = (result['delta'] as int?) ?? 0;
      _replyLiked[replyId] = newLiked;

      if (!mounted) return;
      setState(() {
        final m = _replies[index];
        final current = (m['likeCount'] is int)
            ? m['likeCount'] as int
            : ((m['likeCount'] ?? 0) as num).toInt();
        m['likeCount'] = (current + delta).clamp(0, 1 << 31);
      });
    } catch (e) {
      // Helpful debug log for rule/path issues
      // ignore: avoid_print
      print('[reply-like] write failed for ${widget.postId}/$replyId : $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yorum için beğeni yazılamadı.')),
      );
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
                                final replyId = (m['__id'] ?? '') as String;

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
                                  trailing: replyId.isEmpty
                                      ? null
                                      : Builder(
                                          builder: (context) {
                                            final liked = _replyLiked[replyId];
                                            if (liked == null) {
                                              // kick off a one-time load without blocking UI
                                              // ignore: discarded_futures
                                              _ensureReplyLikedLoaded(replyId);
                                            }
                                            final effectiveLiked =
                                                liked ?? false;
                                            final currentLikeCount =
                                                (m['likeCount'] is int)
                                                ? m['likeCount'] as int
                                                : ((m['likeCount'] ?? 0) as num)
                                                      .toInt();
                                            return InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              onTap: () => _toggleReplyLike(
                                                replyId: replyId,
                                                like: !effectiveLiked,
                                                index: i,
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 6,
                                                    ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      effectiveLiked
                                                          ? Icons.favorite
                                                          : Icons
                                                                .favorite_border,
                                                      size: 18,
                                                      color: effectiveLiked
                                                          ? Theme.of(context)
                                                                .colorScheme
                                                                .primary
                                                          : Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text('$currentLikeCount'),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
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
