import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- SAYFA IMPORTLARI ---
import 'package:fluttergirdi/screens/leaderboard_screen.dart';
import 'package:fluttergirdi/screens/badges_progress_screen.dart';
import 'package:fluttergirdi/screens/settings_page.dart';
import 'package:fluttergirdi/screens/clubs_tab.dart';
import 'package:fluttergirdi/screens/profilescreen.dart'; // Dosya adı doğru
import 'package:fluttergirdi/theme.dart';

class CustomDrawer extends StatefulWidget {
  const CustomDrawer({super.key});

  @override
  State<CustomDrawer> createState() => _CustomDrawerState();
}

class _CustomDrawerState extends State<CustomDrawer> {
  String? _lastSeenAnnouncementId;

  @override
  void initState() {
    super.initState();
    _loadLastSeenId();
  }

  Future<void> _loadLastSeenId() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _lastSeenAnnouncementId = prefs.getString('last_seen_announcement_id');
      });
    }
  }

  Future<void> _markAnnouncementAsSeen(String currentId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_seen_announcement_id', currentId);
    if (mounted) {
      setState(() {
        _lastSeenAnnouncementId = currentId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final backgroundColor = isDark ? const Color(0xFF121212) : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white54 : Colors.grey.shade600;
    final Color iconColor = isDark ? Colors.white70 : Colors.black54;
    final Color dividerColor = isDark ? Colors.white12 : Colors.black12;

    return Drawer(
      backgroundColor: backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(0)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // 1. HEADER (Tıklanabilir yapıldı)
            _buildHeaderStream(uid, textColor, subTextColor, isDark),

            Divider(color: dividerColor, height: 1, thickness: 1),

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
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const LeaderboardScreen())),
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.groups_rounded,
                    title: 'Kulüpler',
                    iconColor: iconColor,
                    textColor: textColor,
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => Scaffold(
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
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const BadgesProgressScreen())),
                  ),

                  // --- YENİLİKLER ---
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('system')
                        .doc('announcement')
                        .snapshots(),
                    builder: (context, snapshot) {
                      Widget? trailingWidget;
                      String? currentId;

                      if (snapshot.hasData && snapshot.data!.exists) {
                        final data = snapshot.data!.data() as Map<String, dynamic>;
                        final bool isActive = data['isActive'] ?? false;
                        currentId = data['id'] ?? 'v0';

                        if (isActive &&
                            currentId != null &&
                            currentId != _lastSeenAnnouncementId) {
                          trailingWidget = Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          );
                        }
                      }

                      return _buildMenuItem(
                        context,
                        icon: Icons.campaign_rounded,
                        title: 'Yenilikler',
                        iconColor: iconColor,
                        textColor: textColor,
                        trailing: trailingWidget,
                        onTap: () {
                          if (currentId != null) {
                            _markAnnouncementAsSeen(currentId);
                          }
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const AnnouncementsScreen()));
                        },
                      );
                    },
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Divider(
                        color: dividerColor, height: 1, indent: 16, endIndent: 16),
                  ),

                  _buildMenuItem(
                    context,
                    icon: Icons.settings_rounded,
                    title: 'Ayarlar',
                    iconColor: iconColor,
                    textColor: textColor,
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const SettingsPage())),
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.person_add_alt_1_rounded,
                    title: 'Arkadaşlarını Davet Et',
                    iconColor: iconColor,
                    textColor: textColor,
                    onTap: () {
                      Share.share(
                          'MovieMatch ile film zevkini keşfet! Hemen indir: https://moviematch.app');
                    },
                  ),
                  _buildMenuItem(
                    context,
                    icon: Icons.palette_rounded,
                    title: 'Tema Ayarları',
                    iconColor: iconColor,
                    textColor: textColor,
                    onTap: () => _showThemeSelector(context),
                  ),

                  const SizedBox(height: 20),
                  Divider(color: dividerColor, height: 1),

                  _buildMenuItem(
                    context,
                    icon: Icons.logout_rounded,
                    title: 'Çıkış Yap',
                    isDestructive: true,
                    iconColor:
                        isDark ? const Color(0xFFEF5350) : const Color(0xFFC62828),
                    textColor:
                        isDark ? const Color(0xFFEF5350) : const Color(0xFFC62828),
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

  // --- HEADER (TIKLANABİLİR YAPILDI & DÜZELTİLDİ) ---
  Widget _buildHeaderStream(String? uid, Color textColor, Color subTextColor, bool isDark) {
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final name = data?['displayName'] ?? data?['username'] ?? 'Kullanıcı';
        final email = FirebaseAuth.instance.currentUser?.email ?? '';
        final photo = data?['photoURL'];

        return InkWell(
          onTap: () {
            // DÜZELTME: ProfileScreen -> ProfilePage
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor:
                      isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                  backgroundImage: photo != null ? NetworkImage(photo) : null,
                  child: photo == null
                      ? Icon(Icons.person,
                          size: 32,
                          color: isDark ? Colors.white70 : Colors.grey.shade600)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                            color: textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
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
      leading: Icon(icon, color: iconColor, size: 24),
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
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Görünüm",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 24),
            _buildThemeOption(ctx, Icons.dark_mode_rounded, "Karanlık Mod", ThemeMode.dark),
            const SizedBox(height: 12),
            _buildThemeOption(ctx, Icons.light_mode_rounded, "Aydınlık Mod", ThemeMode.light),
            const SizedBox(height: 12),
            _buildThemeOption(ctx, Icons.settings_system_daydream_rounded, "Sistem Teması", ThemeMode.system),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption(BuildContext ctx, IconData icon, String text, ThemeMode mode) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.grey.shade200, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.black87),
      ),
      title: Text(text),
      onTap: () async {
        ThemeBridge.themeMode.value = mode;
        final prefs = await SharedPreferences.getInstance();
        String modeStr = 'system';
        if (mode == ThemeMode.light) modeStr = 'light';
        if (mode == ThemeMode.dark) modeStr = 'dark';
        await prefs.setString('themeMode', modeStr);
        
        if (ctx.mounted) Navigator.pop(ctx);
      },
    );
  }
}

class AnnouncementsScreen extends StatelessWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yenilikler & Duyurular'),
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('system').doc('announcement').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return _buildEmptyState();
          }
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final List items = data['items'] ?? [];

          if (items.isEmpty) {
             final title = data['title'] as String?;
             final message = data['message'] as String?;
             if (title != null && message != null) {
               items.add({'title': title, 'message': message, 'date': Timestamp.now()});
             } else {
               return _buildEmptyState();
             }
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final item = items[index] as Map<String, dynamic>;
              return _buildAnnouncementCard(context, item, isDark);
            },
          );
        },
      ),
    );
  }
  
  Widget _buildEmptyState() {
     return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_off_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('Henüz bir duyuru yok.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
  }

  Widget _buildAnnouncementCard(BuildContext context, Map<String, dynamic> item, bool isDark) {
      final title = item['title'] ?? 'Duyuru';
      final message = item['message'] ?? '';
      final date = (item['date'] as Timestamp?)?.toDate();
      
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade900 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
          ],
          border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.campaign, color: Theme.of(context).primaryColor),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                if (date != null)
                  Text("${date.day}.${date.month}.${date.year}", style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            Text(message, style: TextStyle(color: isDark ? Colors.grey.shade300 : Colors.grey.shade700, height: 1.5)),
          ],
        ),
      );
  }
}