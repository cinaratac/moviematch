import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FollowEvent {
  final String actorUid;
  final String targetUid;
  final bool followed;
  const FollowEvent({required this.actorUid, required this.targetUid, required this.followed});
}

class FollowSystemService {
  FollowSystemService._();
  static final FollowSystemService I = FollowSystemService._();

  static final StreamController<FollowEvent> _bus = StreamController<FollowEvent>.broadcast();
  Stream<FollowEvent> get events => _bus.stream;

  FirebaseFirestore get _fs => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  String pairIdOf(String a, String b) => (a.compareTo(b) < 0) ? '${a}_$b' : '${b}_$a';

  Future<void> followUser(String targetUid) async {
    final me = _auth.currentUser?.uid;
    if (me == null || me == targetUid) return;

    final followingDoc = _fs.collection('users').doc(me).collection('following').doc(targetUid);
    final followerDoc = _fs.collection('users').doc(targetUid).collection('followers').doc(me);

    final already = (await followingDoc.get(const GetOptions(source: Source.server))).exists;
    if (already) return;

    final batch = _fs.batch();
    
    // 1. Beni takip ettiklerime ekle, onu takipçilerine ekle
    batch.set(followingDoc, {'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    batch.set(followerDoc, {'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

    // 2. Karşı taraf beni takip ediyor mu KONTROL ET
    final theyFollowMe = await _fs.collection('users').doc(me).collection('followers').doc(targetUid).get();
    
    if (theyFollowMe.exists) {
      // 3. Karşılıklı takip varsa EŞLEŞMEYİ ORTAK HAVUZA YAZ
      final matchId = pairIdOf(me, targetUid);
      batch.set(_fs.collection('matches').doc(matchId), {
        'matchedAt': FieldValue.serverTimestamp(),
        'users': [me, targetUid],
      }, SetOptions(merge: true));
    }

    await batch.commit();
    _bus.add(FollowEvent(actorUid: me, targetUid: targetUid, followed: true));
  }

  Future<void> unfollowUser(String targetUid) async {
    final me = _auth.currentUser?.uid;
    if (me == null || me == targetUid) return;

    final followingDoc = _fs.collection('users').doc(me).collection('following').doc(targetUid);
    final followerDoc = _fs.collection('users').doc(targetUid).collection('followers').doc(me);

    final exists = (await followingDoc.get(const GetOptions(source: Source.server))).exists;
    if (!exists) return;

    final batch = _fs.batch();
    batch.delete(followingDoc);
    batch.delete(followerDoc);

    // Ortak eşleşmeyi (Match) boz
    final matchId = pairIdOf(me, targetUid);
    batch.delete(_fs.collection('matches').doc(matchId));

    await batch.commit();
    _bus.add(FollowEvent(actorUid: me, targetUid: targetUid, followed: false));
  }

  // YENİ: Anında sayan yüksek performanslı sayaçlar
  Future<int> fetchFollowerCountOnce(String uid) async {
    final agg = await _fs.collection('users').doc(uid).collection('followers').count().get();
    return agg.count ?? 0;
  }

  Future<int> fetchFollowingCountOnce(String uid) async {
    final agg = await _fs.collection('users').doc(uid).collection('following').count().get();
    return agg.count ?? 0;
  }
}