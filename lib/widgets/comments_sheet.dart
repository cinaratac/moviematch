import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/services/text_filter_service.dart';
import 'package:fluttergirdi/services/feed_service.dart';
// Film arama ve detay sayfaları
import '../screens/search_movie.dart'; 
import '../screens/movie_detail_screen.dart'; 
import 'poster_image.dart';

class CommentsSheet extends StatefulWidget {
  final String postId;
  final String postAuthorId; 

  const CommentsSheet({
    super.key,
    required this.postId,
    required this.postAuthorId,
  });

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final TextEditingController _commentCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  
  late final Stream<QuerySnapshot> _mainRepliesStream;

  String? _replyingToDocId; 
  String? _replyingToUserName;
  String? _replyingToUid;

  // Seçilen filmi tutmak için
  Map<String, dynamic>? _selectedMovie;

  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _mainRepliesStream = FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .collection('replies')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // Film seçme fonksiyonu
  Future<void> _pickMovie() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SearchMoviePage(isSelectionMode: true),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _selectedMovie = result;
      });
    }
  }

  void _removeSelectedMovie() {
    setState(() {
      _selectedMovie = null;
    });
  }

  Future<void> _send() async {
    final text = _commentCtrl.text.trim();
    // Metin boş olsa bile film seçiliyse gönderilebilir
    if (text.isEmpty && _selectedMovie == null) return;

    if (text.isNotEmpty && TextFilterService.hasProfanity(text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uygunsuz içerik tespit edildi.'), backgroundColor: Colors.red),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSending = true);

    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      final now = FieldValue.serverTimestamp();

      final Map<String, dynamic> data = {
        'text': text,
        'authorId': user.uid,
        'createdAt': now,
        'likeCount': 0,
      };

      if (_selectedMovie != null) {
        data['movie'] = _selectedMovie;
      }

      if (_replyingToDocId == null) {
        // --- ANA YORUM ---
        data['replyCount'] = 0;
        final ref = db.collection('posts').doc(widget.postId).collection('replies').doc();
        batch.set(ref, data);
        
        final postRef = db.collection('posts').doc(widget.postId);
        batch.update(postRef, {'replyCount': FieldValue.increment(1)});

      } else {
        // --- ALT YANIT (REPLY) ---
        final parentRef = db.collection('posts').doc(widget.postId).collection('replies').doc(_replyingToDocId);
        final subRef = parentRef.collection('subReplies').doc();
        
        batch.set(subRef, data);

        batch.update(parentRef, {'replyCount': FieldValue.increment(1)});
        
        final postRef = db.collection('posts').doc(widget.postId);
        batch.update(postRef, {'replyCount': FieldValue.increment(1)});
      }

      await batch.commit();

      // Bildirim Gönderme
      String previewText = text.isNotEmpty ? text : 'Bir film paylaştı 🎬';
      if (_replyingToDocId == null) {
        FeedService.instance.notifyComment(
          postId: widget.postId,
          postAuthorUid: widget.postAuthorId,
          preview: previewText,
        );
      } else if (_replyingToUid != null) {
        FeedService.instance.notifyComment(
          postId: widget.postId,
          postAuthorUid: _replyingToUid!, 
          preview: previewText,
        );
      }

      // --- TEMİZLİK ---
      _commentCtrl.clear();
      _removeSelectedMovie(); 
      _cancelReply(); 
      FocusScope.of(context).unfocus();

    } catch (e) {
      debugPrint('Yorum hatası: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _initiateReply(String docId, String userName, String uid) {
    setState(() {
      _replyingToDocId = docId;
      _replyingToUserName = userName;
      _replyingToUid = uid;
    });
    _focusNode.requestFocus(); 
  }

  void _cancelReply() {
    setState(() {
      _replyingToDocId = null;
      _replyingToUserName = null;
      _replyingToUid = null;
    });
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85, 
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 12),
                const Text('Yorumlar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
          const Divider(height: 1),

          // Liste
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _mainRepliesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text("Henüz yorum yok.", style: TextStyle(color: Colors.grey)));
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    // DÜZELTME 1: Her yoruma benzersiz bir Key veriyoruz.
                    // Böylece Flutter bunları birbirine karıştırmaz.
                    return _CommentTile(
                      key: ValueKey(docs[index].id), 
                      postId: widget.postId,
                      doc: docs[index],
                      onReply: _initiateReply, 
                    );
                  },
                );
              },
            ),
          ),

          // Input Alanı
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), 
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.2))),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5, offset: Offset(0,-2))]
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_replyingToUserName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0, left: 4),
                    child: Row(
                      children: [
                        Icon(Icons.reply, size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$_replyingToUserName adlı kişiye yanıt veriliyor',
                            style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        InkWell(
                          onTap: _cancelReply,
                          child: const Icon(Icons.close, size: 18, color: Colors.grey),
                        )
                      ],
                    ),
                  ),
                
                // Seçilen Film Önizlemesi
                if (_selectedMovie != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: PosterImage(
                            posterUrl: _selectedMovie!['poster'] ?? '',
                            title: _selectedMovie!['title'] ?? '',
                            width: 30,
                            height: 45,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedMovie!['title'] ?? '',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _selectedMovie!['releaseDate']?.toString().split('-').first ?? '',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: _removeSelectedMovie,
                        )
                      ],
                    ),
                  ),

                Row(
                  children: [
                    // Film Ekleme Butonu
                    IconButton(
                      onPressed: _pickMovie,
                      icon: Icon(
                        Icons.movie_creation_outlined, 
                        color: _selectedMovie != null ? theme.colorScheme.primary : Colors.grey.shade600
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: _commentCtrl,
                        focusNode: _focusNode,
                        decoration: InputDecoration(
                          hintText: _replyingToUserName != null ? 'Yanıtını yaz...' : 'Yorum yap...',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                        ),
                        minLines: 1,
                        maxLines: 4,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _isSending ? null : _send,
                      icon: _isSending
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(Icons.send_rounded, color: theme.colorScheme.primary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: bottomInset), 
        ],
      ),
    );
  }
}

// --- FİLM WIDGET'I (TIKLANINCA DETAY'A GİDER) ---
class _AttachedMovieWidget extends StatelessWidget {
  final Map<String, dynamic> movie;
  const _AttachedMovieWidget({required this.movie});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Film ID'si varsa detay sayfasına yönlendir
        final movieId = movie['id']; 
        if (movieId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MovieDetailScreen(tmdbId: movieId), 
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: PosterImage(
                posterUrl: movie['poster'] ?? '',
                title: movie['title'] ?? '',
                width: 24,
                height: 36,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movie['title'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Text(
                        movie['releaseDate']?.toString().split('-').first ?? '',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios, size: 8, color: Colors.grey.shade600)
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- TEKİL YORUM SATIRI ---
class _CommentTile extends StatelessWidget {
  final String postId;
  final QueryDocumentSnapshot doc;
  final Function(String docId, String userName, String uid) onReply;

  const _CommentTile({
    super.key, // Key parametresini aldık
    required this.postId,
    required this.doc,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final authorId = data['authorId'] as String? ?? '';
    final text = data['text'] as String? ?? '';
    final likeCount = (data['likeCount'] ?? 0) as int;
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
    final movieData = data['movie'] as Map<String, dynamic>?;

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(authorId).get(),
      builder: (context, userSnap) {
        String name = "Kullanıcı";
        String? photo;
        if (userSnap.hasData && userSnap.data!.exists) {
          final uData = userSnap.data!.data() as Map<String, dynamic>;
          name = uData['displayName'] ?? uData['username'] ?? "Kullanıcı";
          photo = uData['photoURL'];
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: photo != null ? NetworkImage(photo) : null,
                child: photo == null ? const Icon(Icons.person, size: 20) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 6),
                        if (createdAt != null)
                          Text(
                            _formatTime(createdAt), 
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    if (text.isNotEmpty)
                      Text(text, style: const TextStyle(fontSize: 14)),
                    
                    if (movieData != null)
                      _AttachedMovieWidget(movie: movieData),

                    const SizedBox(height: 6),
                    
                    Row(
                      children: [
                        _CommentLikeButton(
                          postId: postId,
                          commentId: doc.id,
                          initialCount: likeCount,
                          isSubReply: false,
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () => onReply(doc.id, name, authorId),
                          child: Text('Yanıtla', style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),

                    // DÜZELTME 2: Alt yanıt listesine de benzersiz Key veriyoruz.
                    // Böylece üstteki yorumun yanıtları buraya kopyalanmaz.
                    _SubRepliesList(
                      key: ValueKey(doc.id), 
                      postId: postId, 
                      parentId: doc.id
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

  String _formatTime(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'şimdi';
    if (diff.inMinutes < 60) return '${diff.inMinutes}dk';
    if (diff.inHours < 24) return '${diff.inHours}s';
    return '${diff.inDays}g';
  }
}

class _SubRepliesList extends StatefulWidget {
  final String postId;
  final String parentId;

  const _SubRepliesList({
    super.key, // Key eklendi
    required this.postId, 
    required this.parentId
  });

  @override
  State<_SubRepliesList> createState() => _SubRepliesListState();
}

class _SubRepliesListState extends State<_SubRepliesList> {
  late final Stream<QuerySnapshot> _subStream;

  @override
  void initState() {
    super.initState();
    // Key kullandığımız için artık initState her yeni parentId için çalışacak.
    _subStream = FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .collection('replies')
          .doc(widget.parentId)
          .collection('subReplies')
          .orderBy('createdAt', descending: false)
          .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _subStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final subs = snapshot.data!.docs;

        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            children: subs.map((subDoc) {
              final sData = subDoc.data() as Map<String, dynamic>;
              return _SubReplyTile(
                postId: widget.postId,
                parentId: widget.parentId,
                subDoc: subDoc,
                data: sData,
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _SubReplyTile extends StatelessWidget {
  final String postId;
  final String parentId;
  final QueryDocumentSnapshot subDoc;
  final Map<String, dynamic> data;

  const _SubReplyTile({
    required this.postId,
    required this.parentId,
    required this.subDoc,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final authorId = data['authorId'] ?? '';
    final text = data['text'] ?? '';
    final likeCount = (data['likeCount'] ?? 0) as int;
    final movieData = data['movie'] as Map<String, dynamic>?;

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(authorId).get(),
      builder: (context, snap) {
        String name = "";
        String? photo;
        if (snap.hasData) {
          final u = snap.data!.data() as Map<String, dynamic>?;
          name = u?['displayName'] ?? u?['username'] ?? '';
          photo = u?['photoURL'];
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 12,
                backgroundImage: photo != null ? NetworkImage(photo) : null,
                child: photo == null ? const Icon(Icons.person, size: 14) : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name, 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)
                    ),
                    const SizedBox(height: 2),
                    if (text.isNotEmpty)
                      Text(
                        text, 
                        style: const TextStyle(fontSize: 13)
                      ),
                    
                    if (movieData != null)
                      _AttachedMovieWidget(movie: movieData),

                    const SizedBox(height: 4),
                    
                    _CommentLikeButton(
                      postId: postId,
                      commentId: parentId,
                      subReplyId: subDoc.id,
                      initialCount: likeCount,
                      isSubReply: true,
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

class _CommentLikeButton extends StatefulWidget {
  final String postId;
  final String commentId;
  final String? subReplyId; 
  final int initialCount;
  final bool isSubReply;

  const _CommentLikeButton({
    required this.postId,
    required this.commentId,
    this.subReplyId,
    required this.initialCount,
    required this.isSubReply,
  });

  @override
  State<_CommentLikeButton> createState() => _CommentLikeButtonState();
}

class _CommentLikeButtonState extends State<_CommentLikeButton> {
  bool _isLiked = false;
  int _count = 0;
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _count = widget.initialCount;
    _checkIfLiked();
  }

  DocumentReference get _docRef {
    final db = FirebaseFirestore.instance;
    final parent = db.collection('posts').doc(widget.postId).collection('replies').doc(widget.commentId);
    
    if (widget.isSubReply && widget.subReplyId != null) {
      return parent.collection('subReplies').doc(widget.subReplyId);
    }
    return parent;
  }

  Future<void> _checkIfLiked() async {
    if (_uid.isEmpty) return;
    try {
      final likeDoc = await _docRef.collection('likes').doc(_uid).get();
      if (mounted && likeDoc.exists) {
        setState(() => _isLiked = true);
      }
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    if (_uid.isEmpty) return;

    setState(() {
      _isLiked = !_isLiked;
      _count += _isLiked ? 1 : -1;
    });

    final likeRef = _docRef.collection('likes').doc(_uid);
    final batch = FirebaseFirestore.instance.batch();

    if (_isLiked) {
      batch.set(likeRef, {'createdAt': FieldValue.serverTimestamp()});
      batch.update(_docRef, {'likeCount': FieldValue.increment(1)});
    } else {
      batch.delete(likeRef);
      batch.update(_docRef, {'likeCount': FieldValue.increment(-1)});
    }

    try {
      await batch.commit();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLiked = !_isLiked;
          _count += _isLiked ? 1 : -1;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleLike,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isLiked ? Icons.favorite : Icons.favorite_border,
            size: widget.isSubReply ? 14 : 16,
            color: _isLiked ? Colors.red : Colors.grey.shade600,
          ),
          if (_count > 0) ...[
            const SizedBox(width: 4),
            Text(
              '$_count',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
          if (!widget.isSubReply && _count == 0) ...[
             const SizedBox(width: 4),
             Text('Beğen', style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.bold)),
          ]
        ],
      ),
    );
  }
}