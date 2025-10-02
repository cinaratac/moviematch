import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  static const int _maxChars = 280;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Feed')),
      body: Column(
        children: [
          _Composer(
            controller: _controller,
            focusNode: _focusNode,
            maxChars: _maxChars,
            onSend: (text) async {
              await _createPost(text);
              _controller.clear();
              _focusNode.requestFocus();
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .orderBy('createdAt', descending: true)
                  .limit(200)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return const Center(child: Text('Gönderiler yüklenemedi'));
                }
                final docs = snap.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return const Center(child: Text('Henüz gönderi yok'));
                }
                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final m = d.data();
                    final createdAt = (m['createdAt'] as Timestamp?);
                    final timeLabel = createdAt == null
                        ? ''
                        : _timeAgo(createdAt.toDate());
                    return _PostTile(
                      postId: d.id,
                      displayName: (m['displayName'] ?? '') as String,
                      handle: (m['handle'] ?? '') as String,
                      photoURL: (m['photoURL'] ?? '') as String,
                      timeLabel: timeLabel,
                      text: (m['text'] ?? '') as String,
                      likeCount: (m['likeCount'] ?? 0) is int
                          ? m['likeCount'] as int
                          : ((m['likeCount'] ?? 0) as num).toInt(),
                      replyCount: (m['replyCount'] ?? 0) is int
                          ? m['replyCount'] as int
                          : ((m['replyCount'] ?? 0) as num).toInt(),
                      repostCount: (m['repostCount'] ?? 0) is int
                          ? m['repostCount'] as int
                          : ((m['repostCount'] ?? 0) as num).toInt(),
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

  Future<void> _createPost(String text) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = FirebaseFirestore.instance.collection('posts').doc();
    await doc.set({
      'authorId': user.uid,
      'displayName': user.displayName ?? '',
      'handle': '@${(user.email ?? '').split('@').first}',
      'photoURL': user.photoURL ?? '',
      'text': text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'likeCount': 0,
      'replyCount': 0,
      'repostCount': 0,
      'visibility': 'public',
    });
  }

  static String _timeAgo(DateTime dt) {
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

  Future<void> _toggleLike(String postId, bool like) async {
    final fs = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final postRef = fs.collection('posts').doc(postId);
    final likeRef = postRef.collection('likes').doc(uid);
    final batch = fs.batch();
    if (like) {
      batch.set(likeRef, {'createdAt': FieldValue.serverTimestamp()});
      batch.update(postRef, {'likeCount': FieldValue.increment(1)});
    } else {
      batch.delete(likeRef);
      batch.update(postRef, {'likeCount': FieldValue.increment(-1)});
    }
    await batch.commit();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final int maxChars;
  final void Function(String)? onSend;

  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.maxChars,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final text = value.text;
        final remaining = maxChars - text.characters.length;
        final isEmpty = text.trim().isEmpty;

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(radius: 20, child: Icon(Icons.person)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: controller,
                      focusNode: focusNode,
                      maxLines: null,
                      minLines: 1,
                      decoration: const InputDecoration(
                        hintText: 'Neler oluyor?',
                        border: InputBorder.none,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.image_outlined),
                          tooltip: 'Medya',
                        ),
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.poll_outlined),
                          tooltip: 'Anket',
                        ),
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.emoji_emotions_outlined),
                          tooltip: 'Emoji',
                        ),
                        const Spacer(),
                        if (remaining <= 40)
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Text(
                              remaining.toString(),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: remaining < 0
                                    ? cs.error
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        FilledButton(
                          onPressed: isEmpty || remaining < 0
                              ? null
                              : () => onSend?.call(text),
                          child: const Text('Gönder'),
                        ),
                      ],
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

class _PostTile extends StatelessWidget {
  final String postId;
  final String displayName;
  final String handle;
  final String photoURL;
  final String timeLabel;
  final String text;
  final int likeCount;
  final int replyCount;
  final int repostCount;
  const _PostTile({
    required this.postId,
    required this.displayName,
    required this.handle,
    required this.photoURL,
    required this.timeLabel,
    required this.text,
    required this.likeCount,
    required this.replyCount,
    required this.repostCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundImage: photoURL.isNotEmpty
                ? NetworkImage(photoURL)
                : null,
            child: photoURL.isEmpty ? const Icon(Icons.person) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayName.isEmpty ? handle : displayName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '$handle · $timeLabel',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(text),
                const SizedBox(height: 8),
                _ActionBar(
                  postId: postId,
                  likeCount: likeCount,
                  replyCount: replyCount,
                  repostCount: repostCount,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final String postId;
  final int likeCount;
  final int replyCount;
  final int repostCount;
  const _ActionBar({
    required this.postId,
    required this.likeCount,
    required this.replyCount,
    required this.repostCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const SizedBox.shrink();
    }
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
                color: highlighted ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text('$count'),
            ],
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .doc(postId)
          .collection('likes')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        final liked = snap.data?.exists == true;
        final shownLikeCount =
            likeCount +
            (liked && (snap.connectionState == ConnectionState.waiting)
                ? 0
                : 0);
        // shownLikeCount: listen edilen ana post dokümanı yeniden geldiğinde zaten güncellenecek.

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            btn(Icons.mode_comment_outlined, replyCount, () {}),
            btn(Icons.repeat_outlined, repostCount, () {}),
            btn(
              liked ? Icons.favorite : Icons.favorite_border,
              shownLikeCount,
              () async {
                final state = context.findAncestorStateOfType<_FeedPageState>();
                if (state != null) {
                  await state._toggleLike(postId, !liked);
                }
              },
              highlighted: liked,
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined, size: 20),
              onPressed: () {},
              tooltip: 'Paylaş',
            ),
          ],
        );
      },
    );
  }
}
