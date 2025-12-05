import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'; // Resim seçici
import 'package:fluttergirdi/screens/chat_room_screen.dart';
import 'package:fluttergirdi/services/club_service.dart';

class ClubsTab extends StatelessWidget {
  const ClubsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: StreamBuilder<QuerySnapshot>(
        stream: ClubService.instance.getClubsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.groups_3_outlined, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text("Henüz bir kulüp yok. İlkini sen kur!", style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              return _ClubCard(data: data);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'create_club',
        onPressed: () => _showCreateClubSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showCreateClubSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _CreateClubSheet(),
    );
  }
}

class _ClubCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ClubCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final members = List<String>.from(data['members'] ?? []);
    final pending = List<String>.from(data['pendingRequests'] ?? []);
    final ownerId = data['ownerId'];
    final isPrivate = data['isPrivate'] == true;
    final isMember = members.contains(myUid);
    final isPending = pending.contains(myUid);
    final isOwner = ownerId == myUid;
    final imageUrl = data['imageUrl'] as String?; // Resim URL'i

    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (isMember) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatRoomScreen(
                  chatId: data['id'],
                  otherUid: '', 
                  isGroup: true,
                  groupName: data['name'],
                ),
              ),
            );
          } else if (isOwner && pending.isNotEmpty) {
            _showRequestsDialog(context, data['id'], pending);
          } else if (!isPending) {
            _showJoinDialog(context, data['id'], data['name'], isPrivate);
          }
        },
        child: Column(
          children: [
            // --- KULÜP RESMİ ALANI ---
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                // Resim varsa göster, yoksa gradient
                image: (imageUrl != null && imageUrl.isNotEmpty) 
                    ? DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover)
                    : null,
                gradient: (imageUrl == null || imageUrl.isEmpty)
                    ? LinearGradient(
                        colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
              ),
              child: (imageUrl == null || imageUrl.isEmpty)
                  ? Center(child: Icon(Icons.groups, size: 48, color: Colors.white.withOpacity(0.8)))
                  : null,
            ),
            
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          data['name'] ?? 'İsimsiz Kulüp',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isPrivate)
                        const Icon(Icons.lock_outline, size: 16, color: Colors.grey),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data['description'] ?? 'Açıklama yok.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.person, size: 14, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text('${members.length} Üye', style: theme.textTheme.labelMedium),
                      const Spacer(),
                      
                      if (isMember)
                        Chip(label: const Text('Gir'), backgroundColor: theme.colorScheme.primaryContainer, visualDensity: VisualDensity.compact)
                      else if (isPending)
                        const Chip(label: Text('Bekleniyor...'), visualDensity: VisualDensity.compact)
                      else
                        FilledButton.tonal(
                          onPressed: () => _showJoinDialog(context, data['id'], data['name'], isPrivate),
                          child: Text(isPrivate ? 'İstek Gönder' : 'Katıl'),
                        ),
                    ],
                  ),
                  if (isOwner && pending.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: InkWell(
                        onTap: () => _showRequestsDialog(context, data['id'], pending),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.notifications_active, size: 16, color: Colors.deepOrange),
                              const SizedBox(width: 6),
                              Text('${pending.length} kişi katılmak istiyor', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showJoinDialog(BuildContext context, String clubId, String name, bool isPrivate) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isPrivate ? 'İstek Gönder' : 'Kulübe Katıl'),
        content: Text(isPrivate 
          ? '$name kulübü gizli bir kulüp. Katılmak için yöneticinin onayı gerekiyor.' 
          : '$name kulübüne katılmak üzeresin.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () {
              ClubService.instance.joinClub(clubId, isPrivate);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('İşlem yapıldı.')));
            },
            child: Text(isPrivate ? 'Gönder' : 'Katıl'),
          ),
        ],
      ),
    );
  }

  void _showRequestsDialog(BuildContext context, String clubId, List<String> pendingUids) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Katılım İstekleri', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const Divider(),
          if (pendingUids.isEmpty) const Text("Bekleyen istek yok."),
          ...pendingUids.map((uid) => FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
            builder: (context, snap) {
              if (!snap.hasData) return const LinearProgressIndicator();
              final userData = snap.data!.data() as Map<String, dynamic>;
              return ListTile(
                leading: CircleAvatar(backgroundImage: NetworkImage(userData['photoURL'] ?? '')),
                title: Text(userData['displayName'] ?? 'Kullanıcı'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.check, color: Colors.green),
                      onPressed: () => ClubService.instance.approveMember(clubId, uid),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => ClubService.instance.rejectMember(clubId, uid),
                    ),
                  ],
                ),
              );
            },
          )),
        ],
      ),
    );
  }
}

// --- KULÜP OLUŞTURMA SAYFASI (GÜNCELLENMİŞ) ---
class _CreateClubSheet extends StatefulWidget {
  const _CreateClubSheet();

  @override
  State<_CreateClubSheet> createState() => _CreateClubSheetState();
}

class _CreateClubSheetState extends State<_CreateClubSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _isPrivate = false;
  bool _isLoading = false;
  
  // Resim Seçimi İçin
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _imageFile = File(picked.path);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView( // Klavye açılınca taşmasın diye
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Yeni Kulüp Oluştur', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              
              // RESİM SEÇME ALANI
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.withOpacity(0.3)),
                      image: _imageFile != null 
                          ? DecorationImage(image: FileImage(_imageFile!), fit: BoxFit.cover)
                          : null,
                    ),
                    child: _imageFile == null 
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_a_photo, size: 32, color: theme.colorScheme.primary),
                              const SizedBox(height: 8),
                              const Text("Kulüp Resmi Ekle"),
                            ],
                          )
                        : null,
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Kulüp İsmi (Zorunlu)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.groups),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Açıklama (İsteğe bağlı)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Gizli Kulüp'),
                subtitle: const Text('Üyeler sadece onay ile katılabilir.'),
                value: _isPrivate,
                onChanged: (v) => setState(() => _isPrivate = v),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _isLoading ? null : _create,
                  child: _isLoading 
                    ? const CircularProgressIndicator() 
                    : const Text('Oluştur'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() => _isLoading = true);
    
    try {
      String? imageUrl;

      // 1. Resmi Storage'a Yükle (Eğer seçildiyse)
      if (_imageFile != null) {
        final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
        final ref = FirebaseStorage.instance.ref().child('club_images/$fileName');
        await ref.putFile(_imageFile!);
        imageUrl = await ref.getDownloadURL();
      }

      // 2. Kulübü Oluştur (URL ile)
      await ClubService.instance.createClub(
        name: name,
        description: _descCtrl.text.trim(),
        isPrivate: _isPrivate,
        imageUrl: imageUrl, // URL'i servise gönder
      );
      
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('Kulüp oluşturma hatası: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}