import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/onboarding/letterboxd_onboarding.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  double _eyeOffsetX = 0;
  double _eyeOffsetY = 0;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final email = _email.text.trim();
      final pass = _password.text.trim();
      final uname = _username.text.trim();

      // 1) Create user
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: pass,
      );

      // 2) Update displayName
      final user = FirebaseAuth.instance.currentUser;
      try {
        await user?.updateDisplayName(uname);
      } catch (_) {}

      // 3) Firestore: users/{uid} içine uygulama içi kullanıcı adını yaz
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'displayName': uname,
            'displayName_lc': uname.toLowerCase(),
            'email': email,
            'updatedAt': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (e) {
        // Firestore yazımı başarısız olsa bile kayıt akışını durdurma; logla
        debugPrint('users/{uid} set error: $e');
      }

      // 4) Onboarding: Letterboxd kullanıcı adı zorunlu adımı
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OnboardingLetterboxd()),
        (_) => false,
      );
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
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() {
            _eyeOffsetX = 0;
            _eyeOffsetY = 0;
          });
        },
        behavior: HitTestBehavior.translucent,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ForestFace(offsetX: _eyeOffsetX, offsetY: _eyeOffsetY),
                    const SizedBox(height: 16),
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
                      onTap: () {
                        setState(() {
                          _eyeOffsetX = -6; // look slightly to the left
                          _eyeOffsetY = 4; // slightly downward center-left
                        });
                      },
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
                      onTap: () {
                        setState(() {
                          _eyeOffsetX = -8;
                          _eyeOffsetY = 6;
                        });
                      },
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
                          onPressed: () =>
                              setState(() => _obscure1 = !_obscure1),
                          icon: Icon(
                            _obscure1 ? Icons.visibility : Icons.visibility_off,
                          ),
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          _eyeOffsetX = 0;
                          _eyeOffsetY =
                              10; // both password fields look to same downward point
                        });
                      },
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
                          onPressed: () =>
                              setState(() => _obscure2 = !_obscure2),
                          icon: Icon(
                            _obscure2 ? Icons.visibility : Icons.visibility_off,
                          ),
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          _eyeOffsetX = 0;
                          _eyeOffsetY =
                              10; // both password fields look to same downward point
                        });
                      },
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
      ),
    );
  }
}

class _ForestFace extends StatelessWidget {
  final double offsetX;
  final double offsetY;
  const _ForestFace({this.offsetX = 0, this.offsetY = 0});

  @override
  Widget build(BuildContext context) {
    const base = Color(0xFF1B5E20); // forest green
    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _ring(160, base.withOpacity(0.90)),
          _ring(130, base.withOpacity(0.75)),
          _ring(100, base.withOpacity(0.55)),
          _ring(72, base.withOpacity(0.35)),
          _ring(48, base.withOpacity(0.20)),

          Positioned(left: 46, top: 62, child: _eye(offsetX, offsetY)),
          Positioned(right: 46, top: 62, child: _eye(offsetX, offsetY)),
        ],
      ),
    );
  }

  static Widget _ring(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  static Widget _eye(double offsetX, double offsetY) {
    return Container(
      width: 30,
      height: 30,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment(offsetX / 10, offsetY / 10),
        child: Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
            color: Colors.black87,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
