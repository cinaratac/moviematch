import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _errorMessage;
  bool _showRegisterPrompt = false;
  double _eyeOffsetX = 0;
  double _eyeOffsetY = 0;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _errorMessage = null;
      _showRegisterPrompt = false;
    });
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text.trim(),
      );
      if (!mounted) return;
      // Login başarılı, AuthGate otomatik olarak HomeShell'e yönlendirecek
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'user-not-found':
          msg = 'Bu e-posta ile kayıt bulunamadı';
          break;
        case 'wrong-password':
          msg = 'Hatalı şifre';
          break;
        case 'invalid-email':
          msg = 'Geçersiz e-posta';
          break;
        case 'too-many-requests':
          msg = 'Çok fazla deneme yapıldı. Bir süre sonra tekrar deneyin.';
          break;
        case 'invalid-credential':
          msg =
              'Geçersiz kimlik bilgisi. E-posta veya şifre hatalı ya da süresi dolmuş.';
          break;
        default:
          msg = 'Hata: ${e.message ?? e.code}';
      }
      if (mounted) {
        setState(() {
          _errorMessage = msg;
          _showRegisterPrompt = (e.code == 'user-not-found');
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onForgotPassword() async {
    if (_loading) return;
    final email = _email.text.trim();
    if (email.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen e-posta adresini girin')),
      );
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Şifre sıfırlama bağlantısı e-posta adresine gönderildi.',
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: ${e.message ?? e.code}')));
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
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
                      'Hoş geldin',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'E-posta',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'E-posta zorunlu';
                        if (!v.contains('@')) return 'Geçerli bir e-posta gir';
                        return null;
                      },
                      onTap: () {
                        setState(() {
                          _eyeOffsetX = -8;
                          _eyeOffsetY = 6;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Şifre',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off,
                          ),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Şifre zorunlu';
                        if (v.length < 6) return 'En az 6 karakter olmalı';
                        return null;
                      },
                      onTap: () {
                        setState(() {
                          _eyeOffsetX = 0;
                          _eyeOffsetY = 12;
                        });
                      },
                    ),
                    if (_errorMessage != null) ...[
                      Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_showRegisterPrompt) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _loading
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const RegisterPage(),
                                    ),
                                  );
                                },
                          child: const Text('Hemen kayıt ol'),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
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
                            : const Text('Giriş Yap'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.center,
                      child: TextButton(
                        onPressed: _loading ? null : _onForgotPassword,
                        child: const Text('Şifremi unuttum'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const RegisterPage(),
                                ),
                              );
                            },
                      child: Text(
                        'Hesabın yok mu? Kaydol',
                        style: TextStyle(color: cs.primary),
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
          // Concentric circles (face made of nested circles)
          _ring(160, base.withOpacity(0.90)),
          _ring(130, base.withOpacity(0.75)),
          _ring(100, base.withOpacity(0.55)),
          _ring(72, base.withOpacity(0.35)),
          _ring(48, base.withOpacity(0.20)),

          // Eyes (only eyes visible)
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
