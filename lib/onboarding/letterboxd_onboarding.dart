import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/services/user_profile_service.dart';
import 'package:fluttergirdi/shell.dart';

class OnboardingLetterboxd extends StatefulWidget {
  const OnboardingLetterboxd({super.key});

  @override
  State<OnboardingLetterboxd> createState() => _OnboardingLetterboxdState();
}

class _OnboardingLetterboxdState extends State<OnboardingLetterboxd> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextFieldController();
  final _svc = UserProfileService();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _checkAlreadySet();
  }

  Future<void> _checkAlreadySet() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      // güvenlik: çıkışa düş
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (_) => false,
      );
      return;
    }
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final exists =
        doc.exists &&
        (doc.data()?['letterboxdUsername'] ?? '').toString().isNotEmpty;
    if (exists && mounted) {
      // zaten ayarlı → direkt HomeShell
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (_) => false,
      );
    } else {
      setState(() => _loading = false);
    }
  }

  String? _validator(String? v) {
    final val = (v ?? '').trim();
    if (val.isEmpty) return 'Kullanıcı adı zorunlu';
    // letterboxd kullanıcı adı: harf/rakam/altçizgi/tire kabul edelim, boşluk yok
    final ok = RegExp(r'^[a-zA-Z0-9_\-\.]+$').hasMatch(val);
    if (!ok) return 'Geçersiz karakter var';
    if (val.length < 2) return 'En az 2 karakter';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final raw = _controller.text.trim();
      // Tek seferlik kaydet (servis merge çalışır)
      await _svc.setLetterboxdUsername(raw);
      await _svc.syncAuthProfile();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Letterboxd kullanıcı adı')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const Text(
                'Lütfen Letterboxd kullanıcı adını gir. Bu adım zorunludur ve daha sonra değiştirilemez.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: 'Kullanıcı adı (ör. silhouettofaman)',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                validator: _validator,
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.check),
                  label: _saving
                      ? const Text('Kaydediliyor...')
                      : const Text('Kaydet ve devam et'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Küçük yardımcı: iOS klavyede done tetiklemeyi kolaylaştırmak için
class TextFieldController extends TextEditingController {}
