import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Saves FCM token(s) under users/{uid}/fcmTokens/{token}
class PushTokenService {
  PushTokenService._();
  static final PushTokenService I = PushTokenService._();

  Stream<String?>? _tokenStream;

  Future<void> start() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Request permission (iOS + Android13+)
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );

    // Initial token save
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _saveToken(user.uid, token);
    }

    // Listen for token refresh
    _tokenStream ??= FirebaseMessaging.instance.onTokenRefresh;
    _tokenStream!.listen((t) async {
      if (t == null) return;
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return;
      await _saveToken(u.uid, t);
    });
  }

  Future<void> stop() async {
    // No-op: we keep historical tokens for multi-device support.
    // Optionally, you could delete the token doc on sign-out.
  }

  Future<void> _saveToken(String uid, String token) async {
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('fcmTokens')
        .doc(token);
    await ref.set({
      'token': token,
      'platform': Platform.operatingSystem,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
