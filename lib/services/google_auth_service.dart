import 'package:firebase_auth/firebase_auth.dart';
// 'as gsi' diyerek pakete takma isim veriyoruz, böylece karışıklık önlenir.
import 'package:google_sign_in/google_sign_in.dart' as gsi; 
import 'package:flutter/material.dart';

class GoogleAuthService {
  // gsi.GoogleSignIn kullanarak paketten geldiğini belirtiyoruz
  static final gsi.GoogleSignIn _googleSignIn = gsi.GoogleSignIn();

  /// Google ile Giriş Yap
  static Future<User?> signInWithGoogle(BuildContext context) async {
    try {
      // 1. Google giriş penceresini aç
      final gsi.GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // Kullanıcı iptal etti

      // 2. Kimlik doğrulama detaylarını al
      final gsi.GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // 3. Firebase için credential oluştur
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 4. Firebase'e giriş yap
      final UserCredential userCredential = 
          await FirebaseAuth.instance.signInWithCredential(credential);
      
      return userCredential.user;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google girişi başarısız: $e')),
        );
      }
      return null;
    }
  }

  /// Google Hesabını Bağla
  static Future<void> linkGoogleAccount(BuildContext context) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final gsi.GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return;

      final gsi.GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await user.linkWithCredential(credential);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google hesabı başarıyla bağlandı!')),
        );
      }
    } on FirebaseAuthException catch (e) {
      String msg = 'Bağlama hatası oluştu.';
      if (e.code == 'credential-already-in-use') {
        msg = 'Bu Google hesabı zaten başka bir kullanıcıya bağlı.';
      } else if (e.code == 'provider-already-linked') {
        msg = 'Hesap zaten Google\'a bağlı.';
      }
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }
}