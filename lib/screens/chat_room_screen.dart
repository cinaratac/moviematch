import 'dart:async';
import 'package:fluttergirdi/screens/search_movie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/services/notification_settings_service.dart';
import 'package:fluttergirdi/services/chat_service.dart';
import '../services/text_filter_service.dart';

import 'package:fluttergirdi/widgets/green_characters.dart';
import 'package:fluttergirdi/widgets/chat_ui_components.dart';
import 'package:fluttergirdi/widgets/chat_sheets.dart';
import 'package:fluttergirdi/services/blocking_service.dart';

// --- YENİ EKLENEN: Merkezi Önbellek Servisi ---
import '../services/user_cache_service.dart';

class ChatRoomScreen extends StatefulWidget {
  final String chatId;
  final String otherUid;
  final String? otherTitle;
  final bool isGroup;
  final String? groupName;

  const ChatRoomScreen({
    super.key,
    required this.chatId,
    required this.otherUid,
    this.otherTitle,
    this.isGroup = false,
    this.groupName,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  static final Map<String, bool> _blockedCache = {};
  bool _initialMuteStatus = false; // Ekran açıldığındaki orjinal durum
  late final ValueNotifier<bool> _isMutedNotifier;

  static final Map<String, bool> _blockedMeCache = {};
  static final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _messageCache = {};

  Timer? _muteDebounceTimer;
  final ValueNotifier<bool> _showGuideNotifier = ValueNotifier<bool>(false);
  final _svc = ChatService.instance;
  final _ctrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late Stream<QuerySnapshot<Map<String, dynamic>>> _messagesStream;
  StreamSubscription? _latestSub;
  Timer? _typingStopTimer;
  bool _isTyping = false;
  DateTime? _lastTypingWriteAt;
  bool _isBlocked = false;
  bool _hasBlockedMe = false;
  bool _isLoadingBlock = true;

  late Stream<List<String>> _mutedChatsStream;

  // --- YENİ EKLENEN: Teslim edildi / Görüldü tik sistemi ---
  DateTime? _otherReadAt;
  DateTime? _otherDeliveredAt;
  StreamSubscription? _otherReadSub;
  StreamSubscription? _otherDeliveredSub;

  Future<void> _loadBlockStatus() async {
    if (widget.isGroup) {
      if (mounted) setState(() => _isLoadingBlock = false);
      return;
    }

    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    try {
      final status = await BlockingService.instance.checkBlockStatus(
        currentUserId: myUid,
        targetUserId: widget.otherUid,
      );

      // KİLİT BURADA: Eğer veritabanından cevap gelene kadar kullanıcı sayfadan çıktıysa işlemi iptal et!
      if (!mounted) return;

      _blockedCache[widget.otherUid] = status['iBlockedThem'] ?? false;
      _blockedMeCache[widget.otherUid] = status['theyBlockedMe'] ?? false;

      setState(() {
        _isBlocked = status['iBlockedThem'] ?? false;
        _hasBlockedMe = status['theyBlockedMe'] ?? false;
        _isLoadingBlock = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingBlock = false);
    }
  }

  @override
  void initState() {
    super.initState();

    // 1. EKRAN AÇILDIĞI AN İKONU "AÇIK" OLARAK GÖSTER
    _isMutedNotifier = ValueNotifier<bool>(false);
    _ctrl.addListener(_handleTypingChanged);

    final myUid = FirebaseAuth.instance.currentUser!.uid;

    // 2. IŞIK HIZINDA SORGUMUZ (Eski cache'i tetikler, anında açılır)
    _messagesStream = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(60)
        .snapshots();

    // 3. Cache üzerinden engelleme durumunu kontrol et
    if (_blockedCache.containsKey(widget.otherUid)) {
      _isBlocked = _blockedCache[widget.otherUid]!;
      _hasBlockedMe = _blockedMeCache[widget.otherUid] ?? false;
      _isLoadingBlock = false;
    }

    _svc.markAsRead(widget.chatId, myUid);
    // Oda açıldığı an, o ana kadarki tüm mesajlar bu cihaza teslim edilmiş
    // sayılır (görüldü zaten markAsRead ile ayrıca işaretleniyor).
    _svc.markDelivered(widget.chatId, myUid);

    // --- YENİ EKLENEN: Karşı tarafın "teslim edildi" / "görüldü" bilgisini dinle ---
    if (!widget.isGroup) {
      _otherReadSub = _svc
          .otherReadAtStream(widget.chatId, widget.otherUid)
          .listen((dt) {
            if (mounted) setState(() => _otherReadAt = dt);
          });
      _otherDeliveredSub = _svc
          .otherDeliveredAtStream(widget.chatId, widget.otherUid)
          .listen((dt) {
            if (mounted) setState(() => _otherDeliveredAt = dt);
          });
    }

    // 4. En son mesajın okundu bilgisi için dinleyici
    _latestSub = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .listen((snap) {
          if (snap.docs.isEmpty) return;
          final data = snap.docs.first.data();
          final author = (data['authorId'] ?? data['from'] ?? '') as String;
          if (author != myUid) {
            _svc.markAsRead(widget.chatId, myUid);
            _svc.markDelivered(widget.chatId, myUid);
          }
        });

    // 5. KESİN ÇÖZÜM: Ağır işlemleri sayfa açılış animasyonu bitene kadar (300ms) ertele
    Future.delayed(Duration.zero, () {
      if (!mounted) return;
      _checkAndShowGuide();
      _loadBlockStatus();
      _loadInitialMuteStatus();
    });
  }

  Future<void> _loadInitialMuteStatus() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      // Çok daha hızlı olması için önce yerel önbellekten (cache) okumayı dener:
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.cache))
          .catchError(
            (_) =>
                FirebaseFirestore.instance.collection('users').doc(uid).get(),
          );

      // KİLİT BURADA: Eğer sayfadan çıkıldıysa notifer'a dokunma, çöker!
      if (!mounted) return;

      final mutedChats = List<String>.from(doc.data()?['mutedChats'] ?? []);

      _initialMuteStatus = mutedChats.contains(widget.chatId);
      // Arka planda gerçek durumu sessizce güncelle (Ekranda loading vs dönmez)
      _isMutedNotifier.value = _initialMuteStatus;
    } catch (e) {
      debugPrint('Bildirim ayarı yüklenemedi: $e');
    }
  }

  Future<void> _checkAndShowGuide() async {
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final bool seen = sp.getBool('seen_watchlist_guide') ?? false;
      if (!seen) {
        _showGuideNotifier.value = true;
        await sp.setBool('seen_watchlist_guide', true);
      }
    } catch (e) {
      debugPrint('');
    }
  }

  void _handleTypingChanged() {
    if (widget.isGroup || _isBlocked || _hasBlockedMe) return;

    final hasText = _ctrl.text.trim().isNotEmpty;
    if (!hasText) {
      _typingStopTimer?.cancel();
      _setTyping(false, force: true);
      return;
    }

    final now = DateTime.now();
    final shouldRefresh =
        _lastTypingWriteAt == null ||
        now.difference(_lastTypingWriteAt!) > const Duration(seconds: 4);

    if (!_isTyping || shouldRefresh) {
      _setTyping(true, force: shouldRefresh);
    }

    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(milliseconds: 2800), () {
      _setTyping(false, force: true);
    });
  }

  void _setTyping(bool value, {bool force = false}) {
    if (widget.isGroup) return;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;
    if (!force && _isTyping == value) return;

    _isTyping = value;
    _lastTypingWriteAt = DateTime.now();
    unawaited(_svc.setTyping(widget.chatId, myUid, value));
  }

  @override
  void dispose() {
    // 1. Önce sunucuya kaydedilecek bir şey varsa onu hallet
    if (_isMutedNotifier.value != _initialMuteStatus) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final isMutedNow = _isMutedNotifier.value;

        if (isMutedNow) {
          FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .update({
                'mutedChats': FieldValue.arrayUnion([widget.chatId]),
              })
              .catchError((_) {});
        } else {
          FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .update({
                'mutedChats': FieldValue.arrayRemove([widget.chatId]),
              })
              .catchError((_) {});
        }
      }
    }

    // 2. Kapatma, iptal etme ve temizleme işlemleri (Sadece BİR KERE)
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid != null) _svc.markAsRead(widget.chatId, myUid);
    if (myUid != null && _isTyping) {
      unawaited(_svc.setTyping(widget.chatId, myUid, false));
    }

    _latestSub?.cancel();
    _otherReadSub?.cancel();
    _otherDeliveredSub?.cancel();
    _muteDebounceTimer?.cancel();
    _typingStopTimer?.cancel();
    _ctrl.removeListener(_handleTypingChanged);

    _ctrl.dispose();
    _scrollController.dispose();
    _showGuideNotifier.dispose();
    _isMutedNotifier.dispose();

    // 3. super.dispose() HER ZAMAN EN SONDA OLMALIDIR!
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final txt = _ctrl.text.trim();
    if (txt.isEmpty) return;

    if (TextFilterService.hasProfanity(txt)) {
      _showError('Mesajınız uygunsuz ifadeler içeriyor.');
      return;
    }

    try {
      final myUid = FirebaseAuth.instance.currentUser!.uid;
      _typingStopTimer?.cancel();
      _setTyping(false, force: true);
      _ctrl.clear();

      await _svc.send(widget.chatId, myUid, txt, otherUid: widget.otherUid);

      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showError('Gönderilemedi: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  Future<void> _openFilmPicker() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => const SearchMoviePage(isSelectionMode: true),
      ),
    );

    if (!mounted || result == null) return;

    final myUid = FirebaseAuth.instance.currentUser!.uid;
    try {
      await _svc.send(
        widget.chatId,
        myUid,
        "",
        otherUid: widget.otherUid,
        movie: {
          'title': result['title'],
          'poster': result['poster'],
          'id': result['id'].toString(),
        },
      );

      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (mounted) _showError('Film gönderilemedi: $e');
    }
  }

  void _openWatchlistWheel() {
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WatchlistWheelSheet(
        chatId: widget.chatId,
        myUid: myUid,
        otherUid: widget.otherUid,
      ),
    );
  }

  Widget _buildFeaturedMovieBanner() {
    if (!widget.isGroup) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('clubs')
          .doc(widget.chatId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) return const SizedBox.shrink();
        final data = snap.data!.data() as Map<String, dynamic>;
        final movie = data['featuredMovie'] as Map<String, dynamic>?;

        if (movie == null) return const SizedBox.shrink();

        return FeaturedMovieBannerWidget(movie: movie);
      },
    );
  }

  Widget _buildInputArea() {
    if (_isLoadingBlock) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_isBlocked || _hasBlockedMe) {
      return SafeArea(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.black26
              : Colors.grey.shade200,
          child: const Text(
            'Bu kullanıcıyla mesajlaşamazsınız.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inputBg = isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade200;
    final hintColor = isDark ? Colors.white38 : Colors.black38;
    final iconColor = isDark ? Colors.white54 : Colors.black54;
    final textColor = isDark ? Colors.white : Colors.black;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: inputBg,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.black12,
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        style: TextStyle(color: textColor),
                        decoration: InputDecoration(
                          hintText: 'Mesaj...',
                          hintStyle: TextStyle(color: hintColor),
                          isCollapsed: true,
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Film paylaş',
                          onPressed: _openFilmPicker,
                          icon: Icon(
                            Icons.movie_filter_outlined,
                            color: iconColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (!widget.isGroup)
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Watchlist Çarkı',
                            onPressed: _openWatchlistWheel,
                            icon: Icon(Icons.donut_large, color: iconColor),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sendMessage,
              child: CircleAvatar(
                radius: 22,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: const Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: ChatAppBarTitle(
          chatId: widget.chatId,
          otherUid: widget.otherUid,
          initialTitle: widget.otherTitle,
          isGroup: widget.isGroup,
          groupName: widget.groupName,
        ),
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: _isMutedNotifier,
            builder: (context, isMuted, child) {
              return IconButton(
                icon: Icon(
                  isMuted ? Icons.notifications_off : Icons.notifications,
                  color: isMuted
                      ? Colors.grey
                      : Theme.of(context).iconTheme.color,
                ),
                onPressed: () {
                  _isMutedNotifier.value = !isMuted;
                },
              );
            },
          ),
        ],
      ),
      body: _isLoadingBlock
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
            )
          : (_isBlocked || _hasBlockedMe)
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.block, size: 48, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Bu kullanıcıyla mesajlaşamazsınız.',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                Column(
                  children: [
                    _buildFeaturedMovieBanner(),
                    Expanded(
                      child: Container(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: _messagesStream,
                          builder: (context, snap) {
                            if (snap.hasData && snap.data != null) {
                              _messageCache[widget.chatId] = snap.data!.docs;
                            }

                            final docs =
                                snap.data?.docs ??
                                _messageCache[widget.chatId] ??
                                [];

                            // --- MERKEZİ CACHE KULLANIMI: Sohbet edenleri anında RAM'e al ---
                            final Set<String> authorIds = {};
                            // Eğer otherUid boş değilse listeye ekle (Grup sohbetlerinde boş gelebilir)
                            if (widget.otherUid.isNotEmpty) {
                              authorIds.add(widget.otherUid);
                            }

                            for (var doc in docs) {
                              final m = doc.data();
                              final aId = (m['authorId'] ?? m['from'])
                                  ?.toString();
                              if (aId != null && aId.trim().isNotEmpty) {
                                authorIds.add(aId);
                              }
                            }

                            // Ekstra güvenlik: Sorguya gidecek ID'lerin kesinlikle boş olmadığından emin ol
                            final missingIds = authorIds
                                .where(
                                  (id) =>
                                      id.isNotEmpty &&
                                      UserCacheService.instance.getFromCache(
                                            id,
                                          ) ==
                                          null,
                                )
                                .toList();
                            if (missingIds.isNotEmpty) {
                              Future.microtask(() async {
                                await UserCacheService.instance.fetchUsers(
                                  missingIds,
                                );
                                if (mounted) setState(() {});
                              });
                            }
                            // ---------------------------------------------------------------

                            if (snap.connectionState ==
                                    ConnectionState.waiting &&
                                docs.isEmpty) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            if (docs.isEmpty) {
                              return const EmptyChatView();
                            }

                            return ListView.builder(
                              controller: _scrollController,
                              reverse: true,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              itemCount: docs.length,
                              itemBuilder: (context, i) {
                                final doc = docs[i];
                                final m = doc.data();
                                final author =
                                    (m['authorId'] ?? m['from'] ?? '')
                                        as String;
                                final mine = author == myUid;
                                final text = (m['text'] ?? '') as String;
                                final ts = (m['createdAt'] as Timestamp?);
                                final dt = ts?.toDate();

                                final type = m['type'] as String?;
                                final eventData =
                                    m['event'] as Map<String, dynamic>?;
                                final pollData =
                                    m['poll'] as Map<String, dynamic>?;

                                // --- YENİ EKLENEN: Teslim/Görüldü tik durumu ---
                                // Sadece kendi mesajlarım için, gruplarda gösterilmez.
                                MessageDeliveryStatus? deliveryStatus;
                                if (mine && dt != null && !widget.isGroup) {
                                  if (_otherReadAt != null &&
                                      !dt.isAfter(_otherReadAt!)) {
                                    deliveryStatus =
                                        MessageDeliveryStatus.read;
                                  } else if (_otherDeliveredAt != null &&
                                      !dt.isAfter(_otherDeliveredAt!)) {
                                    deliveryStatus =
                                        MessageDeliveryStatus.delivered;
                                  } else {
                                    deliveryStatus =
                                        MessageDeliveryStatus.sent;
                                  }
                                }

                                final row = MessageRow(
                                  key: ValueKey(doc.id),
                                  text: text,
                                  movie: m['movie'],
                                  isMine: mine,
                                  timestamp: dt,
                                  authorId: author,
                                  type: type,
                                  eventData: eventData,
                                  pollData: pollData,
                                  chatId: widget.chatId,
                                  deliveryStatus: deliveryStatus,
                                );

                                // --- GÜN AYIRICI: Instagram DM tarzı ---
                                // Liste 'reverse: true' olduğundan i+1
                                // ekrandaki bir üst (daha eski) mesajı temsil eder.
                                // Bu mesaj günün ilk mesajıysa (kendinden bir
                                // önceki -eski- mesaj farklı bir güne aitse ya
                                // da sohbetteki en eski mesajsa) üzerine
                                // tarih etiketi ekleriz.
                                bool isFirstOfDay = false;
                                if (dt != null) {
                                  if (i == docs.length - 1) {
                                    isFirstOfDay = true;
                                  } else {
                                    final nextData = docs[i + 1].data();
                                    final nextTs =
                                        nextData['createdAt'] as Timestamp?;
                                    final nextDt = nextTs?.toDate();
                                    if (nextDt == null ||
                                        nextDt.year != dt.year ||
                                        nextDt.month != dt.month ||
                                        nextDt.day != dt.day) {
                                      isFirstOfDay = true;
                                    }
                                  }
                                }

                                if (!isFirstOfDay) return row;

                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    DateSeparator(date: dt!),
                                    row,
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                    _buildInputArea(),
                  ],
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: _showGuideNotifier,
                  builder: (context, isVisible, child) {
                    if (!isVisible) return const SizedBox.shrink();
                    return GuideCharacterOverlay(
                      message:
                          "Beraber film izlemek için watchlist çarkını deneyebilirsin",
                      isVisible: isVisible,
                      onClose: () => _showGuideNotifier.value = false,
                    );
                  },
                ),
              ],
            ),
    );
  }
}