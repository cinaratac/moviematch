import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ClubService {
  ClubService._();
  static final instance = ClubService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<QuerySnapshot> getUserClubsStream(String uid) {
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
      'memberCount': 1, 
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
    final user = _auth.currentUser;
    final uid = user?.uid;
    if (uid == null || user == null) return;

    final clubRef = _db.collection('clubs').doc(clubId);
    final chatRef = _db.collection('chats').doc(clubId);

    if (isPrivate) {
      await clubRef.update({
        'pendingRequests': FieldValue.arrayUnion([uid])
      });

      try {
        final clubDoc = await clubRef.get();
        if (clubDoc.exists) {
          final data = clubDoc.data() as Map<String, dynamic>;
          final admins = List<dynamic>.from(data['admins'] ?? []);
          final clubName = data['name'] ?? 'Kulüp';

          for (final adminId in admins) {
            if (adminId == uid) continue; 

            await _db.collection('users').doc(adminId).collection('notifications').add({
              'type': 'club_request',
              'actorId': uid,
              'actorName': user.displayName ?? 'Bir Kullanıcı',
              'clubId': clubId,
              'clubName': clubName,
              'preview': 'Kulübünüze katılmak istiyor.',
              'createdAt': FieldValue.serverTimestamp(),
              'isRead': false,
            });
          }
        }
      } catch (e) {
        print("Bildirim gönderme hatası: $e");
      }

    } else {
      final batch = _db.batch();
      batch.update(clubRef, {
        'members': FieldValue.arrayUnion([uid]),
        'memberCount': FieldValue.increment(1),
      });
      batch.update(chatRef, {
        'participants': FieldValue.arrayUnion([uid])
      });
      await batch.commit();
    }
  }

  // --- ÜYE YÖNETİMİ ---
  Future<void> approveMember(String clubId, String memberUid) async {
    final clubRef = _db.collection('clubs').doc(clubId);
    final chatRef = _db.collection('chats').doc(clubId);

    final batch = _db.batch();
    batch.update(clubRef, {
      'pendingRequests': FieldValue.arrayRemove([memberUid]),
      'members': FieldValue.arrayUnion([memberUid]),
      'memberCount': FieldValue.increment(1), 
    });
    batch.update(chatRef, {
      'participants': FieldValue.arrayUnion([memberUid])
    });
    await batch.commit();
  }

  Future<void> rejectMember(String clubId, String memberUid) async {
    await _db.collection('clubs').doc(clubId).update({
      'pendingRequests': FieldValue.arrayRemove([memberUid])
    });
  }

  Future<void> kickMember(String clubId, String memberUid) async {
    final clubRef = _db.collection('clubs').doc(clubId);
    final chatRef = _db.collection('chats').doc(clubId);

    final batch = _db.batch();
    batch.update(clubRef, {
      'members': FieldValue.arrayRemove([memberUid]),
      'admins': FieldValue.arrayRemove([memberUid]),
      'memberCount': FieldValue.increment(-1), 
    });
    batch.update(chatRef, {
      'participants': FieldValue.arrayRemove([memberUid])
    });
    await batch.commit();
  }

  Future<void> toggleAdmin(String clubId, String memberUid, bool makeAdmin) async {
    final clubRef = _db.collection('clubs').doc(clubId);
    if (makeAdmin) {
      await clubRef.update({'admins': FieldValue.arrayUnion([memberUid])});
    } else {
      await clubRef.update({'admins': FieldValue.arrayRemove([memberUid])});
    }
  }

  Stream<QuerySnapshot> getClubsStream() {
    return _db.collection('clubs').orderBy('createdAt', descending: true).snapshots();
  }

  // ======================================================
  // YENİ ÖZELLİKLER: HAFTANIN FİLMİ, ETKİNLİKLER, ANKETLER
  // ======================================================

  // 1. HAFTANIN FİLMİ
  Future<void> setFeaturedMovie(String clubId, Map<String, dynamic> movie) async {
    await _db.collection('clubs').doc(clubId).update({
      'featuredMovie': movie,
      'featuredMovieUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removeFeaturedMovie(String clubId) async {
    await _db.collection('clubs').doc(clubId).update({
      'featuredMovie': FieldValue.delete(),
      'featuredMovieUpdatedAt': FieldValue.delete(),
    });
  }

  // 2. ETKİNLİKLER
  Stream<QuerySnapshot> getClubEvents(String clubId) {
    return _db.collection('clubs').doc(clubId).collection('events')
        .orderBy('date', descending: false)
        .snapshots();
  }

  Future<void> createEvent(String clubId, String title, DateTime date) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Etkinliği oluştur
    await _db.collection('clubs').doc(clubId).collection('events').add({
      'title': title,
      'date': date,
      'participants': [],
      'createdAt': FieldValue.serverTimestamp(),
    });

    // YENİ: Sohbet mesajı gönder
    final message = "📅 Yeni Etkinlik: $title";
    await _db.collection('chats').doc(clubId).collection('messages').add({
      'text': message,
      'authorId': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'type': 'system', 
    });

    await _db.collection('chats').doc(clubId).update({
      'lastMessage': message,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> joinEvent(String clubId, String eventId, String uid) async {
    final ref = _db.collection('clubs').doc(clubId).collection('events').doc(eventId);
    final doc = await ref.get();
    if (!doc.exists) return;
    
    final List parts = List.from(doc.data()?['participants'] ?? []);
    if (parts.contains(uid)) {
      await ref.update({'participants': FieldValue.arrayRemove([uid])});
    } else {
      await ref.update({'participants': FieldValue.arrayUnion([uid])});
    }
  }

  Future<void> deleteEvent(String clubId, String eventId) async {
    await _db.collection('clubs').doc(clubId).collection('events').doc(eventId).delete();
  }

  // 4. ANKETLER
  Stream<QuerySnapshot> getClubPolls(String clubId) {
    return _db.collection('clubs').doc(clubId).collection('polls')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> createPoll(String clubId, String question, List<String> options) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final opts = options.map((o) => {'text': o, 'voteCount': 0}).toList();
    
    // Anketi oluştur
    await _db.collection('clubs').doc(clubId).collection('polls').add({
      'question': question,
      'options': opts,
      'voters': {}, 
      'createdAt': FieldValue.serverTimestamp(),
    });

    // YENİ: Sohbet mesajı gönder
    final message = "📊 Yeni Anket: $question";
    await _db.collection('chats').doc(clubId).collection('messages').add({
      'text': message,
      'authorId': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'type': 'system',
    });

    await _db.collection('chats').doc(clubId).update({
      'lastMessage': message,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> votePoll(String clubId, String pollId, String uid, int optionIndex) async {
    final ref = _db.collection('clubs').doc(clubId).collection('polls').doc(pollId);
    
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      
      final data = snap.data() as Map<String, dynamic>;
      final voters = Map<String, dynamic>.from(data['voters'] ?? {});
      final options = List<dynamic>.from(data['options']);

      if (voters.containsKey(uid)) {
        final oldIdx = voters[uid] as int;
        if (oldIdx < options.length) {
          options[oldIdx]['voteCount'] = (options[oldIdx]['voteCount'] ?? 1) - 1;
        }
      }

      voters[uid] = optionIndex;
      options[optionIndex]['voteCount'] = (options[optionIndex]['voteCount'] ?? 0) + 1;

      tx.update(ref, {'voters': voters, 'options': options});
    });
  }
  
  Future<void> deletePoll(String clubId, String pollId) async {
    await _db.collection('clubs').doc(clubId).collection('polls').doc(pollId).delete();
  }
}