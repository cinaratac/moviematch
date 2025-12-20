import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FeedService {
  FeedService._();
  static final FeedService instance = FeedService._();
  FeedService._internal();
  static final FeedService _instance = FeedService._internal();
  factory FeedService() => _instance;
  static FeedService get I => _instance;

  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Query<Map<String, dynamic>> _baseQuery() {
    return _fs.collection('posts').orderBy('createdAt', descending: true);
  }

  DocumentReference<Map<String, dynamic>> _postRef(String postId) {
    return _fs.collection('posts').doc(postId);
  }

  Future<QuerySnapshot<Map<String, dynamic>>> fetchInitial({int limit = 20}) async {
    final q = _baseQuery().limit(limit);
    try {
      return await q.get(const GetOptions(source: Source.server));
    } catch (_) {
      return q.get(const GetOptions(source: Source.cache));
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> fetchMore({
    required DocumentSnapshot<Map<String, dynamic>> lastDoc,
    int limit = 20,
  }) {
    final q = _baseQuery().startAfterDocument(lastDoc).limit(limit);
    return q.get(); 
  }

 Future<Set<String>> fetchUserLikedPostIds(String userId) async {
    try {
      final querySnapshot = await _fs
          .collectionGroup('likes')
          .where('by', isEqualTo: userId)
          .get(const GetOptions(source: Source.serverAndCache));

      final likedIds = <String>{};
      for (var doc in querySnapshot.docs) {
        final parent = doc.reference.parent.parent;
        if (parent != null) {
          likedIds.add(parent.id);
        }
      }
      return likedIds;
    } catch (e) {
      
      return {};
    }
  }

  Future<Set<String>> fetchUserFollowingIds(String userId) async {
    try {
      final querySnapshot = await _fs
          .collection('users')
          .doc(userId)
          .collection('following')
          .get(const GetOptions(source: Source.serverAndCache));
      
      return querySnapshot.docs.map((d) => d.id).toSet();
    } catch (e) {
      return {};
    }
  }

  // --- GÜNCELLENMİŞ FONKSİYON ---
  Future<void> createPost({
    required String text,
    Map<String, dynamic>? movie,
    String? handle,
    String? displayName,
    String? photoURL, 
    List<String>? photoURLs, // YENİ: Çoklu foto desteği
    double? rating,       
    bool isSpoiler = false,
    List<String>? tags,   
    String? reviewTitle,  
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final doc = _fs.collection('posts').doc();
    final now = FieldValue.serverTimestamp();
    
    await doc.set({
      'id': doc.id,
      'authorId': user.uid,
      'displayName': displayName ?? '',
      'handle': (handle ?? '').trim(),
      'photoURL': photoURL ?? '', // Geriye dönük uyumluluk
      'photoURLs': photoURLs ?? [], // Yeni liste
      'movie': movie,
      'text': text.trim(),
      'rating': rating,
      'isSpoiler': isSpoiler,
      'tags': tags ?? [],
      'reviewTitle': reviewTitle?.trim(),
      'isReview': rating != null || (reviewTitle != null && reviewTitle.isNotEmpty),
      'likeCount': 0,
      'replyCount': 0,
      'repostCount': 0,
      'createdAt': now,
      'updatedAt': now,
    }, SetOptions(merge: false));
  }

  Future<void> toggleLike({required String postId, required bool like}) async {
    final user = _auth.currentUser;
    final me = user?.uid;
    if (me == null) return;

    final postRef = _postRef(postId);
    final likeRef = postRef.collection('likes').doc(me);

    String postAuthorUid = '';
    try {
      final ps = await postRef.get();
      postAuthorUid = (ps.data()?['authorId'] ?? '').toString();
      if (postAuthorUid.isEmpty) {
        final pc = await postRef.get(const GetOptions(source: Source.cache));
        postAuthorUid = (pc.data()?['authorId'] ?? '').toString();
      }
    } catch (_) {}

    bool addedLike = false;

    await _fs.runTransaction((tx) async {
      final likeSnap = await tx.get(likeRef);
      final now = FieldValue.serverTimestamp();

      if (like) {
        if (!likeSnap.exists) {
          tx.set(likeRef, {'by': me, 'createdAt': now}, SetOptions(merge: true));
          tx.update(postRef, {'likeCount': FieldValue.increment(1), 'updatedAt': now});
          addedLike = true;
        }
      } else {
        if (likeSnap.exists) {
          tx.delete(likeRef);
          tx.update(postRef, {'likeCount': FieldValue.increment(-1), 'updatedAt': now});
        }
      }
    });

    if (addedLike && postAuthorUid.isNotEmpty && postAuthorUid != me) {
      try {
        await _writeNotification(
          toUid: postAuthorUid,
          type: 'like',
          postId: postId,
          actorId: me,
          actorName: user?.displayName,
          actorPhotoURL: user?.photoURL,
          deterministicId: '${postId}_${me}_like',
        );
      } catch (_) {}
    }
  }

  Future<void> followUser(String otherUid) async {
    final me = _auth.currentUser?.uid;
    if (me == null || me == otherUid) return;
    final ref = _fs.collection('users').doc(me).collection('following').doc(otherUid);
    await ref.set({'by': me, 'to': otherUid, 'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  Future<void> reportPost(String postId) async {
    final me = _auth.currentUser?.uid;
    if (me == null) return;
    await _fs.collection('reports').add({
      'type': 'post',
      'postId': postId,
      'by': me,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> notifyComment({required String postId, required String postAuthorUid, String? preview}) async {
    final user = _auth.currentUser;
    final me = user?.uid;
    if (me == null) return;
    if (postAuthorUid.isEmpty || postAuthorUid == me) return;

    try {
      await _writeNotification(
        toUid: postAuthorUid,
        type: 'comment',
        postId: postId,
        actorId: me,
        actorName: user?.displayName,
        actorPhotoURL: user?.photoURL,
        preview: preview,
        deterministicId: null,
      );
    } catch (_) {}
  }

  Future<void> _writeNotification({
    required String toUid,
    required String type,
    required String postId,
    required String actorId,
    String? actorName,
    String? actorPhotoURL,
    String? preview,
    String? deterministicId,
  }) async {
    final col = _fs.collection('users').doc(toUid).collection('notifications');
    final ref = (deterministicId == null) ? col.doc() : col.doc(deterministicId);
    await ref.set({
      'type': type,
      'actorId': actorId,
      'postId': postId,
      if (preview != null && preview.isNotEmpty) 'preview': preview,
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
      'actorName': actorName ?? '',
      'actorPhotoURL': actorPhotoURL ?? '',
    }, SetOptions(merge: true));
  }

  Future<void> notifyFollow({required String toUid}) async {
    final user = _auth.currentUser;
    final me = user?.uid;
    if (me == null) return;
    if (toUid.isEmpty || toUid == me) return;

    try {
      final col = _fs.collection('users').doc(toUid).collection('notifications');
      final ref = col.doc('${me}_follow');

      await ref.set({
        'type': 'follow',
        'actorId': me,
        'postId': '-',
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
        'actorName': user?.displayName ?? '',
        'actorPhotoURL': user?.photoURL ?? '',
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}