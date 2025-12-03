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

  /// OPTİMİZE EDİLDİ: Mesaj gönderirken alıcının `users` dokümanındaki global sayacı artırma işlemi kaldırıldı (Hot Spot optimizasyonu).
  /// (imageUrl parametresi kaldırıldı, orijinal haline döndü)
  /// OPTİMİZE EDİLDİ: Mesaj gönderirken alıcının `users` dokümanındaki sayacı artırır.
  /// YENİ: 'movie' parametresi eklendi.
  Future<void> send(
    String chatId,
    String fromUid,
    String text, {
    required String otherUid,
    Map<String, dynamic>? movie, // <-- YENİ PARAMETRE
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

    // Eğer film verisi varsa, tipini 'movie' yap ve veriyi ekle
    if (movie != null) {
      msgData['type'] = 'movie';
      msgData['movie'] = movie;
    }

    batch.set(msgRef, msgData);

    batch.set(chatRef, {
      'participants': FieldValue.arrayUnion([fromUid, otherUid]),
      'lastMessage': trimmed.isEmpty && movie != null ? '🎬 Film paylaştı' : trimmed,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageAuthorId': fromUid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    
    // Chat içindeki sayaç
    batch.update(chatRef, {'unreadCounts.$otherUid': FieldValue.increment(1)});
    
    // !!! HOT SPOT OPTİMİZASYONU: ALICININ GLOBAL SAYACINI ARTIRMA İŞLEMİ KALDIRILDI

    await batch.commit();
    unawaited(markMutualLikeSeen(fromUid, otherUid));
  }

  /// OPTİMİZE EDİLDİ: Global sayaç (Hot Spot) güncelleme transaction'ı kaldırıldı.
  Future<void> markAsRead(String chatId, String uid) async {
    final chatRef = _fs.collection('chats').doc(chatId);
    // final userRef = _fs.collection('users').doc(uid); // Artık kullanılmıyor

    // Önce chat içi sayacı temizle (Hot Spot transaction'ı kaldırıldı, bu direkt update yeterli)
    await chatRef.update({'unreadCounts.$uid': 0});

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

  /// DÜZELTME: Bu fonksiyon sadece kullanıcının bulunduğu sohbet sayısını döndürdüğü için adı değiştirildi.
  Stream<int> totalChatCount(String myUid) {
     final q = _fs
        .collection('chats')
        .where('participants', arrayContains: myUid);
    return q.snapshots().map((qs) => qs.docs.length);
  }

  /// YENİ OPTİMİZASYON: Hot Spot'u (totalUnreadCount) kaldırdığımız için,
  /// toplam okunmamış mesaj sayısını tüm ilgili sohbet dokümanlarını okuyarak hesaplar.
  Stream<int> totalUnreadMessagesFor(String myUid) {
    // DÜZELTME: Sadece participants filtresi kullanıyoruz.
    // 'unreadCounts.$myUid' filtresini BURADAN SİLMELİSİNİZ.
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