import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/shell.dart';
import 'package:fluttergirdi/services/user_profile_service.dart';
import 'package:fluttergirdi/services/letterboxd_service.dart'; // Eklendi
import 'package:fluttergirdi/services/match_service.dart';
import 'package:flutter/services.dart'; 

class OnboardingLetterboxd extends StatefulWidget {
  const OnboardingLetterboxd({super.key});

  @override
  State<OnboardingLetterboxd> createState() => _OnboardingLetterboxdState();
}

class _OnboardingLetterboxdState extends State<OnboardingLetterboxd> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  final _ageController = TextEditingController();
  final _directorController = TextEditingController();
  final _actorController = TextEditingController();

  // ... (Geri kalan değişkenler ve _genreOptions listesi aynı kalacak) ...
  final List<String> _genreOptions = const [
    'Aksiyon',
    'Aksiyon-Gerilim',
    'Casus',
    'Dövüş',
    'Felaket',
    'Macera',
    "Klasikler",
    'Bilimkurgu',
    'Kıyamet Sonrası',
    'Steampunk',
    'Dram',
    'Melodram',
    'Politik Dram',
    'Tarihi Dram',
    'Trajedi',
    'Gerilim',
    'Psikolojik Gerilim',
    'Politik Gerilim',
    'Erotik Gerilim',
    'Komedi',
    'Aksiyon Komedisi',
    'Kara Mizah',
    'Komedi-Drama',
    'Romantik Komedi',
    'Parodi',
    'Korku',
    'Gotik',
    'Doğaüstü',
    'Vampir',
    'Zombi',
    'Slasher',
    'Fantastik',
    'Mitolojik',
    'K-drama',
    'Süper Kahraman',
    'Romantik',
    'Romantik Dram',
    'Romantik Gerilim',
    'Savaş',
    'Tarih',
    'Biyografi',
    'Müzikal',
    'Belgesel',
    'Doğa',
    'Gezi',
    'Spor',
    'Suç',
    'Polisiye',
    'Mafya',
    'Gizem',
    'Kara Film (Noir)',
    'Western',
    'Fantastik Komedi',
    'Aile',
    'Çocuk',
    'Gençlik',
    'LGBTQ+',
    'Animasyon',
    'Anime',
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
    // Eğer letterboxdUsername varsa, kullanıcı zaten onboarding'i tamamlamış demektir.
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
    if (v < 16 || v > 120) return null;
    return v;
  }

  // ... (_buildStepBar, _buildStepContent vs. aynı kalacak) ...
  Widget _buildStepBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: List.generate(_totalSteps, (i) {
        final bool done = i < _step;
        final bool current = i == _step;
        final Color color = done
            ? cs.primary
            : current
            ? cs.secondary
            : cs.outlineVariant;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              if (i <= _maxStepReached || i <= _step) {
                setState(() => _step = i);
              }
            },
            child: Container(
              height: 6,
              margin: EdgeInsets.only(right: i == _totalSteps - 1 ? 0 : 6),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStepContent(BuildContext context) {
    switch (_step) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Letterboxd kullanıcı adını gir. Kaydettikten sonra film beğenilerin çekilecek ve eşleşme sistemi için profilin oluşturulacak.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Letterboxd adı (İsteğe bağlı)',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              validator: _validator,
              onFieldSubmitted: (_) {},
            ),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Yaşın',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _ageController,
              decoration: const InputDecoration(
                labelText: 'Yaş',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              validator: (v) {
                if (v == null || v.isEmpty) return 'Yaş zorunlu';
                final val = int.tryParse(v);
                if (val == null) return 'Geçersiz değer';
                if (val < 16) return 'Uygulamayı kullanmak için 16+ olmalısınız';
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
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Sevdiğin türler',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _genreOptions.map((g) {
                final sel = _selectedGenres.contains(g);
                return FilterChip(
                  label: Text(g),
                  selected: sel,
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
          ],
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Sevdiğin yönetmenler',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _directorController,
              decoration: const InputDecoration(
                hintText: 'Bir yönetmen yaz ve Enter’a bas',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: _addDirector,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _favDirectors
                  .map(
                    (d) => InputChip(
                      label: Text(d),
                      onDeleted: () {
                        setState(() {
                          _favDirectors.remove(d);
                        });
                      },
                    ),
                  )
                  .toList(),
            ),
          ],
        );
      case 4:
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Sevdiğin oyuncular',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _actorController,
              decoration: const InputDecoration(
                hintText: 'Bir oyuncu yaz ve Enter’a bas',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: _addActor,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _favActors
                  .map(
                    (a) => InputChip(
                      label: Text(a),
                      onDeleted: () {
                        setState(() {
                          _favActors.remove(a);
                        });
                      },
                    ),
                  )
                  .toList(),
            ),
          ],
        );
    }
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

  // !!! DÜZELTİLDİ: Artık kayıt işlemi bloklayıcı ve garantici !!!
  Future<void> _saveAndBuild() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _saving = true);
    
    // Yükleme ekranını manuel göster (Dialog olarak, kullanıcı etkileşimini engellemek için)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: Dialog(
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text("Profilin oluşturuluyor...", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text("Letterboxd verilerin çekiliyor ve eşleşmeler ayarlanıyor. Bu işlem 1-2 dakika sürebilir, lütfen kapatmayın.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
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

      // 1. ÖNCE Letterboxd Senkronizasyonunu Dene (Eğer kullanıcı adı girilmişse)
      if (lbUsernameRaw.isNotEmpty) {
        await LetterboxdService.fullSyncOnboarding(uid: uid, lbUsername: lbUsernameRaw);
      }

      // 2. Senkronizasyon başarılıysa (veya kullanıcı adı yoksa) veritabanına kullanıcı verilerini yaz
      // Bu adım başarısız olursa yukarıdaki veriler Firestore'da olsa bile kullanıcı uygulamaya giremez (ki bu kabul edilebilir).
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

      // 3. Eşleşme algoritmasını tetikle (Eğer 5 yıldız yoksa bile diğer kriterler için)
      try {
        await MatchService.instance.autoCreateMatches(
            uid,
            minCommonFive: 1,
            minCommonFav: 1,
            minCommonDisliked: 1,
          );
      } catch (_) {}

      if (!mounted) return;
      // Dialog'u kapat
      Navigator.of(context).pop();
      
      // Ana sayfaya git
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (_) => false,
      );

    } catch (e) {
      if (!mounted) return;
      // Dialog'u kapat
      Navigator.of(context).pop();

      String msg = 'Bir hata oluştu: $e';
      if (e.toString().contains('Letterboxd kullanıcısı bulunamadı')) {
        msg = 'Girdiğin Letterboxd kullanıcı adı bulunamadı veya profili gizli. Lütfen kontrol et.';
      } else if (e.toString().contains('unavailable')) {
        msg = 'Sunucuya erişilemiyor. Lütfen internet bağlantını kontrol et.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
      // Hata durumunda _saving false olur ve kullanıcı ekranda kalır, düzeltme yapabilir.
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Profilini Oluştur!')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomInset),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildStepBar(context),
                      const SizedBox(height: 20),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: _buildStepContent(context),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: (_step == 0 || _saving)
                                  ? null
                                  : () => setState(() => _step = _step - 1),
                              icon: const Icon(Icons.chevron_left),
                              label: const Text('Geri'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
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
                              icon: _saving 
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                : Icon(_step == _totalSteps - 1 ? Icons.check : Icons.chevron_right),
                              label: Text(
                                _step == _totalSteps - 1
                                    ? 'Kaydet ve Başla'
                                    : 'İleri',
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
    );
  }
}