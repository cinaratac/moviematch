import 'package:flutter/cupertino.dart'; // iOS widgetları
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluttergirdi/services/tab_service.dart';
// --- SAYFA IMPORTLARI ---
import 'package:fluttergirdi/screens/leaderboard_screen.dart';
import 'package:fluttergirdi/screens/badges_progress_screen.dart';
import 'package:fluttergirdi/screens/settings_page.dart';
import 'package:fluttergirdi/screens/clubs_tab.dart';
import '../screens/trivia_welcome_screen.dart';
import 'package:fluttergirdi/theme.dart';
import 'package:fluttergirdi/screens/admin_trivia_screen.dart'; 

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

    // OPTİMİZASYON: Blur yerine daha opak ve düz renk kullanımı
    // Blur efekti (BackdropFilter) animasyon sırasında FPS düşüşüne sebep olur.
    final Color drawerBgColor = isDark 
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.98) // Neredeyse opak siyah
        : const Color(0xFFF2F2F7).withValues(alpha: 0.98); // Neredeyse opak beyaz

    final Color separatorColor = isDark 
        ? Colors.white.withValues(alpha: 0.1) 
        : Colors.black.withValues(alpha: 0.05);

    return Drawer(
      backgroundColor: Colors.transparent, 
      elevation: 0,
      width: MediaQuery.of(context).size.width * 0.80, // Genişliği biraz düşürdük (Performans ve estetik için)
      child: Container(
        decoration: BoxDecoration(
          color: drawerBgColor,
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)), // Köşe yumuşatma
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 15,
              offset: const Offset(5, 0),
            )
          ]
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
          child: SafeArea(
            child: Column(
              children: [
                // PROFİL ALANI
                _buildProfileHeader(uid, isDark),

                const SizedBox(height: 10),

                // MENÜ LİSTESİ
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _buildSectionTitle("KEŞFET"),
                      _buildIOSMenuItem(
                        context,
                        icon: CupertinoIcons.chart_bar_alt_fill,
                        title: 'Liderlik Tablosu',
                        color: Colors.orange,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaderboardScreen())),
                      ),
                      _buildIOSMenuItem(
                        context,
                        icon: CupertinoIcons.person_3_fill,
                        title: 'Kulüpler',
                        color: Colors.blue,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text("Kulüpler")), body: const ClubsTab()))),
                      ),
                      _buildIOSMenuItem(
                        context,
                        icon: CupertinoIcons.star_fill,
                        title: 'Rozetler',
                        color: Colors.purple,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BadgesProgressScreen())),
                      ),
                      
                      const SizedBox(height: 8),

                      // --- YARIŞMA BUTONU ---
                      Material(
                        color: Colors.transparent,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.quiz_rounded, color: Colors.amber, size: 20),
                          ),
                          title: const Text(
                            'Sinema Yarışması',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          subtitle: Text(
                            'Bilgini test et, rozet kazan!',
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54),
                          ),
                          trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: isDark ? Colors.white24 : Colors.black12),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const TriviaWelcomeScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                      
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Divider(indent: 16, endIndent: 16, height: 1),
                      ),
                      
                      // YENİLİKLER
                      StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance.collection('system').doc('announcement').snapshots(),
                        builder: (context, snapshot) {
                          bool hasNew = false;
                          String? currentId;
                          if (snapshot.hasData && snapshot.data!.exists) {
                            final data = snapshot.data!.data() as Map<String, dynamic>;
                            if (data['isActive'] == true) {
                              currentId = data['id'];
                              if (currentId != null && currentId != _lastSeenAnnouncementId) {
                                hasNew = true;
                              }
                            }
                          }
                          return _buildIOSMenuItem(
                            context,
                            icon: CupertinoIcons.news_solid,
                            title: 'Yenilikler',
                            color: Colors.redAccent,
                            hasBadge: hasNew,
                            onTap: () {
                              if (currentId != null) _markAnnouncementAsSeen(currentId);
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const AnnouncementsScreen()));
                            },
                          );
                        },
                      ),

                      const SizedBox(height: 16),
                      Divider(height: 1, color: separatorColor),
                      const SizedBox(height: 16),
                      
                      if (uid == "RfpPtaZfaKYueG9b2dd2ASScqOO2") 
                        _buildIOSMenuItem(
                          context,
                          icon: CupertinoIcons.lock_shield_fill,
                          title: 'Admin Paneli (Gizli)',
                          color: Colors.red.shade900,
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context, 
                              MaterialPageRoute(builder: (_) => const AdminTriviaScreen())
                            );
                          },
                        ),

                      _buildSectionTitle("UYGULAMA"),
                      _buildIOSMenuItem(
                        context,
                        icon: CupertinoIcons.settings_solid,
                        title: 'Ayarlar',
                        color: Colors.grey,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
                      ),
                      _buildIOSMenuItem(
                        context,
                        icon: CupertinoIcons.share_solid,
                        title: 'Davet Et',
                        color: Colors.green,
                        onTap: () => Share.share('CineMatch ile film zevkini keşfet! https://Cinematch.app'),
                      ),
                      _buildIOSMenuItem(
                        context,
                        icon: CupertinoIcons.paintbrush_fill,
                        title: 'Görünüm',
                        color: Colors.indigo,
                        onTap: () => _showThemeSelector(context),
                      ),

                      const SizedBox(height: 30),
                      
                      // ÇIKIŞ BUTONU
                      Center(
                        child: TextButton(
                          onPressed: () async {
                            await FirebaseAuth.instance.signOut();
                          },
                          child: const Text(
                            "Çıkış Yap",
                            style: TextStyle(
                              color: CupertinoColors.destructiveRed,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- PROFİL HEADER ---
  Widget _buildProfileHeader(String? uid, bool isDark) {
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final name = data?['displayName'] ?? data?['username'] ?? 'Kullanıcı';
        final email = FirebaseAuth.instance.currentUser?.email ?? '';
        final photo = data?['photoURL'];

        return GestureDetector(
          onTap: () {
            Navigator.pop(context);
            TabService.instance.changeTab(3); 
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 5)),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 32, // Boyut biraz optimize edildi
                    backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                    backgroundImage: photo != null ? NetworkImage(photo) : null,
                    child: photo == null 
                      ? Icon(CupertinoIcons.person_fill, size: 32, color: isDark ? Colors.white54 : Colors.grey) 
                      : null,
                  ),
                ),
                const SizedBox(width: 16),
                
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black, letterSpacing: -0.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(email, style: TextStyle(fontSize: 13, color: isDark ? Colors.white54 : Colors.black54), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      Text("Profili Görüntüle", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).primaryColor)),
                    ],
                  ),
                ),
                Icon(CupertinoIcons.chevron_right, color: isDark ? Colors.white24 : Colors.black12, size: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- BÖLÜM BAŞLIĞI ---
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 8, top: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.grey.withValues(alpha: 0.8),
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  // --- MENÜ ELEMANI ---
  Widget _buildIOSMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    required Color color, 
    bool hasBadge = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
        highlightColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), // Padding azaltıldı
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, size: 16, color: Colors.white), // İkon boyutu optimize edildi
              ),
              const SizedBox(width: 16),
              
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15, // Font boyutu optimize edildi
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87,
                    letterSpacing: -0.3,
                  ),
                ),
              ),

              if (hasBadge)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: CupertinoColors.activeGreen,
                    shape: BoxShape.circle,
                  ),
                ),

              Icon(CupertinoIcons.chevron_right, size: 14, color: isDark ? Colors.white24 : Colors.black12),
            ],
          ),
        ),
      ),
    );
  }

  void _showThemeSelector(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        title: const Text('Görünüm Seçin'),
        actions: <CupertinoActionSheetAction>[
          CupertinoActionSheetAction(
            child: const Text('Karanlık Mod'),
            onPressed: () => _changeTheme(context, ThemeMode.dark, 'dark'),
          ),
          CupertinoActionSheetAction(
            child: const Text('Aydınlık Mod'),
            onPressed: () => _changeTheme(context, ThemeMode.light, 'light'),
          ),
          CupertinoActionSheetAction(
            child: const Text('Sistem Teması'),
            onPressed: () => _changeTheme(context, ThemeMode.system, 'system'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text('Vazgeç'),
        ),
      ),
    );
  }

  Future<void> _changeTheme(BuildContext context, ThemeMode mode, String modeStr) async {
    ThemeBridge.themeMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', modeStr);
    if (context.mounted) Navigator.pop(context);
  }
}

class AnnouncementsScreen extends StatelessWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : const Color(0xFFF2F2F7);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Yenilikler'),
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('system').doc('announcement').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data == null) return const Center(child: Text("Duyuru yok"));

          final items = data['items'] as List? ?? [];
          if (items.isEmpty) {
             final title = data['title'] as String?;
             final message = data['message'] as String?;
             if (title != null) items.add({'title': title, 'message': message, 'date': Timestamp.now()});
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final item = items[index];
              final date = (item['date'] as Timestamp?)?.toDate();
              
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(CupertinoIcons.sparkles, color: Colors.orange, size: 20),
                        const SizedBox(width: 8),
                        Text(item['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const Spacer(),
                        if(date != null) Text("${date.day}.${date.month}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(item['message'] ?? '', style: TextStyle(color: isDark ? Colors.grey[300] : Colors.black87, height: 1.4)),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}