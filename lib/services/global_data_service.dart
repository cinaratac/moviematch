import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/services/match_service.dart' as global_match;

class GlobalDataService {
  static final GlobalDataService instance = GlobalDataService._internal();
  GlobalDataService._internal();

  // Arka planda hazırda bekleyecek veriler
  Map<String, dynamic>? myProfileData;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? myChats;
  List<global_match.MatchResult>? myMatches;

  StreamSubscription? _profileSub;
  StreamSubscription? _chatSub;
  StreamSubscription? _matchSub;

  void startPreloading() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // 1. Profil Verisini İndir ve Dinle
    _profileSub ??= FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      if (snap.exists) {
        myProfileData = snap.data();
      }
    });

    // 2. Sohbetleri İndir ve Dinle
    _chatSub ??= FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: uid)
        .snapshots()
        .listen((snap) {
      myChats = snap.docs;
    });

    // 3. Eşleşmeleri İndir ve Dinle
    _matchSub ??= global_match.MatchService.instance
        .findMatchesStream(uid)
        .listen((results) {
      myMatches = results;
    });
  }

  void stopPreloading() {
    _profileSub?.cancel(); _profileSub = null;
    _chatSub?.cancel(); _chatSub = null;
    _matchSub?.cancel(); _matchSub = null;
    myProfileData = null;
    myChats = null;
    myMatches = null;
  }
}