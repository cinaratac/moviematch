import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Feed ile ilgili en minimal Firestore işlemleri.
/// - Gereksiz okuma yok
/// - Yazmalar yalnızca kullanıcı aksiyonunda
/// - Sayfalama için basit yardımcılar
class FeedService {
  FeedService._();
  static final FeedService instance = FeedService._();

  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Base query: en yeni postlar
  Query<Map<String, dynamic>> _baseQuery() {
    return _fs.collection('posts').orderBy('createdAt', descending: true);
  }

  /// İlk sayfayı getirir. (server -> cache fallback)
  Future<QuerySnapshot<Map<String, dynamic>>> fetchInitial({
    int limit = 20,
  }) async {
    final q = _baseQuery().limit(limit);
    try {
      return await q.get(const GetOptions(source: Source.server));
    } catch (_) {
      return q.get(const GetOptions(source: Source.cache));
    }
  }

  /// Son alınan belge sonrası sayfayı getirir. (yalnızca server)
  Future<QuerySnapshot<Map<String, dynamic>>> fetchMore({
    required DocumentSnapshot<Map<String, dynamic>> lastDoc,
    int limit = 20,
  }) {
    final q = _baseQuery().startAfterDocument(lastDoc).limit(limit);
    return q.get(const GetOptions(source: Source.server));
  }

  /// Yeni post oluşturur.
  /// - Sadece kullanıcı aksiyonunda çalışır
  /// - `handle` opsiyoneldir (ör. '@lb'), verilmezse boş geçilir
  Future<void> createPost({
    required String text,
    String? handle,
    String? displayName,
    String? photoURL,
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
      'photoURL': photoURL ?? '',
      'text': text.trim(),
      'likeCount': 0,
      'replyCount': 0,
      'repostCount': 0,
      'createdAt': now,
      'updatedAt': now,
    }, SetOptions(merge: false));
  }

  /// Beğeni değiştir (idempotent, tek batch).
  Future<void> toggleLike({required String postId, required bool like}) async {
    final me = _auth.currentUser?.uid;
    if (me == null) return;

    final likeRef = _fs
        .collection('posts')
        .doc(postId)
        .collection('likes')
        .doc(me);

    if (like) {
      await likeRef.set({
        'by': me,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      await likeRef.delete();
    }
  }

  /// Takip et (idempotent; okuma gerekmez).
  Future<void> followUser(String otherUid) async {
    final me = _auth.currentUser?.uid;
    if (me == null || me == otherUid) return;
    final ref = _fs
        .collection('users')
        .doc(me)
        .collection('following')
        .doc(otherUid);
    await ref.set({
      'by': me,
      'to': otherUid,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Post raporla (yalnızca kullanıcı aksiyonunda).
  Future<void> reportPost(String postId) async {
    final me = _auth.currentUser?.uid;
    if (me == null) return;
    final docId = '${postId}_$me';
    await _fs.collection('reports').doc(docId).set({
      'type': 'post',
      'postId': postId,
      'by': me,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
