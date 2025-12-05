import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttergirdi/services/notification_service.dart';
import 'dart:math' as math;

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

  /// DÜZELTİLDİ: Grup sohbetlerinde (otherUid boş ise) unreadCounts güncellemesi atlanarak hata önlendi.
  Future<void> send(
    String chatId,
    String fromUid,
    String text, {
    required String otherUid,
    Map<String, dynamic>? movie,
    String? imageUrl,
  }) async {
    final chatRef = _fs.collection('chats').doc(chatId);
    final msgRef = chatRef.collection('messages').doc();

    final batch = _fs.batch();
    final trimmed = text.trim();

    // Temel mesaj verisi
    final Map<String, dynamic> msgData = {
      'authorId': fromUid,
      'from': fromUid,
      'text': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
    };

    // Tip belirleme
    if (movie != null) {
      msgData['type'] = 'movie';
      msgData['movie'] = movie;
    } else if (imageUrl != null) {
      msgData['type'] = 'image';
      msgData['imageUrl'] = imageUrl;
    }

    batch.set(msgRef, msgData);

    // Son mesaj metnini belirle
    String lastMsgText = trimmed;
    if (lastMsgText.isEmpty) {
      if (movie != null) lastMsgText = '🎬 Film paylaştı';
      else if (imageUrl != null) lastMsgText = '📷 Fotoğraf';
    }

    // Chat metadata güncellemesi
    final Map<String, dynamic> chatUpdate = {
      'lastMessage': lastMsgText,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageAuthorId': fromUid,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // --- KRİTİK DÜZELTME ---
    // Eğer otherUid doluysa (Birebir sohbet), katılımcı ve sayaç güncelle.
    // Eğer boşsa (Kulüp/Grup sohbeti), bu alanları güncelleme çünkü '' anahtarı hataya yol açar.
    if (otherUid.isNotEmpty) {
      chatUpdate['participants'] = FieldValue.arrayUnion([fromUid, otherUid]);
      // Nested field update (merge ile çalışır)
      chatUpdate['unreadCounts'] = {otherUid: FieldValue.increment(1)};
    } else {
      // Kulüplerde gönderenin participants içinde olduğundan emin olmak isteyebiliriz
      // ama club_service zaten bunu yönetiyor. Yine de garanti olsun:
      chatUpdate['participants'] = FieldValue.arrayUnion([fromUid]);
    }

    batch.set(chatRef, chatUpdate, SetOptions(merge: true));

    await batch.commit();
    
    // Karşılıklı beğeni "görüldü" işaretlemesi sadece birebir sohbette anlamlıdır
    if (otherUid.isNotEmpty) {
      unawaited(markMutualLikeSeen(fromUid, otherUid));
    }
  }

  Future<void> markAsRead(String chatId, String uid) async {
    final chatRef = _fs.collection('chats').doc(chatId);
    
    // Sayaç sıfırlama
    await chatRef.set({
      'unreadCounts': {uid: 0}
    }, SetOptions(merge: true));

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
    final chatRef = _fs.collection('chats').doc(chatId);
    return chatRef.snapshots().map((chatSnap) {
      final data = chatSnap.data();
      if (data == null) return 0;
      final counts = data['unreadCounts'];
      if (counts is Map) {
        final v = counts[myUid];
        if (v is num && v > 0) return v.toInt();
      }
      return 0;
    });
  }

  Stream<int> totalChatCount(String myUid) {
     final q = _fs
        .collection('chats')
        .where('participants', arrayContains: myUid);
    return q.snapshots().map((qs) => qs.docs.length);
  }

  Stream<int> totalUnreadMessagesFor(String myUid) {
    final q = _fs
        .collection('chats')
        .where('participants', arrayContains: myUid);
        
    return q.snapshots().map((qs) {
      int totalUnread = 0;
      for (final doc in qs.docs) {
        final data = doc.data();
        final counts = data['unreadCounts'];
        if (counts is Map) {
          final v = counts[myUid];
          if (v is num && v > 0) {
             totalUnread += v.toInt();
          }
        }
      }
      return math.max(0, totalUnread);
    });
  }

  Future<void> startChatNotifications() async {
    await NotificationService.I.start();
  }

  Future<void> stopChatNotifications() async {
    await NotificationService.I.dispose();
  }

  Future<void> deleteIfEmpty(String chatId) async {
     try {
      final chatRef = _fs.collection('chats').doc(chatId);
      final msgSnap = await chatRef.collection('messages').limit(1).get();
      if (msgSnap.docs.isEmpty) {
        await chatRef.delete();
      }
    } catch (_) {}
  }
}