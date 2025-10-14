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
            future: (() async {
              final ref = FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid);
              // First, try to get from cache
              var snap = await ref.get(const GetOptions(source: Source.cache));
              // If not found in cache, fall back to server
              if (!snap.exists) {
                snap = await ref.get(const GetOptions(source: Source.server));
              }
              return snap;
            })(),
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
