import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluttergirdi/theme.dart';
import 'package:fluttergirdi/shell.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/auth/login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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
