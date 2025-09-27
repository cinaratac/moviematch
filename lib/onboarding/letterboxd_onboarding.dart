import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/shell.dart';
import 'package:fluttergirdi/services/user_profile_service.dart';
import 'package:fluttergirdi/services/match_service.dart';

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

  int? _parseAge(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final v = int.tryParse(t);
    if (v == null) return null;
    if (v < 13 || v > 120) return null;
    return v;
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
    try {
      final raw = _controller.text.trim();

      // Auth kontrolü
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid;
      if (uid == null) {
        throw 'Oturum bulunamadı';
      }

      // 1) Firestore: kullanıcı dökümanına Letterboxd kullanıcı adını ve tercihleri yaz
      final ageVal = _parseAge(_ageController.text);
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'letterboxdUsername': raw,
        'letterboxdUsername_lc': raw.toLowerCase(),
        'age': ageVal, // null yazılırsa merge ile sorun olmaz
        'favGenres': _selectedGenres.toList(),
        'favDirectors': _favDirectors,
        'favActors': _favActors,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2) TasteProfile oluştur (eşleşme sistemi için zorunlu)
      //    Bu çağrı users/{uid} belgesindeki letterboxdUsername alanını okur,
      //    Letterboxd’dan verileri çekip tasteProfiles/{uid} belgesini yazar.
      await UserProfileService.instance.saveFromLetterboxd(
        uid: uid,
        lbUsername: raw,
      );

      // 3) Eşleşmeleri otomatik üret (önce yalnızca 5★, ardından genel kural)
      try {
        await MatchService().autoCreateMatchesFiveOnly(uid, minCommonFive: 1);
      } catch (e) {
        debugPrint('autoCreateMatchesFiveOnly error: $e');
      }
      try {
        await MatchService().autoCreateMatches(
          uid,
          minCommonFive: 1,
          minCommonFav: 1,
          minCommonDisliked: 1,
        );
      } catch (e) {
        debugPrint('autoCreateMatches error: $e');
      }

      if (!mounted) return;
      // Başarılı → ana uygulamaya geç
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeShell()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydetme/Profil oluşturma hatası: $e')),
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
                      const Text(
                        'Letterboxd kullanıcı adını gir. Kaydettikten sonra film beğenilerin çekilecek ve eşleşme sistemi için profilin oluşturulacak.',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          labelText: 'Kullanıcı adı',
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.next,
                        validator: _validator,
                        onFieldSubmitted: (_) => _saveAndBuild(),
                      ),
                      const SizedBox(height: 16),

                      // Yaş
                      TextFormField(
                        controller: _ageController,
                        decoration: const InputDecoration(
                          labelText: 'Yaş ',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),

                      // Sevdiği Türler (çoklu seçim)
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
                      const SizedBox(height: 16),

                      // Yönetmenler
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
                      const SizedBox(height: 16),

                      // Oyuncular
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

                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _saveAndBuild,
                          icon: const Icon(Icons.check),
                          label: _saving
                              ? const Text('Hazırlanıyor...')
                              : const Text('Kaydet ve eşleşmeleri hazırla'),
                        ),
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
