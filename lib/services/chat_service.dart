import 'package:firebase_messaging/firebase_messaging.dart';
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
    }, SetOptions(merge: true));
    return id;
  }

  /// Katılımcılar alanını güvene al (varsa merge eder)
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

  // Live latest N messages (descending). Use with ListView(reverse: true).
  Stream<QuerySnapshot<Map<String, dynamic>>> latestMessagesStream(
    String chatId, {
    int limitCount = 30,
  }) {
    return _fs
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(limitCount)
        .snapshots();
  }

  // One-shot fetch for the next (older) page, starting after a document.
  Future<QuerySnapshot<Map<String, dynamic>>> fetchOlderMessagesPage(
    String chatId, {
    required DocumentSnapshot<Map<String, dynamic>> startAfterDoc,
    int pageSize = 30,
  }) {
    return _fs
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .startAfterDocument(startAfterDoc)
        .limit(pageSize)
        .get();
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
    final trimmed = text.trim();
    batch.set(msgRef, {
      'authorId': fromUid, // REQUIRED by rules
      'from': fromUid, // optional/back-compat
      'text': trimmed,
      'message': trimmed, // for UIs reading `message`
      'content': trimmed, // for UIs reading `content`
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(chatRef, {
      'participants': FieldValue.arrayUnion([fromUid, otherUid]),
      'lastMessage': trimmed,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageAuthorId': fromUid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    // Use dotted-path update so Firestore reliably increments nested counters
    batch.update(chatRef, {'unreadCounts.$otherUid': FieldValue.increment(1)});
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
    await chatRef.update({'unreadCounts.$uid': 0});
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

  /// Total unread conversations count for a user.
  /// Counts chats where the last message is newer than my lastReadAt and
  /// authored by someone else.
  Stream<int> totalUnreadFor(String myUid) {
    final q = _fs
        .collection('chats')
        .where('participants', arrayContains: myUid);

    return q.snapshots().map((qs) {
      int unread = 0;
      for (final d in qs.docs) {
        final data = d.data();
        final lastAuthor =
            (data['lastMessageAuthorId'] ?? data['lastAuthorId'] ?? '')
                as String?;
        final lastTs = data['lastMessageAt'] as Timestamp?;
        final reads = (data['reads'] as Map<String, dynamic>?) ?? const {};
        final mine = (reads[myUid] as Map<String, dynamic>?) ?? const {};
        final lastRead = mine['lastReadAt'] as Timestamp?;

        if (lastTs == null) continue;
        if (lastAuthor == myUid) continue; // my own last message → not unread
        if (lastRead == null || lastTs.toDate().isAfter(lastRead.toDate())) {
          unread++;
        }
      }
      return unread;
    });
  }

  /// Total unread **messages** for this user across all chats.
  Stream<int> totalUnreadMessagesFor(String myUid) {
    final q = _fs
        .collection('chats')
        .where('participants', arrayContains: myUid);
    return q.snapshots().map((qs) {
      int total = 0;
      for (final d in qs.docs) {
        final data = d.data();
        final counts = data['unreadCounts'];
        if (counts is Map) {
          final v = counts[myUid];
          if (v is num) {
            total += v.toInt();
          }
        }
      }
      return total;
    });
  }
}
