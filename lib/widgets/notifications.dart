import 'package:cached_network_image/cached_network_image.dart'; // EKLENDİ
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/post_detail_screen.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart'; 
import 'package:fluttergirdi/screens/chat_room_screen.dart';
/// AppBar içinde kullan: NotificationsButton()
class NotificationsButton extends StatelessWidget {
  const NotificationsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final cs = Theme.of(context).colorScheme;
    if (uid == null) {
      return IconButton(
        icon: const Icon(Icons.notifications_none),
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bildirimler için giriş yapmalısın.')),
          );
        },
      );
    }

    final q = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(20);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        final unread = snap.data?.docs.length ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Bildirimler',
              icon: const Icon(Icons.notifications_none),
              onPressed: () => _openSheet(context, uid),
            ),
            if (unread > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cs.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    unread > 9 ? '9+' : unread.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _openSheet(BuildContext context, String uid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _NotificationsSheet(uid: uid),
    );
  }
}

class _NotificationsSheet extends StatefulWidget {
  final String uid;
  const _NotificationsSheet({required this.uid});

  @override
  State<_NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<_NotificationsSheet> {
  late final Query<Map<String, dynamic>> _q;

  @override
  void initState() {
    super.initState();
    _q = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(100);
    
   
   
  }



  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.6,
      maxChildSize: 0.98,
      builder: (context, controller) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Text(
                    'Bildirimler',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                 
                  IconButton(
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _q.snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snap.data?.docs ?? const [];
                  if (docs.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Henüz bildirimin yok.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    controller: controller,
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final m = docs[i].data();
                      final type = (m['type'] ?? '').toString();
                      final actorId = (m['actorId'] ?? '').toString();
                      final count = (m['count'] as num?)?.toInt() ?? 1;
                      final createdAt = (m['createdAt'] as Timestamp?);
                      final read = (m['read'] ?? false) == true;

                      final timeLabel = createdAt == null
                          ? ''
                          : _timeAgoShort(createdAt.toDate());

                      final title = _titleFor(type);
                     final subtitle = _subtitleFor(type, count);

                      return FutureBuilder<_Actor>(
                        future: _getActor(actorId, m),
                        builder: (context, actorSnap) {
                          final actor = actorSnap.data;
                          return ListTile(
                            onTap: () {
                              final navigator = Navigator.of(context);
                              
                              // 1. Okundu işaretle (await etmeye gerek yok, UI takılmasın)
                              docs[i].reference.update({'read': true});
                              
                              // 2. Bildirim tipine göre yönlendirme yap
                              final postId = (m['postId'] ?? '').toString();

                              if (type == 'follow') {
                                // Takip bildirimiyse profile git
                                if (actorId.isNotEmpty) {
                                  // Önce bildirim penceresini kapat, sonra git
                                  navigator.pop(); 
                                  navigator.push(
                                    MaterialPageRoute(
                                      builder: (_) => PublicProfileScreen(uid: actorId),
                                    ),
                                  );
                                }
                              } else if ((type == 'like' || type == 'comment') && postId.isNotEmpty && postId != '-') {
                                // Like veya Yorum ise GÖNDERİYE git
                                // Önce bildirim penceresini kapat, sonra git
                                navigator.pop();
                                navigator.push(
                                  MaterialPageRoute(
                                    builder: (_) => PostDetailScreen(postId: postId),
                                  ),
                                );
                              }
                              else if (type == 'club_request') {
                                // KULÜP İSTEĞİNE TIKLANINCA
                                final clubId = (m['clubId'] ?? '').toString();
                                final clubName = (m['clubName'] ?? '').toString();
                                
                                if (clubId.isNotEmpty) {
                                  navigator.pop(); // Bildirim sayfasını kapat
                                  navigator.push(
                                    MaterialPageRoute(
                                      builder: (_) => ChatRoomScreen(
                                        chatId: clubId,
                                        otherUid: '', // Grup olduğu için boş
                                        otherTitle: clubName,
                                        isGroup: true,
                                        groupName: clubName,
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            leading: _Avatar(url: actor?.photoURL),
                            title: Text(
                              actor?.displayName ?? title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: read
                                  ? null
                                  : Theme.of(context).textTheme.titleMedium,
                            ),
                            subtitle: Text(
                              '${actor?.handle ?? actor?.displayName ?? 'Kullanıcı'} $subtitle',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  timeLabel,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                const SizedBox(height: 4),
                                if (!read)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: cs.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  String _titleFor(String type) {
    switch (type) {
      case 'like':
        return 'Yeni beğeni';
      case 'comment':
        return 'Yeni yorum';
      case 'follow':
        return 'Yeni takipçi';
      case 'club_request': return 'Kulüp İsteği';
      default:
        return 'Bildirim';
    }
  }

  String _subtitleFor(String type, int count) {
    // Eğer sayı 1'den büyükse özel mesaj döndür
    final suffix = count > 1 ? ' ve ${count - 1} diğer kişi' : '';

    switch (type) {
      case 'like':
        return '$suffix gönderinizi beğendi';
      case 'comment':
        return '$suffix gönderinize yorum yaptı';
      case 'follow':
        return 'sizi takip etmeye başladı';
      case 'club_request': 
        return 'kulübünüze katılmak istiyor';
      default:
        return 'bir etkinlikte bulundu';
    }
  }

  Future<_Actor> _getActor(String uid, Map<String, dynamic> notif) async {
    final cachedName = (notif['actorName'] ?? '').toString();
    final cachedHandle = (notif['actorHandle'] ?? '').toString();
    final cachedPhoto = (notif['actorPhotoURL'] ?? '').toString();
    
    if (cachedName.isNotEmpty || cachedPhoto.isNotEmpty || cachedHandle.isNotEmpty) {
      return _Actor(
        uid: uid,
        displayName: cachedName.isNotEmpty ? cachedName : null,
        handle: cachedHandle.isNotEmpty ? cachedHandle : null,
        photoURL: cachedPhoto.isNotEmpty ? cachedPhoto : null,
      );
    }

    if (uid.isEmpty) return _Actor(uid: uid);
    try {
      final u = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (u.exists) {
        final m = u.data() ?? {};
        return _Actor(
          uid: uid,
          displayName: (m['displayName'] ?? m['name'] ?? '').toString(),
          handle: (m['handle'] ?? m['letterboxdUsername'] ?? '').toString(),
          photoURL: (m['photoURL'] ?? '').toString(),
        );
      }
    } catch (_) {}
    return _Actor(uid: uid);
  }
}

class _Actor {
  final String uid;
  final String? displayName;
  final String? handle;
  final String? photoURL;
  const _Actor({
    required this.uid,
    this.displayName,
    this.handle,
    this.photoURL,
  });
}

class _Avatar extends StatelessWidget {
  final String? url;
  const _Avatar({this.url});

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: url!,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            color: Colors.grey.shade200,
            child: const Icon(Icons.person, color: Colors.grey),
          ),
          errorWidget: (context, url, error) => Container(
            color: Colors.grey.shade200,
            child: const Icon(Icons.person, color: Colors.grey),
          ),
        ),
      );
    }
    return const CircleAvatar(radius: 20, child: Icon(Icons.person));
  }
}

String _timeAgoShort(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inSeconds < 60) return '${diff.inSeconds}s';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}g';
  final months = diff.inDays ~/ 30;
  if (months < 12) return '${months}a';
  final years = diff.inDays ~/ 365;
  return '${years}y';
}