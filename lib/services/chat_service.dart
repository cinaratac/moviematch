import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // No heavy work here; ensure Firebase is initialized in your app's main()
}

class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();
  factory ChatService() =>
      instance; // geri uyumluluk: ChatService() kullanan yerler de çalışır
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
      'lastMessageAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return id;
  }

  /// Katılımcılar alanını güvene al (varsa merge eder)
  Future<void> ensureChat(String chatId, String uidA, String uidB) async {
    final ref = _fs.collection('chats').doc(chatId);
    await ref.set({
      'participants': FieldValue.arrayUnion([uidA, uidB]),
      'lastMessageAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> messages(String chatId) {
    return _fs
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
  }

  /// Mesaj gönderirken participants alanını da garantiye alır
  Future<void> send(
    String chatId,
    String fromUid,
    String text, {
    required String otherUid,
  }) async {
    final chatRef = _fs.collection('chats').doc(chatId);
    final msgRef = chatRef.collection('messages').doc();

    final batch = _fs.batch();
    batch.set(msgRef, {
      'authorId': fromUid, // REQUIRED by rules
      'from': fromUid, // optional/back-compat
      'text': text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(chatRef, {
      'participants': FieldValue.arrayUnion([fromUid, otherUid]),
      'lastMessage': text.trim(),
      'lastMessageAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  /// Mark all messages as read for [uid] in this chat.
  /// It writes to `chats/{chatId}/reads/{uid}` with lastReadAt and lastSeenMessageAt
  Future<void> markAsRead(String chatId, String uid) async {
    final chatRef = _fs.collection('chats').doc(chatId);

    // Fetch latest message timestamp efficiently (desc + limit 1)
    final lastMsgSnap = await chatRef
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    final lastSeenMessageAt = lastMsgSnap.docs.isNotEmpty
        ? (lastMsgSnap.docs.first.data()['createdAt'] as Timestamp?)
        : null;

    final readRef = chatRef.collection('reads').doc(uid);

    await readRef.set({
      'uid': uid,
      'lastReadAt': FieldValue.serverTimestamp(),
      if (lastSeenMessageAt != null) 'lastSeenMessageAt': lastSeenMessageAt,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Mirror into chat root for quick list queries (optional aggregate)
    await chatRef.set({
      'reads': {
        uid: {
          'lastReadAt': FieldValue.serverTimestamp(),
          if (lastSeenMessageAt != null) 'lastSeenMessageAt': lastSeenMessageAt,
        },
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Stream the unread message count for a chat **for this user**.
  ///
  /// - Derives `otherUid` from `chats/{chatId}.participants`.
  /// - Reads my `reads/{myUid}.lastReadAt`.
  /// - Counts only messages authored by `otherUid` and newer than my lastReadAt.
  ///
  /// NOTE: We purposely avoid `isNotEqualTo` and multi-field range filters to
  /// dodge composite index prompts during development. We fetch the latest
  /// N messages and filter client-side. Tune the `limit()` as needed.
  Stream<int> unreadCountForChat(String chatId, String myUid) {
    final chatRef = _fs.collection('chats').doc(chatId);

    // 1) Observe chat to extract other participant
    return chatRef.snapshots().asyncExpand((chatSnap) {
      final partsAny = (chatSnap.data()?['participants'] as List?) ?? const [];
      final parts = partsAny.map((e) => e.toString()).toList();
      final otherUid = parts.firstWhere((x) => x != myUid, orElse: () => '');
      if (otherUid.isEmpty) {
        return Stream<int>.value(0);
      }

      // 2) Observe my read marker
      final myReadRef = chatRef.collection('reads').doc(myUid);
      return myReadRef.snapshots().asyncExpand((readSnap) {
        final lastReadAt = (readSnap.data()?['lastReadAt'] as Timestamp?)
            ?.toDate();

        // 3) Observe recent messages and count client-side
        return chatRef
            .collection('messages')
            .orderBy('createdAt', descending: true)
            .limit(200)
            .snapshots()
            .map((qs) {
              int count = 0;
              for (final doc in qs.docs) {
                final data = doc.data();
                final authorId =
                    (data['authorId'] ?? data['from'] ?? '') as String;
                if (authorId != otherUid) continue;
                final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
                if (createdAt == null) continue;
                if (lastReadAt == null || createdAt.isAfter(lastReadAt)) {
                  count++;
                }
              }
              return count;
            });
      });
    });
  }
}
