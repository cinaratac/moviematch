import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/services/chat_service.dart';

class ChatRoomScreen extends StatefulWidget {
  final String chatId;
  final String otherUid;
  final String?
  otherTitle; // optional pre-resolved title (username/displayName)

  const ChatRoomScreen({
    super.key,
    required this.chatId,
    required this.otherUid,
    this.otherTitle,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _svc = ChatService();
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    // Katılımcılar alanını garantiye al (kalıcılık için kritik)
    _svc.ensureChat(widget.chatId, myUid, widget.otherUid);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final txt = _ctrl.text.trim();
    if (txt.isEmpty) return;
    try {
      final myUid = FirebaseAuth.instance.currentUser!.uid;
      _ctrl.clear();
      await _svc.send(widget.chatId, myUid, txt, otherUid: widget.otherUid);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gönderilemedi: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: _ChatAppBarTitle(
          chatId: widget.chatId,
          otherUid: widget.otherUid,
          initialTitle: widget.otherTitle,
        ),
      ),
      body: Column(
        children: [
          // Mesajlar
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('createdAt', descending: true)
                  .limit(200)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('Henüz mesaj yok.'));
                }
                return ListView.builder(
                  reverse: true,
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final m = docs[i].data();
                    final mine = m['from'] == myUid;
                    final text = (m['text'] ?? '') as String;
                    final ts = (m['createdAt'] as Timestamp?);
                    final dt = ts?.toDate();

                    return Align(
                      alignment: mine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: mine
                                ? Colors.blueAccent
                                : Colors.grey.shade800,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(12),
                              topRight: const Radius.circular(12),
                              bottomLeft: Radius.circular(
                                mine ? 12 : 4,
                              ), // kuyruk
                              bottomRight: Radius.circular(
                                mine ? 4 : 12,
                              ), // kuyruk
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: mine
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              Text(
                                text,
                                style: const TextStyle(color: Colors.white),
                              ),
                              if (dt != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _formatTime(dt),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Girdi alanı
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 6.0,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Mesaj yaz…',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(onPressed: _send, icon: const Icon(Icons.send)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatAppBarTitle extends StatelessWidget {
  final String chatId;
  final String otherUid;
  final String? initialTitle;
  const _ChatAppBarTitle({
    required this.chatId,
    required this.otherUid,
    this.initialTitle,
  });

  @override
  Widget build(BuildContext context) {
    // Eğer dışarıdan başlık (username) verildiyse direkt onu göster (UID flaşlamaz)
    if (initialTitle != null && initialTitle!.isNotEmpty) {
      return Text(initialTitle!, overflow: TextOverflow.ellipsis);
    }

    // Öncelik: chats/{chatId}.participantsMeta[otherUid]
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .snapshots(),
      builder: (context, snap) {
        Map<String, dynamic>? meta;
        if (snap.hasData && snap.data!.exists) {
          final d = snap.data!.data()!;
          final m = d['participantsMeta'];
          if (m is Map) {
            final m2 = Map<String, dynamic>.from(m);
            if (m2.containsKey(otherUid) && m2[otherUid] is Map) {
              meta = Map<String, dynamic>.from(m2[otherUid] as Map);
            }
          }
        }

        if (meta != null) {
          final username = (meta['username'] ?? '') as String;
          final displayName = (meta['displayName'] ?? '') as String;
          final lb = (meta['lb'] ?? meta['letterboxdUsername'] ?? '') as String;
          final title = username.isNotEmpty
              ? username
              : (displayName.isNotEmpty
                    ? displayName
                    : (lb.isNotEmpty ? '@$lb' : ''));
          if (title.isNotEmpty) {
            return Text(title, overflow: TextOverflow.ellipsis);
          }
        }

        // Fallback (bir defa): matches/{chatId} içinden doldurup chats'e persist et
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection('matches')
              .doc(chatId)
              .get(),
          builder: (context, mSnap) {
            String title = '';
            if (mSnap.hasData && mSnap.data!.exists) {
              final md = mSnap.data!.data()!;
              final aP = md['aProfile'] as Map<String, dynamic>?;
              final bP = md['bProfile'] as Map<String, dynamic>?;
              Map<String, dynamic>? otherP;
              if (aP != null && aP['uid'] == otherUid) otherP = aP;
              if (bP != null && bP['uid'] == otherUid) otherP = bP;
              if (otherP != null) {
                final username = (otherP['username'] ?? '') as String;
                final disp = (otherP['displayName'] ?? '') as String;
                final lb =
                    (otherP['lb'] ?? otherP['letterboxdUsername'] ?? '')
                        as String;
                title = username.isNotEmpty
                    ? username
                    : (disp.isNotEmpty ? disp : (lb.isNotEmpty ? '@$lb' : ''));

                FirebaseFirestore.instance.collection('chats').doc(chatId).set({
                  'participantsMeta': {
                    otherUid: {
                      'uid': otherUid,
                      'username': username,
                      'displayName': disp,
                      'lb': lb,
                    },
                  },
                }, SetOptions(merge: true));
              }
            }
            return Text(
              title.isNotEmpty ? title : '',
              overflow: TextOverflow.ellipsis,
            );
          },
        );
      },
    );
  }
}

String _formatTime(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final thatDay = DateTime(dt.year, dt.month, dt.day);
  if (thatDay == today) {
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
  return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}';
}
