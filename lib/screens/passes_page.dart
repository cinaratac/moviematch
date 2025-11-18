import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';

// --- Data Models ---
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

// --- Main Page ---
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

class PassesListBody extends StatefulWidget {
  const PassesListBody({super.key});

  @override
  State<PassesListBody> createState() => _PassesListBodyState();
}

class _PassesListBodyState extends State<PassesListBody>
    with AutomaticKeepAliveClientMixin {
  late final String _uid;
  late final FirebaseFirestore _fs;
  late final Future<List<_PassRow>> _itemsFuture;
  late final Future<Map<String, dynamic>> _myTasteFuture;
  final Map<String, _UserLite> _userCache = <String, _UserLite>{};
  final PageStorageKey _listKey = const PageStorageKey('passes_list');

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser!.uid;
    _fs = FirebaseFirestore.instance;
    _itemsFuture = _loadPassRows();
    _myTasteFuture = _loadMyTasteOnce();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<_PassRow>>(
      future: _itemsFuture,
      builder: (context, listSnap) {
        if (listSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (listSnap.hasError) {
          return Center(
            child: Text('Bir hata oluştu', 
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          );
        }
        final items = listSnap.data ?? const <_PassRow>[];
        
        if (items.isEmpty) {
          return _buildEmptyState(context);
        }

        return FutureBuilder<Map<String, dynamic>>(
          future: _myTasteFuture,
          builder: (context, tasteSnap) {
            final myTaste = tasteSnap.data ?? const <String, dynamic>{};
            return ListView.separated(
              key: _listKey,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: items.length,
              separatorBuilder: (ctx, index) => const SizedBox(height: 16),
              itemBuilder: (context, i) {
                final row = items[i];
                final lite = _userCache[row.otherUid];
                return _PassDetailCard(
                  otherUid: row.otherUid,
                  when: row.when,
                  title: lite?.title,
                  photoURL: lite?.photoURL,
                  precomputedAge: lite?.age,
                  myTaste: myTaste,
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

  Future<List<_PassRow>> _loadPassRows() async {
    final qs = await _fs
        .collection('likes')
        .where('uids', arrayContains: _uid)
        .get(const GetOptions(source: Source.server));

    final items = <_PassRow>[];
    final needUserIds = <String>{};

    for (final d in qs.docs) {
      final data = d.data();
      final a = data['a'] as String?;
      final b = data['b'] as String?;
      if (a == null || b == null) continue;
      final meIsA = (_uid == a);
      final myPass = data[meIsA ? 'aPass' : 'bPass'] == true;
      final myLike = data[meIsA ? 'aLiked' : 'bLiked'] == true;
      final otherLike = data[meIsA ? 'bLiked' : 'aLiked'] == true;
      final matched = myLike && otherLike;

      if (myPass && !matched) {
        final otherUid = meIsA ? b : a;
        final when = (data['updatedAt'] as Timestamp?)?.toDate().toLocal();
        items.add(_PassRow(otherUid: otherUid, when: when));
        if (!_userCache.containsKey(otherUid)) needUserIds.add(otherUid);
      }
    }

    // Sort by updatedAt desc
    items.sort((x, y) {
      final dx = x.when ?? DateTime.fromMillisecondsSinceEpoch(0);
      final dy = y.when ?? DateTime.fromMillisecondsSinceEpoch(0);
      return dy.compareTo(dx);
    });

    // Batch fetch users
    if (needUserIds.isNotEmpty) {
      final ids = needUserIds.toList();
      const chunk = 10;
      for (var i = 0; i < ids.length; i += chunk) {
        final part = ids.sublist(
          i,
          i + chunk > ids.length ? ids.length : i + chunk,
        );
        final qsUsers = await _fs
            .collection('users')
            .where(FieldPath.documentId, whereIn: part)
            .get(const GetOptions(source: Source.server));
        for (final d in qsUsers.docs) {
          final m = d.data();
          final username = (m['username'] ?? '') as String;
          final displayName = (m['displayName'] ?? '') as String;
          final lb = (m['letterboxdUsername'] ?? '') as String;
          final photoURL = (m['photoURL'] ?? '') as String;
          String title = username.isNotEmpty
              ? username
              : (displayName.isNotEmpty
                    ? displayName
                    : (lb.isNotEmpty ? '@$lb' : d.id));
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
          _userCache[d.id] = _UserLite(
            title: title,
            photoURL: photoURL,
            age: age,
          );
        }
      }
    }
    return items;
  }
}

class _PassDetailCard extends StatelessWidget {
  final String otherUid;
  final DateTime? when;
  final String? title;
  final String? photoURL;
  final int? precomputedAge;
  final Map<String, dynamic> myTaste;

  const _PassDetailCard({
    required this.otherUid,
    this.when,
    this.title,
    this.photoURL,
    this.precomputedAge,
    required this.myTaste,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return FutureBuilder<_CardData>(
      future: _loadCardData(otherUid, myTaste, precomputedAge: precomputedAge),
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
                  MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: otherUid)),
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
    final displayTitle = (title == null || title!.isEmpty) ? otherUid : title!;
    
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
                image: (photoURL != null && photoURL!.isNotEmpty)
                    ? DecorationImage(image: NetworkImage(photoURL!), fit: BoxFit.cover)
                    : null,
              ),
              child: (photoURL == null || photoURL!.isEmpty)
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

        // --- Stats (Common Interests) ---
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
             urls: cd.fivePosters.isNotEmpty ? cd.fivePosters : 
                   (cd.favPosters.isNotEmpty ? cd.favPosters : cd.watchPosters)
           ),
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
  final List<String> urls;
  const _PosterStrip({required this.urls});
  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final u = urls[i];
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: PosterImage(posterUrl: u, title: null, fit: BoxFit.cover),
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

// --- Data Logic (Same logic, better formatting) ---

class _CardData {
  final int? age;
  final List<String> genres;
  final List<String> directors;
  final List<String> actors;
  final List<String> fivePosters;
  final List<String> favPosters;
  final List<String> watchPosters;
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
  });
}

Future<_CardData> _loadCardData(
  String otherUid,
  Map<String, dynamic> my, {
  int? precomputedAge,
}) async {
  final fs = FirebaseFirestore.instance;

  List<String> ls(dynamic x) {
    if (x is List) return x.map((e) => e.toString()).toList();
    return const <String>[];
  }

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

  // Basitleştirilmiş helper
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

  Future<List<String>> fetchPostersByDocIds(List<String> ids) async {
    if (ids.isEmpty) return const <String>[];
    final posters = <String>[];
    const chunk = 10;
    final targetIds = ids.take(chunk).toList(); // Limit fetch

    try {
      // Try docId first
      var qs = await fs.collection('catalog_films').where(FieldPath.documentId, whereIn: targetIds).get();
      
      // Fallback key
      if (qs.docs.isEmpty) {
        qs = await fs.collection('catalog_films').where('key', whereIn: targetIds).get();
      }

      for (final d in qs.docs) {
        final p = (d.data()['poster'] ?? d.data()['posterUrl'] ?? '').toString();
        if (p.isNotEmpty) posters.add(p);
      }
    } catch (_) {}
    return posters;
  }

  final hisTaste = await fs.collection('userTasteProfiles').doc(otherUid).get();
  final his = hisTaste.data() ?? const <String, dynamic>{};

  final hisGenres = ls(his['genres'] ?? his['favoriteGenres']);
  final hisDirectors = ls(his['directors'] ?? his['favoriteDirectors']);
  final hisActors = ls(his['actors'] ?? his['favoriteActors']);

  final myFiveIds = pickIds(my, ['fiveIds', 'fiveFilmIds', 'fiveStars']);
  final hisFiveIds = pickIds(his, ['fiveIds', 'fiveFilmIds', 'fiveStars']);
  final myFavIds = pickIds(my, ['favIds', 'favoriteFilmIds', 'favorites']);
  final hisFavIds = pickIds(his, ['favIds', 'favoriteFilmIds', 'favorites']);
  final myWatchIds = pickIds(my, ['watchIds', 'watchlist']);
  final hisWatchIds = pickIds(his, ['watchIds', 'watchlist']);

  final commonFiveIds = inter(myFiveIds, hisFiveIds);
  final commonFavIds = inter(myFavIds, hisFavIds);
  final commonWatchIds = inter(myWatchIds, hisWatchIds);

  // Fetch posters for commons
  List<String> fivePosters = await fetchPostersByDocIds(commonFiveIds);
  List<String> favPosters = await fetchPostersByDocIds(commonFavIds);
  List<String> watchPosters = await fetchPostersByDocIds(commonWatchIds);

  return _CardData(
    age: precomputedAge,
    genres: hisGenres,
    directors: hisDirectors,
    actors: hisActors,
    fivePosters: fivePosters,
    favPosters: favPosters,
    watchPosters: watchPosters,
    commonFiveCount: commonFiveIds.length,
    commonFavCount: commonFavIds.length,
    commonWatchCount: commonWatchIds.length,
  );
}