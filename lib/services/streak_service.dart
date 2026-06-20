import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/streak_bottom_sheet.dart';

class StreakService {
  static final StreakService instance = StreakService._internal();
  StreakService._internal();

  // 🔥 TEST MODU: true iken 1 seride bile gösterir, spam korumasını ezer.
  // Çalıştığını gördükten sonra false yap.
  final bool isTestMode = true;

  // ---------------------------------------------------------------------------
  // In-memory cache: son Firestore okumasının sonucunu tutar.
  // Sheet her açılışında Firestore'a gitmek yerine buradan okur.
  // ---------------------------------------------------------------------------
  _StreakState? _cached;
  String? _cachedUid;

  // ---------------------------------------------------------------------------
  // Ana giriş noktası.
  // Önce cache/tahmini state ile UI'ı anında gösterir,
  // sonra arka planda Firestore'a kaydeder.
  // ---------------------------------------------------------------------------
  Future<void> triggerAction(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Root navigator'ı şimdi yakala (context ölmeden önce).
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    final now        = DateTime.now();
    final todayStr   = _dayStr(now);
    final weekday    = now.weekday;
    final weekKey    = _weekKey(now);
    final yesterday  = _dayStr(now.subtract(const Duration(days: 1)));

    // 1. Cache'den oku (Firestore bekleme yok)
    final cached = (_cachedUid == uid) ? _cached : null;

    // 2. Tahmini yeni state'i hesapla
    final next = _computeNext(
      current: cached,
      todayStr: todayStr,
      yesterdayStr: yesterday,
      weekKey: weekKey,
      weekday: weekday,
    );

    // 3. Spam koruma (test modunda pas geç)
    final alreadyShownToday = cached?.lastActiveDate == todayStr && !isTestMode;
    if (alreadyShownToday) return;

    // 4. Cache'i anında güncelle
    _cached    = next;
    _cachedUid = uid;

    // 5. Yeterli seri varsa UI'ı HEMEN göster (Firestore bitmesini bekleme)
    final required = isTestMode ? 1 : 2;
    if (next.streakCount >= required) {
      // Eğer sheet az önce kapandıysa tek frame bekle, hepsi bu.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (rootNavigator.mounted) {
          showModalBottomSheet(
            context: rootNavigator.context,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => StreakBottomSheet(
              streak: next.streakCount,
              activeDays: next.weeklyActiveDays,
            ),
          );
        }
      });
    }

    // 6. Firestore'a arka planda kaydet (UI'ı bloklamaz)
    _saveToFirestore(uid, next).catchError(
      (e) => debugPrint('Streak kayıt hatası: $e'),
    );
  }

  // ---------------------------------------------------------------------------
  // Cache'i dışarıdan önceden doldur (örn. profil sayfası açılınca).
  // Bu sayede ilk triggerAction() çağrısında Firestore'a hiç gidilmez.
  // ---------------------------------------------------------------------------
  Future<void> preload(String uid) async {
    if (_cachedUid == uid && _cached != null) return; // Zaten var
    try {
      final doc  = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.cache));
      _applyDoc(uid, doc);
    } catch (_) {
      // Cache'de yoksa server'dan dene
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
    final d = doc.data() as Map<String, dynamic>? ?? {};
    _cached = _StreakState(
      lastActiveDate:  (d['lastActiveDate'] as String?) ?? '',
      streakCount:     (d['streakCount']    as num?)?.toInt() ?? 0,
      currentWeekKey:  (d['currentWeekKey'] as String?) ?? '',
      weeklyActiveDays: List<int>.from(d['weeklyActiveDays'] ?? []),
    );
    _cachedUid = uid;
  }

  // ---------------------------------------------------------------------------
  // Yeni state hesapla (saf fonksiyon, IO yok)
  // ---------------------------------------------------------------------------
  _StreakState _computeNext({
    required _StreakState? current,
    required String todayStr,
    required String yesterdayStr,
    required String weekKey,
    required int weekday,
  }) {
    int streak = current?.streakCount ?? 0;
    String lastDate = current?.lastActiveDate ?? '';
    List<int> activeDays = List<int>.from(current?.weeklyActiveDays ?? []);
    String dbWeekKey = current?.currentWeekKey ?? '';

    final isAlreadyActiveToday = lastDate == todayStr;

    // Yeni haftaya geçildiyse günleri sıfırla
    if (dbWeekKey != weekKey) activeDays.clear();

    if (!isAlreadyActiveToday) {
      if (lastDate == yesterdayStr) {
        streak++; // Seri devam ediyor
      } else {
        streak = 1; // Seri koptu, sıfırdan başla
      }
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
  // Firestore yazma (arka planda, UI bloklamaz)
  // ---------------------------------------------------------------------------
  Future<void> _saveToFirestore(String uid, _StreakState state) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'lastActiveDate':   state.lastActiveDate,
      'streakCount':      state.streakCount,
      'currentWeekKey':   state.currentWeekKey,
      'weeklyActiveDays': state.weeklyActiveDays,
    }, SetOptions(merge: true));
  }

  // ---------------------------------------------------------------------------
  // Yardımcılar
  // ---------------------------------------------------------------------------
  String _dayStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _weekKey(DateTime d) {
    final monday = d.subtract(Duration(days: d.weekday - 1));
    return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Basit immutable state modeli
// ---------------------------------------------------------------------------
class _StreakState {
  final String lastActiveDate;
  final int    streakCount;
  final String currentWeekKey;
  final List<int> weeklyActiveDays;

  const _StreakState({
    required this.lastActiveDate,
    required this.streakCount,
    required this.currentWeekKey,
    required this.weeklyActiveDays,
  });
}