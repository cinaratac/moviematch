// lib/widgets/post_tile.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../screens/public_profile_screen.dart';

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
                            displayName.isEmpty
                                ? (handle.isNotEmpty
                                      ? handle.substring(1)
                                      : 'Kullanıcı')
                                : displayName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (handle.isNotEmpty)
                        Flexible(
                          child: Text(
                            '$handle · $timeLabel',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
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
                  _ActionBar(
                    postId: postId,
                    likeCount: likeCount,
                    replyCount: replyCount,
                    repostCount: repostCount,
                    onToggleLike: onToggleLike,
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

class _ActionBar extends StatelessWidget {
  final String postId;
  final int likeCount;
  final int replyCount;
  final int repostCount;
  final Future<void> Function(String postId, bool like) onToggleLike;

  const _ActionBar({
    required this.postId,
    required this.likeCount,
    required this.replyCount,
    required this.repostCount,
    required this.onToggleLike,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

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

    // Sadece like state’i için ince stream (tek doküman)
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('posts')
          .doc(postId)
          .collection('likes')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        final liked = snap.data?.exists == true;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            btn(Icons.mode_comment_outlined, replyCount, () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => _ReplySheet(postId: postId),
              );
            }),
            btn(Icons.repeat_outlined, repostCount, () {}),
            btn(
              liked ? Icons.favorite : Icons.favorite_border,
              likeCount,
              () => onToggleLike(postId, !liked),
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

class _ReplySheet extends StatefulWidget {
  final String postId;
  const _ReplySheet({required this.postId});

  @override
  State<_ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends State<_ReplySheet> {
  final TextEditingController _tc = TextEditingController();
  bool _sending = false;

  Future<void> _send() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (uid == null) return;

    final text = _tc.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    final fs = FirebaseFirestore.instance;
    final postRef = fs.collection('posts').doc(widget.postId);

    await fs.runTransaction((tx) async {
      final replyRef = postRef.collection('replies').doc();
      tx.set(replyRef, {
        'authorId': uid,
        'displayName': user?.displayName ?? '',
        'handle': '', // istersen @lb ekleyebilirsin
        'photoURL': user?.photoURL ?? '',
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.update(postRef, {'replyCount': FieldValue.increment(1)});
    });

    _tc.clear();
    setState(() => _sending = false);
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
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('posts')
                    .doc(widget.postId)
                    .collection('replies')
                    .orderBy('createdAt', descending: true)
                    .limit(100)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snap.data?.docs ?? const [];
                  if (docs.isEmpty) {
                    return const Center(child: Text('Henüz yorum yok'));
                  }
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final m = docs[i].data();
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
                        title: Text((m['displayName'] ?? '').toString()),
                        subtitle: Text((m['text'] ?? '').toString()),
                      );
                    },
                  );
                },
              ),
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
