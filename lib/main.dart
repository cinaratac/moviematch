import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:fluttergirdi/theme.dart';
import 'package:fluttergirdi/shell.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/services/notification_service.dart';
import 'package:fluttergirdi/auth/login_page.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
// KRİTİK EKLEME: SharedPreferences import edilmeli
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
  
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: 100 * 1024 * 1024, 
  );

  // --- TAM ÇÖZÜM: KAYITLI TEMAYI YÜKLE ---
  // Uygulama açılırken SharedPreferences'dan 'themeMode' anahtarını oku.
  final prefs = await SharedPreferences.getInstance();
  final String? savedTheme = prefs.getString('themeMode');

  // Okunan değere göre ThemeBridge içindeki ValueNotifier'ı güncelle.
  if (savedTheme == 'light') {
    ThemeBridge.themeMode.value = ThemeMode.light;
  } else if (savedTheme == 'dark') {
    ThemeBridge.themeMode.value = ThemeMode.dark;
  } else {
    // Eğer kayıt yoksa veya 'system' ise sistem ayarına güven.
    ThemeBridge.themeMode.value = ThemeMode.system;
  }
  // ---------------------------------------

  if (!kIsWeb) {
    await NotificationService.I.init();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ThemeBridge.themeMode'u dinleyerek uygulama temasını anlık ve açılışta değiştirir
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeBridge.themeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Cinematch',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: mode, // main içindeki yüklemeden gelen değer burada kullanılır
          home: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasData) {
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