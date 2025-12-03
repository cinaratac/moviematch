import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttergirdi/widgets/watchlist_wheel.dart'; // WatchlistMovie tanımı için
import 'package:fluttergirdi/screens/profilescreen.dart'; // UserShelfCache için

class WatchlistService {
  WatchlistService._();
  static final WatchlistService instance = WatchlistService._();
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  // Normalleştirme (Küçük harf ve trim)
  static String _norm(String s) => s.toLowerCase().trim();

  // Herhangi bir QuerySnapshot'tan film verilerini güvenli bir şekilde ayıklayan yardımcı fonksiyon
  void _processSnapshot(QuerySnapshot qs, List<Map<String, dynamic>> res) {
    for (final d in qs.docs) {
      final m = d.data() as Map<String, dynamic>?;
      if (m == null) continue;
      
      final title = (m['title'] ?? m['name'] ?? '').toString();
      final poster = (m['poster'] ?? m['posterUrl'] ?? m['image'] ?? '').toString();
      
      if (title.isNotEmpty) {
        res.add({'title': title, 'poster': poster});
      }
    }
  }

  /// Kullanıcının Watchlist verilerini 3 farklı Firestore konumundan çeker
  Future<List<Map<String, dynamic>>> _fetchUserWatchlist(String uid) async {
    final res = <Map<String, dynamic>>[];
    
    // 1. users/{uid}/watchlist alt koleksiyonu
    try {
      final qs = await _fs
          .collection('users')
          .doc(uid)
          .collection('watchlist')
          .limit(500)
          .get();
      _processSnapshot(qs, res);
    } catch (_) { /* Sessiz hata */ }

    // 2. users/{uid}/shelves/watchlist/items alt koleksiyonu
    try {
      final items = await _fs
          .collection('users')
          .doc(uid)
          .collection('shelves')
          .doc('watchlist')
          .collection('items')
          .limit(500)
          .get();
      _processSnapshot(items, res);
    } catch (_) { /* Sessiz hata */ }

    // 3. users/{uid} root dokümanındaki watchlist array'i
    try {
      final u = await _fs.collection('users').doc(uid).get();
      if (u.exists) {
        final data = u.data() ?? {};
        final arr = data['watchlist'];
        if (arr is List) {
          for (final e in arr) {
            if (e is Map) {
              final title = (e['title'] ?? e['name'] ?? '').toString();
              final poster = (e['poster'] ?? e['posterUrl'] ?? e['image'] ?? '').toString();
              if (title.isNotEmpty) res.add({'title': title, 'poster': poster});
            } else if (e is String) {
              final title = e.trim();
              if (title.isNotEmpty) res.add({'title': title, 'poster': ''});
            }
          }
        }
      }
    } catch (_) { /* Sessiz hata */ }

    // Filmleri tekilleştir ve poster varsa koru
    final byKey = <String, Map<String, dynamic>>{};
    for (final m in res) {
      final key = _norm((m['title'] ?? '').toString());
      if (key.isEmpty) continue;
      
      if (!byKey.containsKey(key)) {
        byKey[key] = m;
      } else {
        final hasPoster = ((byKey[key]!['poster'] ?? '').toString()).isNotEmpty;
        final newPoster = ((m['poster'] ?? '').toString()).isNotEmpty;
        if (!hasPoster && newPoster) {
          byKey[key] = m;
        }
      }
    }
    
    return byKey.values.toList();
  }

  /// İki kullanıcının ortak watchlist öğelerini yükler (Yerel Önbellek Fallback'i içerir)
  Future<List<WatchlistMovie>> loadSharedWatchlist(
      String myUid, String otherUid) async {
    
    // 1. Firestore'dan veri çekme
    List<Map<String, dynamic>> listA = await _fetchUserWatchlist(myUid);
    final listB = await _fetchUserWatchlist(otherUid);

    // 2. KRİTİK FALLBACK: Eğer Firestore'dan veri gelmediyse ve yerel önbellek doluysa, KENDİ LİSTENİZ için önbelleği kullanın
    if (listA.isEmpty && UserShelfCache.watchlist.isNotEmpty) {
      final cachedMovies = UserShelfCache.watchlist.map((m) {
        return {
          'title': (m['title'] ?? '').toString(),
          'poster': (m['poster'] ?? '').toString(),
        };
      }).toList();
      
      // Önbellek verisini listA'ya ekle
      listA.addAll(cachedMovies.where((m) => (m['title'] ?? '').isNotEmpty));
      
      // Tekrar temizleme (Duplikasyonları önlemek için)
      final byKey = <String, Map<String, dynamic>>{};
      for (final m in listA) {
        final key = _norm((m['title'] ?? '').toString());
        if (key.isEmpty) continue;
        if (!byKey.containsKey(key)) {
          byKey[key] = m;
        }
      }
      listA = byKey.values.toList();
    }


    // 3. Ortak Film Bulma Mantığı (listA'nın artık dolu olduğunu varsayıyoruz)
    final setB = listB
        .map((m) => _norm((m['title'] ?? '').toString()))
        .where((key) => key.isNotEmpty)
        .toSet(); 
        
    final out = <WatchlistMovie>[];

    for (final m in listA) {
      final t = (m['title'] ?? '').toString();
      if (t.isEmpty) continue;
      
      if (setB.contains(_norm(t))) {
        out.add(
          WatchlistMovie(
            title: t,
            posterUrl: (m['poster'] ?? m['posterUrl'] ?? '').toString(),
          ),
        );
      }
    }
    
    // 4. Poster Eşleştirme (Eksik posterleri diğer kullanıcının listesinden tamamlama)
    if (out.any((x) => (x.posterUrl ?? '').isEmpty)) {
        final mapB = {
          for (final m in listB)
            _norm((m['title'] ?? '').toString()):
                (m['poster'] ?? m['posterUrl'] ?? '').toString(),
        };
        for (var i = 0; i < out.length; i++) {
          final it = out[i];
          if ((it.posterUrl ?? '').isEmpty) {
            final p = mapB[_norm(it.title)] ?? '';
            if (p.isNotEmpty) {
              out[i] = WatchlistMovie(title: it.title, posterUrl: p);
            }
          }
        }
      }


    // 5. FALLBACK: Ortak film yoksa KENDİ GÜNCEL LİSTESİNİ göster
    if (out.isEmpty) {
        final seenTitles = <String>{};
        final fallbackList = <WatchlistMovie>[];
        
        // listA'yı (Firebase + Cache) tekilleştirip gösterin
        for (final m in listA) {
            final t = (m['title'] ?? '').toString();
            if (t.isEmpty) continue;
            final normT = _norm(t);
            if (seenTitles.add(normT)) {
               fallbackList.add(WatchlistMovie(
                  title: t,
                  posterUrl: (m['poster'] ?? m['posterUrl'] ?? '').toString(),
               ));
            }
        }
        return fallbackList;
    }
    
    return out;
  }
}