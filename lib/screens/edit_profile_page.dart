import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttergirdi/services/user_profile_service.dart';
import 'package:fluttergirdi/services/letterboxd_service.dart'; // EKLENDİ: Veri çekmek için gerekli
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io'; 
import 'package:image_picker/image_picker.dart'; 
import 'package:firebase_storage/firebase_storage.dart'; 
import '../services/text_filter_service.dart';

class EditProfilePage extends StatefulWidget {
  final Map<String, dynamic>? initialUserData; 
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
  File? _selectedImage; 
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() {
          _selectedImage = File(picked.path);
        });
      }
    } catch (e) {
      debugPrint('Resim seçme hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Resim seçilemedi.')),
      );
    }
  }

  void _applyInitial(Map<String, dynamic> data) {
    String val = (data['username'] ?? '').toString();
    if (val.isEmpty) {
      final user = FirebaseAuth.instance.currentUser;
      if (user?.displayName != null && user!.displayName!.isNotEmpty) {
        val = user.displayName!;
      }
    }
    _usernameCtrl.text = val;
    _bioCtrl.text = (data['bio'] ?? '').toString();
    _origUsername = (_usernameCtrl.text).trim().isEmpty ? null : _usernameCtrl.text.trim();

    _letterboxdCtrl.text = (data['letterboxdUsername'] ?? '').toString();

    _favDirectors.clear();
    final dArr = data['favDirectors'];
    if (dArr is List) {
      _favDirectors.addAll(dArr.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).toList());
    }
    _favDirectorCtrl.text = '';

    _favActors.clear();
    final aArr = data['favActors'];
    if (aArr is List) {
      _favActors.addAll(aArr.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).toList());
    }
    _favActorCtrl.text = '';

    final age = data['age'];
    if (age is int && age > 15) {
      _ageCtrl.text = age.toString();
    } else if (age is num && age.toInt() > 0) {
      _ageCtrl.text = age.toInt().toString();
    } else {
      _ageCtrl.text = '';
    }

    _origUsername = (_usernameCtrl.text).trim().isEmpty ? null : _usernameCtrl.text.trim();
    final lbStr = (_letterboxdCtrl.text).trim();
    _origLb = lbStr.isEmpty ? null : lbStr.toLowerCase();
    _origFavDirector = null; 
    _origFavActor = null;
    if (_ageCtrl.text.trim().isNotEmpty) {
      _origAge = int.tryParse(_ageCtrl.text.trim());
    } else {
      _origAge = null;
    }
    _origBio = (_bioCtrl.text).trim().isEmpty ? null : _bioCtrl.text.trim();
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialUserData != null) {
      _applyInitial(widget.initialUserData!);
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.initialUserData != null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      var doc = await ref.get(const GetOptions(source: Source.cache));
      if (!doc.exists) {
        doc = await ref.get(const GetOptions(source: Source.server));
      }
      final data = doc.data() ?? <String, dynamic>{};
      _applyInitial(data);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --- DÜZELTİLDİ: Artık sadece veritabanına yazmıyor, doğrudan sync işlemini çağırıyor ---
  Future<void> _requestLbRefresh() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final currLb = _letterboxdCtrl.text.trim();
    if (currLb.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce Letterboxd kullanıcı adını gir.')),
      );
      return;
    }

    setState(() => _saving = true); // İşlem olduğunu göster

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Letterboxd verileri çekiliyor...')),
      );

      // 1. DOĞRUDAN SCRAPING'İ ÇAĞIR
      await LetterboxdService.fullSyncOnboarding(
        uid: user.uid,
        lbUsername: currLb,
      );

      // 2. Kayıt tarihçesi tut (Opsiyonel)
      await FirebaseFirestore.instance
          .collection('userTasteProfiles')
          .doc(user.uid)
          .set({
            'refreshRequestedAt': FieldValue.serverTimestamp(),
            'refreshSource': 'manual_edit_profile',
          }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Letterboxd verileri başarıyla güncellendi!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yenileme hatası: $e')),
      );
    } finally {
      if(mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addDirector() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final raw = _favDirectorCtrl.text.trim();
    if (raw.isEmpty) return;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Yönetmen eklenemedi: $e')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Silinemedi: $e')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Oyuncu eklenemedi: $e')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Silinemedi: $e')),
      );
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
      String? uploadedPhotoUrl;
      if (_selectedImage != null) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('user_avatars')
            .child('${user.uid}.jpg');

        await storageRef.putFile(_selectedImage!);
        uploadedPhotoUrl = await storageRef.getDownloadURL();
        await user.updatePhotoURL(uploadedPhotoUrl);
      }
      final username = _usernameCtrl.text.trim();
      final bio = _bioCtrl.text.trim();
      if (TextFilterService.hasProfanity(username)) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Kullanıcı adı uygunsuz ifadeler içeriyor.')),
         );
         return;
      }

      if (TextFilterService.hasProfanity(bio)) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Biyografi uygunsuz ifadeler içeriyor.')),
         );
         return;
      }
      
      final favDirector = _favDirectorCtrl.text.trim();
      final favActor = _favActorCtrl.text.trim();
      final ageStr = _ageCtrl.text.trim();
      final age = int.tryParse(ageStr);
      final newLb = _letterboxdCtrl.text.trim().toLowerCase();

      Map<String, dynamic> payload = {};
      if (uploadedPhotoUrl != null) {
        payload['photoURL'] = uploadedPhotoUrl;
      }

      String? prevUsername = _origUsername;
      String? currUsername = username.isEmpty ? null : username;
      if (prevUsername != currUsername) {
        payload['username'] = (currUsername != null) ? currUsername : FieldValue.delete();
        if (currUsername != null) {
          payload['username_lc'] = currUsername.toLowerCase();
        } else {
          payload['username_lc'] = FieldValue.delete();
        }
      }

      String? prevBio = _origBio;
      String? currBio = bio.isEmpty ? null : bio;
      if (prevBio != currBio) {
        payload['bio'] = (currBio != null) ? currBio : FieldValue.delete();
      }

      String? prevFavDirector = _origFavDirector;
      String? currFavDirector = favDirector.isEmpty ? null : favDirector;
      if (prevFavDirector != currFavDirector) {
        payload['favoriteDirector'] = (currFavDirector != null) ? currFavDirector : FieldValue.delete();
      }

      String? prevFavActor = _origFavActor;
      String? currFavActor = favActor.isEmpty ? null : favActor;
      if (prevFavActor != currFavActor) {
        payload['favoriteActor'] = (currFavActor != null) ? currFavActor : FieldValue.delete();
      }

      int? prevAge = (_origAge != null && _origAge! > 0) ? _origAge : null;
      int? currAge = (age != null && age > 0) ? age : null;
      if (prevAge != currAge) {
        payload['age'] = (currAge != null) ? currAge : FieldValue.delete();
      }

      String? prevLb = _origLb;
      String? currLb = newLb.isEmpty ? null : newLb;
      bool lbChanged = prevLb != currLb;

      // --- LETTERBOXD DEĞİŞİMİ VE YENİDEN ÇEKME ---
      if (lbChanged) {
        if (currLb != null) {
          // Yeni kullanıcı adı kaydediliyor
          payload['letterboxdUsername'] = currLb;
          payload['letterboxdUsername_lc'] = currLb;
          payload['lbUsername'] = currLb;
          
          // Eskileri temizle (Önemli)
          payload['favoritesKeys'] = FieldValue.delete();
          payload['fiveStarKeys'] = FieldValue.delete();
          payload['dislikedKeys'] = FieldValue.delete();
          payload['watchlistKeys'] = FieldValue.delete();
          payload['watchlist'] = FieldValue.delete();
          payload['favorites'] = FieldValue.delete();
          
          await UserProfileService.instance.clearTasteProfile(user.uid);
        } else {
          // Letterboxd bağlantısını kaldır
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

      payload['updatedAt'] = FieldValue.serverTimestamp();

      // Firestore'u güncelle
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(payload, SetOptions(merge: true));

      try {
        final sp = await SharedPreferences.getInstance();
        if (currLb != null) {
          await sp.setString('lb_username_${user.uid}', currLb);
        } else {
          await sp.remove('lb_username_${user.uid}');
        }
      } catch (_) {}

      // --- DÜZELTME: Veri Çekme İşlemi Başlatılıyor ---
      if (lbChanged && currLb != null) {
        // Kullanıcıya bilgi ver
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil güncellendi. Letterboxd verileri çekiliyor... (Bu işlem 1-2 dk sürebilir)')),
        );

        // DOĞRUDAN SENKRONİZASYON BAŞLAT (Backend trigger yerine)
        try {
          await LetterboxdService.fullSyncOnboarding(
            uid: user.uid, 
            lbUsername: currLb
          );
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Letterboxd verileri başarıyla yüklendi!')),
          );
        } catch (e) {
          debugPrint("LB Sync Error: $e");
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profil kaydedildi ama Letterboxd verileri çekilemedi. "Yenile" butonunu kullanın.')),
          );
        }
      } else {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profil güncellendi.')));
      }

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
            Center(
              child: GestureDetector(
                onTap: _pickImage, 
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.grey.shade800,
                      backgroundImage: _selectedImage != null
                          ? FileImage(_selectedImage!)
                          : (FirebaseAuth.instance.currentUser?.photoURL != null
                              ? NetworkImage(FirebaseAuth.instance.currentUser!.photoURL!)
                              : null) as ImageProvider?,
                      child: (_selectedImage == null && 
                              FirebaseAuth.instance.currentUser?.photoURL == null)
                          ? const Icon(Icons.person, size: 50, color: Colors.white70)
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _Section(title: 'Profil'),
            TextFormField(
              controller: _usernameCtrl,
              decoration: InputDecoration(
                labelText: 'Kullanıcı adı',
                hintText: _origUsername, 
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
              maxLength: 150, 
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
                  return null; 
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