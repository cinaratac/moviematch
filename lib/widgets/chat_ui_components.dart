import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';
import 'package:fluttergirdi/services/club_service.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';
import 'package:fluttergirdi/widgets/club_sheets.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';

// --- HAFTANIN FİLMİ BANNERI ---
class FeaturedMovieBannerWidget extends StatelessWidget {
  final Map<String, dynamic> movie;
  const FeaturedMovieBannerWidget({super.key, required this.movie});

  @override
  Widget build(BuildContext context) {
    // Tema Ayarları
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF252525) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final border = isDark ? Colors.amber.withValues(alpha: 0.3) : Colors.amber.withValues(alpha: 0.5);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 1),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(bottom: BorderSide(color: border)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0,2))]
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (movie['id'] != null) {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => MovieDetailScreen(tmdbId: movie['id'])
                ));
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
                    child: const Icon(Icons.star, color: Colors.black, size: 16),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "HAFTANIN FİLMİ",
                          style: TextStyle(fontWeight: FontWeight.w900, color: Colors.amber, fontSize: 10, letterSpacing: 1),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          movie['title'] ?? 'Film',
                          style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- BOŞ SOHBET GÖRÜNÜMÜ ---
class EmptyChatView extends StatelessWidget {
  const EmptyChatView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white54 : Colors.black54;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 48, color: color),
          const SizedBox(height: 16),
          Text('Sohbete başla!', style: TextStyle(color: color)),
        ],
      ),
    );
  }
}

// --- MESAJ SATIRI ---
class MessageRow extends StatelessWidget {
  final String text;
  final dynamic movie;
  final bool isMine;
  final DateTime? timestamp;
  final String authorId;
  final String? type;      
  final dynamic eventData; 
  final dynamic pollData;  
  final String? chatId;    

  const MessageRow({
    super.key,
    required this.text,
    this.movie,
    required this.isMine,
    this.timestamp,
    required this.authorId,
    this.type,
    this.eventData,
    this.pollData,
    this.chatId,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end, 
        children: [
          if (!isMine) ...[
            UserAvatar(uid: authorId, size: 16),
            const SizedBox(width: 8),
          ],
          
          if (type == 'event' && eventData != null)
            _EventMessageBubble(data: eventData, isMine: isMine, timestamp: timestamp, chatId: chatId)
          else if (type == 'poll' && pollData != null)
            _PollMessageBubble(initialData: pollData, isMine: isMine, timestamp: timestamp, chatId: chatId)
          else
            MessageBubble(text: text, movie: movie, isMine: isMine, timestamp: timestamp),
            
          if (isMine) const SizedBox(width: 8), 
        ],
      ),
    );
  }
}

// --- MESAJ BALONU (STANDART) ---
// --- MESAJ BALONU (STANDART) ---
class MessageBubble extends StatelessWidget {
  final String text;
  final dynamic movie;
  final bool isMine;
  final DateTime? timestamp;

  const MessageBubble({
    super.key,
    required this.text,
    this.movie,
    required this.isMine,
    this.timestamp,
  });

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thatDay = DateTime(dt.year, dt.month, dt.day);
    if (thatDay == today) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // Tema
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    String posterUrl = '';
    String movieTitle = '';
    bool hasMovie = false;
    int? parsedMovieId;

    if (movie is Map) {
      final mm = Map<String, dynamic>.from(movie);
      posterUrl = (mm['poster'] ?? mm['posterUrl'] ?? '').toString();
      movieTitle = (mm['title'] ?? mm['name'] ?? '').toString();
      
      // Veritabanından gelen film objesi içindeki ID'yi olası tüm anahtarlarla arıyoruz
      final possibleKeys = ['id', 'tmdbId', 'movieId', 'movie_id'];
      for (String key in possibleKeys) {
        if (mm[key] != null) {
          parsedMovieId = int.tryParse(mm[key].toString());
          if (parsedMovieId != null) break; // Geçerli bir ID bulduysak döngüden çık
        }
      }
      
      hasMovie = true;
    }

    // Renkler
    final myGradient = LinearGradient(
      colors: [
        Theme.of(context).colorScheme.primary,
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    // Karşı tarafın mesajı: Dark -> Koyu Gri, Light -> Açık Gri (Neredeyse beyaz)
    final otherColor = isDark ? const Color(0xFF2C2C2E) : Colors.grey.shade200;
    final textColor = isMine ? Colors.white : (isDark ? Colors.white : Colors.black87);
    final timeColor = isMine ? Colors.white70 : (isDark ? Colors.white60 : Colors.black54);

    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.70; 
    const movieCardWidth = 200.0;

    return Container(
      constraints: BoxConstraints(maxWidth: maxBubbleWidth, minWidth: 40),
      decoration: BoxDecoration(
        gradient: isMine ? myGradient : null,
        color: isMine ? null : otherColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isMine ? 20 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasMovie)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  width: movieCardWidth,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.black26,
                  ),
                  clipBehavior: Clip.antiAlias,
                  // BURAYA MATERIAL VE INKWELL EKLENDİ (TIKLAMA VE ANİMASYON İÇİN)
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        if (parsedMovieId != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => MovieDetailScreen(
                                tmdbId: parsedMovieId!,
                                title: movieTitle.isNotEmpty ? movieTitle : null,
                                posterUrl: posterUrl.isNotEmpty ? posterUrl : null,
                              ),
                            ),
                          );
                        } else {
                          // BURAYI GÜNCELLEDİK: $mm yerine $movie kullanıyoruz
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('ID Bulunamadı! Gelen Veri: $movie'), 
                              backgroundColor: Colors.red,
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        }
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (posterUrl.isNotEmpty)
                            AspectRatio(
                              aspectRatio: 2 / 3,
                              child: PosterImage(posterUrl: posterUrl, title: movieTitle, fit: BoxFit.cover),
                            )
                          else
                            Container(
                              height: 120, width: double.infinity, color: Colors.grey.shade900,
                              child: const Center(child: Icon(Icons.movie, size: 32, color: Colors.white24)),
                            ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            color: Colors.black38,
                            child: Text(
                              movieTitle,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              if (text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: hasMovie ? movieCardWidth : maxBubbleWidth - 24),
                    child: Text(
                      text,
                      style: TextStyle(color: textColor, fontSize: 15, height: 1.3),
                    ),
                  ),
                ),

              if (timestamp != null)
                Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _formatTime(timestamp!),
                      style: TextStyle(fontSize: 10, color: timeColor),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- KULLANICI AVATARI (PERFORMANS İÇİN STATEFUL + KEEP ALIVE) ---
class UserAvatar extends StatefulWidget {
  final String uid;
  final double size;
  const UserAvatar({super.key, required this.uid, this.size = 20});

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> with AutomaticKeepAliveClientMixin {
  Stream<DocumentSnapshot>? _userStream;

  @override
  bool get wantKeepAlive => true; // Listeden çıkınca hafızadan silinmesin (Titremeyi önler)

  @override
  void initState() {
    super.initState();
    _userStream = FirebaseFirestore.instance.collection('users').doc(widget.uid).snapshots();
  }

  @override
  void didUpdateWidget(covariant UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.uid != oldWidget.uid) {
      _userStream = FirebaseFirestore.instance.collection('users').doc(widget.uid).snapshots();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // KeepAlive için gerekli
    return StreamBuilder<DocumentSnapshot>(
      stream: _userStream,
      builder: (context, snap) {
        String? url;
        if (snap.hasData && snap.data!.exists) {
          final data = snap.data!.data() as Map<String, dynamic>;
          url = data['photoURL'];
        }
        return CircleAvatar(
          radius: widget.size,
          backgroundImage: (url != null && url.isNotEmpty) ? NetworkImage(url) : null,
          child: (url == null || url.isEmpty) ? Icon(Icons.person, size: widget.size) : null,
        );
      },
    );
  }
}

// --- ETKİNLİK KARTI (Stateful + KeepAlive + Theme) ---
class _EventMessageBubble extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool isMine;
  final DateTime? timestamp;
  final String? chatId;

  const _EventMessageBubble({
    required this.data,
    required this.isMine,
    this.timestamp,
    this.chatId,
  });

  @override
  State<_EventMessageBubble> createState() => _EventMessageBubbleState();
}

class _EventMessageBubbleState extends State<_EventMessageBubble> with AutomaticKeepAliveClientMixin {
  Stream<DocumentSnapshot>? _eventStream;

  @override
  bool get wantKeepAlive => true; // Titremeyi önler

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  void _initStream() {
    final eventId = widget.data['id'];
    final chatId = widget.chatId;

    if (eventId != null && chatId != null) {
      _eventStream = FirebaseFirestore.instance
          .collection('clubs')
          .doc(chatId)
          .collection('events')
          .doc(eventId)
          .snapshots();
    }
  }

  @override
  void didUpdateWidget(covariant _EventMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data['id'] != oldWidget.data['id'] || widget.chatId != oldWidget.chatId) {
      _initStream();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Stream henüz yoksa veya yükleniyorsa, eldeki veriyi kullan
    if (_eventStream == null) {
      return _buildEventContent(context, widget.data, null, false);
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: _eventStream,
      builder: (context, snap) {
        // Hata veya silinme durumu
        if (snap.connectionState == ConnectionState.active && !snap.data!.exists) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: const Text("Bu etkinlik silindi.", style: TextStyle(color: Colors.grey, fontSize: 12)),
          );
        }

        // Bekleme durumunda flickering olmaması için widget.data'yı (mesajdaki statik veri) kullan
        final liveData = (snap.hasData && snap.data!.exists)
            ? snap.data!.data() as Map<String, dynamic>
            : widget.data; 
            
        final myUid = FirebaseAuth.instance.currentUser?.uid;
        final participants = List<String>.from(liveData['participants'] ?? []);
        final isJoined = participants.contains(myUid);
        final eventId = widget.data['id'];

        return _buildEventContent(context, liveData, eventId, isJoined);
      },
    );
  }

  Widget _buildEventContent(BuildContext context, Map<String, dynamic> eventMap, String? eventId, bool isJoined) {
    // Tema
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white; // Light modda beyaz
    final borderColor = isDark ? Colors.white10 : Colors.black12;
    final primaryTextColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;

    final date = (eventMap['date'] as Timestamp?)?.toDate() ?? DateTime.now();
    final now = DateTime.now();
    final difference = date.difference(now);
    
    final bool isStarted = difference.isNegative;
    final bool isLive = isStarted && difference.abs().inHours < 3; 
    final bool isExpired = isStarted && !isLive;
    
    String timeText;
    Color statusColor;
    Color statusBgColor;

    if (isLive) {
      timeText = "Etkinlik Saati Geldi 🎬";
      statusColor = Colors.green;
      statusBgColor = Colors.green.withValues(alpha: 0.1);
    } else if (isExpired) {
      timeText = "Sona Erdi";
      statusColor = Colors.red;
      statusBgColor = Colors.red.withValues(alpha: 0.1);
    } else {
      statusColor = Colors.amber.shade700;
      statusBgColor = Colors.amber.withValues(alpha: 0.1);
      if (difference.inDays > 0) {
        timeText = "${difference.inDays} Gün Kaldı";
      } else {
        timeText = "${difference.inHours} Saat Kaldı";
      }
    }

    final btnColor = isExpired 
        ? Colors.grey 
        : (isJoined ? Colors.redAccent : (isLive ? Colors.green : Colors.amber));
    
    final btnText = isExpired 
        ? "Sona Erdi" 
        : (isJoined ? "Etkinlikten Ayrıl" : "Etkinliğe Katıl");

    return Container(
      width: 260,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLive ? Colors.green.withValues(alpha: 0.5) : borderColor, 
          width: isLive ? 2 : 1
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusBgColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, color: statusColor, size: 20),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${date.day}.${date.month}.${date.year}",
                      style: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor, fontSize: 13),
                    ),
                    Text(
                      "${date.hour.toString().padLeft(2,'0')}:${date.minute.toString().padLeft(2,'0')}",
                      style: TextStyle(color: subTextColor, fontSize: 11),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: cardBg.withValues(alpha: 0.5), // Arka planla uyumlu
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    timeText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eventMap['title'] ?? 'Etkinlik',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 36,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: btnColor,
                      foregroundColor: isJoined ? Colors.white : Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: EdgeInsets.zero,
                      elevation: 0,
                    ),
                    onPressed: isExpired ? null : () {
                       if (widget.chatId != null && eventId != null) {
                         final myUid = FirebaseAuth.instance.currentUser?.uid;
                         if(myUid != null) {
                           ClubService.instance.joinEvent(widget.chatId!, eventId, myUid);
                         }
                       }
                    },
                    child: Text(btnText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- ANKET KARTI (Stateful + KeepAlive + Theme) ---
class _PollMessageBubble extends StatefulWidget {
  final Map<String, dynamic> initialData;
  final bool isMine;
  final DateTime? timestamp;
  final String? chatId;

  const _PollMessageBubble({
    required this.initialData,
    required this.isMine,
    this.timestamp,
    this.chatId,
  });

  @override
  State<_PollMessageBubble> createState() => _PollMessageBubbleState();
}

class _PollMessageBubbleState extends State<_PollMessageBubble> with AutomaticKeepAliveClientMixin {
  Stream<DocumentSnapshot>? _pollStream;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  void _initStream() {
    final pollId = widget.initialData['id'];
    final chatId = widget.chatId;

    if (pollId != null && chatId != null) {
      _pollStream = FirebaseFirestore.instance
          .collection('clubs')
          .doc(chatId)
          .collection('polls')
          .doc(pollId)
          .snapshots();
    }
  }

  @override
  void didUpdateWidget(covariant _PollMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialData['id'] != oldWidget.initialData['id'] || widget.chatId != oldWidget.chatId) {
      _initStream();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_pollStream == null) {
      return _buildPollContent(context, widget.initialData, null);
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: _pollStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.active && !snap.data!.exists) {
           return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: const Text("Bu anket silindi.", style: TextStyle(color: Colors.grey, fontSize: 12)),
          );
        }

        final liveData = (snap.hasData && snap.data!.exists) 
            ? snap.data!.data() as Map<String, dynamic> 
            : widget.initialData;
            
        final pollId = widget.initialData['id'];
        return _buildPollContent(context, liveData, pollId);
      },
    );
  }

  Widget _buildPollContent(BuildContext context, Map<String, dynamic> data, String? pollId) {
    // Tema
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor = isDark ? Colors.white10 : Colors.black12;
    final primaryTextColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;
    final optionBg = isDark ? Colors.grey.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.05);

    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final options = List<dynamic>.from(data['options'] ?? []);
    final voters = Map<String, dynamic>.from(data['voters'] ?? {});
    final totalVotes = voters.length;
    final myVoteIndex = voters[myUid];

    return Container(
      width: 280,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.poll, color: Colors.lightBlueAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    data['question'] ?? 'Anket',
                    style: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor),
                  ),
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: List.generate(options.length, (index) {
                final opt = options[index];
                final count = opt['voteCount'] ?? 0;
                final percent = totalVotes == 0 ? 0.0 : (count / totalVotes);
                final isSelected = (myVoteIndex == index);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () {
                      if (widget.chatId != null && pollId != null && myUid != null) {
                        ClubService.instance.votePoll(widget.chatId!, pollId, myUid, index);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      children: [
                        Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: optionBg,
                            borderRadius: BorderRadius.circular(8),
                            border: isSelected ? Border.all(color: Colors.green) : null,
                          ),
                          child: FractionallySizedBox(
                            widthFactor: percent > 0 ? percent : 0.01,
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected 
                                    ? Colors.green.withValues(alpha: 0.3) 
                                    : Colors.lightBlueAccent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                opt['text'],
                                style: TextStyle(fontSize: 13, color: primaryTextColor),
                              ),
                              Text(
                                "${(percent * 100).toInt()}% ($count)",
                                style: TextStyle(fontSize: 11, color: subTextColor),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text(
              "$totalVotes Toplam Oy",
              style: TextStyle(fontSize: 11, color: subTextColor.withValues(alpha: 0.6)),
            ),
          ),
        ],
      ),
    );
  }
}
class ChatAppBarTitle extends StatelessWidget {
  final String chatId;
  final String otherUid;
  final String? initialTitle;
  final bool isGroup;
  final String? groupName;
  
  const ChatAppBarTitle({
    super.key,
    required this.chatId,
    required this.otherUid,
    this.initialTitle,
    required this.isGroup,
    this.groupName,
  });

  void _openClubDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClubDetailSheet(clubId: chatId),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isGroup) {
      return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('clubs').doc(chatId).snapshots(),
        builder: (context, snap) {
          String? imageUrl;
          String displayName = groupName ?? 'Kulüp Sohbeti';

          if (snap.hasData && snap.data!.exists) {
            final data = snap.data!.data() as Map<String, dynamic>;
            imageUrl = data['imageUrl'];
            if(data['name'] != null) displayName = data['name'];
          }

          return InkWell(
            onTap: () => _openClubDetails(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.grey.shade800,
                  backgroundImage: (imageUrl != null && imageUrl.isNotEmpty) ? NetworkImage(imageUrl) : null,
                  child: (imageUrl == null || imageUrl.isEmpty) ? const Icon(Icons.groups, color: Colors.white, size: 20) : null,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      
                    ],
                  ),
                ),
              ],
            ),
          );
        }
      );
    }

    // Kişisel Sohbet Başlığı
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(otherUid).snapshots(),
      builder: (context, uSnap) {
        String title = initialTitle ?? 'Kullanıcı';
        String photo = '';
        
        if (uSnap.hasData && uSnap.data!.exists) {
          final u = uSnap.data!.data()!;
          final username = (u['username'] ?? '') as String;
          final disp = (u['displayName'] ?? '') as String;
          photo = (u['photoURL'] ?? '') as String;
          title = username.isNotEmpty ? username : (disp.isNotEmpty ? disp : title);
        }

        return InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: otherUid))),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.grey.shade800,
                backgroundImage: (photo.isNotEmpty) ? NetworkImage(photo) : null,
                child: (photo.isEmpty) ? Text(title.isNotEmpty ? title[0] : '?', style: const TextStyle(color: Colors.white)) : null,
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(title, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }
}