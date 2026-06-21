import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../auth/login_page.dart';
import 'package:fluttergirdi/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart'; // Önbellek temizliği için
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:fluttergirdi/screens/blocked_users_screen.dart';
import 'package:flutter_cached_pdfview/flutter_cached_pdfview.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;
  bool _notificationsEnabled = true;

  User? get _user => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _loadNotificationPreferences();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _loadNotificationPreferences() async {
    final user = _user;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getBool('notifications_enabled');
    if (local != null) {
      if (mounted) setState(() => _notificationsEnabled = local);
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data();
        final serverEnabled = data?['notificationsEnabled'];
        if (serverEnabled is bool) {
          if (mounted) setState(() => _notificationsEnabled = serverEnabled);
          await prefs.setBool('notifications_enabled', serverEnabled);
        }
      }
    } catch (_) {}
  }

  Future<void> _toggleNotifications(bool value) async {
    final user = _user;
    if (user == null) return;

    setState(() => _notificationsEnabled = value);

    if (value) {
      try {
        // 1. Önce cihazdaki mevcut bildirim izni durumunu kontrol et
        var settings = await FirebaseMessaging.instance
            .getNotificationSettings();

        // 2. Eğer henüz izin verilmemişse (veya reddedilmişse) izin penceresini aç
        if (settings.authorizationStatus != AuthorizationStatus.authorized &&
            settings.authorizationStatus != AuthorizationStatus.provisional) {
          settings = await FirebaseMessaging.instance.requestPermission();
        }

        // 3. Hala izin verilmediyse işlemi iptal et
        if (settings.authorizationStatus != AuthorizationStatus.authorized &&
            settings.authorizationStatus != AuthorizationStatus.provisional) {
          setState(() => _notificationsEnabled = false);
          _toast(
            'Bildirim izni verilmedi. Cihaz ayarlarından açmanız gerekebilir.',
          );
          return;
        }
      } catch (e) {
        // PushTokenService ile çakışırsa çökmeyi engelle ve devam et
        if (e.toString().contains('already running')) {
          _toast('Bildirim izinleri kontrol ediliyor...');
        } else {
          setState(() => _notificationsEnabled = false);
          _toast('İzin hatası: $e');
          return;
        }
      }
    }

    // İzinler tamamsa (veya çakışma atlatıldıysa) Firebase'e kaydet!
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'notificationsEnabled': value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_enabled', value);
    } catch (e) {
      setState(() => _notificationsEnabled = !value);
      _toast('Firebase Hatası: $e');
    }
  }

  // --- Yardımcı Fonksiyonlar ---

  Future<void> _resetPassword() async {
    final user = _user;
    if (user == null || user.email == null) {
      _toast('E-posta bulunamadı.');
      return;
    }
    setState(() => _busy = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: user.email!);
      _toast('Şifre sıfırlama bağlantısı gönderildi.');
    } catch (e) {
      _toast('Hata: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearLetterboxdSync() async {
    final user = _user;
    if (user == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bağlantıyı Kaldır'),
        content: const Text('Letterboxd verileri silinecek. Devam edilsin mi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kaldır', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    final fs = FirebaseFirestore.instance;
    final uid = user.uid;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('lb_username_$uid');

      await fs.collection('userTasteProfiles').doc(uid).set({
        'letterboxdUsername': FieldValue.delete(),
        'loved': <String>[],
        'disliked': <String>[],
        'watchlist': <String>[],
        'posters': <String, String>{},
        'vector': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await fs.collection('users').doc(uid).set({
        'lbUsername': FieldValue.delete(),
        'letterboxdUsername': FieldValue.delete(),
        'favorites': FieldValue.delete(),
        'favoritesKeys': FieldValue.delete(),
        'watchlist': FieldValue.delete(),
        'watchlistKeys': FieldValue.delete(),
        'fiveStar': FieldValue.delete(),
        'fiveStarKeys': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _toast('Eşleşme kaldırıldı.');
    } catch (e) {
      _toast('Hata: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickTheme() async {
    String current = 'system';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .get();
      if (snap.data()?['themeMode'] is String)
        current = snap.data()!['themeMode'];
    } catch (_) {}

    if (!mounted) return;
    String selected = current;

    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Text(
                "Görünüm",
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _ThemeOption(
                label: 'Aydınlık',
                val: 'light',
                group: selected,
                icon: Icons.light_mode_rounded,
                onTap: (v) => setSheetState(() => selected = v),
              ),
              _ThemeOption(
                label: 'Karanlık',
                val: 'dark',
                group: selected,
                icon: Icons.dark_mode_rounded,
                onTap: (v) => setSheetState(() => selected = v),
              ),
              _ThemeOption(
                label: 'Sistem',
                val: 'system',
                group: selected,
                icon: Icons.settings_suggest_rounded,
                onTap: (v) => setSheetState(() => selected = v),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, selected),
                    child: const Text(
                      "Uygula",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );

    if (result != null) await _applyThemeMode(result);
  }

  Future<void> _applyThemeMode(String mode) async {
    final user = _user;
    if (user == null) return;
    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'themeMode': mode,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      ThemeMode tm = ThemeMode.system;
      if (mode == 'light') tm = ThemeMode.light;
      if (mode == 'dark') tm = ThemeMode.dark;

      ThemeBridge.themeMode.value = tm;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('themeMode', mode);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Çıkış Yap'),
        content: const Text(
          'Hesabınızdan çıkış yapmak istediğinize emin misiniz?',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Vazgeç'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Çıkış'),
            onPressed: () async {
              // 1. Önce diyaloğu kapat
              Navigator.pop(ctx);

              // 2. Önbellekteki (resimler vb.) her şeyi temizle
              await DefaultCacheManager().emptyCache();

              // 3. Yerel ayarları (Shared Prefs) temizle
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();

              // 4. KRİTİK ADIM: Önce tüm sayfaları kapat ve en başa (Login'e) dön
              if (mounted) {
                Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                  (route) => false,
                );
              }

              // 5. Ekran temizlendikten sonra güvenle Firebase'den çık
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    bool confirm =
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Hesabı Sil"),
            content: const Text(
              "Hesabınızı ve tüm verilerinizi kalıcı olarak silmek istediğinize emin misiniz? Bu işlem geri alınamaz.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("İptal"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text("Evet, Sil"),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    try {
      // 1. Kullanıcının hangi yöntemle girdiğini bul (Google, Apple, Şifre)
      bool isGoogleUser = user.providerData.any(
        (info) => info.providerId == 'google.com',
      );
      bool isAppleUser = user.providerData.any(
        (info) => info.providerId == 'apple.com',
      ); // YENİ EKLENDİ

      if (isGoogleUser) {
        // --- GOOGLE İLE RE-AUTHENTICATE ---
        final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();

        if (googleUser == null) return; // İptal etti

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        await user.reauthenticateWithCredential(credential);
      } else if (isAppleUser) {
        // --- APPLE İLE RE-AUTHENTICATE (YENİ EKLENDİ) ---
        final AuthorizationCredentialAppleID appleCredential =
            await SignInWithApple.getAppleIDCredential(
              scopes: [
                AppleIDAuthorizationScopes.email,
                AppleIDAuthorizationScopes.fullName,
              ],
            );

        final OAuthProvider oAuthProvider = OAuthProvider('apple.com');
        final AuthCredential credential = oAuthProvider.credential(
          idToken: appleCredential.identityToken,
          accessToken: appleCredential.authorizationCode,
        );

        await user.reauthenticateWithCredential(credential);
      } else {
        // --- E-POSTA/ŞİFRE İLE RE-AUTHENTICATE ---
        String? password = await _showPasswordDialog();
        if (password == null) return; // İptal etti

        final AuthCredential credential = EmailAuthProvider.credential(
          email: user.email!,
          password: password,
        );

        await user.reauthenticateWithCredential(credential);
      }

      // 2. Önce Firestore Verilerini Temizle
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .delete();

      // Ekstra Not: Eğer 'userTasteProfiles' veya 'marketing_emails' tablolarında
      // bu kullanıcıya ait belge varsa onları da burada silmeniz veri gizliliği için çok iyi olur.
      // Örnek: await FirebaseFirestore.instance.collection('userTasteProfiles').doc(user.uid).delete();

      // 3. Cihazdaki Önbelleği ve Verileri Temizle
      await DefaultCacheManager().emptyCache();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // 4. Auth Hesabını Sil
      await user.delete();

      // 5. Çıkış Yap ve Login Ekranına At
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (_) => false,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Hesabınız başarıyla silindi.")),
        );
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      // YENİ EKLENDİ: Kullanıcı FaceID/TouchID ekranında işlemi iptal ederse hata popup'ı çıkmasın
      if (e.code == AuthorizationErrorCode.canceled) {
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Apple Hatası: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String errorMsg = "Bir hata oluştu.";
        if (e.code == 'wrong-password') errorMsg = "Girdiğiniz şifre yanlış.";
        if (e.code == 'requires-recent-login')
          errorMsg = "Güvenlik gereği tekrar giriş yapmalısınız.";

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Hata: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Şifre ile girenlerden şifre istemek için yardımcı fonksiyon
  Future<String?> _showPasswordDialog() async {
    String? password;
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Şifrenizi Girin"),
        content: TextField(
          obscureText: true,
          onChanged: (value) => password = value,
          decoration: const InputDecoration(
            hintText: "Mevcut şifreniz",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("İptal"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, password),
            child: const Text("Onayla"),
          ),
        ],
      ),
    );
  }

  void _showAboutApp() {
    showCupertinoDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('CineMatch'),
        content: const Column(
          children: [
            SizedBox(height: 10),
            Icon(Icons.movie_filter_rounded, size: 40, color: Colors.grey),
            SizedBox(height: 10),
            Text(
              'Sürüm 1.0.0\n\nFilm zevklerini eşleştiren sosyal platform.\n© 2024 Kozmosoft',
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Lisanslar'),
            onPressed: () {
              Navigator.pop(ctx);
              showLicensePage(
                context: context,
                applicationName: 'CineMatch',
                applicationVersion: '1.0.0',
                applicationLegalese: '© 2024 Kozmosoft',
                applicationIcon: const Icon(
                  Icons.movie_filter_rounded,
                  size: 48,
                ),
              );
            },
          ),
          CupertinoDialogAction(
            child: const Text('Tamam'),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  void _showSupportDialog() {
    showCupertinoDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Destek'),
        content: const Column(
          children: [
            Text('Görüş ve önerileriniz için:'),
            SizedBox(height: 8),
            Text(
              'cinematch.app.dev@gmail.com',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Tamam'),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }
  void _showPdfDialog(String title, String assetPath) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.9,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: const PDF(
                  enableSwipe: true,
                  swipeHorizontal: false,
                  autoSpacing: false,
                  pageFling: false,
                ).fromAsset(
                  assetPath,
                  errorWidget: (dynamic error) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 40, color: Colors.red),
                          const SizedBox(height: 10),
                          Text(
                            "Belge görüntülenemedi.\nHata: $error",
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);
    final sectionColor = isDark
        ? const Color(0xFF1C1C1E)
        : const Color(0xFFFFFFFF);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Ayarlar',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: backgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 20),
              children: [
                // BÖLÜM 1: GENEL
                _SettingsSection(
                  title: "TERCİHLER",
                  sectionColor: sectionColor,
                  children: [
                    _SettingsTile(
                      icon: Icons.notifications_rounded,
                      iconColor: Colors.redAccent,
                      title: "Bildirimler",
                      isSwitch: true,
                      switchValue: _notificationsEnabled,
                      onSwitchChanged: (v) => _toggleNotifications(v),
                    ),
                    _SettingsTile(
                      icon: Icons.palette_rounded,
                      iconColor: Colors.blueAccent,
                      title: "Görünüm",
                      trailingText: "Otomatik",
                      onTap: _pickTheme,
                    ),
                  ],
                ),

                // BÖLÜM 2: HESAP & VERİ
                _SettingsSection(
                  title: "HESAP",
                  sectionColor: sectionColor,
                  children: [
                    _SettingsTile(
                      icon: Icons.lock_rounded,
                      iconColor: Colors.grey,
                      title: "Şifre Sıfırla",
                      onTap: _resetPassword,
                    ),
                    _SettingsTile(
                      icon: Icons.link_off_rounded,
                      iconColor: Colors.orange,
                      title: "Letterboxd Bağlantısını Kes",
                      onTap: _clearLetterboxdSync,
                    ),
                    _SettingsTile(
                      icon: Icons.block_outlined,
                      iconColor: Colors.red,
                      title: "Engellenen Kullanıcılar",
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BlockedUsersScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),

                // BÖLÜM 3: DESTEK & BİLGİ
                // BÖLÜM 4: UYGULAMA & YASAL
                _SettingsSection(
                  title: "UYGULAMA",
                  sectionColor: sectionColor,
                  children: [
                    _SettingsTile(
                      icon: Icons.article_rounded,
                      iconColor: Colors.blueGrey,
                      title: "Kullanım Koşulları",
                      onTap: () {
                        // Register sayfasında kullandığınız mevcut PDF
                        _showPdfDialog("Kullanım Koşulları", "assets/docs/sozlesme.pdf");
                      },
                    ),
                    _SettingsTile(
                      icon: Icons.privacy_tip_rounded,
                      iconColor: Colors.blueGrey,
                      title: "Gizlilik Politikası",
                      onTap: () {
                        // Eğer gizlilik sözleşmesi için ayrı bir PDF'iniz varsa 
                        // ismini aşağıdan değiştirebilirsiniz (Örn: gizlilik.pdf)
                        // Şimdilik aynı PDF'i açıyor.
                        _showPdfDialog("Gizlilik Politikası", "assets/docs/sozlesme.pdf");
                      },
                    ),
                    _SettingsTile(
                      icon: Icons.mail_rounded,
                      iconColor: Colors.green,
                      title: "Destek Al",
                      onTap: _showSupportDialog,
                    ),
                    _SettingsTile(
                      icon: Icons.info_rounded,
                      iconColor: Colors.teal,
                      title: "Hakkında",
                      onTap: _showAboutApp,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // BÖLÜM 4: OTURUM
                _SettingsSection(
                  sectionColor: sectionColor,
                  children: [
                    _SettingsTile(
                      title: "Çıkış Yap",
                      textColor: Colors.blue,
                      centerText: true,
                      onTap: _logout,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                // BÖLÜM 5: TEHLİKELİ BÖLGE
                _SettingsSection(
                  footer: "Hesabınızı silmek geri alınamaz bir işlemdir.",
                  sectionColor: sectionColor,
                  children: [
                    _SettingsTile(
                      title: "Hesabı Sil",
                      textColor: Colors.red,
                      centerText: true,
                      onTap: _deleteAccount,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildTmdbAttribution(), // TMDB Atıf Widget'ı
                const SizedBox(height: 40),
              ],
            ),
    );
  }
}

// --- TASARIM BİLEŞENLERİ (APPLE STİLİ) ---

class _SettingsSection extends StatelessWidget {
  final String? title;
  final String? footer;
  final List<Widget> children;
  final Color sectionColor;

  const _SettingsSection({
    this.title,
    required this.sectionColor,
    this.children = const [],
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 16, 16, 8),
            child: Text(
              title!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                letterSpacing: 0.5,
              ),
            ),
          ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: sectionColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1)
                  Padding(
                    padding: const EdgeInsets.only(left: 56),
                    child: Divider(
                      height: 1,
                      color: isDark
                          ? Colors.grey.shade800
                          : Colors.grey.shade200,
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
            child: Text(
              footer!,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
              ),
            ),
          ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String? trailingText;
  final bool isSwitch;
  final bool switchValue;
  final Function(bool)? onSwitchChanged;
  final VoidCallback? onTap;
  final Color? textColor;
  final bool centerText;

  const _SettingsTile({
    this.icon,
    this.iconColor,
    required this.title,
    this.trailingText,
    this.isSwitch = false,
    this.switchValue = false,
    this.onSwitchChanged,
    this.onTap,
    this.textColor,
    this.centerText = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : Colors.black;

    return InkWell(
      onTap: isSwitch ? () => onSwitchChanged?.call(!switchValue) : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: (iconColor ?? Colors.blue).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 20, color: iconColor ?? Colors.blue),
              ),
              const SizedBox(width: 16),
            ],

            Expanded(
              child: Text(
                title,
                textAlign: centerText ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: textColor ?? primaryTextColor,
                ),
              ),
            ),

            if (isSwitch)
              Transform.scale(
                scale: 0.8,
                child: CupertinoSwitch(
                  value: switchValue,
                  activeTrackColor: Theme.of(context).primaryColor,
                  onChanged: onSwitchChanged,
                ),
              )
            else if (trailingText != null)
              Row(
                children: [
                  Text(
                    trailingText!,
                    style: const TextStyle(fontSize: 15, color: Colors.grey),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: Colors.grey,
                  ),
                ],
              )
            else if (!centerText)
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Colors.grey,
              ),
          ],
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String label;
  final String val;
  final String group;
  final IconData icon;
  final Function(String) onTap;

  const _ThemeOption({
    required this.label,
    required this.val,
    required this.group,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isSelected = val == group;
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: isSelected ? theme.primaryColor : Colors.grey),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: theme.primaryColor)
          : const Icon(Icons.circle_outlined, color: Colors.grey),
      onTap: () => onTap(val),
      
    );
    
    
    
    
  }
}

// TMDB Atıf Widget'ı
Widget _buildTmdbAttribution() {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Divider(), // Üstüne ince bir çizgi çeker, şık durur
      const SizedBox(height: 20),

      // LOGO KISMI
      Opacity(
        opacity: 0.8, // Logoyu çok az şeffaf yapar, bağırmaz
        child: Image.asset(
          'assets/images/tmdb_logo.png', // Dosya yolun burası
          width: 60, // İdeal boyut
          height: 60,
        ),
      ),

      const SizedBox(height: 10),

      // ZORUNLU METİN KISMI
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30.0),
        child: Text(
          "This product uses the TMDB API but is not endorsed or certified by TMDB.",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.grey.shade600, // Silik gri renk
            fontSize: 10, // Çok küçük font (Caption tarzı)
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
      const SizedBox(height: 30), // En altta biraz boşluk bırakır
    ],
  );
}
