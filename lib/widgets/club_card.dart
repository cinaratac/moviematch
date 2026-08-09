import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluttergirdi/services/club_service.dart';
import 'package:fluttergirdi/screens/chat_room_screen.dart';

class ClubCard extends StatelessWidget {
  final DocumentSnapshot doc;
  final bool isJoinedView;

  const ClubCard({
    super.key, 
    required this.doc, 
    this.isJoinedView = false
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    
    final String name = data['name'] ?? 'İsimsiz Kulüp';
    final String desc = data['description'] ?? '';
    final String imageUrl = data['imageUrl'] ?? '';
    final bool isPrivate = data['isPrivate'] ?? false;
    final List members = data['members'] ?? [];
    final List pending = data['pendingRequests'] ?? [];
    
    final bool isMember = members.contains(currentUid);
    final bool isPending = pending.contains(currentUid);
    final int memberCount = members.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      height: 320,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // 1. ARKA PLAN RESMİ
            Positioned.fill(
              child: imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      // DÜZELTME: Alt tireler (__) yerine isimlendirilmiş değişkenler veya tekil kullanım
                      placeholder: (context, url) => Container(color: Colors.grey.shade900),
                      errorWidget: (context, url, error) => Container(color: Colors.grey.shade900),
                    )
                  : Container(
                      color: Colors.grey.shade900,
                      child: Icon(Icons.groups, size: 64, color: Colors.white.withValues(alpha: 0.1)),
                    ),
            ),

            // 2. SİNEMATİK GRADYAN
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.2),
                      Colors.black.withValues(alpha: 0.9),
                    ],
                    stops: const [0.4, 0.7, 1.0],
                  ),
                ),
              ),
            ),

            // 3. ÜST BİLGİ
            Positioned(
              top: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isPrivate ? Icons.lock_rounded : Icons.public_rounded,
                      color: Colors.white70, 
                      size: 14
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "$memberCount Üye",
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),

            // 4. ALT İÇERİK
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.toUpperCase(),
                      style: TextStyle(
                        fontFamily: 'Bebas Neue',
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 8),

                    if (desc.isNotEmpty)
                      Text(
                        desc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    
                    const SizedBox(height: 24),

                    _buildActionButton(context, isMember, isPending, isPrivate, data['id'], name),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, bool isMember, bool isPending, bool isPrivate, String clubId, String clubName) {
    String label;
    IconData icon;
    Color color;
    Color textColor;
    VoidCallback? onTap;

    if (isMember) {
      label = "GİRİŞ YAP";
      icon = Icons.arrow_forward_rounded;
      color = Colors.white;
      textColor = Colors.black;
      onTap = () {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => ChatRoomScreen(
            chatId: clubId,
            // DÜZELTME: Zorunlu 'otherUid' parametresi eklendi (Grup olduğu için boş string)
            otherUid: '', 
            // DÜZELTME: 'chatName' yerine 'otherTitle' kullanıldı
            otherTitle: clubName, 
            isGroup: true,
          )
        ));
      };
    } else if (isPending) {
      label = "BEKLENİYOR";
      icon = Icons.hourglass_empty_rounded;
      color = Colors.white.withValues(alpha: 0.2);
      textColor = Colors.white70;
      onTap = null;
    } else {
      label = isPrivate ? "İSTEK GÖNDER" : "KATIL";
      icon = isPrivate ? Icons.lock_open_rounded : Icons.add_circle_outline_rounded;
      color = const Color.fromARGB(255, 64, 184, 40); 
      textColor = Colors.white;
      onTap = () {
        ClubService.instance.joinClub(clubId, isPrivate);
      };
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 50,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isMember || (!isMember && !isPending) 
            ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 15, offset: const Offset(0, 5))]
            : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: textColor, 
                fontWeight: FontWeight.bold, 
                fontSize: 14, 
                letterSpacing: 1
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              Icon(icon, color: textColor, size: 18),
            ]
          ],
        ),
      ),
    );
  }
}