
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fluttergirdi/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

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
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
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
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        setState(() => _notificationsEnabled = false);
        _toast('Bildirim izni verilmedi.');
        return;
      }
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'notificationsEnabled': value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_enabled', value);
    } catch (e) {
      setState(() => _notificationsEnabled = !value);
      _toast('Hata: $e');
    }
  }

  // --- Yardımcı Fonksiyonlar ---
  
  Future<String?> _promptText({required String title, String? initial, String? hint, TextInputType? keyboardType}) async {
    final ctrl = TextEditingController(text: initial ?? '');
    // Platform kontrolü burada yapılabilir, şimdilik standart dialog
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(hintText: hint),
            keyboardType: keyboardType,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Vazgeç')),
            TextButton(onPressed: () => Navigator.of(context).pop(ctrl.text.trim()), child: const Text('Tamam')),
          ],
        );
      },
    );
  }

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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Kaldır', style: TextStyle(color: Colors.red))),
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
      final snap = await FirebaseFirestore.instance.collection('users').doc(_user!.uid).get();
      if (snap.data()?['themeMode'] is String) current = snap.data()!['themeMode'];
    } catch (_) {}

    if (!mounted) return;
    String selected = current;
    
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Text("Görünüm", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _ThemeOption(label: 'Aydınlık', val: 'light', group: selected, icon: Icons.light_mode_rounded, onTap: (v) => setSheetState(() => selected = v)),
              _ThemeOption(label: 'Karanlık', val: 'dark', group: selected, icon: Icons.dark_mode_rounded, onTap: (v) => setSheetState(() => selected = v)),
              _ThemeOption(label: 'Sistem', val: 'system', group: selected, icon: Icons.settings_suggest_rounded, onTap: (v) => setSheetState(() => selected = v)),
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
                      // DEĞİŞİKLİK: Metin rengini contrastı garanti eden onPrimary olarak ayarlıyoruz.
                      foregroundColor: Theme.of(context).colorScheme.onPrimary, 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.pop(context, selected),
                    child: const Text("Uygula", style: TextStyle(fontWeight: FontWeight.bold)),
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
    } catch (_) {} finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
  showCupertinoDialog(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: const Text('Çıkış Yap'),
      content: const Text('Hesabınızdan çıkış yapmak istediğinize emin misiniz?'),
      actions: [
        CupertinoDialogAction(
          child: const Text('Vazgeç'), 
          onPressed: () => Navigator.pop(ctx)
        ),
        CupertinoDialogAction(
          isDestructiveAction: true,
          child: const Text('Çıkış'),
          onPressed: () async {
            // 1. Önce diyaloğu kapat
            Navigator.pop(ctx); 
            
            // 2. Firebase'den çıkış yap
            await FirebaseAuth.instance.signOut();
            
            // 3. KRİTİK ADIM: Tüm sayfaları kapat ve en başa (Login'e) dön
            if (mounted) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          },
        ),
      ],
    ),
  );
}

 

  // lib/screens/settings_page.dart içinde _deleteAccount fonksiyonunu bununla değiştirin:

Future<void> _deleteAccount() async {
  // 1. Onay Diyaloğu
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Hesabı Sil'),
      content: const Text(
          'Bu işlem geri alınamaz. Profiliniz ve tüm verileriniz kalıcı olarak silinecektir.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Sil', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );

  if (confirm != true) return;

  final user = _user;
  if (user == null || user.email == null) return;

  // 2. Güvenlik Doğrulaması (Şifre İste)
  final password = await _promptText(
    title: 'Güvenlik Doğrulaması',
    hint: 'Hesabınızı silmek için şifrenizi girin',
    keyboardType: TextInputType.visiblePassword,
  );

  if (password == null || password.isEmpty) return;

  setState(() => _busy = true);

  try {
    // 3. Re-Authenticate (Tekrar Giriş Yaparak Yetki Tazele)
    AuthCredential credential = EmailAuthProvider.credential(
      email: user.email!,
      password: password,
    );
    await user.reauthenticateWithCredential(credential);

    // 4. Verileri Sil (Firestore Batch)
    final uid = user.uid;
    final batch = FirebaseFirestore.instance.batch();

    // Kullanıcı dokümanlarını sil
    batch.delete(FirebaseFirestore.instance.collection('users').doc(uid));
    batch.delete(FirebaseFirestore.instance.collection('userTasteProfiles').doc(uid));
    batch.delete(FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('recommendations')
        .doc('feed'));

    await batch.commit();

    // 5. Hesabı Sil (Authentication)
    await user.delete();

    // 6. KRİTİK ADIM: Yönlendirme
    if (mounted) {
      // Tüm sayfaları kapat, AuthGate (Login) ekranına düş
      Navigator.of(context).popUntil((route) => route.isFirst);
    }

  } on FirebaseAuthException catch (e) {
    if (e.code == 'wrong-password') {
      _toast('Hatalı şifre.');
    } else {
      _toast('Hata: ${e.message}');
    }
  } catch (e) {
    _toast('Bir sorun oluştu: $e');
  } finally {
    if (mounted) setState(() => _busy = false);
  }
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
            Text('Sürüm 1.0.0\n\nFilm zevklerini eşleştiren sosyal platform.\n© 2024 Kozmosoft'),
          ],
        ),
        actions: [
          // --- EKLENEN KISIM: LİSANSLAR BUTONU ---
          CupertinoDialogAction(
            child: const Text('Lisanslar'),
            onPressed: () {
              Navigator.pop(ctx); // Önce diyaloğu kapat
              // Flutter'ın yerleşik lisans sayfasını aç
              showLicensePage(
                context: context,
                applicationName: 'CineMatch',
                applicationVersion: '1.0.0',
                applicationLegalese: '© 2024 Kozmosoft',
                applicationIcon: const Icon(Icons.movie_filter_rounded, size: 48),
              );
            },
          ),
          // ----------------------------------------
          CupertinoDialogAction(
            child: const Text('Tamam'), 
            onPressed: () => Navigator.pop(ctx)
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
            Text('cinematch.app.dev@gmail.com', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          CupertinoDialogAction(child: const Text('Tamam'), onPressed: () => Navigator.pop(ctx)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7); 
    final sectionColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF); 

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Ayarlar', style: TextStyle(fontWeight: FontWeight.w600)),
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
                ],
              ),

              // BÖLÜM 3: DESTEK & BİLGİ
              _SettingsSection(
                title: "UYGULAMA",
                sectionColor: sectionColor,
                children: [
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
              SizedBox(height: 10,),
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
              SizedBox(height: 5,),
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
                    child: Divider(height: 1, color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                  ),
              ]
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
                  color: (iconColor ?? Colors.blue).withValues(alpha: 0.15), // DÜZELTİLDİ: withValues
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
                  activeTrackColor: Theme.of(context).primaryColor, // DÜZELTİLDİ: activeTrackColor
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
                  const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
                ],
              )
            else if (!centerText)
              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
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

  const _ThemeOption({required this.label, required this.val, required this.group, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool isSelected = val == group;
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: isSelected ? theme.primaryColor : Colors.grey),
      title: Text(label, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      trailing: isSelected ? Icon(Icons.check_circle, color: theme.primaryColor) : const Icon(Icons.circle_outlined, color: Colors.grey),
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