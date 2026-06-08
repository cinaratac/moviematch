import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/notification_service.dart';
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
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
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
    
    // Sadece son 3 aydaki bildirimleri getir
    final threeMonthsAgo = Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 90)));

    _q = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .collection('notifications')
        .where('createdAt', isGreaterThanOrEqualTo: threeMonthsAgo)
        .orderBy('createdAt', descending: true)
        .limit(100);

    // EKRAN AÇILIR AÇILMAZ TÜMÜNÜ OKUNDU YAP
    NotificationService.I.markAllAsRead(widget.uid);
    // ARKA PLANDA 3 AYDAN ESKİLERİ SİL
    NotificationService.I.deleteOldNotifications(widget.uid);
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
                  Text('Bildirimler', style: Theme.of(context).textTheme.titleMedium),
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
                  final docs = snap.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        'Henüz bildirimin yok.', 
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)
                      )
                    );
                  }

                  // 1. BEĞENİLERİ GRUPLA
                  final List<dynamic> displayItems = [];
                  final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> likeGroups = {};

                  for (var doc in docs) {
                    final data = doc.data();
                    final type = (data['type'] ?? '').toString();
                    final postId = (data['postId'] ?? '').toString();

                    if (type == 'like' && postId.isNotEmpty && postId != '-') {
                      likeGroups.putIfAbsent(postId, () => []).add(doc);
                    } else {
                      displayItems.add(doc);
                    }
                  }

                  likeGroups.forEach((postId, groupDocs) {
                    if (groupDocs.length == 1) {
                      displayItems.add(groupDocs.first);
                    } else {
                      displayItems.add({
                        'isGroupedLike': true,
                        'postId': postId,
                        'docs': groupDocs,
                        'createdAt': groupDocs.first.data()['createdAt'], 
                      });
                    }
                  });

                  // 2. TARİHE GÖRE SIRALA
                  displayItems.sort((a, b) {
                    Timestamp? tA = a is QueryDocumentSnapshot 
                        ? (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp? 
                        : a['createdAt'] as Timestamp?;
                    Timestamp? tB = b is QueryDocumentSnapshot 
                        ? (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp? 
                        : b['createdAt'] as Timestamp?;
                        
                    if (tA == null || tB == null) return 0;
                    return tB.compareTo(tA);
                  });

                  return ListView.separated(
                    controller: controller,
                    itemCount: displayItems.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final item = displayItems[i];

                      // ==========================================
                      // DURUM A: GRUPLANMIŞ ÇOKLU BEĞENİ GÖSTERİMİ
                      // ==========================================
                      if (item is Map && item['isGroupedLike'] == true) {
                        final List<QueryDocumentSnapshot<Map<String, dynamic>>> groupDocs = item['docs'];
                        final firstData = groupDocs[0].data();
                        final secondData = groupDocs[1].data(); 
                        
                        final createdAt = firstData['createdAt'] as Timestamp?;
                        final timeLabel = createdAt != null ? _timeAgoShort(createdAt.toDate()) : '';
                        final othersCount = groupDocs.length - 1;

                        // İki kişinin de bilgilerini aynı anda çekiyoruz
                        return FutureBuilder<List<_Actor>>(
                          future: Future.wait([
                            _getActor((firstData['actorId'] ?? '').toString(), firstData),
                            _getActor((secondData['actorId'] ?? '').toString(), secondData),
                          ]),
                          builder: (context, snap) {
                            final actor1 = snap.data?.isNotEmpty == true ? snap.data![0] : null;
                            final actor2 = snap.data?.length == 2 ? snap.data![1] : null;
                            final name = actor1?.handle ?? actor1?.displayName ?? 'Bir kullanıcı';
                            
                            return ListTile(
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: item['postId'])));
                              },
                              // INSTAGRAM STİLİ ÜST ÜSTE BİNEN AVATARLAR
                              leading: SizedBox(
                                width: 52,
                                height: 42,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    // Arkadaki kişi (İkinci)
                                    Positioned(
                                      right: 0,
                                      top: 4,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2.5),
                                        ),
                                        child: _Avatar(url: actor2?.photoURL, radius: 15),
                                      ),
                                    ),
                                    // Öndeki kişi (Birinci)
                                    Positioned(
                                      left: 0,
                                      top: 0,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2.5),
                                        ),
                                        child: _Avatar(url: actor1?.photoURL, radius: 18),
                                      ),
                                    ),
                                    // Kalp ikonu
                                    Positioned(
                                      bottom: -4,
                                      right: -4,
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).scaffoldBackgroundColor,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.favorite, size: 12, color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              title: Text(
                                '$name ve $othersCount diğer kişi',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              subtitle: const Text('gönderini beğendi'),
                              trailing: Text(timeLabel, style: Theme.of(context).textTheme.labelSmall),
                            );
                          },
                        );
                      }

                      // ==========================================
                      // DURUM B: TEKİL BİLDİRİM (1 KİŞİ) GÖSTERİMİ
                      // ==========================================
                      final doc = item as QueryDocumentSnapshot<Map<String, dynamic>>;
                      final m = doc.data();
                      final type = (m['type'] ?? '').toString();
                      final actorId = (m['actorId'] ?? '').toString();
                      final count = (m['count'] as num?)?.toInt() ?? 1;
                      final createdAt = m['createdAt'] as Timestamp?;
                      final read = (m['read'] ?? false) == true;

                      final timeLabel = createdAt != null ? _timeAgoShort(createdAt.toDate()) : '';
                      final title = _titleFor(type);
                      final subtitle = _subtitleFor(type, count);

                      return FutureBuilder<_Actor>(
                        future: _getActor(actorId, m),
                        builder: (context, actorSnap) {
                          final actor = actorSnap.data;

                          // PROFİLE GİTME FONKSİYONU
                          void goToProfile() {
                            if (actorId.isNotEmpty) {
                              Navigator.pop(context);
                              Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: actorId)));
                            }
                          }

                          // İÇERİĞE GİTME FONKSİYONU
                          void goToContent() {
                            final postId = (m['postId'] ?? '').toString();
                            if (type == 'follow') {
                              goToProfile();
                            } else if ((type == 'like' || type == 'comment') && postId.isNotEmpty && postId != '-') {
                              Navigator.pop(context);
                              Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: postId)));
                            } else if (type == 'club_request') {
                              final clubId = (m['clubId'] ?? '').toString();
                              final clubName = (m['clubName'] ?? '').toString();
                              if (clubId.isNotEmpty) {
                                Navigator.pop(context);
                                Navigator.push(context, MaterialPageRoute(builder: (_) => ChatRoomScreen(
                                  chatId: clubId, otherUid: '', otherTitle: clubName, isGroup: true, groupName: clubName,
                                )));
                              }
                            }
                          }

                          return ListTile(
                            onTap: () {
                              doc.reference.update({'read': true});
                              goToContent(); // Tile boşluğuna basınca İçeriğe git
                            },
                            // SADECE RESME BASINCA PROFİLE GİT
                            leading: GestureDetector(
                              onTap: goToProfile,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  _Avatar(url: actor?.photoURL, radius: 20),
                                  if (type == 'like')
                                    Positioned(
                                      bottom: -4,
                                      right: -4,
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).scaffoldBackgroundColor, 
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.favorite, size: 12, color: Colors.red),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // SADECE İSME BASINCA PROFİLE GİT
                            title: GestureDetector(
                              onTap: goToProfile,
                              child: Text(
                                actor?.displayName ?? title, 
                                maxLines: 1, 
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600), // Tıklanabilir hissi verir
                              ),
                            ),
                            subtitle: Text('${actor?.handle ?? actor?.displayName ?? 'Kullanıcı'} $subtitle', maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(timeLabel, style: Theme.of(context).textTheme.labelSmall),
                                const SizedBox(height: 4),
                                if (!read) Container(width: 8, height: 8, decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle)),
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
      case 'like': return 'Yeni beğeni';
      case 'comment': return 'Yeni yorum';
      case 'follow': return 'Yeni takipçi';
      case 'club_request': return 'Kulüp İsteği';
      default: return 'Bildirim';
    }
  }

  String _subtitleFor(String type, int count) {
    final suffix = count > 1 ? ' ve ${count - 1} diğer kişi' : '';
    switch (type) {
      case 'like': return '$suffix gönderinizi beğendi';
      case 'comment': return '$suffix gönderinize yorum yaptı';
      case 'follow': return 'sizi takip etmeye başladı';
      case 'club_request': return 'kulübünüze katılmak istiyor';
      default: return 'bir etkinlikte bulundu';
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
      final u = await FirebaseFirestore.instance.collection('users').doc(uid).get();
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
  const _Actor({required this.uid, this.displayName, this.handle, this.photoURL});
}

// Avatar widgetı boyutlandırma desteği ile güncellendi
class _Avatar extends StatelessWidget {
  final String? url;
  final double radius;
  const _Avatar({this.url, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    if (url != null && url!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: url!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(color: Colors.grey.shade200, width: size, height: size, child: Icon(Icons.person, color: Colors.grey, size: radius)),
          errorWidget: (context, url, error) => Container(color: Colors.grey.shade200, width: size, height: size, child: Icon(Icons.person, color: Colors.grey, size: radius)),
        ),
      );
    }
    return CircleAvatar(radius: radius, child: Icon(Icons.person, size: radius));
  }
}

String _timeAgoShort(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);

  if (diff.inSeconds < 60) return '${diff.inSeconds}s';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}g';
  if (diff.inDays < 30) return '${diff.inDays ~/ 7}hf'; 
  if (diff.inDays < 365) return '${diff.inDays ~/ 30}a';
  return '${diff.inDays ~/ 365}y';
}