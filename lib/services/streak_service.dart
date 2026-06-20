import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/streak_bottom_sheet.dart';

class StreakService {
  static final StreakService instance = StreakService._internal();
  StreakService._internal();

  // 🔥 TEST MODU: true iken 1 seride bile gösterir.
  // Çalıştığını gördükten sonra false yap.
  final bool isTestMode = false;

  _StreakState? _cached;
  String?       _cachedUid;

  // ---------------------------------------------------------------------------
  // GlobalDataService'in profil listener'ından doğrudan besle.
  // Bu sayede uygulama açılırken zaten cache doluyor.
  // ---------------------------------------------------------------------------
  void applyProfileData(Map<String, dynamic> data) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _cached = _StreakState(
      lastActiveDate:   (data['lastActiveDate']  as String?) ?? '',
      streakCount:      (data['streakCount']     as num?)?.toInt() ?? 0,
      currentWeekKey:   (data['currentWeekKey']  as String?) ?? '',
      weeklyActiveDays: List<int>.from(data['weeklyActiveDays'] ?? []),
    );
    _cachedUid = uid;
  }

  // ---------------------------------------------------------------------------
  // Harici preload (profil sayfasından veya başka yerden çağrılabilir)
  // ---------------------------------------------------------------------------
  Future<void> preload(String uid) async {
    if (_cachedUid == uid && _cached != null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.cache));
      _applyDoc(uid, doc);
    } catch (_) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get(const GetOptions(source: Source.server));
        _applyDoc(uid, doc);
      } catch (e) {
        debugPrint('Streak preload hatası: $e');
      }
    }
  }

  void _applyDoc(String uid, DocumentSnapshot doc) {
    if (!doc.exists) return;
    final d = (doc.data() as Map<String, dynamic>?) ?? {};
    _cached = _StreakState(
      lastActiveDate:   (d['lastActiveDate']  as String?) ?? '',
      streakCount:      (d['streakCount']     as num?)?.toInt() ?? 0,
      currentWeekKey:   (d['currentWeekKey']  as String?) ?? '',
      weeklyActiveDays: List<int>.from(d['weeklyActiveDays'] ?? []),
    );
    _cachedUid = uid;
  }

  // ---------------------------------------------------------------------------
  // Ana giriş noktası — önce UI'ı göster, sonra Firestore'a yaz
  // ---------------------------------------------------------------------------
  Future<void> triggerAction(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Root navigator'ı context ölmeden yakala
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    final now        = DateTime.now();
    final todayStr   = _dayStr(now);
    final weekday    = now.weekday;
    final weekKey    = _weekKey(now);
    final yesterday  = _dayStr(now.subtract(const Duration(days: 1)));

    final cached = (_cachedUid == uid) ? _cached : null;

    // Spam koruma (test modunda pas geç)
    if (cached?.lastActiveDate == todayStr && !isTestMode) return;

    // Yeni state'i hesapla (saf fonksiyon, IO yok)
    final next = _computeNext(
      current:      cached,
      todayStr:     todayStr,
      yesterdayStr: yesterday,
      weekKey:      weekKey,
      weekday:      weekday,
    );

    // Cache'i hemen güncelle
    _cached    = next;
    _cachedUid = uid;

    // UI'ı HEMEN göster (tek frame bekle, Firestore bitmesini bekleme)
    final required = isTestMode ? 1 : 2;
    if (next.streakCount >= required) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (rootNavigator.mounted) {
          showModalBottomSheet(
            context: rootNavigator.context,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => StreakBottomSheet(
              streak:     next.streakCount,
              activeDays: next.weeklyActiveDays,
            ),
          );
        }
      });
    }

    // Firestore'a arka planda kaydet
    _saveToFirestore(uid, next)
        .catchError((e) => debugPrint('Streak kayıt hatası: $e'));
  }

  // ---------------------------------------------------------------------------
  // Hesaplama (saf fonksiyon — IO yok, test edilebilir)
  // ---------------------------------------------------------------------------
  _StreakState _computeNext({
    required _StreakState? current,
    required String todayStr,
    required String yesterdayStr,
    required String weekKey,
    required int weekday,
  }) {
    int streak          = current?.streakCount ?? 0;
    String lastDate     = current?.lastActiveDate ?? '';
    List<int> activeDays = List<int>.from(current?.weeklyActiveDays ?? []);
    String dbWeekKey    = current?.currentWeekKey ?? '';

    final isAlreadyActiveToday = lastDate == todayStr;

    if (dbWeekKey != weekKey) activeDays.clear();

    if (!isAlreadyActiveToday) {
      streak = (lastDate == yesterdayStr) ? streak + 1 : 1;
    } else if (isTestMode && streak == 0) {
      streak = 1;
    }

    if (!activeDays.contains(weekday)) activeDays.add(weekday);

    return _StreakState(
      lastActiveDate:   todayStr,
      streakCount:      streak,
      currentWeekKey:   weekKey,
      weeklyActiveDays: activeDays,
    );
  }

  // ---------------------------------------------------------------------------
  // Firestore yazma (arka planda)
  // ---------------------------------------------------------------------------
  Future<void> _saveToFirestore(String uid, _StreakState state) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'lastActiveDate':   state.lastActiveDate,
      'streakCount':      state.streakCount,
      'currentWeekKey':   state.currentWeekKey,
      'weeklyActiveDays': state.weeklyActiveDays,
    }, SetOptions(merge: true));
  }

  String _dayStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _weekKey(DateTime d) {
    final monday = d.subtract(Duration(days: d.weekday - 1));
    return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
  }
}

class _StreakState {
  final String    lastActiveDate;
  final int       streakCount;
  final String    currentWeekKey;
  final List<int> weeklyActiveDays;

  const _StreakState({
    required this.lastActiveDate,
    required this.streakCount,
    required this.currentWeekKey,
    required this.weeklyActiveDays,
  });
}