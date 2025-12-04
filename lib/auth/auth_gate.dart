// lib/auth/auth_gate.dart dosyasının güncellenmiş hali

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../shell.dart';
import '../onboarding/letterboxd_onboarding.dart'; // YENİ IMPORT

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
                // HESAP SİLİNDİĞİNDE GİRİŞ EKRANINA YÖNLENDİR
                return const LoginPage();
              }
              final data = snap.data!.data();
              final lb = (data?['letterboxdUsername'] ?? '').toString();
              if (lb.isEmpty) {
                // DÜZELTME: Letterboxd bilgisi eksikse Onboarding ekranına yönlendir
                return const OnboardingLetterboxd(); // DEĞİŞTİ!
              }
              return const HomeShell();
            },
          );
        }
        // Firebase Auth'tan çıkış yapıldıysa/silindiyse LoginPage göster
        return const LoginPage();
      },
    );
  }
}