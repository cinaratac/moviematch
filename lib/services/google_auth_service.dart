import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart' as gsi; 
import 'package:flutter/material.dart';

class GoogleAuthService {
  static final gsi.GoogleSignIn _googleSignIn = gsi.GoogleSignIn();

  /// 1. Google ile SADECE Giriş Yap (Veritabanı kaydı yapmaz)
  static Future<User?> signInWithGoogle(BuildContext context) async {
    try {
      final gsi.GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // İptal edildi

      final gsi.GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

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

  /// 2. Yeni Google Kullanıcısını Veritabanına Kaydet (Sözleşme onayından sonra çağrılır)
  static Future<void> createGoogleUser(User user) async {
    final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final userDocSnapshot = await userDocRef.get();

    if (!userDocSnapshot.exists) {
      // Mailin başındaki kısmı kullanıcı adı yap
      String derivedUsername = user.email!.split('@')[0];
      // Görünen isim yoksa kullanıcı adını kullan
      String displayName = user.displayName ?? derivedUsername;

      await userDocRef.set({
        'username': derivedUsername,
        'username_lc': derivedUsername.toLowerCase(),
        'email': user.email,
        'displayName': displayName,
        'displayName_lc': displayName.toLowerCase(),
        'photoUrl': user.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'isGoogleAccount': true,
        'letterboxdUsername': '', // Henüz yok
        // Sözleşme onaylandı olarak işaretliyoruz
        'termsAccepted': true, 
        'termsAcceptedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Hesap silme işlemi için tekrar doğrulama
  static Future<bool> reauthenticateWithGoogle(BuildContext context) async {
    try {
      final gsi.GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return false;

      final gsi.GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      if (FirebaseAuth.instance.currentUser != null) {
        await FirebaseAuth.instance.currentUser!.reauthenticateWithCredential(credential);
        return true;
      }
      return false;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Doğrulama hatası: $e')),
        );
      }
      return false;
    }
  }

  /// Hesabı Bağla
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
          const SnackBar(content: Text('Google hesabı bağlandı!')),
        );
      }
    } catch (e) {
      // Hata yönetimi...
    }
  }
}