import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Feed ile ilgili en minimal Firestore işlemleri.
/// - Gereksiz okuma yok
/// - Yazmalar yalnızca kullanıcı aksiyonunda
/// - Sayfalama için basit yardımcılar
class FeedService {
  FeedService._();
  static final FeedService instance = FeedService._();
  FeedService._internal();
  static final FeedService _instance = FeedService._internal();
  factory FeedService() => _instance;
  static FeedService get I => _instance;

  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Base query: en yeni postlar
  Query<Map<String, dynamic>> _baseQuery() {
    return _fs.collection('posts').orderBy('createdAt', descending: true);
  }

  DocumentReference<Map<String, dynamic>> _postRef(String postId) {
    return _fs.collection('posts').doc(postId);
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

  /// Beğeni değiştir (idempotent, tek batch) + bildirim (transaction dışı).
  Future<void> toggleLike({required String postId, required bool like}) async {
    final user = _auth.currentUser;
    final me = user?.uid;
    if (me == null) return;

    final postRef = _postRef(postId);
    final likeRef = postRef.collection('likes').doc(me);

    // Post sahibini transaction dışı, hafif bir okumayla al
    String postAuthorUid = '';
    try {
      final ps = await postRef.get(const GetOptions(source: Source.server));
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
          tx.set(likeRef, {
            'by': me,
            'createdAt': now,
          }, SetOptions(merge: true));
          tx.update(postRef, {
            'likeCount': FieldValue.increment(1),
            'updatedAt': now,
          });
          addedLike = true; // transaction dışında bildirim yazacağız
        }
      } else {
        if (likeSnap.exists) {
          tx.delete(likeRef);
          tx.update(postRef, {
            'likeCount': FieldValue.increment(-1),
            'updatedAt': now,
          });
        }
      }
    });

    // Bildirim: transaction DIŞINDA, böylece like/yorum akışı asla bloklanmaz
    if (addedLike && postAuthorUid.isNotEmpty && postAuthorUid != me) {
      try {
        await _writeNotification(
          toUid: postAuthorUid,
          type: 'like',
          postId: postId,
          actorId: me,
          actorName: user?.displayName,
          actorPhotoURL: user?.photoURL,
          deterministicId: '${postId}_${me}_like', // aynı like için tek kayıt
        );
      } catch (_) {
        // Bildirim yazılamazsa like yine de başarılıdır; sessizce geç
      }
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

  /// Yorum bildirimi göndermek için harici çağrı.
  /// Yorum ekleme kodunun olduğu yerde bu fonksiyonu çağır.
  Future<void> notifyComment({
    required String postId,
    required String postAuthorUid,
    String? preview,
  }) async {
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
        deterministicId: null, // birden fazla yorum için ayrı kayıt
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
    final ref = (deterministicId == null)
        ? col.doc()
        : col.doc(deterministicId);
    await ref.set({
      'type': type,
      'actorId': actorId,
      'postId': postId,
      if (preview != null && preview.isNotEmpty) 'preview': preview,
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
      // UI hızlandırma cache alanları (opsiyonel)
      'actorName': actorName ?? '',
      'actorPhotoURL': actorPhotoURL ?? '',
    }, SetOptions(merge: true));
  }

  /// Takip bildirimi: bir kullanıcı başka bir kullanıcıyı takip ettiğinde çağır.
  Future<void> notifyFollow({required String toUid}) async {
    final user = _auth.currentUser;
    final me = user?.uid;
    if (me == null) return;
    if (toUid.isEmpty || toUid == me) return;

    try {
      final col = _fs
          .collection('users')
          .doc(toUid)
          .collection('notifications');

      // Deterministik id: aynı takip için tekrar kayıt oluşmasın
      final ref = col.doc('${me}_follow');

      await ref.set({
        'type': 'follow',
        'actorId': me,
        'postId': '-', // follow için kullanılmıyor
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
        // UI için küçük cache alanları (opsiyonel)
        'actorName': user?.displayName ?? '',
        'actorPhotoURL': user?.photoURL ?? '',
      }, SetOptions(merge: true));
    } catch (_) {
      // Bildirim düşmezse akışı bozma
    }
  }
}
