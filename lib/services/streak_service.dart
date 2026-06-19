import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/streak_bottom_sheet.dart';

class StreakService {
  static final StreakService instance = StreakService._internal();
  StreakService._internal();

  // 🔥 TEST MODU: 1 seride bile çıkar ve spam korumasını ezer.
  // ÇALIŞTIĞINI GÖZÜNLE GÖRDÜKTEN SONRA BURAYI FALSE YAP!
  final bool isTestMode = true; 

  Future<void> triggerAction(BuildContext context) async {
    // 1. KESİN ÇÖZÜM: Widget'ın o uçucu context'i ölmeden önce, 
    // uygulamanın asla ölmeyen en üst "KÖK NAVIGATOR"ını yakalayıp hapsediyoruz!
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final now = DateTime.now();
    final todayStr = _getDayString(now);
    final yesterdayStr = _getDayString(now.subtract(const Duration(days: 1)));
    
    final currentWeekKey = _getWeekKey(now); 
    final currentWeekday = now.weekday;

    try {
      final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final doc = await docRef.get();
      final data = doc.data() ?? {};

      final lastActiveDate = data['lastActiveDate'] as String?;
      int streakCount = data['streakCount'] ?? 0;
      String dbWeekKey = data['currentWeekKey'] ?? '';
      List<int> weeklyActiveDays = List<int>.from(data['weeklyActiveDays'] ?? []);

      bool isAlreadyActiveToday = (lastActiveDate == todayStr);

      // 2. SPAM KORUMASI: Bugün eklendiyse ve Test modunda değilsek umursama
      if (isAlreadyActiveToday && !isTestMode) return; 

      // 3. HAFTA TEMİZLİĞİ: Yeni haftaya geçildiyse günleri sıfırla
      if (dbWeekKey != currentWeekKey) weeklyActiveDays.clear();

      // 4. SERİ HESAPLAMASI
      if (!isAlreadyActiveToday) {
        // Bugün ilk defa ekliyorsa
        if (lastActiveDate == yesterdayStr) {
          streakCount++; 
        } else {
          streakCount = 1; 
        }
      } else if (isTestMode) {
        // Test modundaysa ve bugün eklemişse seriyi en az 1 yap ki ekran çıksın
        streakCount = streakCount == 0 ? 1 : streakCount;
      }

      if (!weeklyActiveDays.contains(currentWeekday)) {
        weeklyActiveDays.add(currentWeekday);
      }

      // 5. SUNUCUYA KAYIT
      await docRef.set({
        'lastActiveDate': todayStr,
        'streakCount': streakCount,
        'currentWeekKey': currentWeekKey,
        'weeklyActiveDays': weeklyActiveDays,
      }, SetOptions(merge: true));

      final int requiredStreak = isTestMode ? 1 : 2;

      if (streakCount >= requiredStreak) {
        // 6. EKRANA ZORLA BASTIRMA:
        // Yarım saniye bekle (eski pencereler kapansın diye), 
        // ardından widget ölmüş olsa bile ROOT NAVIGATOR üzerinden ekranı fırlat!
        Future.delayed(const Duration(milliseconds: 500), () {
          if (rootNavigator.mounted) {
            showModalBottomSheet(
              context: rootNavigator.context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (ctx) => StreakBottomSheet(streak: streakCount, activeDays: weeklyActiveDays),
            );
          }
        });
      }
      
    } catch (e) {
      debugPrint('Streak Service Hatası: $e');
    }
  }

  String _getDayString(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  String _getWeekKey(DateTime date) {
    int daysToSubtract = date.weekday - 1;
    DateTime monday = date.subtract(Duration(days: daysToSubtract));
    return "${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}";
  }
}