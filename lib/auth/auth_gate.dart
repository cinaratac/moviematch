import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_page.dart';
import 'google_register_page.dart'; // EKLENDİ
import '../shell.dart';
import '../onboarding/letterboxd_onboarding.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 1. Auth Durumu Bekleniyor
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        // 2. Kullanıcı Giriş Yapmış mı?
        if (snapshot.hasData) {
          final user = snapshot.data!;
          
          return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            // 1. Önce cihazın kendi hafızasındaki (cache) veriyi okumayı dener (Anında yanıt verir)
            // 2. Eğer cihazda veri yoksa (ilk giriş veya cache temizlenmişse) server'dan çeker.
            future: FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get(const GetOptions(source: Source.cache))
                .catchError((_) => FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .get()),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }

              // --- KRİTİK DÜZELTME BURADA ---
              
              // Veri yoksa veya 'termsAccepted' (Sözleşme onayı) true değilse -> KAYIT SAYFASINA
              if (!snap.hasData || !snap.data!.exists || snap.data!.data()?['termsAccepted'] != true) {
                return GoogleRegisterPage(user: user);
              }

              // Buraya geldiyse kayıt tamdır. Diğer kontroller:
              final data = snap.data!.data();
              final lb = (data?['letterboxdUsername'] ?? '').toString();
              
              if (lb.isEmpty) {
                return const OnboardingLetterboxd();
              }
              
              return const HomeShell();
            },
          );
        }

        // 3. Giriş Yapılmamış -> Login Sayfası
        return const LoginPage();
      },
    );
  }
}