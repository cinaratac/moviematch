import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../onboarding/letterboxd_onboarding.dart';
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
          final user = snapshot.data!;
          return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (!snap.hasData || !snap.data!.exists) {
                return const OnboardingLetterboxd();
              }
              final data = snap.data!.data();
              final lb = (data?['letterboxdUsername'] ?? '').toString();
              if (lb.isEmpty) {
                return const OnboardingLetterboxd();
              }
              return const HomeShell();
            },
          );
        }
        return const LoginPage();
      },
    );
  }
}
