import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ClubService {
  ClubService._();
  static final instance = ClubService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<QuerySnapshot> getUserClubsStream(String uid) {
    // Not: Firestore'da 'array-contains' ve 'orderBy' aynı anda kullanıldığında
    // konsoldan index oluşturmanız gerekebilir.
    return _db.collection('clubs')
        .where('members', arrayContains: uid)
        .snapshots();
  }

  // --- KULÜP OLUŞTURMA ---
  Future<void> createClub({
    required String name,
    String? description,
    required bool isPrivate,
    String? imageUrl,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final clubRef = _db.collection('clubs').doc();
    final chatRef = _db.collection('chats').doc(clubRef.id);
    final now = FieldValue.serverTimestamp();

    final clubData = {
      'id': clubRef.id,
      'name': name,
      'description': description ?? '',
      'imageUrl': imageUrl ?? '',
      'isPrivate': isPrivate,
      'ownerId': user.uid,
      'createdAt': now,
      'members': [user.uid],
      'admins': [user.uid],
      'pendingRequests': [],
      'memberCount': 1, // <--- EKLENDİ: Başlangıç sayısı
    };

    await _db.runTransaction((tx) async {
      tx.set(clubRef, clubData);
      
      tx.set(chatRef, {
        'isGroup': true,
        'name': name,
        'ownerId': user.uid,
        'participants': [user.uid],
        'lastMessage': 'Kulüp oluşturuldu 🎉',
        'lastMessageAt': now,
        'createdAt': now,
        'updatedAt': now,
      });
    });
  }

  // --- KULÜBE KATILMA İSTEĞİ ---
  Future<void> joinClub(String clubId, bool isPrivate) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final clubRef = _db.collection('clubs').doc(clubId);
    final chatRef = _db.collection('chats').doc(clubId);

    if (isPrivate) {
      await clubRef.update({
        'pendingRequests': FieldValue.arrayUnion([uid])
      });
    } else {
      final batch = _db.batch();
      batch.update(clubRef, {
        'members': FieldValue.arrayUnion([uid]),
        'memberCount': FieldValue.increment(1), // <--- EKLENDİ: Sayaç artırma
      });
      batch.update(chatRef, {
        'participants': FieldValue.arrayUnion([uid])
      });
      await batch.commit();
    }
  }

  // --- ÜYE ONAYLAMA ---
  Future<void> approveMember(String clubId, String memberUid) async {
    final clubRef = _db.collection('clubs').doc(clubId);
    final chatRef = _db.collection('chats').doc(clubId);

    final batch = _db.batch();
    batch.update(clubRef, {
      'pendingRequests': FieldValue.arrayRemove([memberUid]),
      'members': FieldValue.arrayUnion([memberUid]),
      'memberCount': FieldValue.increment(1), // <--- EKLENDİ: Sayaç artırma
    });
    batch.update(chatRef, {
      'participants': FieldValue.arrayUnion([memberUid])
    });
    await batch.commit();
  }

  // --- İSTEĞİ REDDETME ---
  Future<void> rejectMember(String clubId, String memberUid) async {
    await _db.collection('clubs').doc(clubId).update({
      'pendingRequests': FieldValue.arrayRemove([memberUid])
    });
  }

  // --- ÜYEYİ KULÜPTEN ATMA ---
  Future<void> kickMember(String clubId, String memberUid) async {
    final clubRef = _db.collection('clubs').doc(clubId);
    final chatRef = _db.collection('chats').doc(clubId);

    final batch = _db.batch();
    batch.update(clubRef, {
      'members': FieldValue.arrayRemove([memberUid]),
      'admins': FieldValue.arrayRemove([memberUid]),
      'memberCount': FieldValue.increment(-1), // <--- EKLENDİ: Sayaç azaltma
    });
    batch.update(chatRef, {
      'participants': FieldValue.arrayRemove([memberUid])
    });
    await batch.commit();
  }

  // --- YÖNETİCİ YAP / ÇIKAR ---
  Future<void> toggleAdmin(String clubId, String memberUid, bool makeAdmin) async {
    final clubRef = _db.collection('clubs').doc(clubId);
    if (makeAdmin) {
      await clubRef.update({'admins': FieldValue.arrayUnion([memberUid])});
    } else {
      await clubRef.update({'admins': FieldValue.arrayRemove([memberUid])});
    }
  }

  // --- KULÜPLERİ GETİR ---
  Stream<QuerySnapshot> getClubsStream() {
    return _db.collection('clubs').orderBy('createdAt', descending: true).snapshots();
  }
}