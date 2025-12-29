import 'package:firebase_core/firebase_core.dart';
import 'package:fluttergirdi/services/VersionCheckService.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode; // kReleaseMode eklendi

import 'package:fluttergirdi/theme.dart';
import 'package:fluttergirdi/shell.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/services/notification_service.dart';
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
  
  // 1. Ekran yönü ayarları
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 2. Firebase Başlatma
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  // --- APP CHECK AKTİVASYONU (KRİTİK DÜZELTME) ---
  // Bu blok Cloud Functions ve Storage isteklerinin güvenli şekilde yapılmasını sağlar.
  await FirebaseAppCheck.instance.activate(
    // Android için: Yayında Play Integrity, testte Debug provider
    androidProvider: kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug,
    // iOS için: Yayında App Attest veya DeviceCheck, testte Debug provider
    appleProvider: kReleaseMode ? AppleProvider.appAttest : AppleProvider.debug,
    // Web için: ReCaptcha v3 (gerekirse site key ekleyin)
    webProvider: ReCaptchaV3Provider('recaptcha-v3-site-key'), 
  );
  // -------------------------------------------------
  
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

  if (!kIsWeb) {
    await NotificationService.I.init();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget { // StatelessWidget -> StatefulWidget yapıldı
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // Uygulama ayağa kalktığında ilk kare çizildikten sonra kontrolü çalıştır
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
          // StreamBuilder içindeki mantığı güncelleyin
                  home: StreamBuilder<User?>(
                    stream: FirebaseAuth.instance.authStateChanges(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data != null) {
                          // --- KRİTİK EKLEME: Servisleri Burada Başlatın ---
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            NotificationService.I.start();           // Bildirim dinleyicilerini başlatır
                            NotificationService.I.requestPermissions(); // İzin ister (Android 13+)
                            // PushTokenService.I.start();          // Token'ı DB'ye kaydeder (Bu servisin start() metodu olduğundan emin olun)
                          });
                          return const HomeShell();
                        }
                      return const LoginPage();
                    },
                  ),
        );
      },
    );
  }
}