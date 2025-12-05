import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/services/text_filter_service.dart';
import 'package:fluttergirdi/services/feed_service.dart'; // FeedService Importu Şart

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
  String? _replyingToUid; // YENİ: Yanıt verilen kişinin ID'sini tutuyoruz

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

  Future<void> _send() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;

    if (TextFilterService.hasProfanity(text)) {
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

      if (_replyingToDocId == null) {
        // --- ANA YORUM ---
        final ref = db.collection('posts').doc(widget.postId).collection('replies').doc();
        batch.set(ref, {
          'text': text,
          'authorId': user.uid,
          'createdAt': now,
          'likeCount': 0,
          'replyCount': 0, 
        });
        
        final postRef = db.collection('posts').doc(widget.postId);
        batch.update(postRef, {'replyCount': FieldValue.increment(1)});

      } else {
        // --- ALT YANIT (REPLY) ---
        final parentRef = db.collection('posts').doc(widget.postId).collection('replies').doc(_replyingToDocId);
        final subRef = parentRef.collection('subReplies').doc();
        
        batch.set(subRef, {
          'text': text,
          'authorId': user.uid,
          'createdAt': now,
          'likeCount': 0,
        });

        batch.update(parentRef, {'replyCount': FieldValue.increment(1)});
        
        final postRef = db.collection('posts').doc(widget.postId);
        batch.update(postRef, {'replyCount': FieldValue.increment(1)});
      }

      await batch.commit();

      // --- BİLDİRİM GÖNDERME KISMI (YENİ) ---
      if (_replyingToDocId == null) {
        // Post sahibine bildirim gönder
        FeedService.instance.notifyComment(
          postId: widget.postId,
          postAuthorUid: widget.postAuthorId,
          preview: text,
        );
      } else if (_replyingToUid != null) {
        // Yanıt verilen kişiye bildirim gönder
        FeedService.instance.notifyComment(
          postId: widget.postId,
          postAuthorUid: _replyingToUid!, // Yanıt verilen kişinin ID'si
          preview: text,
        );
      }
      // -------------------------------------

      _commentCtrl.clear();
      _cancelReply(); 
      FocusScope.of(context).unfocus();

    } catch (e) {
      debugPrint('Yorum hatası: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // GÜNCELLENDİ: Artık UID de alıyor
  void _initiateReply(String docId, String userName, String uid) {
    setState(() {
      _replyingToDocId = docId;
      _replyingToUserName = userName;
      _replyingToUid = uid; // ID'yi sakla
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

    return Container(
      height: MediaQuery.of(context).size.height * 0.85, 
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // --- HEADER ---
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

          // --- LİSTE ---
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
                    return _CommentTile(
                      postId: widget.postId,
                      doc: docs[index],
                      onReply: _initiateReply, 
                    );
                  },
                );
              },
            ),
          ),

          // --- INPUT ALANI ---
          Container(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + bottomInset), 
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
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
                        Icon(Icons.reply, size: 16, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$_replyingToUserName adlı kişiye yanıt veriliyor',
                            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 12),
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
                
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentCtrl,
                        focusNode: _focusNode,
                        decoration: InputDecoration(
                          hintText: _replyingToUserName != null ? 'Yanıtını yaz...' : 'Yorum yap...',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
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
                          : Icon(Icons.send_rounded, color: Theme.of(context).colorScheme.primary),
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

// --- TEKİL YORUM SATIRI ---
class _CommentTile extends StatelessWidget {
  final String postId;
  final QueryDocumentSnapshot doc;
  // GÜNCELLENDİ: uid parametresi eklendi
  final Function(String docId, String userName, String uid) onReply;

  const _CommentTile({
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
                    Text(text, style: const TextStyle(fontSize: 14)),
                    
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
                          // GÜNCELLENDİ: authorId de gönderiliyor
                          onTap: () => onReply(doc.id, name, authorId),
                          child: Text('Yanıtla', style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),

                    _SubRepliesList(postId: postId, parentId: doc.id),
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

// --- ALT YANITLAR LİSTESİ (STATEFUL) ---
class _SubRepliesList extends StatefulWidget {
  final String postId;
  final String parentId;

  const _SubRepliesList({required this.postId, required this.parentId});

  @override
  State<_SubRepliesList> createState() => _SubRepliesListState();
}

class _SubRepliesListState extends State<_SubRepliesList> {
  late final Stream<QuerySnapshot> _subStream;

  @override
  void initState() {
    super.initState();
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

// --- TEKİL ALT YANIT SATIRI ---
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
                    Text(
                      text, 
                      style: const TextStyle(fontSize: 13)
                    ),
                    
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

// --- BEĞENİ BUTONU ---
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