import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LikesPage extends StatelessWidget {
  const LikesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Beğenilenler')),
      body: const LikesListBody(),
    );
  }
}

/// Pair-doc şemasına göre (likes/{pairId}) beğenilenleri gösterir.
class LikesListBody extends StatelessWidget {
  const LikesListBody({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final fs = FirebaseFirestore.instance;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: fs
          .collection('likes')
          .where('uids', arrayContains: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Hata oluştu'));
        }

        final docs = snapshot.data?.docs ?? const [];

        // Benim açımdan: like = true, pass = false ve MATCH değil → Beğenilenler
        final items = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        for (final d in docs) {
          final data = d.data();
          final a = data['a'] as String?;
          final b = data['b'] as String?;
          if (a == null || b == null) continue;

          final meIsA = (uid == a);
          final myLike = data[meIsA ? 'aLiked' : 'bLiked'] == true;
          final otherLike = data[meIsA ? 'bLiked' : 'aLiked'] == true;
          final myPass = data[meIsA ? 'aPass' : 'bPass'] == true;
          final matched = myLike && otherLike;

          if (myLike && !matched && !myPass) {
            items.add(d);
          }
        }

        if (items.isEmpty) {
          return const Center(child: Text('Henüz beğenilen yok'));
        }

        // updatedAt (yoksa createdAt) ile yeni → eski sırala
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

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final data = items[i].data();
            final otherUid = (uid == data['a'])
                ? data['b'] as String?
                : data['a'] as String?;
            final whenTs =
                (data['updatedAt'] ?? data['createdAt']) as Timestamp?;
            final when = whenTs?.toDate().toLocal();
            if (otherUid == null) return const SizedBox.shrink();
            return _LikesDetailCard(otherUid: otherUid, when: when);
          },
        );
      },
    );
  }
}

class _LikesDetailCard extends StatelessWidget {
  final String otherUid;
  final DateTime? when;
  const _LikesDetailCard({required this.otherUid, this.when});

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: FutureBuilder<_CardData>(
          future: _loadCardData(otherUid),
          builder: (context, snap) {
            final cd = snap.data;
            final loading = snap.connectionState == ConnectionState.waiting;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      future: fs.collection('users').doc(otherUid).get(),
                      builder: (context, uSnap) {
                        String title = otherUid;
                        String? photoURL;
                        if (uSnap.hasData && uSnap.data!.exists) {
                          final u = uSnap.data!.data()!;
                          final username = (u['username'] ?? '') as String;
                          final displayName =
                              (u['displayName'] ?? '') as String;
                          final lb = (u['letterboxdUsername'] ?? '') as String;
                          photoURL = (u['photoURL'] ?? '') as String;
                          title = username.isNotEmpty
                              ? username
                              : (displayName.isNotEmpty
                                    ? displayName
                                    : (lb.isNotEmpty ? '@$lb' : otherUid));
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 40,
                              backgroundImage:
                                  (photoURL != null && photoURL!.isNotEmpty)
                                  ? NetworkImage(photoURL!)
                                  : null,
                              child: (photoURL == null || photoURL!.isEmpty)
                                  ? const Icon(Icons.person, size: 40)
                                  : null,
                            ),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: theme.textTheme.titleMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (when != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      _formatTimeOrDate(when!),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: Colors.grey.shade600,
                                          ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Küçük bilgi pill'leri
                if (cd != null)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (cd.age != null)
                        _Pill(
                          icon: Icons.cake_outlined,
                          text: 'Yaş: ${cd.age}',
                        ),
                      if (cd.commonFiveCount != null)
                        _Pill(
                          icon: Icons.star_rate_rounded,
                          text: 'Ortak 5★: ${cd.commonFiveCount}',
                        ),
                      if (cd.commonFavCount != null)
                        _Pill(
                          icon: Icons.favorite_outline,
                          text: 'Ortak fav: ${cd.commonFavCount}',
                        ),
                      if (cd.commonWatchCount != null)
                        _Pill(
                          icon: Icons.visibility_outlined,
                          text: 'Ortak watchlist: ${cd.commonWatchCount}',
                        ),
                    ],
                  )
                else
                  const _SkeletonLine(),

                const SizedBox(height: 12),

                // Türler / Yönetmenler / Oyuncular
                if (cd != null) ...[
                  if (cd.genres.isNotEmpty)
                    _ChipsRow(
                      label: 'Sevdiği Türler',
                      values: cd.genres.take(6).toList(),
                    ),
                  if (cd.directors.isNotEmpty)
                    _ChipsRow(
                      label: 'Sevdiği Yönetmenler',
                      values: cd.directors.take(4).toList(),
                    ),
                  if (cd.actors.isNotEmpty)
                    _ChipsRow(
                      label: 'Sevdiği Oyuncular',
                      values: cd.actors.take(4).toList(),
                    ),
                ] else ...[
                  const _SkeletonLine(),
                ],

                const SizedBox(height: 8),

                // Poster şeritleri
                if (cd != null &&
                    (cd.fivePosters.isNotEmpty ||
                        cd.favPosters.isNotEmpty ||
                        cd.watchPosters.isNotEmpty)) ...[
                  if (cd.fivePosters.isNotEmpty) ...[
                    const _SectionLabel(text: 'Ortak 5★ Filmler'),
                    const SizedBox(height: 8),
                    _PosterStrip(urls: cd.fivePosters),
                    const SizedBox(height: 12),
                  ],
                  if (cd.favPosters.isNotEmpty) ...[
                    const _SectionLabel(text: 'Ortak Favoriler'),
                    const SizedBox(height: 8),
                    _PosterStrip(urls: cd.favPosters),
                    const SizedBox(height: 12),
                  ],
                  if (cd.watchPosters.isNotEmpty) ...[
                    const _SectionLabel(text: 'Ortak Watchlist'),
                    const SizedBox(height: 8),
                    _PosterStrip(urls: cd.watchPosters),
                    const SizedBox(height: 12),
                  ],
                ] else ...[
                  const _SkeletonPosters(),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

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

Future<_CardData> _loadCardData(String otherUid) async {
  final fs = FirebaseFirestore.instance;
  final me = FirebaseAuth.instance.currentUser!.uid;

  // --- helpers ---
  List<String> _ls(dynamic x) {
    if (x is List) return x.map((e) => e.toString()).toList();
    return const <String>[];
  }

  List<String> _pickList(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final v = map[k];
      if (v != null) {
        final list = _ls(v);
        if (list.isNotEmpty) return list;
      }
    }
    return const <String>[];
  }

  Future<List<String>> _fetchPostersByDocIds(List<String> ids) async {
    if (ids.isEmpty) return const <String>[];
    // Firestore whereIn limit is 10 → chunk
    const chunk = 10;
    final posters = <String>[];
    for (var i = 0; i < ids.length; i += chunk) {
      final part = ids.sublist(
        i,
        i + chunk > ids.length ? ids.length : i + chunk,
      );
      final qs = await fs
          .collection('catalog_films')
          .where(FieldPath.documentId, whereIn: part)
          .get();
      for (final d in qs.docs) {
        final m = d.data();
        final p = (m['poster'] ?? m['posterUrl'] ?? m['poster_path'] ?? '')
            .toString();
        if (p.isNotEmpty) posters.add(p);
      }
    }
    return posters;
  }

  // --- taste profiles ---
  final myTaste = await fs.collection('userTasteProfiles').doc(me).get();
  final hisTaste = await fs.collection('userTasteProfiles').doc(otherUid).get();
  final my = myTaste.data() ?? const <String, dynamic>{};
  final his = hisTaste.data() ?? const <String, dynamic>{};

  // Basic lists (profil metadata)
  final myGenres = _pickList(my, ['genres', 'favoriteGenres']);
  final hisGenres = _pickList(his, ['genres', 'favoriteGenres']);
  final myDirectors = _pickList(my, ['directors', 'favoriteDirectors']);
  final hisDirectors = _pickList(his, ['directors', 'favoriteDirectors']);
  final myActors = _pickList(my, ['actors', 'favoriteActors']);
  final hisActors = _pickList(his, ['actors', 'favoriteActors']);

  // Film ID alanları (tercihli)
  final myFiveIds = _pickList(my, [
    'fiveIds',
    'fiveFilmIds',
    'fiveStars',
    'fiveStarIds',
  ]);
  final hisFiveIds = _pickList(his, [
    'fiveIds',
    'fiveFilmIds',
    'fiveStars',
    'fiveStarIds',
  ]);
  final myFavIds = _pickList(my, [
    'favIds',
    'favoriteFilmIds',
    'favorites',
    'favoriteIds',
  ]);
  final hisFavIds = _pickList(his, [
    'favIds',
    'favoriteFilmIds',
    'favorites',
    'favoriteIds',
  ]);
  final myWatchIds = _pickList(my, ['watchIds', 'watchlistIds', 'watchlist']);
  final hisWatchIds = _pickList(his, ['watchIds', 'watchlistIds', 'watchlist']);

  // Poster URL alanları (yedek)
  final myFivePostersRaw = _pickList(my, ['fivePosters', 'fivePosterUrls']);
  final hisFivePostersRaw = _pickList(his, ['fivePosters', 'fivePosterUrls']);
  final myFavPostersRaw = _pickList(my, [
    'favPosters',
    'favoritePosters',
    'favoritePosterUrls',
  ]);
  final hisFavPostersRaw = _pickList(his, [
    'favPosters',
    'favoritePosters',
    'favoritePosterUrls',
  ]);
  final myWatchPostersRaw = _pickList(my, ['watchPosters', 'watchPosterUrls']);
  final hisWatchPostersRaw = _pickList(his, [
    'watchPosters',
    'watchPosterUrls',
  ]);

  // intersection helper
  List<String> inter(List<String> a, List<String> b) {
    final bs = b.toSet();
    return a.where(bs.contains).toList();
  }

  // --- Compute commons by IDs first (daha güvenilir), yoksa poster URL kesişimi ---
  List<String> commonFiveIds = inter(myFiveIds, hisFiveIds);
  List<String> commonFavIds = inter(myFavIds, hisFavIds);
  List<String> commonWatchIds = inter(myWatchIds, hisWatchIds);

  // Posters: prefer fetching by IDs, fallback to URL intersections
  List<String> fivePosters;
  if (commonFiveIds.isNotEmpty) {
    fivePosters = await _fetchPostersByDocIds(commonFiveIds);
  } else {
    fivePosters = inter(myFivePostersRaw, hisFivePostersRaw);
  }

  List<String> favPosters;
  if (commonFavIds.isNotEmpty) {
    favPosters = await _fetchPostersByDocIds(commonFavIds);
  } else {
    favPosters = inter(myFavPostersRaw, hisFavPostersRaw);
  }

  List<String> watchPosters;
  if (commonWatchIds.isNotEmpty) {
    watchPosters = await _fetchPostersByDocIds(commonWatchIds);
  } else {
    watchPosters = inter(myWatchPostersRaw, hisWatchPostersRaw);
  }

  // Age (optional)
  int? age;
  try {
    final userDoc = await fs.collection('users').doc(otherUid).get();
    final u = userDoc.data();
    if (u != null) {
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
  } catch (_) {}

  return _CardData(
    age: age,
    genres: hisGenres,
    directors: hisDirectors,
    actors: hisActors,
    fivePosters: fivePosters.take(12).toList(),
    favPosters: favPosters.take(12).toList(),
    watchPosters: watchPosters.take(12).toList(),
    commonFiveCount: commonFiveIds.isNotEmpty
        ? commonFiveIds.length
        : inter(myFivePostersRaw, hisFivePostersRaw).length,
    commonFavCount: commonFavIds.isNotEmpty
        ? commonFavIds.length
        : inter(myFavPostersRaw, hisFavPostersRaw).length,
    commonWatchCount: commonWatchIds.isNotEmpty
        ? commonWatchIds.length
        : inter(myWatchPostersRaw, hisWatchPostersRaw).length,
  );
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Pill({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 16), const SizedBox(width: 6), Text(text)],
      ),
    );
  }
}

class _ChipsRow extends StatelessWidget {
  final String label;
  final List<String> values;
  const _ChipsRow({required this.label, required this.values});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values
              .map(
                (v) =>
                    Chip(label: Text(v), visualDensity: VisualDensity.compact),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});
  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleSmall);
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
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final u = urls[i];
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: Image.network(
                u,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey.shade300,
                  child: const Icon(Icons.broken_image),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 16,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _SkeletonPosters extends StatelessWidget {
  const _SkeletonPosters();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => Container(
          width: 80,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}

String _formatTimeOrDate(DateTime dt) {
  final local = dt.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final thatDay = DateTime(local.year, local.month, local.day);
  if (thatDay == today) {
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
  return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}';
}
