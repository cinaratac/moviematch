import 'package:cloud_firestore/cloud_firestore.dart';

class ChatService {
  final _fs = FirebaseFirestore.instance;

  String chatIdFor(String a, String b) {
    final s = [a, b]..sort();
    return '${s[0]}_${s[1]}';
  }

  Future<String> getOrCreateChat(String uidA, String uidB) async {
    final id = chatIdFor(uidA, uidB);
    final ref = _fs.collection('chats').doc(id);
    await ref.set({
      'participants': [uidA, uidB],
      'lastMessageAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return id;
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

  Future<void> send(String chatId, String fromUid, String text) async {
    final chatRef = _fs.collection('chats').doc(chatId);
    final msgRef = chatRef.collection('messages').doc();
    final batch = _fs.batch();
    batch.set(msgRef, {
      'from': fromUid,
      'text': text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(chatRef, {
      'lastMessage': text.trim(),
      'lastMessageAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }
}
