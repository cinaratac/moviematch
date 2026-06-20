import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/services/match_service.dart' as global_match;
import 'package:fluttergirdi/services/shelf_state_cache.dart';
import 'package:fluttergirdi/services/streak_service.dart';

class GlobalDataService {
  static final GlobalDataService instance = GlobalDataService._internal();
  GlobalDataService._internal();

  Map<String, dynamic>? myProfileData;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? myChats;
  List<global_match.MatchResult>? myMatches;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? myFeed;

  StreamSubscription? _profileSub;
  StreamSubscription? _chatSub;
  StreamSubscription? _matchSub;
  StreamSubscription? _feedSub;

  // Profil ve shelf verisi hazır olduğunda resolve eden completer.
  // InitialLoadingScreen bunu await edebilir.
  Completer<void>? _profileReady;
  Future<void> get profileReady =>
      _profileReady?.future ?? Future.value();

  void startPreloading() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _profileReady = Completer<void>();

    // 1. Profil + ShelfStateCache + StreakService — tek listener, üç işi birden
    _profileSub ??= FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) return;
      final data = snap.data()!;
      myProfileData = data;

      // ShelfStateCache'i doldur → MovieDetailScreen anında okuyabilir
      ShelfStateCache.instance.updateAll(uid, data);

      // StreakService cache'ini doldur → triggerAction() Firestore'a gitmez
      StreakService.instance.applyProfileData(data);

      // İlk veri geldiğinde completer'ı tamamla
      if (_profileReady != null && !_profileReady!.isCompleted) {
        _profileReady!.complete();
      }
    });

    // 2. Sohbetler
    _chatSub ??= FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: uid)
        .snapshots()
        .listen((snap) => myChats = snap.docs);

    // 3. Eşleşmeler
    _matchSub ??= global_match.MatchService.instance
        .findMatchesStream(uid)
        .listen((results) => myMatches = results);

    // 4. Feed
    _feedSub ??= FirebaseFirestore.instance
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(15)
        .snapshots()
        .listen((snap) => myFeed = snap.docs);
  }

  void stopPreloading() {
    _profileSub?.cancel(); _profileSub = null;
    _chatSub?.cancel();    _chatSub    = null;
    _matchSub?.cancel();   _matchSub   = null;
    _feedSub?.cancel();    _feedSub    = null;
    myProfileData = null;
    myChats       = null;
    myMatches     = null;
    myFeed        = null;
    _profileReady = null;
  }
}