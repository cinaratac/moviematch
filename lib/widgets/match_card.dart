import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';
import 'package:fluttergirdi/services/match_service.dart' as global_match;
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';
import 'dart:math' as math;

/// Film verisi taşıyıcı sınıf
class FilmItem {
  final String id;
  final String title;
  final String posterUrl;
  final int? tmdbId; // EKLENDİ

  const FilmItem({
    required this.id, 
    required this.title, 
    required this.posterUrl,
    this.tmdbId, // EKLENDİ
  });
}
class MatchCard extends StatefulWidget {
  final global_match.MatchResult result;
  final VoidCallback onOpen;
  final VoidCallback onLike;
  final VoidCallback onPass;

  const MatchCard({
    required this.result,
    required this.onOpen,
    required this.onLike,
    required this.onPass,
    super.key,
  });

  @override
  State<MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends State<MatchCard> with AutomaticKeepAliveClientMixin {
  late final Future<_CardData> _commonDataFuture;
  late final Future<_UserProfileData> _profileDataFuture;

  @override
  void initState() {
    super.initState();
    // 1. Ortak filmleri yükle (Mevcut mantık)
    _commonDataFuture = _loadCommonData(widget.result);
    // 2. Kullanıcının detaylı profilini yükle (YENİ)
    _profileDataFuture = _loadUserProfile(widget.result.uid);
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final m = widget.result;
    final theme = Theme.of(context);
    final pct = m.score.clamp(0, 100).toStringAsFixed(0);

    final title = (m.displayName != null && m.displayName!.isNotEmpty)
        ? m.displayName!
        : (m.letterboxdUsername != null ? '@${m.letterboxdUsername}' : 'Kullanıcı');

    final hasPhoto = m.photoURL != null && m.photoURL!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // --- 1. KATMAN: ARKA PLAN RESMİ ---
          if (hasPhoto)
            Image.network(
              m.photoURL!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildDefaultBackground(theme),
            )
          else
            _buildDefaultBackground(theme),

          // --- 2. KATMAN: KARARTMA (Gradient Overlay) ---
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black54, // Yazıların arkası
                  Colors.black87,
                  Colors.black, // En alt kısım tamamen siyah
                ],
                stops: [0.0, 0.3, 0.5, 0.8, 1.0],
              ),
            ),
          ),

          // --- 3. KATMAN: İÇERİK (Scrollable) ---
          Positioned.fill(
            bottom: 90, // Butonlar için alttan boşluk
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.35), // Resmi boş bırak

                  // --- İsim & Uyum ---
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _goToProfile(context),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '%$pct Uyum',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  height: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: widget.onOpen,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white24,
                          padding: const EdgeInsets.all(12),
                        ),
                        icon: const Icon(Icons.info_outline_rounded, color: Colors.white),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // --- Ortak İstatistikler ---
                  Row(
                    children: [
                      if (m.commonFiveCount > 0)
                        _StatBadge(icon: Icons.star_rounded, count: m.commonFiveCount, color: Colors.amber),
                      if (m.commonFavCount > 0)
                        _StatBadge(icon: Icons.favorite_rounded, count: m.commonFavCount, color: Colors.redAccent),
                      if (m.commonWatchCount > 0)
                        _StatBadge(icon: Icons.visibility_rounded, count: m.commonWatchCount, color: Colors.blueAccent),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // --- YENİ BÖLÜM: Biyografi ve Profil Detayları ---
                  FutureBuilder<_UserProfileData>(
                    future: _profileDataFuture,
                    builder: (context, snap) {
                      if (!snap.hasData) return const SizedBox.shrink();
                      final p = snap.data!;
                      
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Yaş
                          if (p.age != null && p.age! > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Row(
                                children: [
                                  const Icon(Icons.cake, size: 16, color: Colors.white70),
                                  const SizedBox(width: 6),
                                  Text('${p.age} yaşında', style: const TextStyle(color: Colors.white70)),
                                ],
                              ),
                            ),

                          // Biyografi
                          if (p.bio.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16.0),
                              child: Text(
                                p.bio,
                                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),

                          // Sevdiği Yönetmen/Oyuncular (Chip List)
                          if (p.favDirectors.isNotEmpty || p.favActors.isNotEmpty)
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                ...p.favDirectors.take(2).map((d) => _ProfileChip(label: d, icon: Icons.movie_creation_outlined)),
                                ...p.favActors.take(2).map((a) => _ProfileChip(label: a, icon: Icons.person_outline)),
                              ],
                            ),
                          
                          if (p.favDirectors.isNotEmpty || p.favActors.isNotEmpty)
                            const SizedBox(height: 24),

                          // --- ONUN FAVORİLERİ (Ortaksa Kırmızı Çember) ---
                          if (p.favorites.isNotEmpty) ...[
                            const Text(
                              'FAVORİ FİLMLERİ',
                              style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 110, // Kırmızı çember için biraz yer açtık
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: p.favorites.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 12),
                                itemBuilder: (ctx, i) {
                                  final film = p.favorites[i];
                                  
                                  // KONTROL: Bu film bizimle ortak mı?
                                  // MatchResult içindeki commonFavorites listesine bakıyoruz
                                  final isCommon = m.commonFavorites.contains(film.id);

                                  return Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      GestureDetector( // GESTURE DETECTOR EKLENDİ
                                        onTap: () {
                                          if (film.tmdbId != null) {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => MovieDetailScreen(
                                                  tmdbId: film.tmdbId!,
                                                  title: film.title,
                                                  posterUrl: film.posterUrl,
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                        child: Container(
                                          decoration: BoxDecoration(
                                            border: isCommon ? Border.all(color: Colors.redAccent, width: 3) : null,
                                            borderRadius: BorderRadius.circular(10),
                                            boxShadow: isCommon ? [
                                              BoxShadow(color: Colors.redAccent.withOpacity(0.5), blurRadius: 8, spreadRadius: 1)
                                            ] : [],
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: SizedBox(
                                              width: 60, 
                                              height: 90,
                                              child: PosterImage(
                                                posterUrl: film.posterUrl,
                                                title: film.title,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      // ... geri kalan kodlar aynı ...
                                    ],
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ],
                      );
                    },
                  ),

                  // --- Ortak Filmler (Eski Bölüm - Aşağıda Yedek Olarak Kalabilir veya Kaldırılabilir) ---
                  // Kullanıcı favorilerini yukarıya aldığımız için burayı sadeleştirebiliriz.
                  // Ama "Ortak 5 Yıldızlar" gibi diğer kategoriler için tutuyoruz.
                  FutureBuilder<_CardData>(
                    future: _commonDataFuture,
                    builder: (context, snap) {
                      final cd = snap.data;
                      final hasFilms = cd != null && cd.allFilms.isNotEmpty;
                      if (!hasFilms) return const SizedBox.shrink();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'DİĞER ORTAK FİLMLER',
                            style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 100,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: cd!.allFilms.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (ctx, i) {
                                final film = cd.allFilms[i];
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: AspectRatio(
                                    aspectRatio: 2 / 3,
                                    child: PosterImage(
                                      posterUrl: film.posterUrl,
                                      title: film.title,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  
                  const SizedBox(height: 24), // En alttaki butonlar için ekstra boşluk
                ],
              ),
            ),
          ),

          // --- 4. KATMAN: SABİT BUTONLAR (En Alta) ---
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ActionButton(
                  onPressed: widget.onPass,
                  icon: Icons.close_rounded,
                  color: Colors.white,
                  backgroundColor: Colors.white24,
                  size: 60,
                ),
                const SizedBox(width: 20),
                _ActionButton(
                  onPressed: widget.onLike,
                  icon: Icons.favorite_rounded,
                  color: theme.colorScheme.onPrimary,
                  backgroundColor: theme.colorScheme.primary,
                  size: 72,
                  isElevated: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _goToProfile(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(uid: widget.result.uid),
      ),
    );
  }

  Widget _buildDefaultBackground(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [theme.colorScheme.surfaceContainerHighest, theme.colorScheme.surface],
        ),
      ),
      child: Center(
        child: Icon(Icons.person_rounded, size: 100, color: theme.colorScheme.outline.withOpacity(0.3)),
      ),
    );
  }
}

// --- YARDIMCI WIDGET'LAR ---

class _ProfileChip extends StatelessWidget {
  final String label;
  final IconData icon;
  const _ProfileChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white70),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color color;
  const _StatBadge({required this.icon, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text('$count', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final double size;
  final bool isElevated;

  const _ActionButton({
    required this.onPressed,
    required this.icon,
    required this.color,
    required this.backgroundColor,
    required this.size,
    this.isElevated = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: backgroundColor,
          foregroundColor: color,
          elevation: isElevated ? 8 : 0,
          shadowColor: isElevated ? backgroundColor.withOpacity(0.5) : Colors.transparent,
          shape: const CircleBorder(),
        ),
        child: Icon(icon, size: size * 0.5),
      ),
    );
  }
}

// --- VERİ MODELLERİ VE YÜKLEME ---

class _CardData {
  final List<FilmItem> allFilms; 
  const _CardData({this.allFilms = const []});
}

class _UserProfileData {
  final String bio;
  final int? age;
  final List<String> favDirectors;
  final List<String> favActors;
  final List<FilmItem> favorites; // Karşı tarafın tüm favorileri

  const _UserProfileData({
    this.bio = '',
    this.age,
    this.favDirectors = const [],
    this.favActors = const [],
    this.favorites = const [],
  });
}

// Ortak filmleri yükler (Eski fonksiyon)
Future<_CardData> _loadCommonData(global_match.MatchResult m) async {
  final db = FirebaseFirestore.instance;
  final allKeys = <String>{
    ...m.commonFiveStars.take(4),
    ...m.commonFavorites.take(4),
    ...m.commonWatchlist.take(2)
  }.take(6).toList(); 

  if(allKeys.isEmpty) return const _CardData();
  final films = await _fetchFilmsByKeys(allKeys);
  return _CardData(allFilms: films);
}

// Kullanıcı detaylarını yükler (YENİ)
Future<_UserProfileData> _loadUserProfile(String uid) async {
  try {
    final db = FirebaseFirestore.instance;
    final doc = await db.collection('users').doc(uid).get();
    
    if (!doc.exists) return const _UserProfileData();
    final data = doc.data()!;

    final bio = (data['bio'] ?? '').toString();
    final age = data['age'] as int?;
    final dirs = List<String>.from(data['favDirectors'] ?? []);
    final actors = List<String>.from(data['favActors'] ?? []);
    
    // Kullanıcının favori film listesini al (ID'ler)
    final favKeys = List<String>.from(data['favoritesKeys'] ?? []);
    
    // ID'leri Film Objelerine çevir
    // Performans için sadece ilk 10 favoriyi çekiyoruz
    final resolvedFavs = await _fetchFilmsByKeys(favKeys.take(10).toList());

    return _UserProfileData(
      bio: bio,
      age: age,
      favDirectors: dirs,
      favActors: actors,
      favorites: resolvedFavs,
    );
  } catch (_) {
    return const _UserProfileData();
  }
}

// ID listesinden FilmItem listesi üreten yardımcı fonksiyon
Future<List<FilmItem>> _fetchFilmsByKeys(List<String> keys) async {
  if (keys.isEmpty) return [];
  final db = FirebaseFirestore.instance;
  final films = <FilmItem>[];
  
  for (var i = 0; i < keys.length; i += 10) {
    final chunk = keys.sublist(i, math.min(i + 10, keys.length));
    try {
      var qs = await db.collection('catalog_films').where(FieldPath.documentId, whereIn: chunk).get();
      
      if (qs.docs.isEmpty) {
        qs = await db.collection('catalog_films').where('key', whereIn: chunk).get();
      }

      for (final d in qs.docs) {
        final data = d.data();
        final p = (data['posterUrl'] ?? data['poster'] ?? '').toString();
        final t = (data['title'] ?? data['name'] ?? '').toString();
        final tmdbId = data['tmdbId'] as int?; // EKLENDİ

        if (t.isNotEmpty) {
          films.add(FilmItem(
            id: d.id, 
            title: t, 
            posterUrl: p, 
            tmdbId: tmdbId // EKLENDİ
          ));
        }
      }
    } catch (_) {}
  }
  return films;
}