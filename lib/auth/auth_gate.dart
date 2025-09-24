import 'package:flutter/material.dart';
import 'login_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../shell.dart';

/// İleride burada token/SharedPreferences kontrolü yapabilirsin.
/// Şimdilik uygulama açıldığında LoginPage gösteriyoruz.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
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
    );
  }
}
