import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/auth/register_page.dart';
import 'package:fluttergirdi/widgets/green_characters.dart'; // YEŞİL KARAKTER İÇİN EKLENDİ
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore eklendi
import 'package:google_sign_in/google_sign_in.dart';
import 'package:fluttergirdi/auth/google_register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // Controller'lar
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isGoogleLoading = false;

  // Durum değişkenleri
  bool _isLoading = false;
  bool _isPasswordVisible = false;

  // Giriş Fonksiyonu
  Future<void> _login() async {
    if (_emailController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen tüm alanları doldurunuz.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      // Başarılı olursa main.dart'taki StreamBuilder kullanıcıyı otomatik yönlendirir.
    } on FirebaseAuthException catch (e) {
      String message = 'Giriş başarısız.';
      if (e.code == 'user-not-found') message = 'Bu e-posta ile kayıtlı kullanıcı bulunamadı.';
      else if (e.code == 'wrong-password') message = 'Şifre hatalı.';
      else if (e.code == 'invalid-email') message = 'Geçersiz e-posta formatı.';
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Şifre Sıfırlama Fonksiyonu
  Future<void> _resetPassword() async {
    if (_emailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Şifre sıfırlamak için lütfen e-posta adresinizi girin.')),
      );
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: _emailController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sıfırlama bağlantısı e-posta adresinize gönderildi.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }
  // ... importlar ...

// _signInWithGoogle fonksiyonunu bu şekilde güncelleyin:
Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _isGoogleLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Firebase'e giriş yap
      final UserCredential userCredential = 
          await FirebaseAuth.instance.signInWithCredential(credential);
      final User? user = userCredential.user;
      
      if (user != null) {
        // Kullanıcı verisini kontrol et
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (mounted) {
           // KONTROL DEĞİŞTİ: Sadece döküman varlığı yetmez, 'termsAccepted' true olmalı.
           if (userDoc.exists && userDoc.data()?['termsAccepted'] == true) {
            // Kayıtlı kullanıcı -> AuthGate zaten HomeShell'e yönlendirir.
            // Hiçbir şey yapma.
          } else {
            // Yeni kullanıcı veya kaydı yarım kalan -> Register sayfasına git
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => GoogleRegisterPage(user: user),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Yeşil Tema Renkleri
    final primaryGreen = const Color(0xFF2E7D32); // Koyu Yeşil
    final bgGradientStart = const Color(0xFFE8F5E9); 
    final bgGradientEnd = Colors.white;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bgGradientStart, bgGradientEnd],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // --- YEŞİL KARAKTER ALANI ---
                  // Eski 'app_icon.png' yerine interaktif karakteri koyduk
                  Hero(
                    tag: 'app_logo',
                    child: Container(
                      height: 140, // Biraz büyüttük ki karakter net görünsün
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        // Karakterin arkasına hafif bir gölge/parlama efekti
                        boxShadow: [
                          BoxShadow(
                            color: primaryGreen.withOpacity(0.15),
                            blurRadius: 30,
                            spreadRadius: 5,
                            offset: const Offset(0, 10),
                          )
                        ],
                      ),
                      // BURASI GÜNCELLENDİ:
                      child: const GreenEyesCharacter(size: 130),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // --- HOŞ GELDİNİZ METNİ ---
                  Text(
                    'Tekrar Hoş Geldiniz!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: primaryGreen,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Devam etmek için giriş yapın',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 48),

                  // --- E-POSTA ALANI ---
                  _buildTextField(
                    controller: _emailController,
                    hintText: 'E-posta Adresi',
                    icon: Icons.email_outlined,
                    primaryColor: primaryGreen,
                  ),
                  const SizedBox(height: 16),

                  // --- ŞİFRE ALANI ---
                  _buildTextField(
                    controller: _passwordController,
                    hintText: 'Şifre',
                    icon: Icons.lock_outline,
                    isPassword: true,
                    isVisible: _isPasswordVisible,
                    onVisibilityToggle: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                    primaryColor: primaryGreen,
                  ),
                  
                  // --- ŞİFREMİ UNUTTUM ---
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _resetPassword,
                      style: TextButton.styleFrom(
                        foregroundColor: primaryGreen,
                        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                      ),
                      child: const Text('Şifremi Unuttum?'),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // --- GİRİŞ YAP BUTONU ---
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGreen,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shadowColor: primaryGreen.withOpacity(0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'Giriş Yap',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: (_isLoading || _isGoogleLoading) ? null : _signInWithGoogle,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.grey),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        backgroundColor: Colors.white,
                      ),
                      icon: _isGoogleLoading 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Image.asset('assets/images/google_logo.png', height: 24, width: 24, errorBuilder: (c,o,s) => const Icon(Icons.login)), // Google logosu yoksa icon gösterir
                      label: Text(
                        _isGoogleLoading ? 'Bağlanılıyor...' : 'Google ile Bağlan',
                        style: const TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),

                  // --- KAYIT OL ALANI ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Hesabın yok mu?',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const RegisterPage()),
                          );
                        },
                        child: Text(
                          'Kayıt Ol',
                          style: TextStyle(
                            color: primaryGreen,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Özel Text Field Widget'ı
  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    required Color primaryColor,
    bool isPassword = false,
    bool isVisible = false,
    VoidCallback? onVisibilityToggle,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword && !isVisible,
        keyboardType: isPassword ? TextInputType.visiblePassword : TextInputType.emailAddress,
       style: const TextStyle(fontSize: 16, color: Colors.black),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.grey[400]),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    isVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: Colors.grey[400],
                  ),
                  onPressed: onVisibilityToggle,
                )
              : null,
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.grey[400]),
          contentPadding: const EdgeInsets.symmetric(vertical: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: primaryColor, width: 1.5),
          ),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }
}