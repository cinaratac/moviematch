import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/onboarding/letterboxd_onboarding.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart'; // Tıklanabilir metin için
import 'package:flutter_cached_pdfview/flutter_cached_pdfview.dart'; // PDF görüntüleyici
import '../services/text_filter_service.dart';

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

  // --- İZİN DEĞİŞKENLERİ ---
  bool _agreedToTerms = false; // Zorunlu sözleşme onayı
  bool _allowMail = false;     // İsteğe bağlı iletişim izni (Zorunlu değil)

  double _eyeOffsetX = 0;
  double _eyeOffsetY = 0;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;

    // --- ZORUNLU SÖZLEŞME KONTROLÜ ---
    // Sadece sözleşme zorunlu, mail izni zorunlu değil.
    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kayıt olmak için Kullanıcı Sözleşmesini okuyup onaylamanız gerekmektedir.'),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 3),
        ),
      );
      return; // İşlemi durdur
    }

    setState(() => _loading = true);
    try {
      final email = _email.text.trim();
      final pass = _password.text.trim();
      final uname = _username.text.trim();
      if (TextFilterService.hasProfanity(uname)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Bu kullanıcı adı uygunsuz ifadeler içerdiği için kullanılamaz.'),
        backgroundColor: Colors.red,
      ),
    );
    return;
    }

      // 1) Kullanıcıyı Firebase Auth üzerinde oluştur
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: pass,
      );

      // 2) Kullanıcı adını (displayName) güncelle
      final user = FirebaseAuth.instance.currentUser;
      try {
        await user?.updateDisplayName(uname);
      } catch (_) {}

      // 3) Firestore İşlemleri
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          final db = FirebaseFirestore.instance;
          final batch = db.batch();

          // A) Ana Kullanıcı Kaydı (users/{uid})
          final userRef = db.collection('users').doc(uid);
          batch.set(userRef, {
            'displayName': uname,
            'displayName_lc': uname.toLowerCase(),
            'email': email,
            
            // --- İZİN VERİLERİ ---
            'termsAccepted': true, // Sözleşme kabul edildi
            'marketingConsent': _allowMail, // Pazarlama izni durumu (true/false)
            'termsAcceptedAt': FieldValue.serverTimestamp(),
            // ---------------------

            'updatedAt': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          // B) Eğer mail izni verdiyse Ayrı Listeye Ekle (marketing_emails/{uid})
          if (_allowMail) {
            final mailListRef = db.collection('marketing_emails').doc(uid);
            batch.set(mailListRef, {
              'email': email,
              'displayName': uname,
              'consentedAt': FieldValue.serverTimestamp(),
              'source': 'register_page',
            });
          }

          await batch.commit(); // İki işlemi aynı anda yap
        }
      } catch (e) {
        debugPrint('Firestore set error: $e');
      }

      // 4) Başarılı ise Onboarding ekranına yönlendir
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

  // --- PDF GÖSTEREN PENCERE (MODAL - DÜZELTİLMİŞ) ---
  void _showTermsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Tam ekrana yakın açılır
      enableDrag: false, // Yanlışlıkla kapanmayı önler
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (context) {
        // DÜZELTME: DraggableScrollableSheet yerine sabit yükseklikli Container kullanıldı.
        // Bu, PDF'in beyaz ekran verme (height: 0 olma) sorununu çözer.
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.9, // Ekranın %90'ı
          child: Column(
            children: [
              // Başlık ve Kapat Butonu
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Kullanıcı Sözleşmesi",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              
              // PDF Görüntüleyici
              Expanded(
                child: const PDF(
                  enableSwipe: true,
                  swipeHorizontal: false,
                  autoSpacing: false,
                  pageFling: false,
                ).fromAsset(
                  'assets/docs/sozlesme.pdf', // PDF dosyanızın yolu
                  errorWidget: (dynamic error) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 40, color: Colors.red),
                          const SizedBox(height: 10),
                          Text(
                            "Sözleşme görüntülenemedi.\n\nOlası Çözümler:\n1. Uygulamayı durdurup tekrar başlatın (Hot Reload yetmez).\n2. 'assets/docs/sozlesme.pdf' dosyasının varlığını kontrol edin.\n\nHata: $error",
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Alt Onay Butonu
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      // Butona basınca sözleşmeyi kabul etmiş sayılır
                      setState(() {
                        _agreedToTerms = true;
                      });
                      Navigator.pop(context);
                    },
                    child: const Text("Okudum ve Onaylıyorum"),
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
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
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
                child: SingleChildScrollView(
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
                      
                      // Kullanıcı Adı
                      TextFormField(
                        controller: _username,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Kullanıcı adı',
                          prefixIcon: Icon(Icons.alternate_email),
                        ),
                        onTap: () {
                          setState(() {
                            _eyeOffsetX = -6;
                            _eyeOffsetY = 4;
                          });
                        },
                        validator: (v) {
                          final value = (v ?? '').trim();
                          if (value.isEmpty) return 'Kullanıcı adı zorunlu';
                          final re = RegExp(r'^[a-z0-9._-]{3,20}$');
                          if (!re.hasMatch(value)) {
                            return 'Sadece a-z, 0-9, . _ - ve 3-20 karakter olmalı';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      
                      // E-posta
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
                      
                      // Şifre
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
                            _eyeOffsetY = 10;
                          });
                        },
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Zorunlu alan';
                          if (v.length < 6) return 'En az 6 karakter olmalı';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      
                      // Şifre Tekrar
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
                            _eyeOffsetY = 10;
                          });
                        },
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Zorunlu alan';
                          if (v != _password.text) return 'Şifreler uyuşmuyor';
                          return null;
                        },
                      ),
                      
                      const SizedBox(height: 24),

                      // --- 1. KULLANICI SÖZLEŞMESİ (ZORUNLU) ---
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: Checkbox(
                              value: _agreedToTerms,
                              activeColor: cs.primary,
                              onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                text: 'Kaydol butonuna basarak ',
                                style: TextStyle(color: cs.onSurface, fontSize: 13),
                                children: [
                                  TextSpan(
                                    text: 'Kullanıcı Sözleşmesini',
                                    style: TextStyle(
                                      color: cs.primary,
                                      fontWeight: FontWeight.bold,
                                      decoration: TextDecoration.underline,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = _showTermsDialog,
                                  ),
                                  const TextSpan(text: ' okuduğumu ve kabul ettiğimi onaylıyorum.'),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // --- 2. E-POSTA İZNİ (OPSİYONEL) ---
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: Checkbox(
                              value: _allowMail,
                              activeColor: cs.primary,
                              onChanged: (v) => setState(() => _allowMail = v ?? false),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _allowMail = !_allowMail),
                              child: Text(
                                'Cinematch hakkındaki yeniliklerden ve önerilerden e-posta yoluyla haberdar olmak istiyorum.',
                                style: TextStyle(color: cs.onSurface.withOpacity(0.8), fontSize: 13),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 5),
                      // Kaydol Butonu
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