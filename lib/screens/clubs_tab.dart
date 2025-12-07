import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/chat_room_screen.dart';
import 'package:fluttergirdi/services/club_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

// --- 1. DRAWER'DAN AÇILAN HAVALI EKRAN ---
class ClubsScreen extends StatelessWidget {
  const ClubsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kulüpler', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: const ClubsTab(isStandalone: true), // Bağımsız mod
    );
  }
}

// --- 2. TAB İÇERİĞİ (HEM MESAJLARDA HEM BURADA KULLANILIR) ---
class ClubsTab extends StatelessWidget {
  final bool isStandalone;
  const ClubsTab({super.key, this.isStandalone = false});

  @override
  Widget build(BuildContext context) {
    // Scaffold yerine doğrudan içerik döndürüyoruz (Parent yönetiyor)
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
                  Icon(Icons.groups_3_outlined, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text("Henüz bir kulüp yok.\nİlkini sen kur!", 
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              return _ClubCard(data: data);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'create_club_fab',
        onPressed: () => _showCreateClubSheet(context),
        icon: const Icon(Icons.add),
        label: const Text("Kulüp Kur"),
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
    final imageUrl = data['imageUrl'] as String?;

    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- RESİM ---
            SizedBox(
              height: 140,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageUrl != null && imageUrl.isNotEmpty)
                    Image.network(imageUrl, fit: BoxFit.cover)
                  else
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [theme.colorScheme.primaryContainer, theme.colorScheme.secondaryContainer],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Center(child: Icon(Icons.groups, size: 50, color: theme.colorScheme.onPrimaryContainer.withOpacity(0.5))),
                    ),
                  if (isPrivate)
                    Positioned(
                      top: 12, right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                        child: const Row(
                          children: [Icon(Icons.lock, color: Colors.white, size: 12), SizedBox(width: 4), Text("Gizli", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // --- BİLGİLER ---
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data['name'] ?? 'İsimsiz',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  if (data['description'] != null && data['description'].toString().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      data['description'],
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _AvatarPile(count: members.length),
                      const SizedBox(width: 8),
                      Text('${members.length} Üye', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      if (isMember)
                        FilledButton.tonal(onPressed: null, child: const Text("Üyesin"))
                      else if (isPending)
                        OutlinedButton(onPressed: null, child: const Text("Bekleniyor"))
                      else
                        FilledButton(
                          onPressed: () => _showJoinDialog(context, data['id'], data['name'], isPrivate),
                          child: Text(isPrivate ? "İstek At" : "Katıl"),
                        ),
                    ],
                  ),
                  if (isOwner && pending.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: InkWell(
                        onTap: () => _showRequestsDialog(context, data['id'], pending),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.withOpacity(0.3))),
                          child: Row(children: [const Icon(Icons.info_outline, size: 16, color: Colors.orange), const SizedBox(width: 8), Text("${pending.length} onay bekleyen üye", style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold))]),
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
        title: Text(isPrivate ? 'İstek Gönder' : 'Katıl'),
        content: Text('"$name" kulübüne katılmak istiyor musun?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('İptal')),
          FilledButton(
            onPressed: () {
              ClubService.instance.joinClub(clubId, isPrivate);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('İşlem başarılı.')));
            },
            child: const Text('Evet'),
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
          ...pendingUids.map((uid) => FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
            builder: (context, snap) {
              if (!snap.hasData) return const SizedBox.shrink();
              final d = snap.data!.data() as Map<String, dynamic>;
              return ListTile(
                leading: CircleAvatar(backgroundImage: NetworkImage(d['photoURL'] ?? '')),
                title: Text(d['displayName'] ?? 'Kullanıcı'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.check, color: Colors.green), onPressed: () => ClubService.instance.approveMember(clubId, uid)),
                  IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => ClubService.instance.rejectMember(clubId, uid)),
                ]),
              );
            },
          )),
        ],
      ),
    );
  }
}

class _AvatarPile extends StatelessWidget {
  final int count;
  const _AvatarPile({required this.count});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 50, height: 24,
      child: Stack(
        children: [
          const Positioned(left: 0, child: CircleAvatar(radius: 12, backgroundColor: Colors.grey, child: Icon(Icons.person, size: 12, color: Colors.white))),
          if (count > 1) const Positioned(left: 15, child: CircleAvatar(radius: 12, backgroundColor: Colors.grey, child: Icon(Icons.person, size: 12, color: Colors.white))),
          if (count > 2) const Positioned(left: 30, child: CircleAvatar(radius: 12, backgroundColor: Colors.grey, child: Icon(Icons.person, size: 12, color: Colors.white))),
        ],
      ),
    );
  }
}

// ... (_CreateClubSheet aynı kalabilir, sadece yukarıya ekledik)
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
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _imageFile = File(picked.path));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Yeni Kulüp', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 100, width: 100,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                    image: _imageFile != null ? DecorationImage(image: FileImage(_imageFile!), fit: BoxFit.cover) : null,
                  ),
                  child: _imageFile == null ? const Icon(Icons.add_a_photo, size: 30, color: Colors.grey) : null,
                ),
              ),
              const SizedBox(height: 20),
              TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Kulüp İsmi', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _descCtrl, decoration: const InputDecoration(labelText: 'Açıklama', border: OutlineInputBorder()), maxLines: 2),
              SwitchListTile(title: const Text('Gizli Kulüp'), value: _isPrivate, onChanged: (v) => setState(() => _isPrivate = v)),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: _isLoading ? null : _create, child: _isLoading ? const CircularProgressIndicator() : const Text('Oluştur'))),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _create() async {
    if (_nameCtrl.text.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      String? url;
      if (_imageFile != null) {
        final ref = FirebaseStorage.instance.ref().child('club_images/${DateTime.now().millisecondsSinceEpoch}.jpg');
        await ref.putFile(_imageFile!);
        url = await ref.getDownloadURL();
      }
      await ClubService.instance.createClub(name: _nameCtrl.text.trim(), description: _descCtrl.text.trim(), isPrivate: _isPrivate, imageUrl: url);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}