import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluttergirdi/theme.dart';
import 'package:fluttergirdi/shell.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/services/notification_service.dart';
import 'package:fluttergirdi/auth/login_page.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:fluttergirdi/services/push_token_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is available in background isolate
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // We keep background handling minimal; the OS shows the notification payload.
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Register FCM background/foreground handlers (skip on web for now)
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Optional: foreground messages (if push arrives while app is visible)
    FirebaseMessaging.onMessage.listen((RemoteMessage m) {
      // No-op here: if the push has a notification payload, Android/iOS shows it automatically when backgrounded.
      // For foreground, your in-app NotificationService already surfaces social/chat events via Firestore listeners.
    });
  }

  // Load saved theme preference before launching the app
  try {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('themeMode'); // 'light' | 'dark' | 'system'
    if (saved != null) {
      switch (saved) {
        case 'light':
          ThemeBridge.themeMode.value = ThemeMode.light;
          break;
        case 'dark':
          ThemeBridge.themeMode.value = ThemeMode.dark;
          break;
        default:
          ThemeBridge.themeMode.value = ThemeMode.system;
      }
    }
  } catch (_) {
    // ignore errors and use system default
  }

  // Initialize local notifications and bind to auth state (skip on web)
  if (!kIsWeb) {
    await NotificationService.I.init();
    FirebaseAuth.instance.authStateChanges().listen((u) {
      if (u != null) {
        NotificationService.I.start();
        PushTokenService.I.start();
      } else {
        NotificationService.I.dispose();
        PushTokenService.I.stop();
      }
    });
  }
  // main() içinde, runApp'tan ÖNCE
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Hata:\n${details.exceptionAsString()}\n\n${details.stack}',
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
      ),
    );
  };
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
