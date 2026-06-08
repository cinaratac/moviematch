// ignore_for_file: unnecessary_this

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'dart:io'; 
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService I = NotificationService._();

  final _fln = FlutterLocalNotificationsPlugin();
  bool _inited = false;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _followersSub;
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _chatSubs = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _likeLogsSub;

  static const _chChat = 'cinematch_chat';
  static const _chSocial = 'cinematch_social';

  /// 1. Başlatma
  Future<void> init() async {
    if (_inited) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _fln.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    if (Platform.isAndroid) {
      await _fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            _chChat, 'Sohbet', importance: Importance.high));
      await _fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            _chSocial, 'Sosyal', importance: Importance.defaultImportance));
    }

    _inited = true;
  }

  /// 2. İzinler (Hata veren kısım düzeltildi)
  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      debugPrint("Android Bildirim İzni: $status");
    } else if (Platform.isIOS) {
      // Analyzer hatasını engellemek için 'dynamic' üzerinden iOS izinlerini tetikliyoruz
      final dynamic iosPlugin = _fln.resolvePlatformSpecificImplementation();
      await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  /// 3. Akışları Başlat (Senin Orijinal Mantığın)
  Future<void> start() async {
    await init();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _listenNotifications(user.uid);
    _bindChatsAndMessages(user.uid);
  }

  Future<void> dispose() async {
    await _followersSub?.cancel();
    await _likeLogsSub?.cancel();
    for (final s in _chatSubs.values) { await s.cancel(); }
    _chatSubs.clear();
  }

  /* --- Senin Sosyal Akış Dinleyicin --- */
  Future<void> _listenNotifications(String myUid) async {
    final prefs = await SharedPreferences.getInstance();
    final lastKey = 'notif_last_social_$myUid';
    final lastTs = prefs.getInt(lastKey) ?? 0;
    final since = Timestamp.fromMillisecondsSinceEpoch(lastTs);

    final q = FirebaseFirestore.instance
        .collection('users').doc(myUid).collection('notifications')
        .where('createdAt', isGreaterThan: since)
        .orderBy('createdAt', descending: true).limit(50);

    q.snapshots().listen((qs) async {
      await prefs.setInt(lastKey, DateTime.now().millisecondsSinceEpoch);

      for (final ch in qs.docChanges) {
        if (ch.type != DocumentChangeType.added) continue;
        final m = ch.doc.data();
        if (m == null || m['actorId'] == myUid) continue;

        final type = m['type']?.toString() ?? '';
        final actorName = m['actorName']?.toString() ?? '';
        final preview = m['preview']?.toString() ?? '';

        switch (type) {
          case 'like':
            await _showSocial(title: 'Yeni beğeni', body: actorName.isNotEmpty ? '$actorName gönderini beğendi' : 'Gönderin beğenildi');
            break;
          case 'comment':
            await _showSocial(title: 'Yeni yorum', body: preview.isNotEmpty ? '$actorName: $preview' : 'Gönderine yorum yapıldı');
            break;
          case 'follow':
            await _showSocial(title: 'Yeni takipçi', body: '$actorName seni takip etmeye başladı');
            break;
          case 'club_request':
            await _showSocial(title: 'Kulüp İsteği', body: '$actorName kulübüne katılmak istiyor');
            break;
        }
      }
    });
  }

  /* --- Senin Chat Dinleyicilerin --- */
  Future<void> _bindChatsAndMessages(String myUid) async {
    for (final s in _chatSubs.values) { await s.cancel(); }
    _chatSubs.clear();

    final chats = await FirebaseFirestore.instance
        .collection('chats').where('participants', arrayContains: myUid).limit(50).get();

    for (final c in chats.docs) { _listenMessagesForChat(myUid, c.id); }

    FirebaseFirestore.instance.collection('chats').where('participants', arrayContains: myUid)
        .snapshots().listen((qs) {
      for (final ch in qs.docChanges) {
        if (ch.type == DocumentChangeType.added) { _listenMessagesForChat(myUid, ch.doc.id); }
      }
    });
  }

  Future<void> _listenMessagesForChat(String myUid, String chatId) async {
    await _chatSubs[chatId]?.cancel();
    final prefs = await SharedPreferences.getInstance();
    final lastKey = 'notif_last_msg_${myUid}_$chatId';
    final lastTs = prefs.getInt(lastKey) ?? 0;

    _chatSubs[chatId] = FirebaseFirestore.instance
        .collection('chats').doc(chatId).collection('messages')
        .where('createdAt', isGreaterThan: Timestamp.fromMillisecondsSinceEpoch(lastTs))
        .orderBy('createdAt', descending: true).limit(20)
        .snapshots().listen((qs) async {
      
      await prefs.setInt(lastKey, DateTime.now().millisecondsSinceEpoch);
      for (final d in qs.docChanges) {
        if (d.type != DocumentChangeType.added) continue;
        final m = d.doc.data();
        if (m == null || m['authorId'] == myUid) continue;
        await _showChat(title: 'Yeni mesaj', body: m['text']?.toString() ?? 'Yeni mesaj');
      }
    });
  }

  /* --- Senin Bildirim Göstericilerin --- */
  Future<void> _showChat({required String title, required String body}) async {
    const android = AndroidNotificationDetails(_chChat, 'Sohbet', importance: Importance.high, priority: Priority.high);
    const ios = DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true);
    await _fln.show(DateTime.now().hashCode % 1000000, title, body, const NotificationDetails(android: android, iOS: ios), payload: 'chat');
  }

  Future<void> _showSocial({required String title, required String body}) async {
    const android = AndroidNotificationDetails(_chSocial, 'Sosyal', importance: Importance.defaultImportance);
    const ios = DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true);
    await _fln.show(DateTime.now().hashCode % 1000000, title, body, const NotificationDetails(android: android, iOS: ios), payload: 'social');
  }
  Future<void> markAllAsRead(String userId) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .where('read', isEqualTo: false)
          .get();

      if (query.docs.isEmpty) return; // Zaten hepsi okunmuşsa sunucuyu yorma

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in query.docs) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();
    } catch (e) {
      debugPrint("Toplu okundu işaretleme hatası: $e");
    }
  }
  /// 3 aydan (90 gün) eski bildirimleri veritabanından tamamen siler
  Future<void> deleteOldNotifications(String userId) async {
    try {
      // 90 gün öncesinin Timestamp değerini al
      final threeMonthsAgo = Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 90)));

      final query = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .where('createdAt', isLessThan: threeMonthsAgo) // 3 aydan DAHA ESKİ olanlar
          .get();

      if (query.docs.isEmpty) return; // Silinecek eski bildirim yoksa işlemi bitir

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in query.docs) {
        batch.delete(doc.reference); // Toplu silme kuyruğuna ekle
      }
      await batch.commit(); // Hepsini tek seferde sil
      
      debugPrint("${query.docs.length} adet eski bildirim sistemden silindi.");
    } catch (e) {
      debugPrint("Eski bildirimleri silme hatası: $e");
    }
  }
}