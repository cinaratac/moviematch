import 'package:flutter/material.dart';
import 'package:fluttergirdi/services/chat_service.dart';
import 'package:fluttergirdi/services/watchlist_service.dart';
import 'package:fluttergirdi/screens/profilescreen.dart'; // UserShelfCache için
import 'package:fluttergirdi/widgets/watchlist_wheel.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

// --- FİLM SEÇİCİ ---
class FilmPickerSheet extends StatelessWidget {
  const FilmPickerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          const SizedBox(height: 16),
          // withOpacity uyarısı withValues ile düzeltildi
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          const Text('Filmlerim', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(height: 16),
          Expanded(
            child: Builder(builder: (context) {
              final merged = <Map<String, String>>[...UserShelfCache.fiveStar, ...UserShelfCache.favorites, ...UserShelfCache.watchlist, ...UserShelfCache.disliked];
              final seen = <String>{};
              final items = <Map<String, String>>[];
              for (final m in merged) {
                final t = (m['title'] ?? '').trim();
                // 'id' verisi listeye dahil ediliyor
                if (t.isNotEmpty && seen.add(t.toLowerCase())) {
                  items.add({
                    'title': t, 
                    'poster': (m['poster'] ?? '').toString(),
                    'id': (m['id'] ?? m['tmdbId'] ?? '').toString(), 
                  });
                }
              }
              if (items.isEmpty) return const Center(child: Text('Listen boş. Profilinden senkronize et.', style: TextStyle(color: Colors.white54)));
              return ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8), itemCount: items.length, separatorBuilder: (_, i) => const Divider(indent: 16, endIndent: 16),
                itemBuilder: (_, i) => ListTile(
                  leading: ClipRRect(borderRadius: BorderRadius.circular(4), child: items[i]['poster']!.isNotEmpty ? Image.network(items[i]['poster']!, width: 40, height: 60, fit: BoxFit.cover, errorBuilder: (c,e,s) => Container(width: 40, color: Colors.grey)) : const Icon(Icons.movie)),
                  title: Text(items[i]['title']!),
                  onTap: () => Navigator.pop(context, items[i]),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// --- WATCHLIST ÇARKI ---
class WatchlistWheelSheet extends StatefulWidget {
  final String chatId;
  final String myUid;
  final String otherUid;
  const WatchlistWheelSheet({super.key, required this.chatId, required this.myUid, required this.otherUid});

  @override
  State<WatchlistWheelSheet> createState() => _WatchlistWheelSheetState();
}

class _WatchlistWheelSheetState extends State<WatchlistWheelSheet> {
  late Future<List<WatchlistMovie>> _loader;

  @override
  void initState() { super.initState(); _loader = WatchlistService.instance.loadSharedWatchlist(widget.myUid, widget.otherUid); }

  @override
  Widget build(BuildContext context) {
    return Container(
       decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
       height: MediaQuery.of(context).size.height * 0.9,
       child: FutureBuilder<List<WatchlistMovie>>(
         future: _loader,
         builder: (context, snap) {
           if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
           final items = snap.data ?? [];
           if (items.isEmpty) return const Center(child: Text('Ortak watchlist bulunamadı.'));
           return Column(children: [
             const SizedBox(height: 20),
             Text('Watchlist Çarkı', style: Theme.of(context).textTheme.titleLarge),
             Expanded(child: Center(child: WatchlistWheel(items: items, size: 340, onChosen: (m) async {
               final send = await showDialog<bool>(
                 context: context, 
                 builder: (ctx) => AlertDialog(
                   title: Text(m.title), 
                   actions: [
                     TextButton(onPressed:()=>Navigator.pop(ctx,false), child:const Text('Kapat')),
                     FilledButton(onPressed:()=>Navigator.pop(ctx,true), child:const Text('Gönder'))
                   ]
                 )
               );
               
               if (send == true && mounted) {
                 // --- TMDB ID BULMA MANTIĞI EKLENDİ ---
                 String finalId = m.id ?? '';
                 try {
                   int? foundTmdbId;
                   // 1. Önce Firestore'da filmin tmdbId'si kayıtlı mı diye bakalım
                   if (finalId.isNotEmpty) {
                     final doc = await FirebaseFirestore.instance.collection('catalog_films').doc(finalId).get();
                     if (doc.exists && doc.data() != null && doc.data()!['tmdbId'] != null) {
                       foundTmdbId = (doc.data()!['tmdbId'] as num).toInt();
                     }
                   }
                   // 2. Bulamadıysak anlık olarak TMDB'ye adıyla soralım (Kesin çözüm)
                   if (foundTmdbId == null && m.title.isNotEmpty) {
                     final res = await FirebaseFunctions.instance.httpsCallable('searchMovies').call({'query': m.title, 'page': 1});
                     final data = Map<String, dynamic>.from(res.data as Map);
                     final results = data['results'] as List?;
                     if (results != null && results.isNotEmpty) {
                       final firstMovie = Map<String, dynamic>.from(results.first as Map);
                       foundTmdbId = (firstMovie['id'] as num).toInt();
                     }
                   }
                   // Eğer sayısal ID'yi bulduysak finalId'yi güncelleyelim
                   if (foundTmdbId != null) finalId = foundTmdbId.toString();
                 } catch (_) {
                   // Arama sırasında hata olursa uygulamayı çökertme, eldeki neyse onu gönder
                 }
                 // --- SON ---

                 ChatService.instance.send(
                   widget.chatId, 
                   widget.myUid, 
                   '🎯 Çark seçimi: ${m.title}', 
                   otherUid: widget.otherUid, 
                   movie: {
                     'title': m.title, 
                     'poster': m.posterUrl ?? '',
                     'id': finalId, // Bulduğumuz gerçek sayısal ID'yi yolluyoruz
                   }
                 );
                 if (mounted) Navigator.pop(context);
               }
             }))),
           ]);
         }
       ),
    );
  }
}