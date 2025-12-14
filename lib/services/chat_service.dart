import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/services/notification_service.dart';

class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();
  factory ChatService() => instance;
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String chatIdFor(String a, String b) {
    final s = [a, b]..sort();
    return '${s[0]}_${s[1]}';
  }

  // GÜNCELLENDİ: Sohbet oluştururken veya açarken isimleri/resimleri de kaydediyoruz (Denormalizasyon)
  Future<String> getOrCreateChat(String uidA, String uidB) async {
    final id = chatIdFor(uidA, uidB);
    final chatRef = _fs.collection('chats').doc(id);

    final chatSnap = await chatRef.get();
    if (!chatSnap.exists) {
      // Kullanıcı bilgilerini çekip sohbet dokümanına gömüyoruz
      final userA = await _fs.collection('users').doc(uidA).get();
      final userB = await _fs.collection('users').doc(uidB).get();
      
      final dataA = userA.data() ?? {};
      final dataB = userB.data() ?? {};

      await chatRef.set({
        'participants': FieldValue.arrayUnion([uidA, uidB]),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        // Denormalize Veri:
        'titles': {
          uidA: dataB['displayName'] ?? dataB['username'] ?? 'Kullanıcı', // A, B'yi ne diye görecek?
          uidB: dataA['displayName'] ?? dataA['username'] ?? 'Kullanıcı', // B, A'yı ne diye görecek?
        },
        'photos': {
          uidA: dataB['photoURL'] ?? '', // A, B'nin hangi fotosunu görecek?
          uidB: dataA['photoURL'] ?? '', // B, A'nın hangi fotosunu görecek?
        }
      }, SetOptions(merge: true));
    }
    return id;
  }

  String getChatId(String uidA, String uidB) {
    return chatIdFor(uidA, uidB);
  }
  
  // GÜNCELLENDİ: Mesaj atarken de güncel profil bilgilerini basıyoruz
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

    // 1. Mesaj Verisi
    final Map<String, dynamic> msgData = {
      'authorId': fromUid,
      'from': fromUid,
      'text': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
    };

    if (movie != null) {
      msgData['type'] = 'movie';
      msgData['movie'] = movie;
    } else if (imageUrl != null) {
      msgData['type'] = 'image';
      msgData['imageUrl'] = imageUrl;
    }

    batch.set(msgRef, msgData);

    // 2. Sohbet Verisi (Merge true olduğu için yoksa yaratır, varsa günceller)
    String lastMsgText = trimmed;
    if (lastMsgText.isEmpty) {
      if (movie != null) lastMsgText = '🎬 Film paylaştı';
      else if (imageUrl != null) lastMsgText = '📷 Fotoğraf';
    }

    final me = _auth.currentUser;
    
    final Map<String, dynamic> chatUpdate = {
      'lastMessage': lastMsgText,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageAuthorId': fromUid,
      'updatedAt': FieldValue.serverTimestamp(),
      'participants': FieldValue.arrayUnion([fromUid, otherUid]), // Garanti olsun
    };

    if (otherUid.isNotEmpty) {
      chatUpdate['unreadCounts'] = {otherUid: FieldValue.increment(1)};
      
      // İlk mesajda karşı tarafın listesinde düzgün görünmek için:
      if (me != null) {
        chatUpdate['titles.$otherUid'] = me.displayName ?? 'Kullanıcı';
        chatUpdate['photos.$otherUid'] = me.photoURL ?? '';
      }
    }

    // SetOptions(merge: true) sayesinde döküman yoksa oluşturulur!
    batch.set(chatRef, chatUpdate, SetOptions(merge: true));
    await batch.commit();
    
    if (otherUid.isNotEmpty) {
      try {
        final likes = _fs.collection('likes');
        var qs = await likes.where('a', isEqualTo: fromUid).where('b', isEqualTo: otherUid).limit(1).get();
        if (qs.docs.isEmpty) qs = await likes.where('a', isEqualTo: otherUid).where('b', isEqualTo: fromUid).limit(1).get();
        if (qs.docs.isNotEmpty) {
          await qs.docs.first.reference.set({
            'aSeen': true, 'bSeen': true, 'lastInteractedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (_) {}
    }
  }

  Future<void> markAsRead(String chatId, String uid) async {
    final chatRef = _fs.collection('chats').doc(chatId);
    await chatRef.set({'unreadCounts': {uid: 0}}, SetOptions(merge: true));
    
    // Okundu bilgisini güncelle...
    final readRef = chatRef.collection('reads').doc(uid);
    await readRef.set({'uid': uid, 'lastReadAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  Stream<int> unreadCountForChat(String chatId, String myUid) {
    return _fs.collection('chats').doc(chatId).snapshots().map((chatSnap) {
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

  // --- KRİTİK OPTİMİZASYON ---
  // Eskiden tüm sohbetleri dinliyordu. Şimdi sadece kullanıcının kendi profilindeki tek bir alanı dinliyor.
  // Bu alan Cloud Functions tarafından güncelleniyor.
  Stream<int> totalUnreadMessagesFor(String myUid) {
    return _fs.collection('users').doc(myUid).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) return 0;
      return (data['totalUnreadCount'] as num?)?.toInt() ?? 0;
    });
  }
  // ---------------------------

  Future<void> startChatNotifications() async {
    await NotificationService.I.start();
  }

  Future<void> stopChatNotifications() async {
    await NotificationService.I.dispose();
  }
  
  Future<void> deleteIfEmpty(String chatId) async {
    // Boş temizleme mantığı aynen kalabilir
     try {
      final chatRef = _fs.collection('chats').doc(chatId);
      final msgSnap = await chatRef.collection('messages').limit(1).get();
      if (msgSnap.docs.isEmpty) {
        await chatRef.delete();
      }
    } catch (_) {}
  }
}