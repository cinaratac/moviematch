import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fluttergirdi/screens/chat_room_screen.dart';
import 'package:fluttergirdi/screens/post_detail_screen.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService I = NotificationService._();

  final navigatorKey = GlobalKey<NavigatorState>();
  final _fln = FlutterLocalNotificationsPlugin();
  final Map<String, DateTime> _recentPushes = {};

  bool _inited = false;
  Map<String, dynamic>? _pendingNavigation;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  static const _chChat = 'cinematch_chat';
  static const _chSocial = 'cinematch_social';

  Future<void> init() async {
    if (_inited || kIsWeb) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _fln.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) {
        _handlePayload(response.payload);
      },
    );

    if (Platform.isAndroid) {
      final androidPlugin = _fln
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _chChat,
          'Sohbet',
          description: 'Mesaj bildirimleri',
          importance: Importance.high,
        ),
      );
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _chSocial,
          'Sosyal',
          description: 'Begeni, yorum ve takip bildirimleri',
          importance: Importance.defaultImportance,
        ),
      );
    }

    _foregroundSub = FirebaseMessaging.onMessage.listen(_showForegroundPush);
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteTap);

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _pendingNavigation = Map<String, dynamic>.from(initialMessage.data);
    }

    _inited = true;
  }

  Future<void> requestPermissions() async {
    if (kIsWeb) return;
    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      debugPrint('Android bildirim izni: $status');
      return;
    }

    if (Platform.isIOS) {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final dynamic iosPlugin = _fln.resolvePlatformSpecificImplementation();
      await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  Future<void> start() async {
    await init();
  }

  void flushPendingNavigation() {
    final data = _pendingNavigation;
    if (data == null) return;
    _pendingNavigation = null;
    unawaited(_delayedNavigate(data));
  }

  Future<void> dispose() async {
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    _foregroundSub = null;
    _openedSub = null;
    _inited = false;
  }

  Future<void> _showForegroundPush(RemoteMessage message) async {
    final data = message.data;
    final type = data['type']?.toString() ?? 'social';
    final dedupeKey = _dedupeKey(message);

    if (!_shouldShow(dedupeKey)) return;

    final notification = message.notification;
    final title = notification?.title ?? _fallbackTitle(data);
    final body = notification?.body ?? _fallbackBody(data);
    final payload = jsonEncode(
      Map<String, String>.fromEntries(
        data.entries.map(
          (entry) => MapEntry(entry.key, entry.value.toString()),
        ),
      ),
    );

    final details = type == 'chat' ? _chatDetails() : _socialDetails();
    await _fln.show(
      _stableId(dedupeKey),
      title,
      body,
      details,
      payload: payload,
    );
  }

  void _handleRemoteTap(RemoteMessage message) {
    _queueNavigation(message.data);
  }

  void _handlePayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        final data = decoded.map(
          (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
        );
        _queueNavigation(data);
      }
    } catch (e) {
      debugPrint('Bildirim payload okunamadi: $e');
    }
  }

  void _queueNavigation(Map<String, dynamic> data) {
    _pendingNavigation = Map<String, dynamic>.from(data);
    unawaited(_delayedNavigate(data));
  }

  Future<void> _delayedNavigate(Map<String, dynamic> data) async {
    for (var i = 0; i < 24; i++) {
      final nav = navigatorKey.currentState;
      if (nav != null) {
        _pendingNavigation = null;
        _navigate(nav, data);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  void _navigate(NavigatorState nav, Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? data['route']?.toString() ?? '';

    if (type == 'chat') {
      final chatId = data['chatId']?.toString() ?? '';
      final otherUid =
          data['otherUid']?.toString() ?? data['actorId']?.toString() ?? '';
      final isGroup = data['isGroup']?.toString() == 'true';
      final groupName = data['groupName']?.toString();
      if (chatId.isEmpty) return;
      nav.push(
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(
            chatId: chatId,
            otherUid: isGroup ? '' : otherUid,
            otherTitle: isGroup ? groupName : null,
            isGroup: isGroup,
            groupName: isGroup ? groupName : null,
          ),
        ),
      );
      return;
    }

    if (type == 'like' || type == 'comment') {
      final postId = data['postId']?.toString() ?? '';
      if (postId.isEmpty) return;
      nav.push(
        MaterialPageRoute(builder: (_) => PostDetailScreen(postId: postId)),
      );
      return;
    }

    if (type == 'follow') {
      final actorId = data['actorId']?.toString() ?? '';
      if (actorId.isEmpty) return;
      nav.push(
        MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: actorId)),
      );
      return;
    }

    if (type == 'club_request') {
      final clubId = data['clubId']?.toString() ?? '';
      if (clubId.isEmpty) return;
      final clubName = data['clubName']?.toString();
      nav.push(
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(
            chatId: clubId,
            otherUid: '',
            otherTitle: clubName,
            isGroup: true,
            groupName: clubName,
          ),
        ),
      );
    }
  }

  NotificationDetails _chatDetails() {
    const android = AndroidNotificationDetails(
      _chChat,
      'Sohbet',
      importance: Importance.high,
      priority: Priority.high,
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    return const NotificationDetails(android: android, iOS: ios);
  }

  NotificationDetails _socialDetails() {
    const android = AndroidNotificationDetails(
      _chSocial,
      'Sosyal',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    return const NotificationDetails(android: android, iOS: ios);
  }

  bool _shouldShow(String key) {
    final now = DateTime.now();
    _recentPushes.removeWhere(
      (_, shownAt) => now.difference(shownAt) > const Duration(seconds: 20),
    );
    if (_recentPushes.containsKey(key)) return false;
    _recentPushes[key] = now;
    return true;
  }

  String _dedupeKey(RemoteMessage message) {
    final data = message.data;
    return message.messageId ??
        data['messageId']?.toString() ??
        data['notificationId']?.toString() ??
        '${data['type']}_${data['chatId']}_${data['postId']}_${data['actorId']}';
  }

  int _stableId(String value) {
    var hash = 0;
    for (final codeUnit in value.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return hash % 1000000;
  }

  String _fallbackTitle(Map<String, dynamic> data) {
    switch (data['type']?.toString()) {
      case 'chat':
        return data['actorName']?.toString() ?? 'Yeni mesaj';
      case 'like':
        return 'Yeni begeni';
      case 'comment':
        return 'Yeni yorum';
      case 'follow':
        return 'Yeni takipci';
      case 'club_request':
        return 'Kulup istegi';
      default:
        return 'CineMatch';
    }
  }

  String _fallbackBody(Map<String, dynamic> data) {
    final actorName = data['actorName']?.toString() ?? '';
    final preview = data['preview']?.toString() ?? '';
    switch (data['type']?.toString()) {
      case 'chat':
        return preview.isNotEmpty ? preview : 'Yeni mesaj';
      case 'like':
        return actorName.isNotEmpty
            ? '$actorName gonderini begendi'
            : 'Gonderin begenildi';
      case 'comment':
        return preview.isNotEmpty ? '$actorName: $preview' : 'Yeni yorum';
      case 'follow':
        return actorName.isNotEmpty
            ? '$actorName seni takip etmeye basladi'
            : 'Yeni takipcin var';
      case 'club_request':
        return actorName.isNotEmpty
            ? '$actorName kulubune katilmak istiyor'
            : 'Yeni kulup istegi';
      default:
        return 'Yeni bildirimin var';
    }
  }

  Future<void> markAllAsRead(String userId) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .where('read', isEqualTo: false)
          .get();

      if (query.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in query.docs) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Toplu okundu isaretleme hatasi: $e');
    }
  }

  Future<void> deleteOldNotifications(String userId) async {
    try {
      final threeMonthsAgo = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 90)),
      );

      final query = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .where('createdAt', isLessThan: threeMonthsAgo)
          .get();

      if (query.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in query.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      debugPrint('${query.docs.length} eski bildirim silindi.');
    } catch (e) {
      debugPrint('Eski bildirimleri silme hatasi: $e');
    }
  }
}
