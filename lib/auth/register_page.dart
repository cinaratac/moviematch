import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _loading = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text.trim(),
      );
      final uname = _username.text.trim();
      final user = FirebaseAuth.instance.currentUser;

      // Profil adını kaydet (Firestore kullanılmıyor)
      try {
        await user?.updateDisplayName(uname);
        await user?.reload();
      } catch (_) {}

      // Başarılı kayıt: AuthGate otomatik HomeShell'e geçecek; Register sayfasını kapat
      if (mounted) Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'email-already-in-use':
          msg = 'Bu e-posta ile zaten bir hesap var';
          break;
        case 'invalid-email':
          msg = 'Geçersiz e-posta adresi';
          break;
        case 'weak-password':
          msg = 'Şifre çok zayıf (en az 6 karakter)';
          break;
        default:
          msg = 'Hata: ${e.message ?? e.code}';
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kaydol')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Yeni hesap oluştur',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _username,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Kullanıcı adı',
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                    validator: (v) {
                      final value = (v ?? '').trim();
                      if (value.isEmpty) return 'Kullanıcı adı zorunlu';
                      // Sadece a-z, 0-9, nokta, alt tire, tire; 3-20 karakter
                      final re = RegExp(r'^[a-z0-9._-]{3,20}$');
                      if (!re.hasMatch(value)) {
                        return 'Sadece a-z, 0-9, . _ - ve 3-20 karakter olmalı';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'E-posta',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Zorunlu alan';
                      if (!v.contains('@')) return 'Geçerli bir e-posta gir';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure1,
                    decoration: InputDecoration(
                      labelText: 'Şifre',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure1 = !_obscure1),
                        icon: Icon(
                          _obscure1 ? Icons.visibility : Icons.visibility_off,
                        ),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Zorunlu alan';
                      if (v.length < 6) return 'En az 6 karakter olmalı';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirm,
                    obscureText: _obscure2,
                    decoration: InputDecoration(
                      labelText: 'Şifre (Tekrar)',
                      prefixIcon: const Icon(Icons.lock_reset_outlined),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure2 = !_obscure2),
                        icon: Icon(
                          _obscure2 ? Icons.visibility : Icons.visibility_off,
                        ),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Zorunlu alan';
                      if (v != _password.text) return 'Şifreler uyuşmuyor';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Kaydol'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
