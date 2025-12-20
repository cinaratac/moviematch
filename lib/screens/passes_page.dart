import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';

// --- Data Models (Poster Fallback için) ---

class _PosterData {
  final String posterUrl;
  final String? title;
  final int? tmdbId;
  const _PosterData({required this.posterUrl, this.title, this.tmdbId});
}

class _UserLite {
  final String title;
  final String photoURL;
  final int? age;
  const _UserLite({required this.title, required this.photoURL, this.age});
}

class _PassRow {
  final String otherUid;
  final DateTime? when;
  const _PassRow({required this.otherUid, this.when});
}

class _CardData {
  final int? age;
  final List<String> genres;
  final List<String> directors;
  final List<String> actors;
  final List<_PosterData> userFavPosters;
  
  // Zengin poster verisi (Fallback destekli)
  final List<_PosterData> fivePosters;
  final List<_PosterData> favPosters;
  final List<_PosterData> watchPosters;
  
  final int? commonFiveCount;
  final int? commonFavCount;
  final int? commonWatchCount;

  _CardData({
    this.age,
    this.genres = const [],
    this.directors = const [],
    this.actors = const [],
    this.fivePosters = const [],
    this.favPosters = const [],
    this.watchPosters = const [],
    this.commonFiveCount,
    this.commonFavCount,
    this.commonWatchCount,
    this.userFavPosters = const [],
  });
}

// --- Main Page (Opsiyonel, tek başına kullanılırsa diye) ---

class PassesPage extends StatelessWidget {
  const PassesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Geçilenler', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: theme.colorScheme.surface,
      ),
      body: const PassesListBody(),
    );
  }
}

// --- List Body (Match Screen tarafından kullanılan kısım) ---

class PassesListBody extends StatefulWidget {
  const PassesListBody({super.key});

  @override
  State<PassesListBody> createState() => _PassesListBodyState();
}

class _PassesListBodyState extends State<PassesListBody>
    with AutomaticKeepAliveClientMixin {
  late final String _uid;
  late final FirebaseFirestore _fs;
  
  // Future yerine Stream kullanıyoruz (Anlık güncelleme için)
  late final Stream<QuerySnapshot> _likesStream;
  late final Future<Map<String, dynamic>> _myTasteFuture;
  
  // Kart verileri için önbellek
  final Map<String, Future<_CardData>> _cardCache = {};
  // Kullanıcı temel bilgileri için önbellek (Future olarak saklıyoruz)
  final Map<String, Future<_UserLite>> _userLiteCache = {};
  
  final PageStorageKey _listKey = const PageStorageKey('passes_list');

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _uid = user.uid;
      _fs = FirebaseFirestore.instance;
      
      // Stream tanımlıyoruz: 'likes' koleksiyonunu dinle
      _likesStream = _fs
          .collection('likes')
          .where('uids', arrayContains: _uid)
          .snapshots(); // <-- Anlık dinleme

      _myTasteFuture = _loadMyTasteOnce();
    }
  }
  
  Future<_CardData> _getCardData(String otherUid, Map<String, dynamic> myTaste, int? age) {
    return _cardCache[otherUid] ??= _loadCardData(otherUid, myTaste, precomputedAge: age);
  }

  // Kullanıcı adı/fotoğrafı gibi temel bilgileri çeken yardımcı fonksiyon
  Future<_UserLite> _getUserLite(String uid) {
    return _userLiteCache[uid] ??= _fetchUserLiteFromDb(uid);
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (FirebaseAuth.instance.currentUser == null) return const SizedBox();

    // StreamBuilder ile sarmaladık
    return StreamBuilder<QuerySnapshot>(
      stream: _likesStream,
      builder: (context, streamSnap) {
        if (streamSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (streamSnap.hasError) {
          return Center(
            child: Text('Bir hata oluştu', 
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          );
        }

        final docs = streamSnap.data?.docs ?? [];
        final items = <_PassRow>[];

        // Gelen verileri işle ve sadece PAS geçilenleri filtrele
        for (final d in docs) {
          final data = d.data() as Map<String, dynamic>;
          final a = data['a'] as String?;
          final b = data['b'] as String?;
          if (a == null || b == null) continue;
          
          final meIsA = (_uid == a);
          final myPass = data[meIsA ? 'aPass' : 'bPass'] == true;
          // Eğer eşleşme olduysa (iki taraf da beğendiyse) pas listesinde gösterme
          final myLike = data[meIsA ? 'aLiked' : 'bLiked'] == true;
          final otherLike = data[meIsA ? 'bLiked' : 'aLiked'] == true;
          final matched = myLike && otherLike;

          if (myPass && !matched) {
            final otherUid = meIsA ? b : a;
            final when = (data['updatedAt'] as Timestamp?)?.toDate().toLocal();
            items.add(_PassRow(otherUid: otherUid, when: when));
          }
        }

        // Tarihe göre sırala (En yeni en üstte)
        items.sort((x, y) {
          final dx = x.when ?? DateTime.fromMillisecondsSinceEpoch(0);
          final dy = y.when ?? DateTime.fromMillisecondsSinceEpoch(0);
          return dy.compareTo(dx);
        });
        
        if (items.isEmpty) {
          return _buildEmptyState(context);
        }

        return FutureBuilder<Map<String, dynamic>>(
          future: _myTasteFuture,
          builder: (context, tasteSnap) {
            if (tasteSnap.connectionState == ConnectionState.waiting || !tasteSnap.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
            final myTaste = tasteSnap.data ?? const <String, dynamic>{};
            
            return ListView.separated(
              key: _listKey,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: items.length,
              separatorBuilder: (ctx, index) => const SizedBox(height: 16),
              itemBuilder: (context, i) {
                final row = items[i];
                
                // Her satır için kullanıcı bilgisini (UserLite) asenkron çekiyoruz
                return FutureBuilder<_UserLite>(
                  future: _getUserLite(row.otherUid),
                  builder: (context, userSnap) {
                    final lite = userSnap.data;
                    
                    // Stateful KeepAlive Kart
                    return _PassDetailCard(
                      otherUid: row.otherUid,
                      when: row.when,
                      title: lite?.title, // Yüklenirken null olabilir
                      photoURL: lite?.photoURL,
                      // Kart detayları (Posterler vs.)
                      cardDataFuture: _getCardData(row.otherUid, myTaste, lite?.age),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history_toggle_off_rounded,
            size: 64,
            color: Theme.of(context).disabledColor,
          ),
          const SizedBox(height: 16),
          Text(
            'Henüz geçtiğin kimse yok',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).disabledColor,
                ),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>> _loadMyTasteOnce() async {
    final docRef = _fs.collection('userTasteProfiles').doc(_uid);
    try {
      final cache = await docRef.get(const GetOptions(source: Source.cache));
      if (cache.exists && cache.data() != null) return cache.data()!;
    } catch (_) {}
    try {
      final server = await docRef.get(const GetOptions(source: Source.server));
      if (server.exists && server.data() != null) return server.data()!;
    } catch (_) {}
    return const <String, dynamic>{};
  }

  // Tekil kullanıcı bilgisini çeken fonksiyon
  Future<_UserLite> _fetchUserLiteFromDb(String uid) async {
    try {
      final doc = await _fs.collection('users').doc(uid).get();
      if (!doc.exists) {
        return _UserLite(title: 'Kullanıcı', photoURL: '');
      }
      final m = doc.data()!;
      final username = (m['username'] ?? '') as String;
      final displayName = (m['displayName'] ?? '') as String;
      final lb = (m['letterboxdUsername'] ?? '') as String;
      final photoURL = (m['photoURL'] ?? '') as String;
      
      String title = username.isNotEmpty
          ? username
          : (displayName.isNotEmpty
                ? displayName
                : (lb.isNotEmpty ? '@$lb' : 'Kullanıcı'));
      
      int? age;
      final bd = m['birthdate'];
      if (bd is Timestamp) {
        final dtt = bd.toDate();
        final now = DateTime.now();
        age = now.year - dtt.year;
        if (DateTime(now.year, dtt.month, dtt.day).isAfter(now)) {
          age -= 1;
        }
      } else if (m['age'] is int) {
        age = m['age'] as int;
      }
      
      return _UserLite(title: title, photoURL: photoURL, age: age);
    } catch (_) {
      return const _UserLite(title: 'Hata', photoURL: '');
    }
  }
}

// --- Stateful Card with KeepAlive (Scroll Sorunu Çözümü) ---

class _PassDetailCard extends StatefulWidget {
  final String otherUid;
  final DateTime? when;
  final String? title;
  final String? photoURL;
  final Future<_CardData> cardDataFuture;

  const _PassDetailCard({
    required this.otherUid,
    this.when,
    this.title,
    this.photoURL,
    required this.cardDataFuture,
  });

  @override
  State<_PassDetailCard> createState() => _PassDetailCardState();
}

class _PassDetailCardState extends State<_PassDetailCard> 
    with AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true; // Kaydırınca hafızadan silinmez

  @override
  Widget build(BuildContext context) {
    super.build(context); // KeepAlive için şart
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return FutureBuilder<_CardData>(
      future: widget.cardDataFuture,
      builder: (context, snap) {
        final isLoading = snap.connectionState == ConnectionState.waiting;
        final cd = snap.data;

        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow, 
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.5),
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: widget.otherUid)),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: isLoading
                    ? const _SkeletonContent()
                    : _buildLoadedContent(context, cd!, theme),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadedContent(BuildContext context, _CardData cd, ThemeData theme) {
    // Başlık henüz yüklenmediyse UID göster veya '...'
    final displayTitle = (widget.title == null || widget.title!.isEmpty) 
        ? (widget.title == null ? '...' : widget.otherUid) 
        : widget.title!;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- Header ---
        Row(
          children: [
            // Avatar
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.surfaceContainerHighest, 
                  width: 2
                ),
                image: (widget.photoURL != null && widget.photoURL!.isNotEmpty)
                    ? DecorationImage(image: NetworkImage(widget.photoURL!), fit: BoxFit.cover)
                    : null,
              ),
              child: (widget.photoURL == null || widget.photoURL!.isEmpty)
                  ? Icon(Icons.person, size: 30, color: theme.colorScheme.onSurfaceVariant)
                  : null,
            ),
            const SizedBox(width: 16),
            // Name & Age
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (cd.age != null)
                    Text(
                      '${cd.age} yaşında',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            // Arrow
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
            )
          ],
        ),

        const SizedBox(height: 16),

        // --- Stats ---
        if ((cd.commonFiveCount != null && cd.commonFiveCount! > 0) ||
            (cd.commonFavCount != null && cd.commonFavCount! > 0))
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Row(
              children: [
                if (cd.commonFiveCount != null && cd.commonFiveCount! > 0)
                  _StatBox(
                    icon: Icons.star_rounded,
                    val: '${cd.commonFiveCount}',
                    label: 'Ortak 5★',
                    color: Colors.amber,
                  ),
                if (cd.commonFavCount != null && cd.commonFavCount! > 0)
                  _StatBox(
                    icon: Icons.favorite_rounded,
                    val: '${cd.commonFavCount}',
                    label: 'Ortak Fav',
                    color: Colors.redAccent,
                  ),
              ],
            ),
          ),

        // --- Genres ---
        if (cd.genres.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: cd.genres.take(4).map((g) => _ModernChip(label: g)).toList(),
          ),
          const SizedBox(height: 16),
        ],

        // --- Posters ---
        if (cd.fivePosters.isNotEmpty || cd.favPosters.isNotEmpty || cd.watchPosters.isNotEmpty) ...[
           _SectionHeader(
             title: cd.fivePosters.isNotEmpty ? 'ORTAK 5 YILDIZ' : 
                    (cd.favPosters.isNotEmpty ? 'ORTAK FAVORİLER' : 'ORTAK İZLEME LISTESI')
           ),
           const SizedBox(height: 10),
           _PosterStrip(
             data: cd.fivePosters.isNotEmpty ? cd.fivePosters : 
                   (cd.favPosters.isNotEmpty ? cd.favPosters : cd.watchPosters)
           ),
           ] else if (cd.userFavPosters.isNotEmpty) ...[
           // Başlık genel, çünkü fav/5 yıldız/watchlist olabilir
           _SectionHeader(title: 'KULLANICININ SEÇTİKLERİ'),
           const SizedBox(height: 10),
           _PosterStrip(data: cd.userFavPosters),
        ] else ...[
           Container(
             height: 60,
             width: double.infinity,
             alignment: Alignment.center,
             decoration: BoxDecoration(
               color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
               borderRadius: BorderRadius.circular(12)
             ),
             child: Text(
               'Ortak film verisi yok', 
               style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)
             ),
           )
        ]
      ],
    );
  }
}

// --- UI Components ---

class _ModernChip extends StatelessWidget {
  final String label;
  const _ModernChip({required this.label});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.1)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final IconData icon;
  final String val;
  final String label;
  final Color color;
  const _StatBox({required this.icon, required this.val, required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(val, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, color: theme.hintColor)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 1.1,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.outline,
          ),
    );
  }
}

class _PosterStrip extends StatelessWidget {
  final List<_PosterData> data;
  const _PosterStrip({required this.data});
  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: data.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final item = data[i];
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: PosterImage(
                posterUrl: item.posterUrl,
                title: item.title,      
                tmdbId: item.tmdbId,   
                fit: BoxFit.cover,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SkeletonContent extends StatelessWidget {
  const _SkeletonContent();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                color: Colors.black12, shape: BoxShape.circle
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 120, height: 16, color: Colors.black12),
                const SizedBox(height: 8),
                Container(width: 60, height: 12, color: Colors.black12),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(width: double.infinity, height: 40, color: Colors.black12),
        const SizedBox(height: 16),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 4,
            separatorBuilder: (_,__) => const SizedBox(width: 10),
            itemBuilder: (_,__) => AspectRatio(
               aspectRatio: 2/3,
               child: Container(color: Colors.black12),
            )
          ),
        )
      ],
    );
  }
}

// --- Data Logic (PosterData & Null Safety) ---

Future<List<_PosterData>> _fetchPosterDataByDocIds(List<String> ids) async {
  if (ids.isEmpty) return const <_PosterData>[];
  final postersData = <_PosterData>[];
  const chunk = 10;
  final targetIds = ids.take(chunk).toList(); 
  final fs = FirebaseFirestore.instance;

  try {
    QuerySnapshot qs;
    qs = await fs.collection('catalog_films').where(FieldPath.documentId, whereIn: targetIds).get();
    
    if (qs.docs.isEmpty) {
      qs = await fs.collection('catalog_films').where('key', whereIn: targetIds).get();
    }

    for (final d in qs.docs) {
      // Null Safety Cast
      final data = d.data();
      final mapData = data as Map<String, dynamic>?; 
      
      final p = (mapData?['poster'] ?? mapData?['posterUrl'] ?? '').toString();
      final title = (mapData?['title'] ?? mapData?['titleTr'] ?? mapData?['originalTitle'] ?? '') as String?;
      final tmdbId = mapData?['tmdbId'] as int?;

      if (p.isNotEmpty) {
        postersData.add(_PosterData(
          posterUrl: p,
          title: title,
          tmdbId: tmdbId,
        ));
      }
    }
  } catch (_) {}
  return postersData;
}


// lib/screens/passes_page.dart dosyasının en altındaki _loadCardData fonksiyonunu bununla değiştirin:

Future<_CardData> _loadCardData(
  String otherUid,
  Map<String, dynamic> my, {
  int? precomputedAge,
}) async {
  final fs = FirebaseFirestore.instance;

  // --- YARDIMCI METOTLAR ---
  List<String> extractIds(dynamic v) {
    final out = <String>[];
    if (v is List) {
      for (final e in v) {
        if (e is String && e.trim().isNotEmpty) {
          out.add(e.trim());
        } else if (e is num) {
          out.add(e.toString());
        }
      }
    }
    return out;
  }

  // İki haritayı (Taste Profile + User Doc) kontrol edip birleştiren fonksiyon
  List<String> pickMergedIds(
      Map<String, dynamic> map1, Map<String, dynamic> map2, List<String> keys) {
    final Set<String> combined = {};
    for (final k in keys) {
      combined.addAll(extractIds(map1[k]));
      combined.addAll(extractIds(map2[k]));
    }
    return combined.toList();
  }

  // Sadece tek map kontrol eden (kendi profilimiz için)
  List<String> pickIds(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final ids = extractIds(map[k]);
      if (ids.isNotEmpty) return ids;
    }
    return const <String>[];
  }

  List<String> inter(List<String> a, List<String> b) {
    final bs = b.toSet();
    return a.where(bs.contains).toList();
  }
  
  // Paralel poster verisi çekme (likes_page ile aynı robust yapı)
  Future<List<_PosterData>> fetchPosters(List<String> ids) async {
    if (ids.isEmpty) return const <_PosterData>[];
    
    final postersMap = <String, _PosterData>{};
    final chunk = 10;
    final targetIds = ids.take(chunk).toList();
    
    try {
      // 1. Döküman ID sorgusu
      final docIdQuery = fs.collection('catalog_films')
          .where(FieldPath.documentId, whereIn: targetIds)
          .get();

      // 2. tmdbId sorgusu (Sayısal ID'ler için)
      final numericIds = targetIds
          .map((e) => int.tryParse(e))
          .where((e) => e != null)
          .toList();

      Future<QuerySnapshot<Map<String, dynamic>>>? tmdbQuery;
      if (numericIds.isNotEmpty) {
        tmdbQuery = fs.collection('catalog_films')
            .where('tmdbId', whereIn: numericIds)
            .get();
      }

      final results = await Future.wait([
        docIdQuery,
        if (tmdbQuery != null) tmdbQuery else Future.value(null),
      ]);

      final docIdSnap = results[0] as QuerySnapshot<Map<String, dynamic>>?;
      final tmdbSnap = results[1] as QuerySnapshot<Map<String, dynamic>>?;

      void processDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
        for (final d in docs) {
          final data = d.data();
          if (postersMap.containsKey(d.id)) continue;

          final p = (data['poster'] ?? data['posterUrl'] ?? '').toString();
          final title = (data['title'] ?? data['titleTr'] ?? data['originalTitle'] ?? '') as String?;
          final tmdbId = data['tmdbId'] as int?;

          if (p.isNotEmpty) {
            postersMap[d.id] = _PosterData(
              posterUrl: p,
              title: title,
              tmdbId: tmdbId,
            );
          }
        }
      }

      if (docIdSnap != null) processDocs(docIdSnap.docs);
      if (tmdbSnap != null) processDocs(tmdbSnap.docs);

    } catch (_) {}
    return postersMap.values.toList();
  }

  // --- VERİ ÇEKME (PARALEL) ---
  // Hem 'userTasteProfiles' hem 'users' dökümanlarını aynı anda çekiyoruz.
  final results = await Future.wait([
    fs.collection('userTasteProfiles').doc(otherUid).get(),
    fs.collection('users').doc(otherUid).get(),
  ]);

  final tasteDoc = results[0];
  final userDoc = results[1];

  final hisTaste = tasteDoc.data() ?? const <String, dynamic>{};
  final u = userDoc.data() ?? const <String, dynamic>{};

  // Türler, Yönetmenler (Birleşik Veri)
  final hisGenres = pickMergedIds(hisTaste, u, ['genres', 'favoriteGenres']);
  final hisDirectors = pickMergedIds(hisTaste, u, ['directors', 'favoriteDirectors']);
  final hisActors = pickMergedIds(hisTaste, u, ['actors', 'favoriteActors']);

  // ID Listeleri (Birleşik Veri)
  final hisFiveIds = pickMergedIds(hisTaste, u, ['loved', 'fiveIds', 'fiveFilmIds', 'fiveStars']);
  final hisFavIds = pickMergedIds(hisTaste, u, ['favIds', 'favoriteFilmIds', 'favorites']);
  final hisWatchIds = pickMergedIds(hisTaste, u, ['watchIds', 'watchlist']);

  // Benim Listelerim
  final myFiveIds = pickIds(my, ['loved', 'fiveIds', 'fiveFilmIds', 'fiveStars']);
  final myFavIds = pickIds(my, ['favIds', 'favoriteFilmIds', 'favorites']);
  final myWatchIds = pickIds(my, ['watchIds', 'watchlist']);

  // Ortakları Bul
  final commonFiveIds = inter(myFiveIds, hisFiveIds);
  final commonFavIds = inter(myFavIds, hisFavIds);
  final commonWatchIds = inter(myWatchIds, hisWatchIds);

  // Ortak Posterleri Çek
  List<_PosterData> fivePosters = await fetchPosters(commonFiveIds);
  List<_PosterData> favPosters = await fetchPosters(commonFavIds);
  List<_PosterData> watchPosters = await fetchPosters(commonWatchIds);

  // --- FALLBACK MANTIĞI (Kullanıcı Verisi Gösterme) ---
  List<_PosterData> userFavPosters = [];

  // Ortak hiçbir şey yoksa karşı tarafın listelerini sırayla dene
  if (fivePosters.isEmpty && favPosters.isEmpty && watchPosters.isEmpty) {
     
     // 1. Favoriler
     if (hisFavIds.isNotEmpty) {
       userFavPosters = await fetchPosters(hisFavIds);
     }
     
     // 2. Favori yoksa 5 Yıldızlar
     if (userFavPosters.isEmpty && hisFiveIds.isNotEmpty) {
       userFavPosters = await fetchPosters(hisFiveIds);
     }
     
     // 3. O da yoksa İzleme Listesi
     if (userFavPosters.isEmpty && hisWatchIds.isNotEmpty) {
       userFavPosters = await fetchPosters(hisWatchIds);
     }
  }

  return _CardData(
    age: precomputedAge,
    genres: hisGenres,
    directors: hisDirectors,
    actors: hisActors,
    fivePosters: fivePosters,
    favPosters: favPosters,
    watchPosters: watchPosters,
    userFavPosters: userFavPosters, // Yeni eklenen alan
    commonFiveCount: commonFiveIds.length,
    commonFavCount: commonFavIds.length,
    commonWatchCount: commonWatchIds.length,
  );
}