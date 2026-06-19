import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/models/shelf_target.dart';
import 'package:fluttergirdi/models/custom_list.dart';
import 'package:fluttergirdi/services/user_profile_service.dart';
import 'package:fluttergirdi/services/custom_list_service.dart';
import 'package:fluttergirdi/services/streak_service.dart';

class MovieActionSheet extends StatefulWidget {
  final int tmdbId;
  final Map<String, dynamic> movieData;
  final String? posterUrl;
  final String? catalogDocId;

  const MovieActionSheet({
    super.key,
    required this.tmdbId,
    required this.movieData,
    this.posterUrl,
    this.catalogDocId,
  });

  @override
  State<MovieActionSheet> createState() => _MovieActionSheetState();
}

class _MovieActionSheetState extends State<MovieActionSheet> {
  bool _isLoading = true;
  List<CustomList> _customLists = [];

  Set<String> _watchedSet = {};
  Set<String> _watchlistSet = {};
  Set<String> _favoritesSet = {};
  Set<String> _fiveStarSet = {};
  Set<String> _dislikedSet = {};

  late String _tmdbStr;
  late String? _catalogId;

  // ⚡ Abonelikleri (Stream) hafızada tutuyoruz ki kapatırken iptal edebilelim
  StreamSubscription<DocumentSnapshot>? _userSub;
  StreamSubscription<List<CustomList>>? _listsSub;

  @override
  void initState() {
    super.initState();
    _tmdbStr = widget.tmdbId.toString();
    _catalogId = widget.catalogDocId?.toLowerCase();
    _loadInstantly();
  }

  @override
  void dispose() {
    // Sayfa kapandığında dinlemeyi bırakır, işlemciyi yormaz
    _userSub?.cancel();
    _listsSub?.cancel();
    super.dispose();
  }

  void _loadInstantly() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // ⚡ GERÇEK IŞIK HIZI: .get() kullanmıyoruz! .snapshots().listen() 
    // yerel hafızadaki veriyi arka plan kuyruğunu beklemeden ŞAK diye ekrana fırlatır.
    _userSub = FirebaseFirestore.instance.collection('users').doc(uid).snapshots().listen((doc) {
      if (!mounted) return;
      final data = doc.data() ?? {};
      setState(() {
        _watchedSet = _toNormalizedSet(data['watchedKeys']);
        _watchlistSet = _toNormalizedSet(data['watchlistKeys']);
        _favoritesSet = _toNormalizedSet(data['favoritesKeys']);
        _fiveStarSet = _toNormalizedSet(data['fiveStarKeys']);
        _dislikedSet = _toNormalizedSet(data['dislikedKeys']);
        _isLoading = false; // İlk veri geldiği an yükleme ekranını kapat
      });
    }, onError: (e) {
      debugPrint("Kullanıcı verisi çekilemedi: $e");
      if (mounted) setState(() => _isLoading = false);
    });

    // Özel listeleri de aynı şekilde dinliyoruz
    _listsSub = CustomListService.instance.getUserLists(uid).listen((lists) {
      if (mounted) setState(() => _customLists = lists);
    });
  }

  Set<String> _toNormalizedSet(dynamic raw) {
    if (raw == null) return {};
    return List<dynamic>.from(raw as List).map((e) => e.toString().trim().toLowerCase()).toSet();
  }

  bool _isIn(Set<String> set) => set.contains(_tmdbStr) || (_catalogId != null && set.contains(_catalogId));

  void _executeToggle({required Future<void> Function() onServiceCall, bool triggerStreak = false}) {
    if (triggerStreak) StreakService.instance.triggerAction(context);
    
    Navigator.pop(context);

    Future.delayed(const Duration(milliseconds: 300), () async {
      try { await onServiceCall(); } catch (e) { debugPrint("DB Hatası: $e"); }
    });
  }

  Future<void> _toggleWatched(bool isCurrentlyAdded, bool inFav, bool inFive, bool inDisliked) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Arayüzü anında güncelle (İnterneti bekleme)
    setState(() {
      if (isCurrentlyAdded) {
        _watchedSet.remove(_tmdbStr);
        if (_catalogId != null) _watchedSet.remove(_catalogId);
        _favoritesSet.remove(_tmdbStr); _fiveStarSet.remove(_tmdbStr); _dislikedSet.remove(_tmdbStr);
        if (_catalogId != null) { _favoritesSet.remove(_catalogId); _fiveStarSet.remove(_catalogId); _dislikedSet.remove(_catalogId); }
      } else {
        _watchedSet.add(_tmdbStr);
      }
    });

    final title = widget.movieData['title'];

    if (isCurrentlyAdded && (inFav || inFive || inDisliked)) {
      _executeToggle(
        triggerStreak: false,
        onServiceCall: () async {
          await UserProfileService.instance.fastToggleWatched(uid: user.uid, movieData: widget.movieData, tmdbId: widget.tmdbId, catalogDocId: widget.catalogDocId, isCurrentlyAdded: true);
          await Future.delayed(const Duration(milliseconds: 50));
          if (inFav) await UserProfileService.instance.fastToggleStandardList(uid: user.uid, movieData: widget.movieData, tmdbId: widget.tmdbId, catalogDocId: widget.catalogDocId, target: ShelfTarget.favorites, isCurrentlyAdded: true, posterUrl: widget.posterUrl);
          if (inFive) await UserProfileService.instance.fastToggleStandardList(uid: user.uid, movieData: widget.movieData, tmdbId: widget.tmdbId, catalogDocId: widget.catalogDocId, target: ShelfTarget.fiveStar, isCurrentlyAdded: true, posterUrl: widget.posterUrl);
          if (inDisliked) await UserProfileService.instance.fastToggleStandardList(uid: user.uid, movieData: widget.movieData, tmdbId: widget.tmdbId, catalogDocId: widget.catalogDocId, target: ShelfTarget.disliked, isCurrentlyAdded: true, posterUrl: widget.posterUrl);
        },
      );
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("'$title' bağlantılı tüm listelerden çıkarıldı."), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating));
      return;
    }

    _executeToggle(
      triggerStreak: !isCurrentlyAdded,
      onServiceCall: () async => await UserProfileService.instance.fastToggleWatched(uid: user.uid, movieData: widget.movieData, tmdbId: widget.tmdbId, catalogDocId: widget.catalogDocId, isCurrentlyAdded: isCurrentlyAdded),
    );
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isCurrentlyAdded ? "'$title', çıkarıldı." : "'$title', izledim olarak işaretlendi."), backgroundColor: isCurrentlyAdded ? Colors.redAccent : Colors.teal, behavior: SnackBarBehavior.floating));
  }

  Future<void> _toggleStandardList(ShelfTarget target, bool isCurrentlyAdded) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Arayüzü anında güncelle (İnterneti bekleme)
    setState(() {
      Set<String> targetSet = switch (target) {
        ShelfTarget.fiveStar => _fiveStarSet,
        ShelfTarget.disliked => _dislikedSet,
        ShelfTarget.favorites => _favoritesSet,
        ShelfTarget.watchlist => _watchlistSet,
      };
      
      if (isCurrentlyAdded) {
        targetSet.remove(_tmdbStr);
        if (_catalogId != null) targetSet.remove(_catalogId);
      } else {
        targetSet.add(_tmdbStr);
        if (target != ShelfTarget.watchlist) _watchedSet.add(_tmdbStr);
      }
    });

    final title = widget.movieData['title'];
    final bool shouldTriggerStreak = (!isCurrentlyAdded && target != ShelfTarget.watchlist);

    _executeToggle(
      triggerStreak: shouldTriggerStreak,
      onServiceCall: () async {
        if (!isCurrentlyAdded && target != ShelfTarget.watchlist) {
          await UserProfileService.instance.fastToggleWatched(uid: user.uid, movieData: widget.movieData, tmdbId: widget.tmdbId, catalogDocId: widget.catalogDocId, isCurrentlyAdded: false);
          await Future.delayed(const Duration(milliseconds: 50));
        }
        await UserProfileService.instance.fastToggleStandardList(uid: user.uid, movieData: widget.movieData, tmdbId: widget.tmdbId, catalogDocId: widget.catalogDocId, target: target, isCurrentlyAdded: isCurrentlyAdded, posterUrl: widget.posterUrl);
      },
    );

    final targetName = switch (target) {
      ShelfTarget.fiveStar => 'Sevdiklerim',
      ShelfTarget.disliked => 'Sevmedim',
      ShelfTarget.favorites => 'Favoriler',
      ShelfTarget.watchlist => 'İzlenecekler',
    };

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isCurrentlyAdded ? "'$title', listeden çıkartıldı." : "'$title', eklendi."), backgroundColor: isCurrentlyAdded ? Colors.redAccent : Colors.green.shade700, behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(height: 250, child: Center(child: CircularProgressIndicator(color: Colors.teal)));
    }

    bool isWatchlist = _isIn(_watchlistSet);
    bool isFavorite = _isIn(_favoritesSet);
    bool isFiveStar = _isIn(_fiveStarSet);
    bool isDisliked = _isIn(_dislikedSet);
    bool isWatched = _isIn(_watchedSet) || isFavorite || isFiveStar || isDisliked;

    return Container(
      padding: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              const Text('Listelere Ekle', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              const Text('Profil Listeleri', style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              GridView.count(
                shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10,
                children: [
                  _buildQuickAction(Icons.visibility_rounded, 'İzledim', Colors.teal, isWatched, () => _toggleWatched(isWatched, isFavorite, isFiveStar, isDisliked)),
                  _buildQuickAction(Icons.bookmark_add_rounded, 'İzlenecekler', Colors.blue, isWatchlist, () => _toggleStandardList(ShelfTarget.watchlist, isWatchlist)),
                  _buildQuickAction(Icons.favorite_rounded, 'Favoriler', Colors.pink, isFavorite, () => _toggleStandardList(ShelfTarget.favorites, isFavorite)),
                  _buildQuickAction(Icons.star_rounded, 'Sevdiklerim', Colors.amber, isFiveStar, () => _toggleStandardList(ShelfTarget.fiveStar, isFiveStar)),
                  _buildQuickAction(Icons.thumb_down_rounded, 'Sevmedim', Colors.redAccent, isDisliked, () => _toggleStandardList(ShelfTarget.disliked, isDisliked)),
                ],
              ),
              const Divider(height: 40),
              const Text('Özel Listelerim', style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
              if (_customLists.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('Henüz özel bir listen yok.', style: TextStyle(color: Colors.grey)))
              else
                ListView.builder(
                  shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                  itemCount: _customLists.length,
                  itemBuilder: (context, index) {
                    final list = _customLists[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(color: Colors.grey.shade800, borderRadius: BorderRadius.circular(8), image: list.coverImageUrl != null ? DecorationImage(image: NetworkImage(list.coverImageUrl!), fit: BoxFit.cover) : null),
                        child: list.coverImageUrl == null ? const Icon(Icons.list, color: Colors.white54) : null,
                      ),
                      title: Text(list.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${list.movieCount} film', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      trailing: const Icon(Icons.add_circle_outline),
                      onTap: () => _addToCustomList(context, list.id, list.title),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String label, Color color, bool isAdded, VoidCallback onTap) {
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: isAdded ? color : color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(isAdded ? Icons.check_rounded : icon, color: isAdded ? Colors.white : color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: isAdded ? FontWeight.bold : FontWeight.w600, color: isAdded ? color : Colors.grey.shade600), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Future<void> _addToCustomList(BuildContext context, String listId, String listTitle) async {
    final query = await FirebaseFirestore.instance.collection('custom_lists').doc(listId).collection('items').where('id', isEqualTo: widget.tmdbId).get();
    if (!mounted) return;
    if (query.docs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Bu film zaten "$listTitle" listesinde ekli!'), backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating));
      Navigator.pop(context);
      return;
    }
    Navigator.pop(context);
    final movieMap = {'id': widget.tmdbId, 'title': widget.movieData['title'], 'poster': widget.movieData['poster_path'] != null ? 'https://image.tmdb.org/t/p/w500${widget.movieData['poster_path']}' : null};
    CustomListService.instance.addMovieToList(listId, movieMap);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${widget.movieData['title']}, "$listTitle" listesine eklendi.'), backgroundColor: Colors.green.shade700, behavior: SnackBarBehavior.floating));
  }
}