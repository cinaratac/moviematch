import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import 'package:fluttergirdi/screens/post_detail_screen.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:fluttergirdi/screens/chat_room_screen.dart';

// --- YENİ EKLENEN: Merkezi Önbellek Servisi ---
import '../services/user_cache_service.dart';

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
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _notificationsStream;

  // NOT: Özel _actorCache tamamen silindi. Artık UserCacheService kullanıyoruz.

  @override
  void initState() {
    super.initState();
    final threeMonthsAgo = Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 90)));

    _q = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .collection('notifications')
        .where('createdAt', isGreaterThanOrEqualTo: threeMonthsAgo)
        .orderBy('createdAt', descending: true)
        .limit(100);

    _notificationsStream = _q.snapshots();

    NotificationService.I.markAllAsRead(widget.uid);
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
                stream: _notificationsStream,
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

                  // --- MERKEZİ CACHE KULLANIMI: Eksik kullanıcıları toplu olarak arka planda çek ---
                  final Set<String> actorIds = {};
                  for (var doc in docs) {
                    final aId = doc.data()['actorId'];
                    if (aId != null && aId.toString().isNotEmpty) {
                      actorIds.add(aId.toString());
                    }
                  }
                  final missingIds = actorIds.where((id) => UserCacheService.instance.getFromCache(id) == null).toList();
                  if (missingIds.isNotEmpty) {
                    Future.microtask(() async {
                      await UserCacheService.instance.fetchUsers(missingIds);
                      if (mounted) setState(() {}); // Veriler geldiğinde ekranı pürüzsüz yenile
                    });
                  }
                  // ----------------------------------------------------------------------------------

                  // BEĞENİLERİ GRUPLA
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
                      });
                    }
                  });

                  // TARİHE GÖRE SIRALA
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

                      if (item is Map && item['isGroupedLike'] == true) {
                        return _GroupedNotificationTile(
                          postId: item['postId'],
                          docs: item['docs'],
                        );
                      } else {
                        return _SingleNotificationTile(
                          doc: item as QueryDocumentSnapshot<Map<String, dynamic>>,
                        );
                      }
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
}

// ============================================================================
// 1. TEKİL BİLDİRİM KARTI (SIFIR YANIP SÖNME GARANTİLİ)
// ============================================================================
class _SingleNotificationTile extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _SingleNotificationTile({required this.doc});

  @override
  State<_SingleNotificationTile> createState() => _SingleNotificationTileState();
}

class _SingleNotificationTileState extends State<_SingleNotificationTile> {
  CachedUser? actor;

  @override
  void initState() {
    super.initState();
    _loadActor();
  }

  void _loadActor() async {
    final m = widget.doc.data();
    final actorId = (m['actorId'] ?? '').toString();
    
    if (actorId.isEmpty) return;

    // 1. ADIM: Daha önce yüklendiyse direkt RAM'den al
    final cached = UserCacheService.instance.getFromCache(actorId);
    if (cached != null) {
      if (mounted) setState(() => actor = cached);
      return; 
    }

    // 2. ADIM: Hafızada yoksa, bildirimin içindeki eski/yedek veriyi ekrana bas (Fallback)
    final fallback = CachedUser(
      uid: actorId,
      displayName: (m['actorName'] ?? '').toString(),
      handle: (m['actorHandle'] ?? '').toString(),
      photoURL: (m['actorPhotoURL'] ?? '').toString(),
    );
    if (mounted) setState(() => actor = fallback);

    // 3. ADIM: Merkezi servisten en güncelini bekle
    final fetched = await UserCacheService.instance.getUser(actorId);
    if (fetched != null && mounted) {
      setState(() => actor = fetched);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final m = widget.doc.data();
    final type = (m['type'] ?? '').toString();
    final actorId = (m['actorId'] ?? '').toString();
    final count = (m['count'] as num?)?.toInt() ?? 1;
    final createdAt = m['createdAt'] as Timestamp?;
    final read = (m['read'] ?? false) == true;

    final timeLabel = createdAt != null ? _timeAgoShort(createdAt.toDate()) : '';
    final title = _titleFor(type);
    final subtitle = _subtitleFor(type, count);

    void goToProfile() {
      if (actorId.isNotEmpty) {
        Navigator.pop(context);
        Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: actorId)));
      }
    }

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

    final displayName = actor?.displayName.isNotEmpty == true ? actor!.displayName : title;
    final handle = actor?.handle.isNotEmpty == true ? actor!.handle : (actor?.displayName.isNotEmpty == true ? actor!.displayName : 'Kullanıcı');

    return ListTile(
      onTap: () {
        widget.doc.reference.update({'read': true});
        goToContent(); 
      },
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
      title: GestureDetector(
        onTap: goToProfile,
        child: Text(
          displayName, 
          maxLines: 1, 
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600), 
        ),
      ),
      subtitle: Text('$handle $subtitle', maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(timeLabel, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          if (!read) Container(width: 8, height: 8, decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle)),
        ],
      ),
    );
  }
}

// ============================================================================
// 2. ÇOKLU (GRUPLANMIŞ) BİLDİRİM KARTI
// ============================================================================
class _GroupedNotificationTile extends StatefulWidget {
  final String postId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  
  const _GroupedNotificationTile({required this.postId, required this.docs});

  @override
  State<_GroupedNotificationTile> createState() => _GroupedNotificationTileState();
}

class _GroupedNotificationTileState extends State<_GroupedNotificationTile> {
  CachedUser? actor1;
  CachedUser? actor2;

  @override
  void initState() {
    super.initState();
    _loadActors();
  }

  void _loadActors() async {
    final firstData = widget.docs[0].data();
    final secondData = widget.docs[1].data();
    
    final id1 = (firstData['actorId'] ?? '').toString();
    final id2 = (secondData['actorId'] ?? '').toString();

    actor1 = await _resolveActor(id1, firstData);
    actor2 = await _resolveActor(id2, secondData);
    
    if (mounted) setState(() {});
  }

  Future<CachedUser> _resolveActor(String actorId, Map<String, dynamic> m) async {
    if (actorId.isEmpty) return CachedUser(uid: '', displayName: '', handle: '', photoURL: '');
    
    // Hafızada varsa anında dön
    final cached = UserCacheService.instance.getFromCache(actorId);
    if (cached != null) return cached;

    final tempActor = CachedUser(
      uid: actorId,
      displayName: (m['actorName'] ?? '').toString(),
      handle: (m['actorHandle'] ?? '').toString(),
      photoURL: (m['actorPhotoURL'] ?? '').toString(),
    );

    try {
      final fetched = await UserCacheService.instance.getUser(actorId);
      if (fetched != null) return fetched;
    } catch (_) {}
    return tempActor;
  }

  @override
  Widget build(BuildContext context) {
    final firstData = widget.docs[0].data();
    final createdAt = firstData['createdAt'] as Timestamp?;
    final timeLabel = createdAt != null ? _timeAgoShort(createdAt.toDate()) : '';
    final othersCount = widget.docs.length - 1;

    String name = 'Bir kullanıcı';
    if (actor1 != null) {
      if (actor1!.handle.isNotEmpty) name = actor1!.handle;
      else if (actor1!.displayName.isNotEmpty) name = actor1!.displayName;
    }

    return ListTile(
      onTap: () {
        Navigator.pop(context);
        Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: widget.postId)));
      },
      leading: SizedBox(
        width: 52,
        height: 42,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
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
  }
}

// ============================================================================
// YARDIMCI FONKSİYONLAR
// ============================================================================
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

String _timeAgoShort(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inDays > 365) return '${(diff.inDays / 365).floor()}y';
  if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}a';
  if (diff.inDays > 0) return '${diff.inDays}g';
  if (diff.inHours > 0) return '${diff.inHours}s';
  if (diff.inMinutes > 0) return '${diff.inMinutes}d';
  return 'Az önce';
}

// Avatar widgetı boyutlandırma desteği ile
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