import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttergirdi/widgets/comments_sheet.dart';
import '../widgets/poster_image.dart';
import '../screens/public_profile_screen.dart';
import '../screens/post_detail_screen.dart';
import '../screens/chat_room_screen.dart';
import '../services/chat_service.dart';
import '../services/follow_system_service.dart'; 
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';

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
  final int? movieTmdbId;

  // --- YENİ ALANLAR ---
  final double? rating;
  final bool isSpoiler;
  final List<String> tags;
  final String? reviewTitle;
  
  final Function(String postId, bool isLiked) onToggleLike;
  final Function(String userId) onStartChat;
  final Function(String userId) onFollow;
  final Function(String postId) onReport;
  
  // EKLENDİ: Silme işlemi tamamlanınca çalışacak fonksiyon
  final VoidCallback? onDelete;

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
    this.movieTmdbId,
    
    this.rating,
    this.isSpoiler = false,
    this.tags = const [],
    this.reviewTitle,

    required this.onToggleLike,
    required this.onStartChat,
    required this.onFollow,
    required this.onReport,
    this.onDelete, // Constructor'a eklendi
  });

  @override
  State<PostTile> createState() => _PostTileState();
}

class _PostTileState extends State<PostTile> {
  bool _isLiked = false;
  bool _isFollowing = false;
  int _currentLikeCount = 0;
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  bool _revealSpoiler = false;

  @override
  void initState() {
    super.initState();
    _currentLikeCount = widget.likeCount;
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    if (_currentUserId.isEmpty) return;
    
    FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .collection('likes')
        .doc(_currentUserId)
        .get()
        .then((doc) {
      if (mounted && doc.exists) setState(() => _isLiked = true);
    });

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

  void _showCommentsSheet() {
     showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CommentsSheet(
        postId: widget.postId,
        postAuthorId: widget.authorId,
      ),
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
                      await FollowSystemService.I.unfollowUser(widget.authorId);
                      if (mounted) setState(() => _isFollowing = false);
                    } else {
                      await FollowSystemService.I.followUser(widget.authorId);
                      widget.onFollow(widget.authorId); 
                      if (mounted) setState(() => _isFollowing = true);
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
                        // GÜNCELLENDİ: Silme başarılı olunca callback'i çağırıyoruz.
                        if (widget.onDelete != null) {
                          widget.onDelete!();
                        }
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

  Widget _buildRatingStars(double rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        IconData icon = Icons.star_border_rounded;
        if (index < rating) {
          icon = Icons.star_rounded;
        }
        return Icon(icon, color: Colors.amber, size: 18);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.2), width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. HEADER (Avatar, İsim, Zaman)
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
                        ? CachedNetworkImageProvider(widget.photoURL, maxWidth: 150)
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
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
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
                                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              ' • ${widget.timeLabel}',
                              style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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

          // İNCELEME BAŞLIĞI VE PUAN
          if (widget.reviewTitle != null || widget.rating != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.reviewTitle != null && widget.reviewTitle!.isNotEmpty)
                    Text(
                      widget.reviewTitle!,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  if (widget.rating != null) ...[
                    const SizedBox(height: 4),
                    _buildRatingStars(widget.rating!),
                  ]
                ],
              ),
            ),

          // 2. GÖRSEL ALAN
          if (widget.postImage != null && widget.postImage!.isNotEmpty)
            GestureDetector(
              onTap: _navigateToDetail, 
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 500),
                    width: double.infinity,
                    color: Colors.black12,
                    child: CachedNetworkImage(
                      imageUrl: widget.postImage!,
                      memCacheWidth: 1080, 
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const SizedBox(
                        height: 250,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (context, url, error) => const SizedBox(
                        height: 150,
                        child: Center(child: Icon(Icons.broken_image, size: 50, color: Colors.grey)),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 3. TEXT CONTENT
          if (widget.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                if (widget.isSpoiler && !_revealSpoiler) {
                  setState(() => _revealSpoiler = true);
                } else {
                  _navigateToDetail();
                }
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: widget.isSpoiler && !_revealSpoiler
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.errorContainer.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cs.error.withOpacity(0.5)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: cs.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Spoiler içerir! Okumak için dokun.",
                                style: TextStyle(color: cs.error, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Text(
                        widget.text,
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.4, fontSize: 15),
                      ),
              ),
            ),

           // 4. MOVIE CARD
          if (widget.movieTitle != null && widget.moviePoster != null)
            GestureDetector(
              onTap: () {
                if (widget.movieTmdbId != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MovieDetailScreen(
                        tmdbId: widget.movieTmdbId!,
                        title: widget.movieTitle,
                        posterUrl: widget.moviePoster,
                      ),
                    ),
                  );
                }
              },
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
                                    fontSize: 10
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.movieTitle!,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(right: 16), 
                        child: Icon(Icons.chevron_right, color: Colors.grey)
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ETİKETLER
            if (widget.tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(
                  spacing: 8,
                  children: widget.tags.map((tag) {
                    return Chip(
                      label: Text('#$tag'),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: cs.surfaceContainerHighest.withOpacity(0.5),
                      labelStyle: TextStyle(color: cs.primary, fontSize: 11),
                      padding: EdgeInsets.zero,
                      side: BorderSide.none,
                    );
                  }).toList(),
                ),
              ),

            // 5. ACTION BAR
           Padding(
            padding: const EdgeInsets.only(top: 4, left: 16, right: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
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
                      onTap: _showCommentsSheet,
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.share_outlined, size: 20, color: cs.onSurfaceVariant),
                  onPressed: () {
                    final String appLink = 'cinematch://app/post?id=${widget.postId}';
                    final String content = widget.text.isNotEmpty 
                        ? widget.text 
                        : (widget.movieTitle ?? 'Bir gönderi');
                    final String shareText = 
                        '${widget.displayName} (@${widget.handle.replaceAll('@', '')}) CineMatch\'te paylaştı:\n\n'
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

  const _ActionButton({required this.icon, required this.color, required this.count, required this.onTap});

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
              Text('$count', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }
}