import 'dart:io'; // Platform kontrolü için eklendi
import 'package:firebase_core/firebase_core.dart';
import 'package:fluttergirdi/services/VersionCheckService.dart';
import 'package:fluttergirdi/services/push_token_service.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

import 'package:fluttergirdi/theme.dart';
import 'package:fluttergirdi/shell.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/services/notification_service.dart';
// import 'package:fluttergirdi/services/push_token_service.dart'; // Eğer dosya adı buysa aktif et
import 'package:fluttergirdi/auth/login_page.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// App Check importu
import 'package:firebase_app_check/firebase_app_check.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Ekran yönü ayarları (Dikey moda sabitleme)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 2. Firebase Başlatma
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // --- KRİTİK iOS AYARI ---
  // Uygulama açıkken (foreground) bildirimlerin tepeden düşmesini sağlar.
  if (!kIsWeb && Platform.isIOS) {
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
  }

  // --- APP CHECK AKTİVASYONU (GEÇİCİ OLARAK KAPATILDI) ---
  
  await FirebaseAppCheck.instance.activate(
    // Release modunda Play Integrity, test modunda Debug kullanılır
    androidProvider: kReleaseMode
        ? AndroidProvider.playIntegrity
        : AndroidProvider.debug,
    appleProvider: kReleaseMode 
        ? AppleProvider.appAttest 
        : AppleProvider.debug,
  );
 
  // Firestore Ayarları
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: 100 * 1024 * 1024,
  );

  // --- KAYITLI TEMAYI YÜKLE ---
  final prefs = await SharedPreferences.getInstance();
  final String? savedTheme = prefs.getString('themeMode');

  if (savedTheme == 'light') {
    ThemeBridge.themeMode.value = ThemeMode.light;
  } else if (savedTheme == 'dark') {
    ThemeBridge.themeMode.value = ThemeMode.dark;
  } else {
    ThemeBridge.themeMode.value = ThemeMode.system;
  }

  // Bildirim Servis Başlangıcı
  if (!kIsWeb) {
    await NotificationService.I.init();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // YENİ: Servislerin birden fazla kez başlatılmasını engelleyecek kontrol bayrağı
  bool _servicesStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      VersionCheckService.instance.checkVersion(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeBridge.themeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Cinematch',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode,
          home: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data != null) {
                // YENİ KONTROL: Servisler daha önce başlatılmadıysa BAŞLAT
                if (!_servicesStarted) {
                  _servicesStarted = true; // Bayrağı işaretle
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    NotificationService.I.start();
                    NotificationService.I.requestPermissions();
                    PushTokenService.I.start();
                  });
                }

                return const HomeShell();
              } else {
                // Kullanıcı çıkış yaptıysa veya oturum yoksa bayrağı sıfırla
                _servicesStarted = false;
                return const LoginPage();
              }
            },
          ),
        );
      },
    );
  }
}
