import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Stable, order-independent pair id using two UIDs (sorted lexicographically)
String pairIdOf(String u1, String u2) =>
    (u1.compareTo(u2) < 0) ? '${u1}_$u2' : '${u2}_$u1';

class LikeService {
  LikeService._();
  static final instance = LikeService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _likesCol =>
      _db.collection('likes');
  CollectionReference<Map<String, dynamic>> get _matchesCol =>
      _db.collection('matches');
  CollectionReference<Map<String, dynamic>> get _chatsCol =>
      _db.collection('chats');

  /// Current user's UID or throws if not signed in
  String get _uid =>
      _auth.currentUser?.uid ?? (throw StateError('No Firebase user'));

  /// Register a like from the current user to [otherUid].
  /// If both sides liked each other, creates/updates `matches/{pairId}` and a chat stub.
  Future<void> likeUser(
    String otherUid, {
    int commonFavoritesCount = 0,
    int commonFiveStarsCount = 0,
  }) async {
    final me = _uid;
    if (me == otherUid) return; // ignore self

    final pairId = pairIdOf(me, otherUid);
    final docRef = _likesCol.doc(pairId);

    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        late String a;
        late String b;
        if (!snap.exists) {
          // First interaction for this pair
          a = (me.compareTo(otherUid) < 0) ? me : otherUid;
          b = (a == me) ? otherUid : me;
          tx.set(docRef, {
            'a': a,
            'b': b,
            'uids': [a, b],
            'aLiked': a == me,
            'bLiked': b == me,
            'aPass': false,
            'bPass': false,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return;
        }

        final data = Map<String, dynamic>.from(snap.data()!);
        a = data['a'] as String;
        b = data['b'] as String;
        final meIsA = me == a;
        final likeField = meIsA ? 'aLiked' : 'bLiked';
        final passField = meIsA ? 'aPass' : 'bPass';

        final newALiked = meIsA ? true : (data['aLiked'] == true);
        final newBLiked = meIsA ? (data['bLiked'] == true) : true;
        final willBothLike = newALiked && newBLiked;

        if (data[likeField] != true || data[passField] == true) {
          tx.update(docRef, {
            likeField: true,
            passField: false, // like overrides pass
            'uids': FieldValue.arrayUnion([a, b]),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        if (willBothLike) {
          final matchId = pairId; // use the same id for simplicity
          final matchRef = _matchesCol.doc(matchId);
          final now = FieldValue.serverTimestamp();
          tx.set(matchRef, {
            'uids': [a, b],
            'commonFavoritesCount': commonFavoritesCount,
            'commonFiveStarsCount': commonFiveStarsCount,
            'createdAt': now,
            'updatedAt': now,
          }, SetOptions(merge: true));

          // Ensure chat stub exists (optional)
          final chatRef = _chatsCol.doc(matchId);
          tx.set(chatRef, {
            'participants': [a, b],
            'createdAt': now,
            'updatedAt': now,
            'lastMessageAt': now,
          }, SetOptions(merge: true));
        }
      });
    } catch (e) {
      // Fallback merge write so like is not lost if transaction fails (e.g., permissions/index)
      await docRef.set({
        'a': (me.compareTo(otherUid) < 0) ? me : otherUid,
        'b': (me.compareTo(otherUid) < 0) ? otherUid : me,
        'uids': [me, otherUid],
        // mark my side like, clear my pass
        (me.compareTo(otherUid) < 0) ? 'aLiked' : 'bLiked': true,
        (me.compareTo(otherUid) < 0) ? 'aPass' : 'bPass': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    // Mirror log to a separate collection
    try {
      await _db.collection('likeLogs').add({
        'from': me,
        'to': otherUid,
        'action': 'like',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // non-fatal
    }
  }

  /// Register a pass (skip). This does not delete likes; it just marks pass.
  Future<void> passUser(String otherUid) async {
    final me = _uid;
    if (me == otherUid) return;

    final pairId = pairIdOf(me, otherUid);
    final docRef = _likesCol.doc(pairId);

    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        late String a;
        late String b;
        if (!snap.exists) {
          a = (me.compareTo(otherUid) < 0) ? me : otherUid;
          b = (a == me) ? otherUid : me;
          tx.set(docRef, {
            'a': a,
            'b': b,
            'uids': [a, b],
            'aLiked': false,
            'bLiked': false,
            'aPass': a == me,
            'bPass': b == me,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return;
        }

        final data = Map<String, dynamic>.from(snap.data()!);
        a = data['a'] as String;
        b = data['b'] as String;
        final meIsA = me == a;
        final passField = meIsA ? 'aPass' : 'bPass';
        if (data[passField] != true) {
          tx.update(docRef, {
            passField: true,
            'uids': FieldValue.arrayUnion([a, b]),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (e) {
      // Fallback merge write so pass is not lost if transaction fails
      await docRef.set({
        'a': (me.compareTo(otherUid) < 0) ? me : otherUid,
        'b': (me.compareTo(otherUid) < 0) ? otherUid : me,
        'uids': [me, otherUid],
        (me.compareTo(otherUid) < 0) ? 'aPass' : 'bPass': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    // Mirror log to a separate collection
    try {
      await _db.collection('likeLogs').add({
        'from': me,
        'to': otherUid,
        'action': 'pass',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // non-fatal
    }
  }

  /// Remove a match for this pair. Keeps the like history unless [alsoClearLikes] is true.
  Future<void> unmatch(String otherUid, {bool alsoClearLikes = false}) async {
    final me = _uid;
    final matchId = pairIdOf(me, otherUid);

    final batch = _db.batch();
    batch.delete(_matchesCol.doc(matchId));
    // Optionally clear like doc too
    if (alsoClearLikes) {
      batch.delete(_likesCol.doc(matchId));
    }
    // Optionally clear chat stub (messages subcollection left intact unless you also delete recursively via Cloud Functions)
    batch.delete(_chatsCol.doc(matchId));
    await batch.commit();
  }

  /// True if a match doc exists for current user and [otherUid]
  Future<bool> isMatchedWith(String otherUid) async {
    final me = _uid;
    final matchId = pairIdOf(me, otherUid);
    final doc = await _matchesCol.doc(matchId).get();
    return doc.exists;
  }

  /// Stream the current user's matches ordered by updatedAt desc
  Stream<QuerySnapshot<Map<String, dynamic>>> myMatchesStream() {
    final me = _uid;
    return _matchesCol
        .where('uids', arrayContains: me)
        .orderBy('updatedAt', descending: true)
        .snapshots();
  }
}
