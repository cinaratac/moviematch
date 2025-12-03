import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttergirdi/services/user_profile_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EditProfilePage extends StatefulWidget {
  final Map<String, dynamic>?
  initialUserData; // optional pre-fetched user doc data
  const EditProfilePage({super.key, this.initialUserData});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _letterboxdCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _favDirectorCtrl = TextEditingController();
  final _favActorCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();

  final List<String> _favDirectors = [];
  final List<String> _favActors = [];

  String? _origUsername;
  String? _origBio;
  String? _origLb;
  String? _origFavDirector;
  String? _origFavActor;
  int? _origAge;

  bool _loading = true;
  bool _saving = false;

  void _applyInitial(Map<String, dynamic> data) {
    // ---------------------------------------------------------
    // 1. KULLANICI ADI (Firestore Öncelikli, Yoksa Auth)
    // ---------------------------------------------------------
    String val = (data['username'] ?? '').toString();

    // Eğer Firestore'da 'username' alanı boşsa veya yoksa,
    // FirebaseAuth (Google/Apple) profilindeki isme bak.
    if (val.isEmpty) {
      final user = FirebaseAuth.instance.currentUser;
      if (user?.displayName != null && user!.displayName!.isNotEmpty) {
        val = user.displayName!;
      }
    }
    _usernameCtrl.text = val;
    // --- BİYOGRAFİ YÜKLEME ---
    _bioCtrl.text = (data['bio'] ?? '').toString();
    // -------------------------
    _origUsername = (_usernameCtrl.text).trim().isEmpty ? null : _usernameCtrl.text.trim();

    // ---------------------------------------------------------
    // 2. LETTERBOXD KULLANICI ADI
    // ---------------------------------------------------------
    _letterboxdCtrl.text = (data['letterboxdUsername'] ?? '').toString();

    // ---------------------------------------------------------
    // 3. FAVORİ YÖNETMENLER (Liste veya String Desteği)
    // ---------------------------------------------------------
    _favDirectors.clear();
    final dArr = data['favDirectors'];
    if (dArr is List) {
      // Eğer veritabanında liste olarak kayıtlıysa (Yeni versiyon)
      _favDirectors.addAll(
        dArr
            .whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
      );
    } else {
      // Eğer veritabanında tek satır string ise (Eski versiyon fallback)
      final v1 = data['favoriteDirector'];
      final v2 = data['favDirector'];
      final s = (v1 is String && v1.trim().isNotEmpty)
          ? v1.trim()
          : (v2 is String ? v2.trim() : '');
      if (s.isNotEmpty) {
        _favDirectors.addAll(
          s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
        );
      }
    }
    // Ekleme kutusu boş başlasın
    _favDirectorCtrl.text = '';

    // ---------------------------------------------------------
    // 4. FAVORİ OYUNCULAR (Liste veya String Desteği)
    // ---------------------------------------------------------
    _favActors.clear();
    final aArr = data['favActors'];
    if (aArr is List) {
      _favActors.addAll(
        aArr
            .whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
      );
    } else {
      // Fallback
      final v1 = data['favoriteActor'];
      final v2 = data['favActor'];
      final s = (v1 is String && v1.trim().isNotEmpty)
          ? v1.trim()
          : (v2 is String ? v2.trim() : '');
      if (s.isNotEmpty) {
        _favActors.addAll(
          s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
        );
      }
    }
    // Ekleme kutusu boş başlasın
    _favActorCtrl.text = '';

    // ---------------------------------------------------------
    // 5. YAŞ BİLGİSİ
    // ---------------------------------------------------------
    final age = data['age'];
    if (age is int && age > 15) {
      _ageCtrl.text = age.toString();
    } else if (age is num && age.toInt() > 0) {
      _ageCtrl.text = age.toInt().toString();
    } else {
      _ageCtrl.text = '';
    }

    // ---------------------------------------------------------
    // 6. ORİJİNAL DEĞERLERİ SAKLA (Değişiklik Kontrolü ve Hint Text İçin)
    // ---------------------------------------------------------
    
    // Kullanıcı adı hint text'i için orijinal değeri sakla
    _origUsername = (_usernameCtrl.text).trim().isEmpty
        ? null
        : _usernameCtrl.text.trim();

    // Letterboxd
    final lbStr = (_letterboxdCtrl.text).trim();
    _origLb = lbStr.isEmpty ? null : lbStr.toLowerCase();

    // Yönetmen/Oyuncu (Listeler üzerinden kontrol edildiği için text field orijinalleri boş kalabilir veya mantığına göre ayarlayabilirsin)
    // Ancak değişiklik kontrolü (dirty check) için şimdilik null bırakıyoruz çünkü çiplerle yönetiliyor.
    _origFavDirector = null; 
    _origFavActor = null;

    // Yaş
    if (_ageCtrl.text.trim().isNotEmpty) {
      _origAge = int.tryParse(_ageCtrl.text.trim());
    } else {
      _origAge = null;
    }
    // --- BİYOGRAFİ ORİJİNAL ---
    _origBio = (_bioCtrl.text).trim().isEmpty ? null : _bioCtrl.text.trim();
    // --------------------------
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialUserData != null) {
      _applyInitial(widget.initialUserData!);
      _loading = false;
    } else {
      // Fallback: keep current behavior (single read) if no initial data passed
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.initialUserData != null) {
      // Already applied in initState; no network read.
      if (mounted) setState(() => _loading = false);
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      // cache-first user doc
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      var doc = await ref.get(const GetOptions(source: Source.cache));
      if (!doc.exists) {
        doc = await ref.get(const GetOptions(source: Source.server));
      }
      final data = doc.data() ?? <String, dynamic>{};
      _applyInitial(data);
    } catch (_) {
      // no-op; show empty form
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestLbRefresh() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final currLb = _letterboxdCtrl.text.trim();
    if (currLb.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce Letterboxd kullanıcı adını gir.')),
      );
      return; // do not write refresh request when LB username is empty
    }
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

  Future<void> _addDirector() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final raw = _favDirectorCtrl.text.trim();
    if (raw.isEmpty) return;
    // Prevent duplicates (case-insensitive)
    final exists = _favDirectors.any(
      (e) => e.toLowerCase() == raw.toLowerCase(),
    );
    if (exists) {
      _favDirectorCtrl.clear();
      return;
    }
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'favDirectors': FieldValue.arrayUnion([raw]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() {
        _favDirectors.add(raw);
        _favDirectorCtrl.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Yönetmen eklenemedi: $e')));
    }
  }

  Future<void> _removeDirector(String name) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'favDirectors': FieldValue.arrayRemove([name]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() {
        _favDirectors.removeWhere((e) => e == name);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Silinemedi: $e')));
    }
  }

  Future<void> _addActor() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final raw = _favActorCtrl.text.trim();
    if (raw.isEmpty) return;
    final exists = _favActors.any((e) => e.toLowerCase() == raw.toLowerCase());
    if (exists) {
      _favActorCtrl.clear();
      return;
    }
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'favActors': FieldValue.arrayUnion([raw]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() {
        _favActors.add(raw);
        _favActorCtrl.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Oyuncu eklenemedi: $e')));
    }
  }

  Future<void> _removeActor(String name) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'favActors': FieldValue.arrayRemove([name]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      setState(() {
        _favActors.removeWhere((e) => e == name);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Silinemedi: $e')));
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
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
      final bio = _bioCtrl.text.trim();
      final favDirector = _favDirectorCtrl.text.trim();
      final favActor = _favActorCtrl.text.trim();
      final ageStr = _ageCtrl.text.trim();
      final age = int.tryParse(ageStr);
      final newLb = _letterboxdCtrl.text.trim().toLowerCase();

      Map<String, dynamic> payload = {};


      String? prevUsername = _origUsername;
      String? currUsername = username.isEmpty ? null : username;
      if (prevUsername != currUsername) {
        payload['username'] = (currUsername != null)
            ? currUsername
            : FieldValue.delete();
            if (currUsername != null) {
          payload['username_lc'] = currUsername.toLowerCase();
        } else {
          payload['username_lc'] = FieldValue.delete();
        }
      }


      // --- BİYOGRAFİ DEĞİŞİKLİK KONTROLÜ ---
      String? prevBio = _origBio;
      String? currBio = bio.isEmpty ? null : bio;
      if (prevBio != currBio) {
        // Eğer boşsa veritabanından 'bio' alanını sil, doluysa güncelle
        payload['bio'] = (currBio != null) ? currBio : FieldValue.delete();
      }

      String? prevFavDirector = _origFavDirector;
      String? currFavDirector = favDirector.isEmpty ? null : favDirector;
      if (prevFavDirector != currFavDirector) {
        payload['favoriteDirector'] = (currFavDirector != null)
            ? currFavDirector
            : FieldValue.delete();
      }

      String? prevFavActor = _origFavActor;
      String? currFavActor = favActor.isEmpty ? null : favActor;
      if (prevFavActor != currFavActor) {
        payload['favoriteActor'] = (currFavActor != null)
            ? currFavActor
            : FieldValue.delete();
      }

      int? prevAge = (_origAge != null && _origAge! > 0) ? _origAge : null;
      int? currAge = (age != null && age > 0) ? age : null;
      if (prevAge != currAge) {
        payload['age'] = (currAge != null) ? currAge : FieldValue.delete();
      }

      String? prevLb = _origLb; // already lowercased in _load originals
      String? currLb = newLb.isEmpty ? null : newLb; // already lowercased above
      bool lbChanged = prevLb != currLb;
      if (lbChanged) {
        if (currLb != null) {
          payload['letterboxdUsername'] = currLb;
          payload['letterboxdUsername_lc'] = currLb; // normalized
          payload['lbUsername'] = currLb; // legacy compatibility
          payload['favoritesKeys'] = FieldValue.delete();
          payload['fiveStarKeys'] = FieldValue.delete();
          payload['dislikedKeys'] = FieldValue.delete();
          payload['watchlistKeys'] = FieldValue.delete();
          payload['watchlist'] = FieldValue.delete();
          payload['favorites'] = FieldValue.delete();
          await UserProfileService.instance.clearTasteProfile(user.uid);
        } else {
          payload['favoritesKeys'] = FieldValue.delete();
          payload['fiveStarKeys'] = FieldValue.delete();
          payload['dislikedKeys'] = FieldValue.delete();
          payload['watchlistKeys'] = FieldValue.delete();
          payload['watchlist'] = FieldValue.delete(); 
          payload['favorites'] = FieldValue.delete();
          payload['letterboxdUsername'] = FieldValue.delete();
          payload['letterboxdUsername_lc'] = FieldValue.delete();
          payload['lbUsername'] = FieldValue.delete();
          await UserProfileService.instance.clearTasteProfile(user.uid);
        }
      }

      // only set updatedAt if there is a real change
      payload['updatedAt'] = FieldValue.serverTimestamp();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(payload, SetOptions(merge: true));

      // Persist lbUsername in SharedPreferences for instant update in other screens
      try {
        final sp = await SharedPreferences.getInstance();
        if (currLb != null) {
          await sp.setString('lb_username_${user.uid}', currLb);
        } else {
          await sp.remove('lb_username_${user.uid}');
        }
      } catch (_) {}

      try {
        if (lbChanged && currLb != null) {
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
      final msg = (lbChanged && currLb != null)
          ? 'Profil güncellendi. Letterboxd eşitlemesi başlatıldı.'
          : 'Profil güncellendi.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

      // sync originals with the just-saved state
      _origUsername = currUsername;
      _origBio = currBio;
      _origFavDirector = currFavDirector;
      _origFavActor = currFavActor;
      _origAge = currAge;
      _origLb = currLb;

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
              decoration: InputDecoration(
                labelText: 'Kullanıcı adı',
                hintText: _origUsername, // <-- MEVCUT KULLANICI ADI SİLİK YAZI OLARAK GÖRÜNÜR
              ),
              textInputAction: TextInputAction.next,
              validator: (v) {
                if (v == null || v.isEmpty) return null;
                final rx = RegExp(r'^[a-zA-Z0-9_.\-]{3,20}$');
                if (!rx.hasMatch(v)) return '3-20 karakter, harf/rakam/_ . -';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bioCtrl,
              decoration: const InputDecoration(
                labelText: 'Biyografi',
                hintText: 'Kendinden veya film zevkinden bahset...',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.newline,
              keyboardType: TextInputType.multiline,
              maxLines: 3,
              maxLength: 150, // İsteğe bağlı karakter sınırı
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

            // Directors chips + add box
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Favori yönetmenler',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _favDirectors
                  .map(
                    (name) => Chip(
                      label: Text(name),
                      onDeleted: _saving ? null : () => _removeDirector(name),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _favDirectorCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Yeni yönetmen ekle',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addDirector(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _saving ? null : _addDirector,
                  tooltip: 'Ekle',
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Actors chips + add box
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Favori oyuncular',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _favActors
                  .map(
                    (name) => Chip(
                      label: Text(name),
                      onDeleted: _saving ? null : () => _removeActor(name),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _favActorCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Yeni oyuncu ekle',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addActor(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _saving ? null : _addActor,
                  tooltip: 'Ekle',
                ),
              ],
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
                if (n == null || n <= 15 || n > 120) return 'Geçersiz yaş';
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
