import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fluttergirdi/services/letterboxd_service.dart';
import 'package:fluttergirdi/auth/auth_gate.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:fluttergirdi/services/user_profile_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _lbUsername;
  Future<List<LetterboxdFilm>>? _futureFavs;
  final _profileSvc = UserProfileService();
  StreamSubscription? _profileSub;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _attachProfileStream();
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
    });
  }

  void _attachProfileStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _profileSub?.cancel();
    if (uid == null) return;
    _profileSub = _profileSvc.profileStream(uid).listen((profile) async {
      final lb = profile?.letterboxdUsername?.trim();
      if (lb == null || lb.isEmpty) return;
      // Yerelde de güncel tut
      final sp = await SharedPreferences.getInstance();
      await sp.setString('lb_username_$uid', lb);
      if (!mounted) return;
      setState(() {
        _lbUsername = lb;
        _futureFavs = LetterboxdService.fetchFavorites(lb);
      });
    });
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    super.dispose();
  }

  String _shownName(User user) {
    final dn = (user.displayName ?? '').trim();
    if (dn.isNotEmpty) return dn; // önce displayName
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
        });
      } else {
        await sp.setString(key, result);
        setState(() {
          _lbUsername = result;
          _futureFavs = LetterboxdService.fetchFavorites(result);
        });
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          await _profileSvc.setLetterboxdUsername(result);
        }
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
    });
    final uid2 = FirebaseAuth.instance.currentUser?.uid;
    if (uid2 != null) {
      await _profileSvc.clearLetterboxdUsername();
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Bağlantı açılamadı.')));
      }
    }
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
    });
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

        final displayName = _shownName(user);
        final email = user.email ?? '—';
        ImageProvider? avatarImage;
        if (user.photoURL != null && user.photoURL!.isNotEmpty) {
          avatarImage = NetworkImage(user.photoURL!);
        }

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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Favori Filmler',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (_lbUsername != null)
                        TextButton(
                          onPressed: () =>
                              _openUrl('https://letterboxd.com/$_lbUsername/'),
                          child: const Text('Profili aç'),
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
                                child: InkWell(
                                  onTap: () => _openUrl(f.url),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.network(
                                        f.posterUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: Colors.grey.shade800,
                                          child: Center(
                                            child: Padding(
                                              padding: const EdgeInsets.all(
                                                8.0,
                                              ),
                                              child: Text(
                                                f.title,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Align(
                                        alignment: Alignment.bottomCenter,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 4,
                                          ),
                                          color: Colors.black54,
                                          child: Text(
                                            f.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.white,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ],

                const SizedBox(height: 24),
                Text(
                  'Top 10 Films',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 140,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 10,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, i) => AspectRatio(
                      aspectRatio: 2 / 3,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Theme.of(context).colorScheme.surfaceContainer,
                        ),
                        child: Center(child: Text('#${i + 1}')),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
