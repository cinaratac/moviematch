import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/gamification.dart';

class GamificationService {
  GamificationService._();
  static final instance = GamificationService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // --- ROZET KONTROL SİSTEMİ ---
  Future<void> checkAndAwardBadges() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final userDocRef = _db.collection('users').doc(user.uid);
    final userDoc = await userDocRef.get();
    if (!userDoc.exists) return;
    
    final data = userDoc.data()!;
    final currentBadges = List<String>.from(data['badges'] ?? []);
    final List<String> newBadges = [];

    // 1. Film Kurdu Kontrolü (Benzersiz Film Sayısı)
    // Letterboxd'dan gelenler de bu alanlara yazıldığı için otomatik olarak sayılır.
    final favs = List<String>.from(data['favoritesKeys'] ?? []);
    final fives = List<String>.from(data['fiveStarKeys'] ?? []);
    final watch = List<String>.from(data['watchlistKeys'] ?? []);
    final disliked = List<String>.from(data['dislikedKeys'] ?? []); // Sevmedikleri de bir "kayıt" sayılabilir

    // Set kullanarak mükerrer kayıtları (hem favori hem 5 yıldız olanları) eliyoruz
    final uniqueMovies = {...favs, ...fives, ...watch, ...disliked};
    final totalMovies = uniqueMovies.length;

    _checkRule(AppBadge.allBadges.firstWhere((b) => b.type == BadgeType.filmBuff), totalMovies, currentBadges, newBadges);

    // 2. Eleştirmen Kontrolü
    final postsQuery = await _db.collection('posts')
        .where('authorId', isEqualTo: user.uid)
        .where('isReview', isEqualTo: true)
        .count()
        .get();
    final reviewCount = postsQuery.count ?? 0;
    _checkRule(AppBadge.allBadges.firstWhere((b) => b.type == BadgeType.critic), reviewCount, currentBadges, newBadges);

    // 3. Arşivci Kontrolü
    final listQuery = await _db.collection('custom_lists')
        .where('ownerId', isEqualTo: user.uid)
        .count()
        .get();
    final listCount = listQuery.count ?? 0;
    _checkRule(AppBadge.allBadges.firstWhere((b) => b.type == BadgeType.archivist), listCount, currentBadges, newBadges);

    // Veritabanına Yaz
    if (newBadges.isNotEmpty) {
      await userDocRef.update({
        'badges': FieldValue.arrayUnion(newBadges)
      });
    }
  }

  void _checkRule(AppBadge badge, int currentValue, List<String> owned, List<String> toAdd) {
    if (currentValue >= badge.threshold && !owned.contains(badge.id)) {
      toAdd.add(badge.id);
    }
  }

  // --- LİDERLİK TABLOLARI ---
  Future<List<LeaderboardUser>> getWeeklyTopUsers() async {
    // Takipçi sayısına göre sıralama
    final qs = await _db.collection('users')
        .orderBy('followersCount', descending: true) // Bu alanın user'da tutulduğundan emin olun
        .limit(10)
        .get();

    return qs.docs.asMap().entries.map((entry) {
      final idx = entry.key;
      final d = entry.value.data();
      
      return LeaderboardUser(
        uid: entry.value.id,
        rank: idx + 1,
        displayName: d['displayName'] ?? d['username'] ?? 'Kullanıcı',
        photoURL: d['photoURL'],
        score: (d['followersCount'] ?? 0) as int,
      );
    }).toList();
  }
}