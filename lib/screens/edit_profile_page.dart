import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _letterboxdCtrl = TextEditingController();
  final _favDirectorCtrl = TextEditingController();
  final _favActorCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      // Firestore user doc
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = doc.data() ?? <String, dynamic>{};
      _usernameCtrl.text = (data['username'] ?? '').toString();
      _letterboxdCtrl.text = (data['letterboxdUsername'] ?? '').toString();
      _favDirectorCtrl.text =
          (data['favoriteDirector'] ?? data['favDirector'] ?? '').toString();
      _favActorCtrl.text = (data['favoriteActor'] ?? data['favActor'] ?? '')
          .toString();

      final age = data['age'];
      if (age is int && age > 0) {
        _ageCtrl.text = age.toString();
      } else if (age is num && age.toInt() > 0) {
        _ageCtrl.text = age.toInt().toString();
      }
    } catch (_) {
      // no-op; show empty form
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestLbRefresh() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      // İsteği taste profile dokümanına yazarak Cloud Function / backend tetikleyelim
      await FirebaseFirestore.instance
          .collection('userTasteProfiles')
          .doc(user.uid)
          .set({
            'refreshRequestedAt': FieldValue.serverTimestamp(),
            'refreshSource': 'manual_edit_profile',
          }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Letterboxd verileri yenileme isteği gönderildi.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Yenileme isteği başarısız: $e')));
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _letterboxdCtrl.dispose();
    _favDirectorCtrl.dispose();
    _favActorCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      final username = _usernameCtrl.text.trim();
      final favDirector = _favDirectorCtrl.text.trim();
      final favActor = _favActorCtrl.text.trim();
      final ageStr = _ageCtrl.text.trim();
      final age = int.tryParse(ageStr);
      final newLb = _letterboxdCtrl.text.trim().toLowerCase();

      final payload = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      // Write only non-empty values to avoid junk
      if (username.isNotEmpty)
        payload['username'] = username;
      else
        payload['username'] = FieldValue.delete();
      if (favDirector.isNotEmpty)
        payload['favoriteDirector'] = favDirector;
      else
        payload['favoriteDirector'] = FieldValue.delete();
      if (favActor.isNotEmpty)
        payload['favoriteActor'] = favActor;
      else
        payload['favoriteActor'] = FieldValue.delete();
      if (age != null && age > 0)
        payload['age'] = age;
      else
        payload['age'] = FieldValue.delete();

      if (newLb.isNotEmpty)
        payload['letterboxdUsername'] = newLb;
      else
        payload['letterboxdUsername'] = FieldValue.delete();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(payload, SetOptions(merge: true));

      try {
        if (newLb.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('userTasteProfiles')
              .doc(user.uid)
              .set({
                'refreshRequestedAt': FieldValue.serverTimestamp(),
                'refreshSource': 'edit_profile_letterboxd',
              }, SetOptions(merge: true));
        }
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profil güncellendi.')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kaydetme hatası: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profili Düzenle')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profili Düzenle'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Kaydet'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Section(title: 'Profil'),
            TextFormField(
              controller: _usernameCtrl,
              decoration: const InputDecoration(labelText: 'Kullanıcı adı'),
              textInputAction: TextInputAction.next,
              validator: (v) {
                if (v == null || v.isEmpty) return null;
                final rx = RegExp(r'^[a-zA-Z0-9_\.\\-]{3,20}$');
                if (!rx.hasMatch(v)) return '3-20 karakter, harf/rakam/_ . -';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _letterboxdCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Letterboxd kullanıcı adı',
                helperText: 'İsteğe bağlı — girersen eşitleme yapılır',
                prefixText: '@',
              ),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (v) {
                if (v == null || v.trim().isEmpty)
                  return null; // opsiyonel alan
                final ok = RegExp(r'^[A-Za-z0-9_\-.]+$').hasMatch(v.trim());
                return ok ? null : 'Sadece harf, rakam, _ . - kullan';
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _saving ? null : _requestLbRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Letterboxd verilerini yenile'),
              ),
            ),

            const SizedBox(height: 24),
            _Section(title: 'Favoriler'),
            TextFormField(
              controller: _favDirectorCtrl,
              decoration: const InputDecoration(
                labelText: 'Favori yönetmen',
                hintText: 'Örn: Nuri Bilge Ceylan',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _favActorCtrl,
              decoration: const InputDecoration(
                labelText: 'Favori oyuncu',
                hintText: 'Örn: Haluk Bilginer',
              ),
              textInputAction: TextInputAction.next,
            ),

            const SizedBox(height: 24),
            _Section(title: 'Diğer'),
            TextFormField(
              controller: _ageCtrl,
              decoration: const InputDecoration(
                labelText: 'Yaş',
                hintText: 'Örn: 24',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.isEmpty) return null;
                final n = int.tryParse(v);
                if (n == null || n <= 0 || n > 120) return 'Geçersiz yaş';
                return null;
              },
            ),

            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
              label: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
