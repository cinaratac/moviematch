import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserProfile {
  final String? username;
  final String? letterboxdUsername;
  final String? displayName;
  final String? photoURL;

  UserProfile({
    this.username,
    this.letterboxdUsername,
    this.displayName,
    this.photoURL,
  });

  factory UserProfile.fromMap(Map<String, dynamic>? data) {
    if (data == null) return UserProfile();
    return UserProfile(
      username: (data['username'] as String?)?.trim(),
      letterboxdUsername: (data['letterboxdUsername'] as String?)?.trim(),
      displayName: (data['displayName'] as String?)?.trim(),
      photoURL: (data['photoURL'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toMap() => {
    if (username != null) 'username': username,
    if (letterboxdUsername != null) 'letterboxdUsername': letterboxdUsername,
    if (displayName != null) 'displayName': displayName,
    if (photoURL != null) 'photoURL': photoURL,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

class UserProfileService {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;
  DocumentReference<Map<String, dynamic>> get _doc =>
      _fs.collection('users').doc(_uid);

  /// Canlı profil akışı (cihazlar arası senkron)
  Stream<UserProfile?> profileStream(String uid) {
    return _fs.collection('users').doc(uid).snapshots().map((snap) {
      if (!snap.exists) return UserProfile();
      return UserProfile.fromMap(snap.data());
    });
  }

  /// Tek seferlik oku
  Future<UserProfile?> getProfileOnce(String uid) async {
    final snap = await _fs.collection('users').doc(uid).get();
    if (!snap.exists) return UserProfile();
    return UserProfile.fromMap(snap.data());
  }

  /// Letterboxd kullanıcı adını ayarla / güncelle
  Future<void> setLetterboxdUsername(String username) async {
    if (_uid == null) throw Exception('Not signed in');
    await _doc.set({
      'letterboxdUsername': username.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Letterboxd kullanıcı adını kaldır
  Future<void> clearLetterboxdUsername() async {
    if (_uid == null) throw Exception('Not signed in');
    await _doc.set({
      'letterboxdUsername': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// App-specific kullanıcı adını ayarla / güncelle
  Future<void> setUsername(String username) async {
    if (_uid == null) throw Exception('Not signed in');
    await _doc.set({
      'username': username.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Profil meta bilgilerini FirebaseAuth’tan Firestore’a senkronla (opsiyonel)
  Future<void> syncAuthProfile() async {
    if (_uid == null) return;
    final u = _auth.currentUser!;
    await _doc.set({
      'displayName': u.displayName ?? '',
      'photoURL': u.photoURL ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
