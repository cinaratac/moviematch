import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:fluttergirdi/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;
  final ImagePicker _picker = ImagePicker();

  User? get _user => FirebaseAuth.instance.currentUser;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<String?> _promptText({
    required String title,
    String? initial,
    String? hint,
    TextInputType? keyboardType,
  }) async {
    final ctrl = TextEditingController(text: initial ?? '');
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
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Vazgeç'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
              child: const Text('Tamam'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _setPhoto() async {
    final user = _user;
    if (user == null) return;

    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1024,
      );
      if (picked == null) return; // cancelled

      setState(() => _busy = true);

      final file = File(picked.path);
      final ref = FirebaseStorage.instance.ref().child(
        'user_photos/${user.uid}.jpg',
      );
      await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();

      await user.updatePhotoURL(url);
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'photoURL': url,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _toast('Profil fotoğrafı güncellendi');
      setState(() {});
    } catch (e) {
      _toast('Hata: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearPhoto() async {
    final user = _user;
    if (user == null) return;
    setState(() => _busy = true);
    try {
      // Clear Auth + Firestore
      await user.updatePhotoURL(null);
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'photoURL': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      // Try delete from storage (best-effort)
      final ref = FirebaseStorage.instance.ref().child(
        'user_photos/${user.uid}.jpg',
      );
      try {
        await ref.delete();
      } catch (_) {}

      _toast('Profil fotoğrafı kaldırıldı');
      setState(() {});
    } catch (e) {
      _toast('Hata: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final user = _user;
    if (user == null) return;
    final email = user.email;
    if (email == null || email.isEmpty) {
      _toast('Hesabınız bir e‑posta ile bağlı görünmüyor.');
      return;
    }
    setState(() => _busy = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _toast('Şifre sıfırlama e-postası gönderildi: $email');
    } catch (e) {
      _toast('Hata: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearLetterboxdSync() async {
    final user = _user;
    if (user == null) return;

    // Onay al
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Letterboxd eşleştirmesini kaldır?'),
        content: const Text(
          'Letterboxd’dan içe aktarılan/ eşleştirilen tüm film listeleri (favoriler, izleme listesi, beğenmedikler vb.) kaldırılacak. Devam edilsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    final fs = FirebaseFirestore.instance;
    final uid = user.uid;

    try {
      // 1) SharedPreferences: kayıtlı lb kullanıcı adını sil
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('lb_username_$uid');
      } catch (_) {}

      // 2) userTasteProfiles/{uid} belgesini temizle (Loved, Disliked, Watchlist)
      await fs.collection('userTasteProfiles').doc(uid).set({
        'letterboxdUsername': FieldValue.delete(),
        'loved': <String>[],
        'disliked': <String>[],
        'watchlist': <String>[],
        'posters': <String, String>{},
        'vector': FieldValue.delete(),
        'computedAtMs': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 3) User doc üzerindeki LB alanlarını sil (eski/mirror alanları)
      await fs.collection('users').doc(uid).set({
        'lbUsername': FieldValue.delete(),
        'lbSyncedAt': FieldValue.delete(),
        'letterboxdUsername': FieldValue.delete(),
        'letterboxdUsername_lc': FieldValue.delete(),
        // olası dizi alanları
        'favorites': FieldValue.delete(),
        'favoritesKeys': FieldValue.delete(),
        'watchlist': FieldValue.delete(),
        'watchlistKeys': FieldValue.delete(),
        'disliked': FieldValue.delete(),
        'dislikedKeys': FieldValue.delete(),
        'fiveStar': FieldValue.delete(),
        'fiveStarKeys': FieldValue.delete(),
        'liked': FieldValue.delete(),
        'likedKeys': FieldValue.delete(),
        'shelfCounts': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 4) Alt koleksiyonları temizle (varsa): shelves/*, movies, userMovies
      // shelves/*/items
      try {
        final shelvesCol = fs
            .collection('users')
            .doc(uid)
            .collection('shelves');
        final shelvesSnap = await shelvesCol.get();
        for (final shelf in shelvesSnap.docs) {
          // items alt koleksiyonunu temizle
          try {
            await _deleteQuery(shelf.reference.collection('items'));
          } catch (_) {}
          // shelf dokümanını sil
          try {
            await shelf.reference.delete();
          } catch (_) {}
        }
      } catch (_) {}

      // users/{uid}/movies
      try {
        await _deleteQuery(
          fs.collection('users').doc(uid).collection('movies'),
        );
      } catch (_) {}

      // users/{uid}/userMovies
      try {
        await _deleteQuery(
          fs.collection('users').doc(uid).collection('userMovies'),
        );
      } catch (_) {}

      _toast('Letterboxd eşleştirmesi ve filmler kaldırıldı');
    } catch (e) {
      _toast('Kaldırma hatası: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyEmail() async {
    final user = _user;
    if (user == null) return;
    if (user.email == null || user.email!.isEmpty) {
      _toast('Bu hesapta doğrulanacak bir e‑posta yok.');
      return;
    }
    if (user.emailVerified) {
      _toast('E‑posta zaten doğrulanmış.');
      return;
    }
    setState(() => _busy = true);
    try {
      await user.sendEmailVerification();
      _toast('Doğrulama e‑postası gönderildi.');
    } catch (e) {
      _toast('Hata: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickTheme() async {
    final user = _user;
    if (user == null) return;

    // read current choice from Firestore (best-effort)
    String current = 'system';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = snap.data();
      if (data != null && data['themeMode'] is String) {
        current = (data['themeMode'] as String);
      }
    } catch (_) {}

    if (!mounted) return;
    // Bottom sheet'in yerel state'i; Firestore yoksa mevcut çalışma modunu kullan
    String selected = current;
    if (selected == 'system') {
      final m = ThemeBridge.themeMode.value;
      if (m == ThemeMode.light) selected = 'light';
      if (m == ThemeMode.dark) selected = 'dark';
    }

    final String? result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(
                    title: Text('Tema'),
                    subtitle: Text('Uygulama görünümünü seçin'),
                  ),
                  RadioListTile<String>(
                    value: 'light',
                    groupValue: selected,
                    title: const Text('Aydınlık'),
                    secondary: const Icon(Icons.light_mode_outlined),
                    onChanged: (v) => setModalState(() => selected = v!),
                  ),
                  RadioListTile<String>(
                    value: 'dark',
                    groupValue: selected,
                    title: const Text('Karanlık'),
                    secondary: const Icon(Icons.dark_mode_outlined),
                    onChanged: (v) => setModalState(() => selected = v!),
                  ),
                  RadioListTile<String>(
                    value: 'system',
                    groupValue: selected,
                    title: const Text('Sistem varsayılanı'),
                    secondary: const Icon(Icons.settings_suggest_outlined),
                    onChanged: (v) => setModalState(() => selected = v!),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Vazgeç'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(context, selected),
                            child: const Text('Uygula'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      await _applyThemeMode(result);
    }
  }

  Future<void> _applyThemeMode(String mode) async {
    final user = _user;
    if (user == null) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      // persist preference for future sessions
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'themeMode': mode, // 'light' | 'dark' | 'system'
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      ThemeMode? tm;
      switch (mode) {
        case 'light':
          tm = ThemeMode.light;
          break;
        case 'dark':
          tm = ThemeMode.dark;
          break;
        default:
          tm = ThemeMode.system;
          break;
      }
      ThemeBridge.themeMode.value = tm;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('themeMode', mode); // 'light' | 'dark' | 'system'
      } catch (_) {}

      _toast('Tema kaydedildi');
    } catch (e) {
      _toast('Tema kaydedilemedi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Çıkış yapılsın mı?'),
        content: const Text('Hesabınızdan çıkış yapacaksınız.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Çıkış'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      _toast('Çıkış hatası: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteQuery(
    Query<Map<String, dynamic>> q, {
    int pageSize = 200,
  }) async {
    Query<Map<String, dynamic>> cursor = q.limit(pageSize);
    while (true) {
      final snap = await cursor.get();
      if (snap.docs.isEmpty) break;
      final batch = FirebaseFirestore.instance.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      if (snap.docs.length < pageSize) break; // done
      final last = snap.docs.last;
      cursor = q.startAfterDocument(last).limit(pageSize);
    }
  }

  Future<void> _deleteAccount() async {
    final user = _user;
    if (user == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hesabı kalıcı olarak sil?'),
        content: const Text(
          'Bu işlem geri alınamaz. Tüm eşleşmeler, beğeniler, takipçi/takip listeleri ve profil verileri silinecek. Sohbet mesajlarınız karşı taraf için korunacaktır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Evet, sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    final fs = FirebaseFirestore.instance;
    final uid = user.uid;

    try {
      // 1) Storage: profil fotoğrafını sil (best-effort)
      try {
        final ref = FirebaseStorage.instance.ref().child(
          'user_photos/$uid.jpg',
        );
        await ref.delete();
      } catch (_) {}

      // 2) likes (pair docs): uids contains uid
      await _deleteQuery(
        fs.collection('likes').where('uids', arrayContains: uid),
      );

      // 3) likeLogs: from==uid, to==uid
      await _deleteQuery(
        fs.collection('likeLogs').where('from', isEqualTo: uid),
      );
      await _deleteQuery(fs.collection('likeLogs').where('to', isEqualTo: uid));

      // 4) matches: uids contains uid
      await _deleteQuery(
        fs.collection('matches').where('uids', arrayContains: uid),
      );

      // 5) chats: messages SİLİNMEYECEK, sadece kullanıcının verisini temizle
      final chatsSnap = await fs
          .collection('chats')
          .where('participants', arrayContains: uid)
          .get();
      for (final chat in chatsSnap.docs) {
        // reads: Okuma durumunu sil (bu kullanıcının özel verisi)
        try {
          await _deleteQuery(chat.reference.collection('reads'));
        } catch (_) {}
        // Chat dokümanını güncelle: Katılımcı listesinden kullanıcıyı çıkar
        try {
          await chat.reference.set({
            'participants': FieldValue.arrayRemove([uid]),
            'updatedAt': FieldValue.serverTimestamp(),
            'deletedParticipant': uid, // Silindiğini işaretle
          }, SetOptions(merge: true));
        } catch (_) {}
      }

      // 6) Kullanıcının Postları
      try {
        await _deleteQuery(
          fs.collection('posts').where('authorId', isEqualTo: uid),
        );
      } catch (_) {}

      // 7) Kullanıcının Eklediği Filmler (userAddedFilms)
      try {
        await _deleteQuery(
          fs.collection('userAddedFilms').where('authorId', isEqualTo: uid),
        );
      } catch (_) {}

      // --- users/{uid} ALT KOLEKSİYONLARI TEMİZLE ---

      // 8) users/{uid}/following
      try {
        await _deleteQuery(
          fs.collection('users').doc(uid).collection('following'),
        );
      } catch (_) {}
      // 9) users/{uid}/followers
      try {
        await _deleteQuery(
          fs.collection('users').doc(uid).collection('followers'),
        );
      } catch (_) {}
      // 10) users/{uid}/blocked & blockedBy
      try {
        await _deleteQuery(
          fs.collection('users').doc(uid).collection('blocked'),
        );
      } catch (_) {}
      try {
        await _deleteQuery(
          fs.collection('users').doc(uid).collection('blockedBy'),
        );
      } catch (_) {}
      
      // 11) users/{uid}/shelves (ve altındaki items), movies, userMovies
      final shelvesCol = fs.collection('users').doc(uid).collection('shelves');
      final shelvesSnap = await shelvesCol.get();
      for (final shelf in shelvesSnap.docs) {
          try {
            await _deleteQuery(shelf.reference.collection('items'));
          } catch (_) {}
          try {
            await shelf.reference.delete();
          } catch (_) {}
      }
      try {
        await _deleteQuery(
          fs.collection('users').doc(uid).collection('movies'),
        );
      } catch (_) {}
      try {
        await _deleteQuery(
          fs.collection('users').doc(uid).collection('userMovies'),
        );
      } catch (_) {}

      // 12) userTasteProfiles/{uid} (Merkezi film verisi)
      try {
        await fs.collection('userTasteProfiles').doc(uid).delete();
      } catch (_) {}

      // 13) users/{uid} (Ana kullanıcı dokümanı)
      try {
        await fs.collection('users').doc(uid).delete();
      } catch (_) {}

      // 14) Firebase Auth hesabını sil
      try {
        await user.delete();

        // BAŞARILI SİLME: Auth silindi, AuthStateChanges tetiklenecek.
        if (!mounted) return;
        _toast('Hesabınız ve ilgili veriler silindi.');
        // Ayarlar sayfasından çıkış yap, AuthGate LoginPage'e yönlendirecektir.
        Navigator.of(context).pop();

      } on FirebaseAuthException catch (e) {
        if (e.code == 'requires-recent-login') {
          // BAŞARISIZ SİLME: Kullanıcıyı bilgilendir, tekrar denemeye zorla.
          if (!mounted) return;
          _toast(
            'Güvenlik nedeniyle tekrar giriş yapmanız gerekiyor. Lütfen ÇIKIŞ YAPIN, hemen tekrar giriş yapın ve silme işlemini tekrarlayın.',
          );
          if (mounted) setState(() => _busy = false); // Butonu aktif et
          return; // İşlemi durdur
        }
        // Diğer Auth hataları
        _toast('Hesap silme hatası: ${e.code}');
        if (mounted) setState(() => _busy = false);
        return; // İşlemi durdur
      }

      // Bu koda sadece Auth delete başarılı olursa ulaşılır.
      // Diğer durumlar yukarıdaki return'ler ile kontrol edildi.

    } catch (e) {
      _toast('Silme hatası: $e');
      if (mounted) setState(() => _busy = false); // Kapsamlı hata durumunda butonu aktif et
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Profil fotoğrafını ayarla'),
            subtitle: (user?.photoURL != null && user!.photoURL!.isNotEmpty)
                ? Text(
                    user.photoURL!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : null,
            onTap: _busy ? null : _setPhoto,
          ),
          const Divider(height: 0),
          ListTile(
            leading: const Icon(Icons.image_not_supported_outlined),
            title: const Text('Profil fotoğrafını kaldır'),
            enabled:
                (user?.photoURL != null &&
                (user!.photoURL?.isNotEmpty ?? false)),
            onTap: _busy ? null : _clearPhoto,
          ),
          const Divider(height: 0),
          ListTile(
            leading: const Icon(Icons.lock_reset),
            title: const Text('Şifre sıfırla'),
            onTap: _busy ? null : _resetPassword,
          ),
          const Divider(height: 0),
          ListTile(
            leading: const Icon(Icons.mark_email_read_outlined),
            title: const Text('E-postayı doğrula'),
            subtitle: (user?.email != null)
                ? Text(
                    user!.email!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : const Text('Hesabınız e‑posta ile bağlı görünmüyor'),
            onTap: _busy ? null : _verifyEmail,
          ),
          const Divider(height: 0),
          ListTile(
            leading: const Icon(Icons.color_lens_outlined),
            title: const Text('Tema'),
            subtitle: const Text('Aydınlık / Karanlık / Sistem'),
            onTap: _busy ? null : _pickTheme,
          ),
          const Divider(height: 0),
          ListTile(
            leading: const Icon(Icons.link_off_outlined),
            title: const Text('Letterboxd eşleştirmesini kaldır'),
            subtitle: const Text('İçe aktarılan tüm film listelerini temizle'),
            onTap: _busy ? null : _clearLetterboxdSync,
          ),
          const Divider(height: 0),

          const ListTile(
            leading: Icon(Icons.notifications_outlined),
            title: Text('Bildirimler'),
            subtitle: Text('Bildirim tercihlerini yapılandır'),
          ),
          const Divider(height: 0),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Gizlilik'),
            subtitle: Text('Hesap ve veri ayarları'),
          ),
          const Divider(height: 0),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Hakkında'),
            subtitle: Text('Sürüm ve lisanslar'),
          ),
          const Divider(height: 0),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Çıkış yap'),
            onTap: _busy ? null : _logout,
          ),
          const Divider(height: 0),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
            title: const Text('Hesabı sil'),
            subtitle: const Text(
              'Hesabınız ve ilişkili tüm veriler kalıcı olarak silinir',
            ),
            textColor: Colors.redAccent,
            iconColor: Colors.redAccent,
            onTap: _busy ? null : _deleteAccount,
          ),
        ],
      ),
    );
  }
}