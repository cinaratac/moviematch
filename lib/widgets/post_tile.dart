import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/poster_image.dart';
import '../screens/public_profile_screen.dart';
import '../screens/post_detail_screen.dart';
import '../screens/chat_room_screen.dart';
import '../services/chat_service.dart';
import '../services/follow_system_service.dart'; 
import 'package:share_plus/share_plus.dart';

class PostTile extends StatefulWidget {
  final String postId;
  final String authorId;
  final String? postImage;
  final String displayName;
  final String handle;
  final String photoURL;
  final String timeLabel;
  final String? movieTitle;
  final String? moviePoster;
  final String text;
  final int likeCount;
  final int replyCount;
  // repostCount kaldırıldı
  
  final Function(String postId, bool isLiked) onToggleLike;
  final Function(String userId) onStartChat;
  final Function(String userId) onFollow;
  final Function(String postId) onReport;

  const PostTile({
    super.key,
    this.postImage,
    required this.postId,
    required this.authorId,
    required this.displayName,
    required this.handle,
    required this.photoURL,
    required this.timeLabel,
    this.movieTitle,
    this.moviePoster,
    required this.text,
    required this.likeCount,
    required this.replyCount,
    // required this.repostCount, // Kaldırıldı
    required this.onToggleLike,
    required this.onStartChat,
    required this.onFollow,
    required this.onReport,
  });

  @override
  State<PostTile> createState() => _PostTileState();
}

class _PostTileState extends State<PostTile> {
  bool _isLiked = false;
  bool _isFollowing = false;
  int _currentLikeCount = 0;
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _currentLikeCount = widget.likeCount;
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    if (_currentUserId.isEmpty) return;
    
    // 1. Beğeni Durumu
    FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .collection('likes')
        .doc(_currentUserId)
        .get()
        .then((doc) {
      if (mounted && doc.exists) setState(() => _isLiked = true);
    });

    // 2. Takip Durumu
    if (widget.authorId != _currentUserId) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .collection('following')
          .doc(widget.authorId)
          .get()
          .then((doc) {
        if (mounted && doc.exists) setState(() => _isFollowing = true);
      });
    }
  }

  void _handleLike() {
    setState(() {
      _isLiked = !_isLiked;
      if (_isLiked) {
        _currentLikeCount++;
      } else {
        _currentLikeCount--;
      }
    });
    widget.onToggleLike(widget.postId, _isLiked);
  }

  void _navigateToProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(uid: widget.authorId),
      ),
    );
  }

  void _navigateToDetail() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(postId: widget.postId),
      ),
    );
  }

  // --- YENİ YORUM PENCERESİ (BottomSheet) ---
  void _showCommentsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _CommentsSheet(postId: widget.postId),
    );
  }

  Future<void> _startMessage() async {
    try {
      final chatId = await ChatService.instance.getOrCreateChat(_currentUserId, widget.authorId);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatRoomScreen(chatId: chatId, otherUid: widget.authorId),
          ),
        );
      }
    } catch (e) {
      debugPrint('Sohbet hatası: $e');
    }
  }

  void _showMoreOptions() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.authorId != _currentUserId) ...[
                // --- DÜZELTİLEN TAKİP MANTIĞI ---
                ListTile(
                  leading: Icon(
                    _isFollowing ? Icons.person_remove_outlined : Icons.person_add_outlined,
                    color: _isFollowing ? Colors.red : null,
                  ),
                  title: Text(
                    _isFollowing 
                      ? '@${widget.handle.replaceAll('@', '')} takipten çık'
                      : '@${widget.handle.replaceAll('@', '')} takip et',
                    style: TextStyle(
                      color: _isFollowing ? Colors.red : null,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    
                    if (_isFollowing) {
                      // Takipten Çık (Unfollow)
                      await FollowSystemService.I.unfollowUser(widget.authorId);
                      if (mounted) {
                        setState(() => _isFollowing = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Takipten çıkıldı')),
                        );
                      }
                    } else {
                      // Takip Et (Follow)
                      await FollowSystemService.I.followUser(widget.authorId);
                      // Bildirim göndermek için parent callback'i çağırabiliriz
                      widget.onFollow(widget.authorId); 
                      if (mounted) {
                        setState(() => _isFollowing = true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Takip ediliyor')),
                        );
                      }
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: const Text('Mesaj Gönder'),
                  onTap: () {
                    Navigator.pop(context);
                    _startMessage();
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.flag_outlined, color: Colors.red),
                  title: const Text('Bildir / Şikayet Et', style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onReport(widget.postId);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Bildiriminiz alındı.')),
                    );
                  },
                ),
              ] else 
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('Gönderiyi Sil', style: TextStyle(color: Colors.red)),
                  onTap: () async {
                    Navigator.pop(context);
                    final confirm = await showDialog<bool>(
                      context: context, 
                      builder: (ctx) => AlertDialog(
                        title: const Text("Silinsin mi?"),
                        content: const Text("Bu işlem geri alınamaz."),
                        actions: [
                          TextButton(onPressed: ()=>Navigator.pop(ctx, false), child: const Text("İptal")),
                          TextButton(onPressed: ()=>Navigator.pop(ctx, true), child: const Text("Sil", style: TextStyle(color: Colors.red))),
                        ],
                      )
                    );
                    
                    if (confirm == true) {
                      try {
                        await FirebaseFirestore.instance.collection('posts').doc(widget.postId).delete();
                      } catch (e) {
                        debugPrint('Silme hatası: $e');
                      }
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // GestureDetector KALDIRILDI: Artık tüm karta tıklayınca işlem yapmıyor.
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(
            color: cs.outlineVariant.withOpacity(0.2),
            width: 1,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. HEADER
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: _navigateToProfile,
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: cs.surfaceContainerHighest,
                    backgroundImage: widget.photoURL.isNotEmpty
                        ? NetworkImage(widget.photoURL)
                        : null,
                    child: widget.photoURL.isEmpty
                        ? Icon(Icons.person, color: cs.onSurfaceVariant)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _navigateToProfile,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.displayName,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.handle,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              ' • ${widget.timeLabel}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.more_horiz, color: cs.onSurfaceVariant),
                  onPressed: _showMoreOptions,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            ),

            // 2. TEXT CONTENT (Tıklanınca Detaya Git)
            if (widget.text.isNotEmpty)
            if (widget.postImage != null && widget.postImage!.isNotEmpty)
            GestureDetector(
              onTap: _navigateToDetail, // Resme basınca da detaya gitsin
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 400), // Çok uzun resimler ekranı kaplamasın
                    width: double.infinity,
                    color: Colors.black12, // Yüklenirken arka plan
                    child: Image.network(
                      widget.postImage!,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(child: Padding(
                          padding: EdgeInsets.all(20.0),
                          child: CircularProgressIndicator(),
                        ));
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return const SizedBox(
                          height: 150,
                          child: Center(child: Icon(Icons.broken_image, size: 50, color: Colors.grey)),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            GestureDetector(
              onTap: _navigateToDetail, // Sadece yazıya tıklayınca detay açılır
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  widget.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.4,
                    fontSize: 15,
                  ),
                ),
              ),
            ),

           // 3. MOVIE CARD (Tıklanınca Detaya Git)
            if (widget.movieTitle != null && widget.moviePoster != null)
            GestureDetector(
              onTap: _navigateToDetail, // Filme tıklayınca detay açılır
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Container(
                  height: 100,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                        child: SizedBox(
                          width: 70,
                          height: double.infinity,
                          child: PosterImage(
                            posterUrl: widget.moviePoster,
                            title: widget.movieTitle,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: cs.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'İZLİYOR',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.movieTitle!,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(right: 16),
                        child: Icon(Icons.chevron_right, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 4. ACTION BAR (Repost kaldırıldı)
           Padding(
            padding: const EdgeInsets.only(top: 4, left: 16, right: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Sol Taraf: Like & Reply
                Row(
                  children: [
                    _ActionButton(
                      icon: _isLiked ? Icons.favorite : Icons.favorite_border,
                      color: _isLiked ? Colors.red : cs.onSurfaceVariant,
                      count: _currentLikeCount,
                      onTap: _handleLike,
                    ),
                    const SizedBox(width: 24),
                    _ActionButton(
                      icon: Icons.chat_bubble_outline_rounded,
                      color: cs.onSurfaceVariant,
                      count: widget.replyCount,
                      onTap: _showCommentsSheet, // SADECE Yorum butonuna basınca açılır
                    ),
                  ],
                ),
                
                // Sağ Taraf: Share
                // Sağ Taraf: Share
                IconButton(
                  icon: Icon(Icons.share_outlined, size: 20, color: cs.onSurfaceVariant),
                  onPressed: () {
                    // Site olmadan çalışacak Özel Link:
                    // cinematch://app/post?id=POST_ID
                    final String appLink = 'cinematch://app/post?id=${widget.postId}';
                    
                    final String content = widget.text.isNotEmpty 
                        ? widget.text 
                        : (widget.movieTitle ?? 'Bir gönderi');
                    
                    final String shareText = 
                        '${widget.displayName} (@${widget.handle.replaceAll('@', '')}) MovieMatch\'te paylaştı:\n\n'
                        '$content\n\n'
                        '${widget.movieTitle != null ? "🎬 İzliyor: ${widget.movieTitle}\n" : ""}'
                        'Uygulamada aç: $appLink';

                    Share.share(shareText);
                  },
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int count;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color), 
            if (count > 0) ...[
              const SizedBox(width: 6),
              Text(
                '$count',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --- GÜNCELLENEN YORUM PENCERESİ (DÜZELTİLDİ: 'replies' koleksiyonu) ---
class _CommentsSheet extends StatefulWidget {
  final String postId;
  const _CommentsSheet({required this.postId});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final TextEditingController _commentCtrl = TextEditingController();
  bool _isSending = false;

  Future<void> _sendComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSending = true);
    try {
      // DÜZELTME: Koleksiyon adı 'replies' olarak değiştirildi
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .collection('replies') // <-- replies olarak düzeltildi
          .add({
        'text': text,
        'authorId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // ReplyCount artır
      await FirebaseFirestore.instance.collection('posts').doc(widget.postId).update({
        'replyCount': FieldValue.increment(1),
      });

      _commentCtrl.clear();
      FocusScope.of(context).unfocus();
    } catch (e) {
      debugPrint("Yorum hatası: $e");
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Yorumlar', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const Divider(height: 1),
            
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                // DÜZELTME: Stream de 'replies' koleksiyonunu dinliyor
                stream: FirebaseFirestore.instance
                    .collection('posts')
                    .doc(widget.postId)
                    .collection('replies') // <-- replies olarak düzeltildi
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return const Center(child: Text("Henüz yorum yok. İlk yorumu sen yap!", style: TextStyle(color: Colors.grey)));
                  }
                  
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      return FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance.collection('users').doc(data['authorId']).get(),
                        builder: (ctx, userSnap) {
                          String name = "Kullanıcı";
                          String? photo;
                          if (userSnap.hasData && userSnap.data!.exists) {
                            final userData = userSnap.data!.data() as Map<String, dynamic>;
                            name = userData['displayName'] ?? userData['username'] ?? "Kullanıcı";
                            photo = userData['photoURL'];
                          }
                          
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundImage: photo != null ? NetworkImage(photo) : null,
                              child: photo == null ? const Icon(Icons.person) : null,
                              radius: 16,
                            ),
                            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: Text(data['text'] ?? '', style: const TextStyle(fontSize: 14)),
                          );
                        }
                      );
                    },
                  );
                },
              ),
            ),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.2))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentCtrl,
                      decoration: InputDecoration(
                        hintText: 'Yorum yaz...',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      ),
                      minLines: 1,
                      maxLines: 3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _isSending ? null : _sendComment,
                    icon: _isSending 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                      : Icon(Icons.send_rounded, color: Theme.of(context).colorScheme.primary),
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