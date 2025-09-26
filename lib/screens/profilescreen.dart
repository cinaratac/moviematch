import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluttergirdi/services/letterboxd_service.dart';
import 'package:fluttergirdi/services/match_service.dart';
import 'package:fluttergirdi/auth/auth_gate.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _lbUsername;
  String? _appUsername;
  Future<List<LetterboxdFilm>>? _futureFavs;
  Future<List<LetterboxdFilm>>? _futureFiveStar;
  Future<List<LetterboxdFilm>>? _futureDisliked;
  bool _autoSynced = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final sp = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;

    // Eski global anahtar -> kullanıcıya özel anahtara tek seferlik taşıma
    final oldGlobal = sp.getString('lb_username');
    if (uid != null && oldGlobal != null) {
      await sp.setString('lb_username_$uid', oldGlobal);
      await sp.remove('lb_username');
    }

    final u = uid != null
        ? sp.getString('lb_username_$uid')
        : sp.getString('lb_username');
    setState(() {
      _lbUsername = u;
      _futureFavs = (u == null || u.isEmpty)
          ? null
          : LetterboxdService.fetchFavorites(u);
      _futureFiveStar = (u == null || u.isEmpty)
          ? null
          : LetterboxdService.fetchFiveStar(u);
      _futureDisliked = (u == null || u.isEmpty)
          ? null
          : LetterboxdService.fetchDisliked(u);
    });
    // Auto-sync once per session if LB username exists and Firestore is missing data
    if (!_autoSynced && u != null && u.isNotEmpty && uid != null) {
      try {
        final db = FirebaseFirestore.instance;
        final usersDoc = await db.collection('users').doc(uid).get();
        final tasteDoc = await db
            .collection('userTasteProfiles')
            .doc(uid)
            .get();
        final hasFavKeys = List.from(
          (usersDoc.data() ?? const {})['favoritesKeys'] ?? const [],
        ).isNotEmpty;
        final hasFive = List.from(
          (tasteDoc.data() ?? const {})['fiveStars'] ?? const [],
        ).isNotEmpty;
        if (!hasFavKeys || !hasFive) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _syncLetterboxdToFirestore(u);
          });
        }
        _autoSynced = true;
      } catch (_) {
        // ignore; manual refresh or next open will try again
      }
    }
  }

  /// Upsert film docs into `catalog_films/{filmKey}` so posters/titles resolve in UI
  Future<void> _upsertCatalogFromList(List<LetterboxdFilm> films) async {
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    for (final f in films) {
      if ((f.key).isEmpty) continue;
      final ref = db.collection('catalog_films').doc(f.key);
      batch.set(ref, {
        'title': f.title,
        'url': f.url,
        'posterUrl': f.posterUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  /// Writes fiveStars and lowRatings into `userTasteProfiles/{uid}`
  Future<void> _writeTasteProfile({
    required String uid,
    required String lbUsername,
    required List<LetterboxdFilm> fiveStars,
    required List<LetterboxdFilm> lowRatings,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final db = FirebaseFirestore.instance;
    final doc = db.collection('userTasteProfiles').doc(uid);
    await doc.set({
      'fiveStars': fiveStars
          .map((e) => e.key)
          .where((k) => k.isNotEmpty)
          .toList(),
      'lowRatings': lowRatings
          .map((e) => e.key)
          .where((k) => k.isNotEmpty)
          .toList(),
      'profile': {
        'displayName': user?.displayName,
        'letterboxdUsername': lbUsername,
        'avatarUrl': user?.photoURL,
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Full sync: favorites -> users/{uid}.favoritesKeys, fiveStars/lowRatings -> userTasteProfiles/{uid}
  Future<void> _syncLetterboxdToFirestore(String lbUsername) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || lbUsername.isEmpty) return;

    // 1) Favorites: fills users/{uid}.favoritesKeys and catalog
    final favorites = await LetterboxdService.syncFavoritesToFirestore(
      lbUsername: lbUsername,
    );

    // 2) Five stars & low ratings; also upsert catalogs so posters resolve
    final five = await LetterboxdService.fetchFiveStar(lbUsername);
    final low = await LetterboxdService.fetchDisliked(lbUsername);
    await _upsertCatalogFromList(five);
    await _upsertCatalogFromList(low);

    // 3) Mirror disliked into users/{uid}.dislikedKeys as well (and catalog already upserted above)
    try {
      await LetterboxdService.syncDislikedToFirestore(lbUsername: lbUsername);
    } catch (_) {
      // optional: ignore if not available
    }

    // 4) Write taste profile for 5★ and low ratings
    await _writeTasteProfile(
      uid: uid,
      lbUsername: lbUsername,
      fiveStars: five,
      lowRatings: low,
    );

    // 5) Sync bitti: ortak 5★/favori veya ortak disliked olanlar için otomatik eşleşme oluştur
    try {
      await MatchService().autoCreateMatches(
        uid,
        minCommonFive: 1,
        minCommonFav: 1,
        minCommonDisliked: 1,
      );
    } catch (e) {
      // Sessiz geç; eşleşme oluşmasa da uygulama çalışmaya devam etsin
      debugPrint('autoCreateMatches error: $e');
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  String _shownName(User user) {
    final local = (_appUsername ?? '').trim();
    if (local.isNotEmpty) {
      return local; // Firestore'daki uygulama kullanıcı adı öncelikli
    }
    final dn = (user.displayName ?? '').trim();
    if (dn.isNotEmpty) return dn; // sonra Firebase Auth displayName
    final email = user.email ?? '';
    return email.contains('@') ? email.split('@').first : 'Kullanıcı';
  }

  Future<void> _promptLetterboxdUsername() async {
    final controller = TextEditingController(text: _lbUsername ?? '');
    final re = RegExp(r'^[A-Za-z0-9_.-]{2,30}$');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String? err;
        return StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            title: const Text('Letterboxd kullanıcı adı'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    prefixText: 'letterboxd.com/',
                    hintText: 'kullaniciadi',
                    errorText: err,
                  ),
                  onChanged: (v) {
                    final ok = re.hasMatch(v.trim());
                    setSt(
                      () => err = ok || v.trim().isEmpty
                          ? null
                          : 'Geçersiz kullanıcı adı',
                    );
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sadece harf, rakam, nokta, tire ve alt tire. Örn: silhouettofaman',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () {
                  final v = controller.text.trim();
                  if (v.isNotEmpty && !re.hasMatch(v)) {
                    setSt(() {}); // errorText already set via onChanged
                    return;
                  }
                  Navigator.pop(ctx, v);
                },
                child: const Text('Kaydet'),
              ),
            ],
          ),
        );
      },
    );

    if (result != null) {
      final sp = await SharedPreferences.getInstance();
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final key = uid != null ? 'lb_username_$uid' : 'lb_username';

      if (result.isEmpty) {
        await sp.remove(key);
        setState(() {
          _lbUsername = null;
          _futureFavs = null;
          _futureDisliked = null;
        });
      } else {
        await sp.setString(key, result);
        setState(() {
          _lbUsername = result;
          _futureFavs = LetterboxdService.fetchFavorites(result);
          _futureFiveStar = LetterboxdService.fetchFiveStar(result);
          _futureDisliked = LetterboxdService.fetchDisliked(result);
        });
        // NEW: auto-sync to Firestore
        await _syncLetterboxdToFirestore(result);
      }
    }
  }

  Future<void> _clearLetterboxdUsername() async {
    final sp = await SharedPreferences.getInstance();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final key = uid != null ? 'lb_username_$uid' : 'lb_username';
    await sp.remove(key);
    setState(() {
      _lbUsername = null;
      _futureFavs = null;
      _futureFiveStar = null;
      _futureDisliked = null;
    });
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final db = FirebaseFirestore.instance;
        await db.collection('users').doc(uid).set({
          'favoritesKeys': [],
          'dislikedKeys': [],
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await db.collection('userTasteProfiles').doc(uid).set({
          'fiveStars': [],
          'lowRatings': [],
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {}
    // Removed Firestore update
  }

  Widget _posterTile(LetterboxdFilm f) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            f.posterUrl,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            headers: LetterboxdService.imageHeaders,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                color: Colors.black12,
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            },
            errorBuilder: (_, __, ___) => Container(
              color: Colors.grey.shade800,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    _noYear(f.title),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              color: Colors.black54,
              child: Text(
                _noYear(f.title),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Zorla yenile: cache'i temizleyip tekrar çekmek için
  Future<void> _refreshFavorites() async {
    if (_lbUsername == null || _lbUsername!.isEmpty) return;
    // Cache temizle
    final sp = await SharedPreferences.getInstance();
    final key = 'lb_cache_${_lbUsername!.toLowerCase()}';
    await sp.remove(key);
    await sp.remove('${key}_time');
    // Yeniden çek
    setState(() {
      _futureFavs = LetterboxdService.fetchFavorites(_lbUsername!);
      _futureFiveStar = LetterboxdService.fetchFiveStar(_lbUsername!);
      _futureDisliked = LetterboxdService.fetchDisliked(_lbUsername!);
    });
  }

  String _noYear(String t) {
    // "Movie Title (1999)" -> "Movie Title"
    return t.replaceAll(RegExp(r'\s*\(\d{4}\)$'), '');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(), // canlı dinle
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snap.data;
        if (user == null) {
          return const Scaffold(body: Center(child: Text('Oturum açılmadı')));
        }

        // Removed unused local variables

        Future<void> _resetPassword() async {
          if (user.email == null) return;
          try {
            await FirebaseAuth.instance.sendPasswordResetEmail(
              email: user.email!,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Şifre sıfırlama e-postası gönderildi.'),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Hata: $e')));
            }
          }
        }

        Future<void> _sendEmailVerification() async {
          try {
            await user.sendEmailVerification();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Doğrulama e-postası gönderildi.'),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Hata: $e')));
            }
          }
        }

        Future<void> _confirmAndLogout() async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Çıkış yapılsın mı?'),
              content: const Text(
                'Hesabınızdan çıkış yapmak istediğinize emin misiniz?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Çıkış Yap'),
                ),
              ],
            ),
          );
          if (ok == true) {
            try {
              await FirebaseAuth.instance.signOut();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const AuthGate()),
                (route) => false,
              );
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Çıkış yapılamadı: $e')));
              }
            }
          }
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Profil'),
            actions: [
              IconButton(
                tooltip: 'Yenile',
                icon: const Icon(Icons.refresh),
                onPressed: _refreshFavorites,
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  switch (value) {
                    case 'set_lb':
                      await _promptLetterboxdUsername();
                      break;
                    case 'clear_lb':
                      await _clearLetterboxdUsername();
                      break;
                    case 'reset':
                      await _resetPassword();
                      break;
                    case 'verify':
                      await _sendEmailVerification();
                      break;
                    case 'logout':
                      await _confirmAndLogout();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'set_lb',
                    child: ListTile(
                      leading: const Icon(Icons.alternate_email),
                      title: Text(
                        _lbUsername == null || _lbUsername!.isEmpty
                            ? 'Letterboxd hesabı ekle'
                            : 'Letterboxd hesabını değiştir',
                      ),
                      subtitle: _lbUsername == null || _lbUsername!.isEmpty
                          ? null
                          : Text(
                              '@${_lbUsername!}',
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                  ),
                  if (_lbUsername != null && _lbUsername!.isNotEmpty)
                    const PopupMenuItem(
                      value: 'clear_lb',
                      child: ListTile(
                        leading: Icon(Icons.link_off),
                        title: Text('Letterboxd bağlantısını kaldır'),
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'reset',
                    child: ListTile(
                      leading: Icon(Icons.lock_reset),
                      title: Text('Şifre sıfırla'),
                    ),
                  ),
                  if (!user.emailVerified)
                    const PopupMenuItem(
                      value: 'verify',
                      child: ListTile(
                        leading: Icon(Icons.mark_email_read_outlined),
                        title: Text('E-postayı doğrula'),
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'logout',
                    child: ListTile(
                      leading: Icon(Icons.logout),
                      title: Text('Çıkış yap'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              await user.reload();
              if (_lbUsername != null && _lbUsername!.isNotEmpty) {
                setState(() {
                  _futureFavs = LetterboxdService.fetchFavorites(_lbUsername!);
                  _futureFiveStar = LetterboxdService.fetchFiveStar(
                    _lbUsername!,
                  );
                });
              }
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Header
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundImage:
                          user.photoURL != null && user.photoURL!.isNotEmpty
                          ? NetworkImage(user.photoURL!)
                          : null,
                      child: (user.photoURL == null || user.photoURL!.isEmpty)
                          ? Text(
                              _shownName(user).isNotEmpty
                                  ? _shownName(user)[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(fontSize: 24),
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _shownName(user),
                            style: Theme.of(context).textTheme.titleLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user.email ?? '—',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          if (!user.emailVerified)
                            Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Row(
                                children: const [
                                  Icon(Icons.info_outline, size: 16),
                                  SizedBox(width: 6),
                                  Text('E-posta doğrulanmadı'),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                if (_lbUsername == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: const [
                        Icon(Icons.alternate_email),
                        SizedBox(width: 8),
                        Text('Letterboxd bağlı değil'),
                      ],
                    ),
                  )
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Chip(label: Text('Letterboxd: @$_lbUsername')),
                  ),

                if (_lbUsername != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        'Favori Filmler',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  FutureBuilder<List<LetterboxdFilm>>(
                    future: _futureFavs,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const SizedBox(
                          height: 180,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Favoriler alınamadı: ${snapshot.error}'),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FilledButton.icon(
                                  onPressed: _refreshFavorites,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Tekrar dene'),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      final items = snapshot.data ?? [];
                      if (items.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Favori film bulunamadı.'),
                        );
                      }
                      return SizedBox(
                        height: 180,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, i) {
                            final f = items[i];
                            return AspectRatio(
                              aspectRatio: 2 / 3,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: _posterTile(f),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        'Sevdiği Filmler',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  FutureBuilder<List<LetterboxdFilm>>(
                    future: _futureFiveStar,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const SizedBox(
                          height: 180,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('5★ filmler alınamadı: ${snapshot.error}'),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FilledButton.icon(
                                  onPressed: _refreshFavorites,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Tekrar dene'),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      final items = snapshot.data ?? [];
                      if (items.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('5★ film bulunamadı.'),
                        );
                      }
                      return SizedBox(
                        height: 180,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, i) {
                            final f = items[i];
                            return AspectRatio(
                              aspectRatio: 2 / 3,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: _posterTile(f),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        'Sevmediği Filmler',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  FutureBuilder<List<LetterboxdFilm>>(
                    future: _futureDisliked,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const SizedBox(
                          height: 180,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sevmediği filmler alınamadı: ${snapshot.error}',
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FilledButton.icon(
                                  onPressed: _refreshFavorites,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Tekrar dene'),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      final items = snapshot.data ?? [];
                      if (items.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Sevmediği film bulunamadı.'),
                        );
                      }
                      return SizedBox(
                        height: 180,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, i) {
                            final f = items[i];
                            return AspectRatio(
                              aspectRatio: 2 / 3,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: _posterTile(f),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ],

                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}
