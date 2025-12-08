import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';

// --- SAYFA IMPORTLARI ---
import 'package:fluttergirdi/screens/leaderboard_screen.dart';
import 'package:fluttergirdi/screens/badges_progress_screen.dart';
import 'package:fluttergirdi/screens/settings_page.dart';
import 'package:fluttergirdi/screens/clubs_tab.dart';

// --- SERVİS IMPORTU ---
// (Bu dosyanın projenizde lib/services/announcement_service.dart yolunda olduğunu varsayıyorum)
import 'package:fluttergirdi/services/announcement_service.dart';

class CustomDrawer extends StatelessWidget {
  const CustomDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    
    // Tema Durumu
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // --- RENK PALETİ (MAT VE DÜZ) ---
    // Arkaplan: Tam Siyah veya Tam Beyaz
    final backgroundColor = isDark ? const Color(0xFF121212) : Colors.white;
    
    // Yazılar
    final Color textColor = isDark ? Colors.white : const Color(0xFF1B5E20); // Koyu Yeşil (Light mod)
    final Color subTextColor = isDark ? Colors.white54 : Colors.grey.shade600;
    
    // İkonlar
    final Color iconColor = isDark ? Colors.white70 : const Color(0xFF2E7D32); 
    
    // Çizgiler
    final Color dividerColor = isDark ? Colors.white12 : Colors.black12;

    return Drawer(
      // Düz zemin rengi
      backgroundColor: backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(0)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // 1. HEADER
            _buildHeader(uid, textColor, subTextColor, isDark),

            // 2. İNCE ÇİZGİ (Mat)
            Divider(color: dividerColor, height: 1, thickness: 1),

            // 3. MENÜ LİSTESİ
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 10),
                children: [
                  _buildMenuItem(
                    context,
                    icon: Icons.bar_chart_rounded,
                    title: 'Liderlik Tablosu',
                    iconColor: iconColor,
                    textColor: textColor,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaderboardScreen())),
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.groups_rounded,
                    title: 'Kulüpler',
                    iconColor: iconColor,
                    textColor: textColor,
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text("Kulüpler")),
                        body: const ClubsTab(),
                      )));
                    },
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.emoji_events_rounded,
                    title: 'Rozet İlerlemesi',
                    iconColor: iconColor,
                    textColor: textColor,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BadgesProgressScreen())),
                  ),
                  
                  // --- YENİLİKLER (SERVİS ENTEGRASYONU) ---
                  _buildMenuItem(
                    context,
                    icon: Icons.campaign_rounded,
                    title: 'Yenilikler',
                    iconColor: iconColor,
                    textColor: textColor,
                    // Bildirim sayısı (Mat tasarım)
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.red.withOpacity(0.2) : Colors.red.shade50, 
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: isDark ? Colors.redAccent : Colors.red, width: 1)
                      ),
                      child: Text(
                        '1', 
                        style: TextStyle(
                          fontSize: 11, 
                          color: isDark ? Colors.redAccent : Colors.red.shade900, 
                          fontWeight: FontWeight.bold
                        )
                      ),
                    ),
                    onTap: () {
                      // Burada senin var olan servis dosyanı çağırıyoruz.
                      // Kullanıcı butona bastığında servis kontrol edip dialogu açacak.
                      AnnouncementService.instance.checkAndShowAnnouncement(context);
                    },
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Divider(color: dividerColor, height: 1, indent: 16, endIndent: 16),
                  ),

                  _buildMenuItem(
                    context,
                    icon: Icons.settings_rounded,
                    title: 'Ayarlar',
                    iconColor: iconColor,
                    textColor: textColor,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
                  ),
                  
                  _buildMenuItem(
                    context,
                    icon: Icons.person_add_alt_1_rounded,
                    title: 'Arkadaşlarını Davet Et',
                    iconColor: iconColor,
                    textColor: textColor,
                    onTap: () {
                      Share.share('MovieMatch ile film zevkini keşfet! Hemen indir: https://moviematch.app');
                    },
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.palette_rounded,
                    title: 'Tema Ayarları',
                    iconColor: iconColor,
                    textColor: textColor,
                    onTap: () {
                      _showThemeSelector(context);
                    },
                  ),

                  const SizedBox(height: 20),
                  Divider(color: dividerColor, height: 1),

                  _buildMenuItem(
                    context,
                    icon: Icons.logout_rounded,
                    title: 'Çıkış Yap',
                    isDestructive: true, 
                    // Çıkış butonu rengi (Mat Kırmızı)
                    iconColor: isDark ? const Color(0xFFEF5350) : const Color(0xFFC62828),
                    textColor: isDark ? const Color(0xFFEF5350) : const Color(0xFFC62828),
                    onTap: () async {
                      await FirebaseAuth.instance.signOut();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- YARDIMCI WIDGETLAR ---

  Widget _buildHeader(String? uid, Color textColor, Color subTextColor, bool isDark) {
    if (uid == null) return const SizedBox.shrink();

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final name = data?['displayName'] ?? data?['username'] ?? 'Kullanıcı';
        final email = FirebaseAuth.instance.currentUser?.email ?? '';
        final photo = data?['photoURL'];

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
          child: Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                backgroundImage: photo != null ? NetworkImage(photo) : null,
                child: photo == null 
                  ? Icon(Icons.person, size: 32, color: isDark ? Colors.white70 : Colors.grey.shade600) 
                  : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: TextStyle(color: subTextColor, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    required Color iconColor,
    required Color textColor,
    Widget? trailing,
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Icon(
        icon, 
        color: iconColor,
        size: 24,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: textColor,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: trailing,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
      dense: true,
      visualDensity: VisualDensity.compact,
    );
  }

  void _showThemeSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Görünüm", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.grey.shade200, shape: BoxShape.circle),
                child: const Icon(Icons.dark_mode_rounded, color: Colors.black),
              ),
              title: const Text("Karanlık Mod"),
              onTap: () {
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.orange.shade100, shape: BoxShape.circle),
                child: const Icon(Icons.light_mode_rounded, color: Colors.orange),
              ),
              title: const Text("Aydınlık Mod"),
              onTap: () {
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.blue.shade100, shape: BoxShape.circle),
                child: const Icon(Icons.settings_system_daydream_rounded, color: Colors.blue),
              ),
              title: const Text("Sistem Teması"),
              onTap: () {
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }
}