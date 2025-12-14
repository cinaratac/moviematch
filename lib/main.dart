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

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is available in background isolate
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // We keep background handling minimal; the OS shows the notification payload.
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: 100 * 1024 * 1024, 
  );

  // DÜZELTME: Listener'ları burada manuel başlatmak yerine,
  // MyApp içinde StreamBuilder veya AuthService kullanmak daha sağlıklıdır.
  // Ancak mevcut yapınızı bozmamak için NotificationService.I.init() yeterlidir.
  // NotificationService zaten authStateChanges'i dinleyip kendini yönetiyor (dosyanızı inceledim).
  
  if (!kIsWeb) {
    // Notification servisini başlatır, o da kendi içinde auth durumunu dinler.
    await NotificationService.I.init();
    
    // Background mesaj işleyici (Zaten vardı)
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  // ... (Theme yükleme ve ErrorWidget kısımları aynı kalsın) ...

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
          themeMode: mode, // ← live theme mode from Settings
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
