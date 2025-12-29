import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttergirdi/shell.dart';
import 'package:fluttergirdi/services/letterboxd_service.dart';
import 'package:fluttergirdi/services/match_service.dart';

class OnboardingLetterboxd extends StatefulWidget {
  const OnboardingLetterboxd({super.key});

  @override
  State<OnboardingLetterboxd> createState() => _OnboardingLetterboxdState();
}

class _OnboardingLetterboxdState extends State<OnboardingLetterboxd> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController(); // Letterboxd Username
  
  bool _loading = true;
  bool _saving = false;

  final _ageController = TextEditingController();
  final _directorController = TextEditingController();
  final _actorController = TextEditingController();

  // Tema Renkleri
  final primaryGreen = const Color(0xFF2E7D32);
  final bgGradientStart = const Color(0xFFE8F5E9);
  final bgGradientEnd = Colors.white;

  final List<String> _genreOptions = const [
    'Aksiyon', 'Aksiyon-Gerilim', 'Casus', 'Dövüş', 'Felaket', 'Macera', "Klasikler",
    'Bilimkurgu', 'Kıyamet Sonrası', 'Steampunk', 'Dram', 'Melodram', 'Politik Dram',
    'Tarihi Dram', 'Trajedi', 'Gerilim', 'Psikolojik Gerilim', 'Politik Gerilim',
    'Erotik Gerilim', 'Komedi', 'Aksiyon Komedisi', 'Kara Mizah', 'Komedi-Drama',
    'Romantik Komedi', 'Parodi', 'Korku', 'Gotik', 'Doğaüstü', 'Vampir', 'Zombi',
    'Slasher', 'Fantastik', 'Mitolojik', 'K-drama', 'Süper Kahraman', 'Romantik',
    'Romantik Dram', 'Romantik Gerilim', 'Savaş', 'Tarih', 'Biyografi', 'Müzikal',
    'Belgesel', 'Doğa', 'Gezi', 'Spor', 'Suç', 'Polisiye', 'Mafya', 'Gizem',
    'Kara Film (Noir)', 'Western', 'Fantastik Komedi', 'Aile', 'Çocuk', 'Gençlik',
    'LGBTQ+', 'Animasyon', 'Anime',
  ];
  final Set<String> _selectedGenres = {};
  final List<String> _favDirectors = [];
  final List<String> _favActors = [];

  static const int _totalSteps = 5;
  int _step = 0;
  int _maxStepReached = 0;

  @override
  void initState() {
    super.initState();
    _checkAlreadySet();
  }

  Future<void> _checkAlreadySet() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (_) => false,
      );
      return;
    }
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);
    var doc = await ref.get(const GetOptions(source: Source.cache));
    if (!doc.exists) {
      doc = await ref.get(const GetOptions(source: Source.server));
    }
    
    final exists =
        doc.exists &&
        (doc.data()?['letterboxdUsername'] ?? '').toString().isNotEmpty;
    if (exists && mounted) {
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
    if (val.isEmpty) return null; 
    final ok = RegExp(r'^[a-zA-Z0-9_\-\.]+$').hasMatch(val);
    if (!ok) return 'Geçersiz karakter var';
    if (val.length < 2) return 'En az 2 karakter';
    return null;
  }

  int? _parseAge(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final v = int.tryParse(t);
    if (v == null) return null;
    if (v < 13 || v > 120) return null;
    return v;
  }

  // --- İLERLEME ÇUBUĞU ---
  Widget _buildStepBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: List.generate(_totalSteps, (i) {
          final bool done = i < _step;
          final bool current = i == _step;
          // Renk mantığı
          final Color color = done
              ? primaryGreen // Tamamlananlar yeşil
              : current
                  ? const Color(0xFF81C784) // Şu anki adım açık yeşil
                  : Colors.grey.withOpacity(0.3); // Kalanlar gri
          
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (i <= _maxStepReached || i <= _step) {
                  setState(() => _step = i);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 8,
                margin: EdgeInsets.symmetric(horizontal: i == _totalSteps - 1 ? 0 : 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: current ? [
                    BoxShadow(color: primaryGreen.withOpacity(0.4), blurRadius: 4, offset: const Offset(0,2))
                  ] : null,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // --- ADIM İÇERİKLERİ ---
  Widget _buildStepContent(BuildContext context) {
    switch (_step) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
             _buildHeaderTitle('Letterboxd Bağlantısı'),
            const SizedBox(height: 8),
            Text(
              'Letterboxd kullanıcı adını girersen, izlediğin ve beğendiğin filmleri otomatik çekip senin için harika eşleşmeler bulabiliriz.',
              style: TextStyle(color: Colors.grey[700], fontSize: 15),
            ),
            const SizedBox(height: 24),
            _buildStyledTextField(
              controller: _controller,
              hintText: 'Letterboxd Kullanıcı Adı (İsteğe bağlı)',
              icon: Icons.alternate_email,
              validator: _validator,
            ),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeaderTitle('Yaşın Kaç?'),
            const SizedBox(height: 8),
            Text(
              'Sana uygun yaş grubundaki kişilerle eşleşmen için gerekli.',
              style: TextStyle(color: Colors.grey[700], fontSize: 15),
            ),
            const SizedBox(height: 24),
            _buildStyledTextField(
              controller: _ageController,
              hintText: 'Yaş',
              icon: Icons.cake_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              validator: (v) {
                if (v == null || v.isEmpty) return 'Yaş zorunlu';
                final val = int.tryParse(v);
                if (val == null) return 'Geçersiz değer';
                if (val < 13) return 'Uygulamayı kullanmak için 13+ olmalısınız';
                if (val > 120) return 'Geçersiz yaş';
                return null;
              },
            ),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeaderTitle('Sevdiğin Türler'),
            const SizedBox(height: 8),
            Text(
              'Hangi tür filmleri izlemekten keyif alırsın? (Birden fazla seçebilirsin)',
              style: TextStyle(color: Colors.grey[700], fontSize: 15),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _genreOptions.map((g) {
                  final sel = _selectedGenres.contains(g);
                  return FilterChip(
                    label: Text(g),
                    labelStyle: TextStyle(
                      color: sel ? Colors.white : Colors.black87,
                      fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                    ),
                    selected: sel,
                    selectedColor: primaryGreen,
                    backgroundColor: Colors.grey[100],
                    checkmarkColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: sel ? primaryGreen : Colors.transparent),
                    ),
                    onSelected: (v) {
                      setState(() {
                        if (v) {
                          _selectedGenres.add(g);
                        } else {
                          _selectedGenres.remove(g);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
             _buildHeaderTitle('Favori Yönetmenler'),
            const SizedBox(height: 8),
            Text(
              'Takip ettiğin yönetmenleri ekle.',
              style: TextStyle(color: Colors.grey[700], fontSize: 15),
            ),
            const SizedBox(height: 24),
            _buildStyledTextField(
              controller: _directorController,
              hintText: 'Bir yönetmen yaz ve Enter’a bas',
              icon: Icons.movie_creation_outlined,
              onSubmitted: _addDirector,
              textInputAction: TextInputAction.send,
            ),
            const SizedBox(height: 16),
            _buildChipList(_favDirectors, (item) {
              setState(() => _favDirectors.remove(item));
            }),
          ],
        );
      case 4:
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
             _buildHeaderTitle('Favori Oyuncular'),
            const SizedBox(height: 8),
            Text(
              'Hayranı olduğun oyuncuları ekle.',
              style: TextStyle(color: Colors.grey[700], fontSize: 15),
            ),
            const SizedBox(height: 24),
             _buildStyledTextField(
              controller: _actorController,
              hintText: 'Bir oyuncu yaz ve Enter’a bas',
              icon: Icons.person_outline,
              onSubmitted: _addActor,
              textInputAction: TextInputAction.send,
            ),
            const SizedBox(height: 16),
             _buildChipList(_favActors, (item) {
              setState(() => _favActors.remove(item));
            }),
          ],
        );
    }
  }

  // Helper Widget: Chip Listesi
  Widget _buildChipList(List<String> items, Function(String) onDelete) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items.map((item) => Chip(
          label: Text(item, style: const TextStyle(color: Colors.white)),
          backgroundColor: primaryGreen.withOpacity(0.8),
          deleteIcon: const Icon(Icons.close, size: 18, color: Colors.white),
          onDeleted: () => onDelete(item),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
        )).toList(),
      ),
    );
  }

  // Helper Widget: Başlık
  Widget _buildHeaderTitle(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: primaryGreen,
        letterSpacing: -0.5,
      ),
    );
  }

  // Helper Widget: Stil Verilmiş Text Field
  Widget _buildStyledTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    void Function(String)? onSubmitted,
    TextInputAction textInputAction = TextInputAction.done,
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
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        textInputAction: textInputAction,
        onFieldSubmitted: onSubmitted,
        validator: validator,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.grey[400]),
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.grey[400]),
          contentPadding: const EdgeInsets.symmetric(vertical: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: primaryGreen, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1),
          ),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }

  void _addDirector(String v) {
    final t = v.trim();
    if (t.isEmpty) return;
    if (!_favDirectors.contains(t)) _favDirectors.add(t);
    _directorController.clear();
    setState(() {});
  }

  void _addActor(String v) {
    final t = v.trim();
    if (t.isEmpty) return;
    if (!_favActors.contains(t)) _favActors.add(t);
    _actorController.clear();
    setState(() {});
  }

  Future<void> _saveAndBuild() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _saving = true);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: primaryGreen),
                const SizedBox(height: 20),
                Text(
                  "Profilin oluşturuluyor...",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, color: primaryGreen, fontSize: 18),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Letterboxd verilerin çekiliyor ve eşleşmeler ayarlanıyor. Bu işlem 1-2 dakika sürebilir, lütfen kapatmayın.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final lbUsernameRaw = _controller.text.trim();
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid;
      if (uid == null) throw 'Oturum bulunamadı';

      final ageVal = _parseAge(_ageController.text);

      if (lbUsernameRaw.isNotEmpty) {
        await LetterboxdService.fullSyncOnboarding(uid: uid, lbUsername: lbUsernameRaw);
      }

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'letterboxdUsername': lbUsernameRaw,
        'letterboxdUsername_lc': lbUsernameRaw.toLowerCase(),
        'age': ageVal,
        'favGenres': _selectedGenres.toList(),
        'favDirectors': _favDirectors,
        'favActors': _favActors,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastSyncedAt': FieldValue.serverTimestamp(),
        'syncReason': 'onboarding',
      }, SetOptions(merge: true));

      try {
        await MatchService.instance.autoCreateMatches(
            uid,
            minCommonFive: 1,
            minCommonFav: 1,
            minCommonDisliked: 1,
          );
      } catch (_) {}

      if (!mounted) return;
      Navigator.of(context).pop();
      
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (_) => false,
      );

    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();

      String msg = 'Bir hata oluştu: $e';
      if (e.toString().contains('Letterboxd kullanıcısı bulunamadı')) {
        msg = 'Girdiğin Letterboxd kullanıcı adı bulunamadı. Lütfen kontrol et.';
      } else if (e.toString().contains('unavailable')) {
        msg = 'Sunucuya erişilemiyor. İnternet bağlantını kontrol et.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _ageController.dispose();
    _directorController.dispose();
    _actorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [bgGradientStart, bgGradientEnd],
            ),
          ),
          child: Center(child: CircularProgressIndicator(color: primaryGreen)),
        ),
      );
    }

    return Scaffold(
      // AppBar yerine Container gradient
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bgGradientStart, bgGradientEnd],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bottomInset = MediaQuery.of(context).viewInsets.bottom;
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 50),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Üst İlerleme Çubuğu
                        _buildStepBar(context),
                        
                        const SizedBox(height: 32),
                        
                        // İçerik (Animasyonlu geçiş)
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (Widget child, Animation<double> animation) {
                            return FadeTransition(opacity: animation, child: SlideTransition(
                              position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(animation),
                              child: child,
                            ));
                          },
                          child: KeyedSubtree(
                            key: ValueKey<int>(_step),
                            child: _buildStepContent(context),
                          ),
                        ),
                        
                        const SizedBox(height: 40),
                        
                        // Alt Butonlar
                        Row(
                          children: [
                            // GERİ BUTONU
                            Expanded(
                              child: SizedBox(
                                height: 50,
                                child: OutlinedButton(
                                  onPressed: (_step == 0 || _saving)
                                      ? null
                                      : () => setState(() => _step = _step - 1),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: primaryGreen,
                                    side: BorderSide(color: primaryGreen.withOpacity(0.5)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Geri', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            // İLERİ / KAYDET BUTONU
                            Expanded(
                              flex: 2,
                              child: SizedBox(
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: _saving
                                      ? null
                                      : () async {
                                          if (!_formKey.currentState!.validate()) {
                                            return; 
                                          }

                                          if (_step < _totalSteps - 1) {
                                            setState(() {
                                              _step += 1;
                                              if (_maxStepReached < _step) {
                                                _maxStepReached = _step;
                                              }
                                            });
                                          } else {
                                            await _saveAndBuild();
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryGreen,
                                    foregroundColor: Colors.white,
                                    elevation: 4,
                                    shadowColor: primaryGreen.withOpacity(0.4),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: _saving 
                                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            _step == _totalSteps - 1 ? 'Tamamla' : 'Devam Et',
                                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(_step == _totalSteps - 1 ? Icons.check_circle : Icons.arrow_forward),
                                        ],
                                      ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}