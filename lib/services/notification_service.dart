// ignore_for_file: unnecessary_this

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// NotificationService
/// --------------------
/// - Görev: Uygulama açıkken **yerel bildirim** gösterir.
/// - Kaynaklar:
///   • Chat mesajları: chats/{chatId}/messages/* (authorId != me)
///   • Yeni takipçi:   users/{me}/followers/*
///   • Beğeni:         likeLogs/*  (targetUid == me)
///
/// Not:
///  - Bu servis **push (FCM)** yerine **local notification** gösterir.
///  - Android & iOS için `flutter_local_notifications` kurulu olmalı.
///  - App arka plandayken OS kısıtlarından dolayı bu dinleyiciler tetiklenmeyebilir;
///    arkaplan/push ihtiyacı varsa FCM ile sunucu tarafında tetik kurun.
class NotificationService {
  NotificationService._();
  static final NotificationService I = NotificationService._();

  final _fln = FlutterLocalNotificationsPlugin();
  bool _inited = false;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _followersSub;
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _chatSubs = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _likeLogsSub;

  /// Kanal ID'leri
  static const _chChat = 'cinematch_chat';
  static const _chSocial = 'cinematch_social';

  /// Local notifications init + izinler
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

    // Android kanalları
    const androidChat = AndroidNotificationChannel(
      _chChat,
      'Sohbet',
      description: 'Sohbet mesaj bildirimleri',
      importance: Importance.high,
    );
    const androidSocial = AndroidNotificationChannel(
      _chSocial,
      'Sosyal',
      description: 'Takip ve beğeni bildirimleri',
      importance: Importance.defaultImportance,
    );

    try {
      await _fln
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(androidChat);
      await _fln
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(androidSocial);
    } catch (_) {}

    _inited = true;
  }

  /// Tüm akışları başlat. Aynı oturumda bir kez çağırman yeterli.
  Future<void> start() async {
    await init();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final myUid = user.uid;

    // Takipçiler
    _listenFollowers(myUid);

    // Like logs (hedef benimse)
    _listenLikeLogs(myUid);

    // Sohbetlerim
    _bindChatsAndMessages(myUid);
  }

  Future<void> dispose() async {
    await _followersSub?.cancel();
    await _likeLogsSub?.cancel();
    for (final s in _chatSubs.values) {
      await s.cancel();
    }
    _chatSubs.clear();
  }

  /* -------------------------- Internal: Followers ------------------------- */
  Future<void> _listenFollowers(String myUid) async {
    await _followersSub?.cancel();

    final prefs = await SharedPreferences.getInstance();
    final lastKey = 'notif_last_follow_$myUid';
    final lastTs = prefs.getInt(lastKey) ?? 0; // millis
    final since = Timestamp.fromMillisecondsSinceEpoch(lastTs);

    final q = FirebaseFirestore.instance
        .collection('users')
        .doc(myUid)
        .collection('followers')
        .where('createdAt', isGreaterThan: since);

    _followersSub = q.snapshots().listen((qs) async {
      // Güncel TS'yi yaz (spam engel)
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(lastKey, nowMs);

      for (final d in qs.docChanges) {
        if (d.type != DocumentChangeType.added) continue;
        final followerUid = d.doc.id;
        await _showSocial(title: 'Yeni takipçi', body: 'Biri seni takip etti');
        if (kDebugMode) debugPrint('notif: new follower $followerUid');
      }
    });
  }

  /* --------------------------- Internal: LikeLogs ------------------------- */
  Future<void> _listenLikeLogs(String myUid) async {
    await _likeLogsSub?.cancel();

    final prefs = await SharedPreferences.getInstance();
    final lastKey = 'notif_last_like_$myUid';
    final lastTs = prefs.getInt(lastKey) ?? 0; // millis
    final since = Timestamp.fromMillisecondsSinceEpoch(lastTs);

    // likeLogs şemasında: { targetUid, actorUid, postId, createdAt }
    final q = FirebaseFirestore.instance
        .collection('likeLogs')
        .where('targetUid', isEqualTo: myUid)
        .where('createdAt', isGreaterThan: since);

    _likeLogsSub = q.snapshots().listen((qs) async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(lastKey, nowMs);

      for (final d in qs.docChanges) {
        if (d.type != DocumentChangeType.added) continue;
        final actor = d.doc.data()?['actorUid'];
        if (actor == myUid) continue; // kendi beğenim
        await _showSocial(title: 'Yeni beğeni', body: 'Gönderin beğenildi');
        if (kDebugMode) debugPrint('notif: like by $actor');
      }
    });
  }

  /* ----------------------------- Internal: Chats -------------------------- */
  Future<void> _bindChatsAndMessages(String myUid) async {
    // Mevcut chat dinleyicilerini kes
    for (final s in _chatSubs.values) {
      await s.cancel();
    }
    _chatSubs.clear();

    final chats = await FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: myUid)
        .limit(50)
        .get();

    for (final c in chats.docs) {
      _listenMessagesForChat(myUid, c.id);
    }

    // Yeni açılan sohbetler için de ek dinleyici
    FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: myUid)
        .snapshots()
        .listen((qs) {
          for (final ch in qs.docChanges) {
            if (ch.type == DocumentChangeType.added) {
              _listenMessagesForChat(myUid, ch.doc.id);
            }
          }
        });
  }

  Future<void> _listenMessagesForChat(String myUid, String chatId) async {
    await _chatSubs[chatId]?.cancel();

    final prefs = await SharedPreferences.getInstance();
    final lastKey = 'notif_last_msg_${myUid}_$chatId';
    final lastTs = prefs.getInt(lastKey) ?? 0; // millis
    final since = Timestamp.fromMillisecondsSinceEpoch(lastTs);

    final q = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('createdAt', isGreaterThan: since)
        .orderBy('createdAt', descending: true)
        .limit(20);

    _chatSubs[chatId] = q.snapshots().listen((qs) async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(lastKey, nowMs);

      for (final d in qs.docChanges) {
        if (d.type != DocumentChangeType.added) continue;
        final m = d.doc.data();
        if (m == null) continue;
        if ((m['authorId'] ?? '') == myUid) continue; // kendi mesajım
        final txt = (m['text'] ?? 'Yeni mesaj').toString();
        await _showChat(title: 'Yeni mesaj', body: txt);
        if (kDebugMode) debugPrint('notif: chat $chatId -> $txt');
      }
    });
  }

  /* --------------------------- Local notify helpers ---------------------- */
  Future<void> _showChat({required String title, required String body}) async {
    // Foreground’da bildirim göstermiyoruz.
    return;
  }

  Future<void> _showSocial({
    required String title,
    required String body,
  }) async {
    // Foreground’da bildirim göstermiyoruz.
    return;
  }
}
