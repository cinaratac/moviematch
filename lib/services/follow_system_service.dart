import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// FollowSystemService
/// --------------------
/// Tek sorumluluğu: takip / takipten çık işlemlerini Firestore'a güvenli
/// ve minimum yazma ile yapmak. Ayrıca, sayfayı yenilemeden sayaçların
/// anında güncellenmesi için hafif bir yerel EventBus yayınlar.
class FollowEvent {
  final String actorUid; // Takip eden (ben)
  final String targetUid; // Takip edilen profil
  final bool followed; // true: follow, false: unfollow
  const FollowEvent({
    required this.actorUid,
    required this.targetUid,
    required this.followed,
  });
}

class FollowSystemService {
  FollowSystemService._();
  static final FollowSystemService I = FollowSystemService._();

  // Yerel yayın — PublicProfile / Profile gibi ekranlar abone olup
  // sayılarını ek okuma yapmadan anında artırıp/azaltabilir.
  static final StreamController<FollowEvent> _bus =
      StreamController<FollowEvent>.broadcast();
  Stream<FollowEvent> get events => _bus.stream;

  FirebaseFirestore get _fs => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  /// Takip et
  Future<void> followUser(String targetUid) async {
    final me = _auth.currentUser?.uid;
    if (me == null || me == targetUid) return;

    final followerDoc = _fs
        .collection('users')
        .doc(targetUid)
        .collection('followers')
        .doc(me);

    final followingDoc = _fs
        .collection('users')
        .doc(me)
        .collection('following')
        .doc(targetUid);

    // Minimum yazma: Zaten takip ediyorsa hiç yazma.
    final already = (await followerDoc.get(
      const GetOptions(source: Source.server),
    )).exists;
    if (already) return;

    final batch = _fs.batch();
    batch.set(followerDoc, {
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(followingDoc, {
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();

    _bus.add(FollowEvent(actorUid: me, targetUid: targetUid, followed: true));
  }

  /// Takipten çık
  Future<void> unfollowUser(String targetUid) async {
    final me = _auth.currentUser?.uid;
    if (me == null || me == targetUid) return;

    final followerDoc = _fs
        .collection('users')
        .doc(targetUid)
        .collection('followers')
        .doc(me);

    final followingDoc = _fs
        .collection('users')
        .doc(me)
        .collection('following')
        .doc(targetUid);

    // Minimum yazma: Zaten yoksa yazma.
    final exists = (await followerDoc.get(
      const GetOptions(source: Source.server),
    )).exists;
    if (!exists) return;

    final batch = _fs.batch();
    batch.delete(followerDoc);
    batch.delete(followingDoc);
    await batch.commit();

    _bus.add(FollowEvent(actorUid: me, targetUid: targetUid, followed: false));
  }

  /// Bir kullanıcının takipçi sayısını tek seferlik getirir (ek okuma yapmamak için).
  Future<int> fetchFollowerCountOnce(String uid) async {
    final agg = await _fs
        .collection('users')
        .doc(uid)
        .collection('followers')
        .count()
        .get();
    return agg.count ?? 0; // requires cloud_firestore >= 4.9
  }

  /// Bir kullanıcının takip ettiği kişi sayısını tek seferlik getirir.
  Future<int> fetchFollowingCountOnce(String uid) async {
    final agg = await _fs
        .collection('users')
        .doc(uid)
        .collection('following')
        .count()
        .get();
    return agg.count ?? 0;
  }
}
