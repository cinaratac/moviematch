import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

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
          'Bu işlem geri alınamaz. Tüm eşleşmeler, sohbetler, beğeniler ve profil verileri silinecek.',
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

      // 5) chats: participants contains uid → delete subcollections (best-effort), then chat doc
      final chatsSnap = await fs
          .collection('chats')
          .where('participants', arrayContains: uid)
          .get();
      for (final chat in chatsSnap.docs) {
        // delete reads
        try {
          await _deleteQuery(chat.reference.collection('reads'));
        } catch (_) {}
        // delete messages
        try {
          await _deleteQuery(chat.reference.collection('messages'));
        } catch (_) {}
        // delete chat itself
        try {
          await chat.reference.delete();
        } catch (_) {}
      }

      // 6) userTasteProfiles/{uid}
      try {
        await fs.collection('userTasteProfiles').doc(uid).delete();
      } catch (_) {}

      // 7) users/{uid}
      try {
        await fs.collection('users').doc(uid).delete();
      } catch (_) {}

      // 8) Firebase Auth hesabını sil
      try {
        await user.delete();
      } on FirebaseAuthException catch (e) {
        if (e.code == 'requires-recent-login') {
          _toast(
            'Güvenlik için tekrar giriş yapmanız gerekiyor. Lütfen tekrar giriş yaptıktan sonra hesabı silin.',
          );
        } else {
          _toast('Hesap silme hatası: ${e.code}');
        }
      }

      if (!mounted) return;
      _toast('Hesabınız ve ilgili veriler silindi.');
      Navigator.of(context).pop();
    } catch (e) {
      _toast('Silme hatası: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
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
