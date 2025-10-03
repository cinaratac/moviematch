import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/profilescreen.dart' show ProfilePage;
import 'package:fluttergirdi/screens/public_profile_screen.dart';

class PassesPage extends StatelessWidget {
  const PassesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Geçilenler')),
      body: const PassesListBody(),
    );
  }
}

/// Pair-doc şemasına göre (likes/{pairId}) geçilenleri gösterir.
class PassesListBody extends StatefulWidget {
  const PassesListBody({super.key});

  @override
  State<PassesListBody> createState() => _PassesListBodyState();
}

class _PassesListBodyState extends State<PassesListBody>
    with AutomaticKeepAliveClientMixin {
  late final String _uid;
  late final FirebaseFirestore _fs;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream;
  final PageStorageKey _listKey = const PageStorageKey('passes_list');

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser!.uid;
    _fs = FirebaseFirestore.instance;
    // Create the stream once so it doesn't get recreated on tab switches
    _stream = _fs
        .collection('likes')
        .where('uids', arrayContains: _uid)
        .snapshots();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Hata oluştu'));
        }

        final docs = snapshot.data?.docs ?? const [];

        // Benim açımdan PASS olan ve MATCH olmayan çiftleri seç
        final items = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        for (final d in docs) {
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
            items.add(d);
          }
        }

        if (items.isEmpty) {
          return const Center(child: Text('Henüz geçilen yok'));
        }

        // updatedAt'e göre yeni → eski sırala
        items.sort((a, b) {
          final ta = a.data()['updatedAt'];
          final tb = b.data()['updatedAt'];
          final da = (ta is Timestamp)
              ? ta.toDate()
              : DateTime.fromMillisecondsSinceEpoch(0);
          final db = (tb is Timestamp)
              ? tb.toDate()
              : DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        });

        return ListView.builder(
          key: _listKey,
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final data = items[i].data();
            final otherUid = (_uid == data['a'])
                ? data['b'] as String?
                : data['a'] as String?;
            final when = (data['updatedAt'] as Timestamp?)?.toDate().toLocal();
            if (otherUid == null) return const SizedBox.shrink();
            return _PassDetailCard(otherUid: otherUid, when: when);
          },
        );
      },
    );
  }
}

class _PassDetailCard extends StatelessWidget {
  final String otherUid;
  final DateTime? when;
  const _PassDetailCard({required this.otherUid, this.when});

  void _openProfile(BuildContext context, String uid) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ProfilePage(),
        settings: RouteSettings(arguments: uid),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: otherUid)),
        );
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: FutureBuilder<_CardData>(
            future: _loadCardData(otherUid),
            builder: (context, snap) {
              final cd = snap.data;
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
                            final lb =
                                (u['letterboxdUsername'] ?? '') as String;
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
                                    (photoURL != null && photoURL.isNotEmpty)
                                    ? NetworkImage(photoURL)
                                    : null,
                                child: (photoURL == null || photoURL.isEmpty)
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
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Bilgi pill'leri
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

  // helpers
  List<String> ls(dynamic x) {
    if (x is List) return x.map((e) => e.toString()).toList();
    return const <String>[];
  }

  // More robust extractors: support ["a","b"], [1,2], or [{id:"x"},{poster:"..."}]
  List<String> extractIds(dynamic v) {
    final out = <String>[];
    if (v is List) {
      for (final e in v) {
        if (e is String) {
          if (e.trim().isNotEmpty) out.add(e.trim());
        } else if (e is num) {
          out.add(e.toString());
        } else if (e is Map) {
          final m = e.cast<String, dynamic>();
          final candidates = [
            'id',
            'key',
            'filmId',
            'movieId',
            'tmdbId',
            'imdbId',
            'letterboxdId',
          ];
          for (final k in candidates) {
            final val = m[k];
            if (val is String && val.trim().isNotEmpty) {
              out.add(val.trim());
              break;
            }
            if (val is num) {
              out.add(val.toString());
              break;
            }
          }
        }
      }
    }
    return out;
  }

  List<String> extractPosters(dynamic v) {
    final out = <String>[];
    if (v is List) {
      for (final e in v) {
        if (e is String) {
          if (e.trim().isNotEmpty) out.add(e.trim());
        } else if (e is Map) {
          final m = e.cast<String, dynamic>();
          final candidates = [
            'poster',
            'posterUrl',
            'poster_url',
            'posterPath',
            'poster_path',
            'image',
            'url',
          ];
          for (final k in candidates) {
            final val = m[k];
            if (val is String && val.trim().isNotEmpty) {
              out.add(val.trim());
              break;
            }
          }
        }
      }
    }
    return out;
  }

  List<String> pickIds(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final v = map[k];
      final ids = extractIds(v);
      if (ids.isNotEmpty) return ids;
    }
    return const <String>[];
  }

  List<String> pickPosters(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final v = map[k];
      final posters = extractPosters(v);
      if (posters.isNotEmpty) return posters;
    }
    return const <String>[];
  }

  List<String> pickList(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final v = map[k];
      if (v != null) {
        final list = ls(v);
        if (list.isNotEmpty) return list;
      }
    }
    return const <String>[];
  }

  List<String> inter(List<String> a, List<String> b) {
    final bs = b.toSet();
    return a.where(bs.contains).toList();
  }

  Future<List<String>> fetchPostersByDocIds(List<String> ids) async {
    if (ids.isEmpty) return const <String>[];
    const chunk = 10; // whereIn limit
    final posters = <String>[];
    for (var i = 0; i < ids.length; i += chunk) {
      final part = ids.sublist(
        i,
        i + chunk > ids.length ? ids.length : i + chunk,
      );

      QuerySnapshot<Map<String, dynamic>> qs = await fs
          .collection('catalog_films')
          .where(FieldPath.documentId, whereIn: part)
          .get();

      if (qs.docs.isEmpty) {
        // fallback: try matching by 'key' field
        qs = await fs
            .collection('catalog_films')
            .where('key', whereIn: part)
            .get();
      }

      for (final d in qs.docs) {
        final m = d.data();
        final p =
            (m['poster'] ??
                    m['posterUrl'] ??
                    m['image'] ??
                    m['poster_path'] ??
                    '')
                .toString();
        if (p.isNotEmpty) posters.add(p);
      }
    }
    return posters;
  }

  // taste profiles
  final myTaste = await fs.collection('userTasteProfiles').doc(me).get();
  final hisTaste = await fs.collection('userTasteProfiles').doc(otherUid).get();
  final my = myTaste.data() ?? const <String, dynamic>{};
  final his = hisTaste.data() ?? const <String, dynamic>{};

  final hisGenres = pickList(his, ['genres', 'favoriteGenres']);
  final hisDirectors = pickList(his, ['directors', 'favoriteDirectors']);
  final hisActors = pickList(his, ['actors', 'favoriteActors']);

  final myFiveIds = pickIds(my, [
    'fiveIds',
    'fiveFilmIds',
    'fiveStars',
    'fiveStarIds',
  ]);
  final hisFiveIds = pickIds(his, [
    'fiveIds',
    'fiveFilmIds',
    'fiveStars',
    'fiveStarIds',
  ]);
  final myFavIds = pickIds(my, [
    'favIds',
    'favoriteFilmIds',
    'favorites',
    'favoriteIds',
  ]);
  final hisFavIds = pickIds(his, [
    'favIds',
    'favoriteFilmIds',
    'favorites',
    'favoriteIds',
  ]);
  final myWatchIds = pickIds(my, [
    'watchIds',
    'watchlistIds',
    'watchlist',
    'wlIds',
    'watch_list',
    'wl',
  ]);
  final hisWatchIds = pickIds(his, [
    'watchIds',
    'watchlistIds',
    'watchlist',
    'wlIds',
    'watch_list',
    'wl',
  ]);

  final myFivePostersRaw = pickPosters(my, ['fivePosters', 'fivePosterUrls']);
  final hisFivePostersRaw = pickPosters(his, ['fivePosters', 'fivePosterUrls']);
  final myFavPostersRaw = pickPosters(my, [
    'favPosters',
    'favoritePosters',
    'favoritePosterUrls',
  ]);
  final hisFavPostersRaw = pickPosters(his, [
    'favPosters',
    'favoritePosters',
    'favoritePosterUrls',
  ]);
  final myWatchPostersRaw = pickPosters(my, [
    'watchPosters',
    'watchPosterUrls',
    'watchlistPosters',
    'watchlistPosterUrls',
    'wlPosters',
    'watchlist',
  ]);
  final hisWatchPostersRaw = pickPosters(his, [
    'watchPosters',
    'watchPosterUrls',
    'watchlistPosters',
    'watchlistPosterUrls',
    'wlPosters',
    'watchlist',
  ]);

  List<String> commonFiveIds = inter(myFiveIds, hisFiveIds);
  List<String> commonFavIds = inter(myFavIds, hisFavIds);
  List<String> commonWatchIds = inter(myWatchIds, hisWatchIds);

  List<String> fivePosters = commonFiveIds.isNotEmpty
      ? await fetchPostersByDocIds(commonFiveIds)
      : inter(myFivePostersRaw, hisFivePostersRaw);

  List<String> favPosters = commonFavIds.isNotEmpty
      ? await fetchPostersByDocIds(commonFavIds)
      : inter(myFavPostersRaw, hisFavPostersRaw);

  List<String> watchPosters = commonWatchIds.isNotEmpty
      ? await fetchPostersByDocIds(commonWatchIds)
      : inter(myWatchPostersRaw, hisWatchPostersRaw);

  // Fallback: ID listeleri var ama kesişim ve poster-intersection boşsa, ID -> poster çöz ve poster'e göre kesiştir
  Future<List<String>> resolveAndIntersectByPoster(
    List<String> mineIds,
    List<String> hisIds,
  ) async {
    if (mineIds.isEmpty || hisIds.isEmpty) return const <String>[];
    final mine = await fetchPostersByDocIds(mineIds);
    final his = await fetchPostersByDocIds(hisIds);
    final hisSet = his.toSet();
    return mine.where(hisSet.contains).toList();
  }

  if (commonWatchIds.isEmpty &&
      watchPosters.isEmpty &&
      myWatchIds.isNotEmpty &&
      hisWatchIds.isNotEmpty) {
    final p = await resolveAndIntersectByPoster(myWatchIds, hisWatchIds);
    if (p.isNotEmpty) watchPosters = p;
  }
  if (commonFavIds.isEmpty &&
      favPosters.isEmpty &&
      myFavIds.isNotEmpty &&
      hisFavIds.isNotEmpty) {
    final p = await resolveAndIntersectByPoster(myFavIds, hisFavIds);
    if (p.isNotEmpty) favPosters = p;
  }
  if (commonFiveIds.isEmpty &&
      fivePosters.isEmpty &&
      myFiveIds.isNotEmpty &&
      hisFiveIds.isNotEmpty) {
    final p = await resolveAndIntersectByPoster(myFiveIds, hisFiveIds);
    if (p.isNotEmpty) fivePosters = p;
  }

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
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
        color: Colors.black.withValues(alpha: 0.06),
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
            color: Colors.black.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
