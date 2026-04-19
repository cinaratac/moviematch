import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart'
    show PublicProfileScreen;
import 'package:fluttergirdi/widgets/poster_image.dart';

// --- Data Models (Poster Fallback için Geri Getirildi) ---

class _PosterData {
  final String posterUrl;
  final String? title;
  final int? tmdbId;
  const _PosterData({required this.posterUrl, this.title, this.tmdbId});
}

class _CardData {
  final String? title;
  final String? photoURL;
  final int? age;
  final List<String> genres;
  final List<String> directors;
  final List<String> actors;
  
  // String listesi yerine zengin veri modeli kullanıyoruz
  final List<_PosterData> fivePosters;
  final List<_PosterData> favPosters;
  final List<_PosterData> watchPosters;
  final List<_PosterData> userFavPosters;

  final int? commonFiveCount;
  final int? commonFavCount;
  final int? commonWatchCount;

  _CardData({
    this.title,
    this.photoURL,
    this.age,
    this.genres = const [],
    this.directors = const [],
    this.actors = const [],
    this.fivePosters = const [],
    this.favPosters = const [],
    this.watchPosters = const [],
    this.userFavPosters = const [],
    this.commonFiveCount,
    this.commonFavCount,
    this.commonWatchCount,
  });
}

// --- Main Page ---

class LikesPage extends StatelessWidget {
  const LikesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Beğenilenler',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: theme.colorScheme.surface,
      ),
      body: const LikesListBody(),
    );
  }
}

class LikesListBody extends StatefulWidget {
  const LikesListBody({super.key});

  @override
  State<LikesListBody> createState() => _LikesListBodyState();
}

class _LikesListBodyState extends State<LikesListBody>
    with AutomaticKeepAliveClientMixin<LikesListBody> {
  late final String _uid;
  late final FirebaseFirestore _fs;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;
  late final Future<Map<String, dynamic>> _myTasteFuture;
  
  final Map<String, Future<_CardData>> _cardCache = {};
  
  Future<_CardData> _getCardData(
    String otherUid,
    Map<String, dynamic> myTaste,
  ) {
    return _cardCache[otherUid] ??= _loadCardData(otherUid, myTaste);
  }

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser!.uid;
    _fs = FirebaseFirestore.instance;
    
    _stream = _fs
        .collection('likes')
        .where('uids', arrayContains: _uid)
        .limit(200)
        .snapshots();
        
    _myTasteFuture = () async {
      final docRef = _fs.collection('userTasteProfiles').doc(_uid);
      try {
        final cache = await docRef.get(const GetOptions(source: Source.cache));
        if (cache.exists && (cache.data() != null)) return cache.data()!;
      } catch (_) {}
      try {
        final server = await docRef.get(const GetOptions(source: Source.server));
        if (server.exists && (server.data() != null)) return server.data()!;
      } catch (_) {}
      return const <String, dynamic>{};
    }();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); 
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !(snapshot.hasData && (snapshot.data?.docs.isNotEmpty ?? false))) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Bir hata oluştu',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? const [];
        final items = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        
        for (final d in docs) {
          final data = d.data();
          final a = data['a'] as String?;
          final b = data['b'] as String?;
          if (a == null || b == null) continue;

          final meIsA = (_uid == a);
          final myLike = data[meIsA ? 'aLiked' : 'bLiked'] == true;
          final otherLike = data[meIsA ? 'bLiked' : 'aLiked'] == true;
          final myPass = data[meIsA ? 'aPass' : 'bPass'] == true;
          final matched = myLike && otherLike;

          if (myLike && !matched && !myPass) {
            items.add(d);
          }
        }

        if (items.isEmpty) {
          return _buildEmptyState(context);
        }

        items.sort((a, b) {
          final ma = a.data();
          final mb = b.data();
          final ta = (ma['updatedAt'] ?? ma['createdAt']);
          final tb = (mb['updatedAt'] ?? mb['createdAt']);
          final da = (ta is Timestamp)
              ? ta.toDate()
              : DateTime.fromMillisecondsSinceEpoch(0);
          final db = (tb is Timestamp)
              ? tb.toDate()
              : DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        });

        return FutureBuilder<Map<String, dynamic>>(
          future: _myTasteFuture,
          builder: (context, tasteSnap) {
            if (tasteSnap.connectionState == ConnectionState.waiting || !tasteSnap.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
            final myTaste = tasteSnap.data ?? const <String, dynamic>{};
            return ListView.separated(
              key: const PageStorageKey('likes_list'),
              // SCROLL FIX: cacheExtent yerine KeepAlive kullanıyoruz.
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: items.length,
              separatorBuilder: (ctx, index) => const SizedBox(height: 16),
              itemBuilder: (context, i) {
                final data = items[i].data();
                final otherUid = (_uid == data['a'])
                    ? data['b'] as String?
                    : data['a'] as String?;
                final whenTs =
                    (data['updatedAt'] ?? data['createdAt']) as Timestamp?;
                final when = whenTs?.toDate().toLocal();
                if (otherUid == null) return const SizedBox.shrink();
                
                // POSTER FIX + SCROLL FIX: Hem veri çekimi doğru hem de stateful widget.
                return _LikesDetailCard(
                  otherUid: otherUid,
                  when: when,
                  cardDataFuture: _getCardData(otherUid, myTaste),
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
            Icons.favorite_border_rounded,
            size: 64,
            color: Theme.of(context).disabledColor,
          ),
          const SizedBox(height: 16),
          Text(
            'Henüz beğendiğin kimse yok',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).disabledColor,
                ),
          ),
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

// --- SCROLL FIX İÇİN STATEFUL WIDGET ---

class _LikesDetailCard extends StatefulWidget {
  final String otherUid;
  final DateTime? when;
  final Future<_CardData> cardDataFuture;

  const _LikesDetailCard({
    required this.otherUid,
    this.when,
    required this.cardDataFuture,
  });

  @override
  State<_LikesDetailCard> createState() => _LikesDetailCardState();
}

class _LikesDetailCardState extends State<_LikesDetailCard>
    with AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true; // Scroll sırasında widget'ı canlı tutar.

  @override
  Widget build(BuildContext context) {
    super.build(context); // KeepAlive için gerekli
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return FutureBuilder<_CardData>(
      future: widget.cardDataFuture,
      builder: (context, snap) {
        if (snap.hasError) return const SizedBox.shrink();
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
                  MaterialPageRoute(
                      builder: (_) => PublicProfileScreen(uid: widget.otherUid)),
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

  Widget _buildLoadedContent(
      BuildContext context, _CardData cd, ThemeData theme) {
    final title = cd.title ?? 'Kullanıcı';
    final photoURL = cd.photoURL;
    final age = cd.age;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- HEADER ---
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Hero(
              tag: 'avatar_${widget.otherUid}',
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.surfaceContainerHighest, 
                    width: 2
                  ),
                  image: (photoURL != null && photoURL.isNotEmpty)
                      ? DecorationImage(
                          image: NetworkImage(photoURL), fit: BoxFit.cover)
                      : null,
                ),
                child: (photoURL == null || photoURL.isEmpty)
                    ? Icon(Icons.person,
                        size: 30, color: theme.colorScheme.onSurfaceVariant)
                    : null,
              ),
            ),
            const SizedBox(width: 16),
            
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (age != null)
                    Text(
                      '$age yaşında',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
            )
          ],
        ),

        const SizedBox(height: 16),

        // --- STATS ---
        if (cd.commonFiveCount != null && cd.commonFiveCount! > 0)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withOpacity(0.4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star_rounded, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '${cd.commonFiveCount} Ortak 5 Yıldız',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        
        if (cd.commonFiveCount != null && cd.commonFiveCount! > 0)
           const SizedBox(height: 16),

        // --- GENRES ---
        if (cd.genres.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: cd.genres.take(4).map((g) => _ModernChip(label: g)).toList(),
          ),
          const SizedBox(height: 16),
        ],

        // --- POSTER STRIP (POSTER FIX UYGULANDI) ---
        if (cd.fivePosters.isNotEmpty || cd.favPosters.isNotEmpty) ...[
          _SectionHeader(
              title: cd.fivePosters.isNotEmpty
                  ? 'Ortak Sevilenler'
                  : 'Favori Filmleri'),
          const SizedBox(height: 10),
          _PosterStrip(
            data: cd.fivePosters.isNotEmpty ? cd.fivePosters : cd.favPosters,
          ),
        ] else if (cd.watchPosters.isNotEmpty) ...[
           _SectionHeader(title: 'İzleme Listesi'),
           const SizedBox(height: 10),
           _PosterStrip(data: cd.watchPosters),
           ] else if (cd.userFavPosters.isNotEmpty) ...[
           _SectionHeader(title: 'KULLANICININ FAVORİLERİ'),
           const SizedBox(height: 10),
           _PosterStrip(data: cd.userFavPosters),
        ] else ...[
           Container(
             height: 80,
             width: double.infinity,
             alignment: Alignment.center,
             decoration: BoxDecoration(
               color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
               borderRadius: BorderRadius.circular(12)
             ),
             child: Text(
               'Henüz film bilgisi yok', 
               style: TextStyle(color: theme.colorScheme.onSurfaceVariant)
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

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 1.1,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.outline,
          ),
    );
  }
}

// POSTER FIX: List<_PosterData> kabul ediyor ve PosterImage'a detay gönderiyor.
class _PosterStrip extends StatelessWidget {
  final List<_PosterData> data;
  const _PosterStrip({required this.data});
  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 130, 
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
                title: item.title,      // Title gönderiyoruz
                tmdbId: item.tmdbId,    // ID gönderiyoruz
                fit: BoxFit.cover
              ),
            ),
          );
        },
      ),
    );
  }
}

// --- Skeleton Loading ---

class _SkeletonContent extends StatelessWidget {
  const _SkeletonContent();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SkeletonBox(width: 60, height: 60, isCircle: true),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _SkeletonBox(width: 120, height: 20),
                SizedBox(height: 8),
                _SkeletonBox(width: 60, height: 14),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _SkeletonBox(width: double.infinity, height: 40), 
        const SizedBox(height: 16),
        Row(
          children: const [
            _SkeletonBox(width: 80, height: 24),
            SizedBox(width: 8),
            _SkeletonBox(width: 100, height: 24),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 130,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, __) => AspectRatio(
              aspectRatio: 2 / 3,
              child: const _SkeletonBox(width: double.infinity, height: double.infinity),
            ),
          ),
        )
      ],
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final bool isCircle;
  const _SkeletonBox({required this.width, required this.height, this.isCircle = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(8),
      ),
    );
  }
}

// --- DATA LOGIC (POSTER FIX ve NULL SAFETY) ---

// BU FONKSİYONU ESKİSİYLE DEĞİŞTİRİN
Future<_CardData> _loadCardData(
  String otherUid,
  Map<String, dynamic> my,
) async {
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

  Future<List<_PosterData>> fetchPosters(List<String> ids) async {
    if (ids.isEmpty) return [];
    
    final postersMap = <String, _PosterData>{};
    final targetIds = ids.take(10).toList();
    
    try {
      // 1. Döküman ID araması
      final docIdQuery = fs.collection('catalog_films')
          .where(FieldPath.documentId, whereIn: targetIds)
          .get();

      // 2. TMDB ID (Sayısal) araması
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

      final docIdSnap = results[0];
      final tmdbSnap = results[1];

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

    } catch (_) { }
    
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
  final u = userDoc.data() ?? const <String, dynamic>{}; // User doc verisi
  final username = u['username'] as String?;
  if (username == null || username.trim().isEmpty) {
    throw Exception('Kullanıcı silinmiş veya username belirlenmemiş.');
  }
  
  // Türler, Yönetmenler (Taste + User birleşimi)
  final hisGenres = pickMergedIds(hisTaste, u, ['genres', 'favoriteGenres']);
  final hisDirectors = pickMergedIds(hisTaste, u, ['directors', 'favoriteDirectors']);
  final hisActors = pickMergedIds(hisTaste, u, ['actors', 'favoriteActors']);

  // ID Listeleri (Taste + User birleşimi)
  // Artık hem 'hisTaste' hem 'u' (users) haritalarındaki alanlara bakıyoruz.
  final hisFiveIds = pickMergedIds(hisTaste, u, ['loved', 'fiveIds', 'fiveFilmIds', 'fiveStars']);
  final hisFavIds = pickMergedIds(hisTaste, u, ['favIds', 'favoriteFilmIds', 'favorites']);
  final hisWatchIds = pickMergedIds(hisTaste, u, ['watchIds', 'watchlist']);

  // Benim ID'lerim (Sadece myTaste)
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
  
  // Ortak hiçbir şey yoksa karşı tarafın listelerini dene
  if (fivePosters.isEmpty && favPosters.isEmpty && watchPosters.isEmpty) {
     
     // 1. Favoriler
     if (hisFavIds.isNotEmpty) {
       userFavPosters = await fetchPosters(hisFavIds);
     }
     
     // 2. 5 Yıldızlar
     if (userFavPosters.isEmpty && hisFiveIds.isNotEmpty) {
       userFavPosters = await fetchPosters(hisFiveIds);
     }
     
     // 3. İzleme Listesi
     if (userFavPosters.isEmpty && hisWatchIds.isNotEmpty) {
       userFavPosters = await fetchPosters(hisWatchIds);
     }
  }

  // Profil Bilgileri (Zaten çekmiştik)
  String? title;
  String? photoURL;
  int? age;
  
  if (userDoc.exists) {
  
    photoURL = (u['photoURL'] ?? '') as String?;
    title = username;

    final bd = u['birthdate'];
    if (bd is Timestamp) {
      final d = bd.toDate();
      final now = DateTime.now();
      int a = now.year - d.year;
      if (DateTime(now.year, d.month, d.day).isAfter(now)) a -= 1;
      age = a;
    } else if (u['age'] is int) {
      age = u['age'] as int;
    }
  }
  
  return _CardData(
    title: title,
    photoURL: photoURL,
    age: age,
    genres: hisGenres,
    directors: hisDirectors,
    actors: hisActors,
    fivePosters: fivePosters,
    favPosters: favPosters,
    watchPosters: watchPosters,
    userFavPosters: userFavPosters,
    commonFiveCount: commonFiveIds.length,
    commonFavCount: commonFavIds.length,
    commonWatchCount: commonWatchIds.length,
  );
}