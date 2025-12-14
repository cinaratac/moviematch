import 'dart:async'; 
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/create_club_screen.dart';
import 'package:fluttergirdi/services/club_service.dart';
import 'package:fluttergirdi/widgets/club_card.dart'; // <--- YENİ KART TASARIMI EKLENDİ


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

  // Verileri hafızada tutuyoruz (Local Filtering)
  List<DocumentSnapshot> _allClubs = []; 
  bool _isLoading = true; 
  StreamSubscription? _streamSub; 

  @override
  void initState() {
    super.initState();
    // Firebase'i dinle ve veriyi hafızaya al
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

    // YEREL FİLTRELEME
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
                      // 1. Hiç veri yoksa
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

                      // 2. Arama sonucu boşsa
                      if (filteredClubs.isEmpty) {
                        return const Center(
                          child: Text(
                            "Kulüp bulunamadı",
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                        );
                      }

                      // 3. Listeyi Göster (YENİ KART TASARIMI İLE)
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                        itemCount: filteredClubs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 16),
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        itemBuilder: (context, index) {
                          // BURADA ARTIK YENİ 'ClubCard' WIDGET'INI KULLANIYORUZ
                          // Parametre olarak DocumentSnapshot (doc) gönderiyoruz.
                          return ClubCard(doc: filteredClubs[index]);
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