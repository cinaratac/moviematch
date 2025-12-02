import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttergirdi/services/notification_service.dart';
import 'dart:math' as math; // EKLENDİ: math.max kullanmak için

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Keep lightweight.
}

class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();
  factory ChatService() => instance;
  final _fs = FirebaseFirestore.instance;

  String chatIdFor(String a, String b) {
    final s = [a, b]..sort();
    return '${s[0]}_${s[1]}';
  }

  Future<String> getOrCreateChat(String uidA, String uidB) async {
    final id = chatIdFor(uidA, uidB);
    final ref = _fs.collection('chats').doc(id);
    await ref.set({
      'participants': FieldValue.arrayUnion([uidA, uidB]),
    }, SetOptions(merge: true));
    return id;
  }

  Future<void> ensureChat(String chatId, String uidA, String uidB) async {
    final ref = _fs.collection('chats').doc(chatId);
    await ref.set({
      'participants': FieldValue.arrayUnion([uidA, uidB]),
    }, SetOptions(merge: true));
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> messages(
    String chatId, {
    bool newestFirst = true,
  }) {
    return _fs
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: newestFirst)
        .limit(100)
        .snapshots();
  }

  /// OPTİMİZE EDİLDİ: Mesaj gönderirken alıcının `users` dokümanındaki sayacı artırır.
  Future<void> send(
    String chatId,
    String fromUid,
    String text, {
    required String otherUid,
  }) async {
    final chatRef = _fs.collection('chats').doc(chatId);
    final msgRef = chatRef.collection('messages').doc();

    final batch = _fs.batch();
    final trimmed = text.trim();
    batch.set(msgRef, {
      'authorId': fromUid,
      'from': fromUid,
      'text': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(chatRef, {
      'participants': FieldValue.arrayUnion([fromUid, otherUid]),
      'lastMessage': trimmed,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageAuthorId': fromUid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    
    // Chat içindeki sayaç
    batch.update(chatRef, {'unreadCounts.$otherUid': FieldValue.increment(1)});
    
    // YENİ: Alıcının global sayacını artır (users/{otherUid}/totalUnreadCount)
    // SetOptions(merge: true) kullanarak doküman yoksa bile oluşturur.
    batch.set(
      _fs.collection('users').doc(otherUid),
      {'totalUnreadCount': FieldValue.increment(1)},
      SetOptions(merge: true),
    );

    await batch.commit();
    unawaited(markMutualLikeSeen(fromUid, otherUid));
  }

  /// OPTİMİZE EDİLDİ: Okundu yaparken global sayaçtan düşer.
  Future<void> markAsRead(String chatId, String uid) async {
    final chatRef = _fs.collection('chats').doc(chatId);
    final userRef = _fs.collection('users').doc(uid);

    // Transaction ile güvenli düşüm yapıyoruz
    await _fs.runTransaction((tx) async {
      final chatSnap = await tx.get(chatRef);
      if (!chatSnap.exists) return;

      final data = chatSnap.data()!;
      final counts = data['unreadCounts'];
      int currentUnread = 0;
      if (counts is Map) {
        currentUnread = (counts[uid] as num?)?.toInt() ?? 0;
      }

      // Eğer okunmamış mesaj varsa düş
      if (currentUnread > 0) {
        tx.update(chatRef, {'unreadCounts.$uid': 0});
        tx.set(
          userRef, 
          {'totalUnreadCount': FieldValue.increment(-currentUnread)},
          SetOptions(merge: true),
        );
      }
    });

    // Son okunma zamanını güncelle (Eski mantık devam ediyor)
    final lastMsgSnap = await chatRef
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    final lastSeenMessageAt = lastMsgSnap.docs.isNotEmpty
        ? (lastMsgSnap.docs.first.data()['createdAt'] as Timestamp?)
        : null;

    final readRef = chatRef.collection('reads').doc(uid);
    final payload = {
      'uid': uid,
      'lastReadAt': FieldValue.serverTimestamp(),
      if (lastSeenMessageAt != null) 'lastSeenMessageAt': lastSeenMessageAt,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await readRef.set(payload, SetOptions(merge: true));
    await chatRef.set({
      'reads': {
        uid: payload,
      },
    }, SetOptions(merge: true));
  }

  Future<void> markMutualLikeSeen(String uidA, String uidB) async {
    // ... (Mevcut kod aynen kalsın) ...
    try {
      final likes = _fs.collection('likes');
      var qs = await likes
          .where('a', isEqualTo: uidA)
          .where('b', isEqualTo: uidB)
          .limit(1)
          .get();
      if (qs.docs.isEmpty) {
        qs = await likes
            .where('a', isEqualTo: uidB)
            .where('b', isEqualTo: uidA)
            .limit(1)
            .get();
      }
      if (qs.docs.isNotEmpty) {
        await qs.docs.first.reference.set({
          'aSeen': true,
          'bSeen': true,
          'lastInteractedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  Stream<int> unreadCountForChat(String chatId, String myUid) {
    // ... (Mevcut kod aynen kalsın) ...
    final chatRef = _fs.collection('chats').doc(chatId);
    return chatRef.snapshots().map((chatSnap) {
      final data = chatSnap.data();
      if (data == null) return 0;
      final counts = data['unreadCounts'];
      if (counts is Map) {
        final v = counts[myUid];
        if (v is num) return v.toInt();
      }
      return 0;
    });
  }

  Stream<int> totalUnreadFor(String myUid) {
    // Bu metod conversation sayısını döndürür, istenirse benzer mantıkla optimize edilebilir
    // ancak şimdilik olduğu gibi bırakıyoruz çünkü genellikle mesaj sayısı (aşağıdaki) kullanılır.
     final q = _fs
        .collection('chats')
        .where('participants', arrayContains: myUid);
    return q.snapshots().map((qs) => qs.docs.length); // Basitleştirildi
  }

  /// OPTİMİZE EDİLDİ: Artık N tane chat yerine tek bir user dokümanını dinliyor.
  Stream<int> totalUnreadMessagesFor(String myUid) {
    return _fs.collection('users').doc(myUid).snapshots().map((snap) {
      final val = (snap.data()?['totalUnreadCount'] as num?)?.toInt() ?? 0;
      // Negatif olursa 0 göster (güvenlik için)
      return math.max(0, val);
    });
  }

  Future<void> startChatNotifications() async {
    await NotificationService.I.start();
  }

  Future<void> stopChatNotifications() async {
    await NotificationService.I.dispose();
  }

  Future<void> deleteIfEmpty(String chatId) async {
    // ... (Mevcut kod aynen kalsın) ...
     try {
      final chatRef = _fs.collection('chats').doc(chatId);
      final msgSnap = await chatRef.collection('messages').limit(1).get();
      if (msgSnap.docs.isEmpty) {
        await chatRef.delete();
      }
    } catch (_) {}
  }
}