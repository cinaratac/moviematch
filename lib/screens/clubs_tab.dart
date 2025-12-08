import 'dart:async'; // StreamSubscription için gerekli
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/chat_room_screen.dart';
import 'package:fluttergirdi/screens/create_club_screen.dart';
import 'package:fluttergirdi/services/club_service.dart';
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
      body: const ClubsTab(isStandalone: true),
    );
  }
}

// --- 2. TAB İÇERİĞİ ---
class ClubsTab extends StatefulWidget {
  final bool isStandalone;
  const ClubsTab({super.key, this.isStandalone = false});

  @override
  State<ClubsTab> createState() => _ClubsTabState();
}

class _ClubsTabState extends State<ClubsTab> {
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();

  // PERFORMANS ÇÖZÜMÜ: Verileri hafızada tutuyoruz
  List<DocumentSnapshot> _allClubs = []; // Tüm kulüpler burada duracak
  bool _isLoading = true; // İlk yükleme kontrolü
  StreamSubscription? _streamSub; // Canlı bağlantı kontrolcüsü

  @override
  void initState() {
    super.initState();
    // Sayfa açıldığında Firebase'i dinlemeye başla
    // StreamBuilder kullanmadığımız için bu bağlantı arama yaparken ASLA kopmaz/yenilenmez.
    _streamSub = ClubService.instance.getClubsStream().listen((snapshot) {
      if (mounted) {
        setState(() {
          _allClubs = snapshot.docs;
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    // Sayfadan çıkınca dinlemeyi durdur
    _streamSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _navigateToCreateClub(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateClubScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // --- YEREL FİLTRELEME (FIREBASE'E GİTMEZ) ---
    // Hafızadaki _allClubs listesini arama metnine göre süzüyoruz.
    final filteredClubs = _allClubs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final name = (data['name'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery);
    }).toList();

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Column(
        children: [
          // --- ARAMA ALANI ---
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                final cleanText = val.trim().toLowerCase();
                // Gereksiz setState'i önle
                if (_searchQuery != cleanText) {
                  setState(() {
                    _searchQuery = cleanText;
                  });
                }
              },
              decoration: InputDecoration(
                hintText: 'Kulüp ara...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          if (_searchQuery.isNotEmpty) {
                            setState(() {
                              _searchQuery = "";
                            });
                          }
                        },
                      )
                    : null,
              ),
            ),
          ),

          // --- KULÜP OLUŞTUR BUTONU ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: () => _navigateToCreateClub(context),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text("Yeni Kulüp Oluştur", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // --- LİSTE GÖRÜNÜMÜ ---
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Builder(
                    builder: (context) {
                      // 1. Hiç veri yoksa (Veritabanı boşsa)
                      if (_allClubs.isEmpty) {
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

                      // 2. Arama sonucu boşsa (Sadece istenen sade mesaj)
                      if (filteredClubs.isEmpty) {
                        return const Center(
                          child: Text(
                            "Kulüp bulunamadı",
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                        );
                      }

                      // 3. Listeyi Göster
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                        itemCount: filteredClubs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        itemBuilder: (context, index) {
                          final data = filteredClubs[index].data() as Map<String, dynamic>;
                          return _ClubCard(data: data);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// --- CARD SINIFI ---

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
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
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
                  otherTitle: data['name'],
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
                      child: Center(child: Icon(Icons.groups, size: 50, color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.5))),
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
                          decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.withValues(alpha: 0.3))),
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