import 'package:flutter/material.dart';
import 'package:fluttergirdi/services/chat_service.dart';
import 'package:fluttergirdi/services/watchlist_service.dart';
import 'package:fluttergirdi/screens/profilescreen.dart'; // UserShelfCache için
import 'package:fluttergirdi/widgets/watchlist_wheel.dart';

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
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
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
                if (t.isNotEmpty && seen.add(t.toLowerCase())) items.add({'title': t, 'poster': (m['poster'] ?? '').toString()});
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
               final send = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text(m.title), actions: [TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Kapat')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Gönder'))]));
               if (send == true && mounted) {
                 ChatService.instance.send(widget.chatId, widget.myUid, '🎯 Çark seçimi: ${m.title}', otherUid: widget.otherUid, movie: {'title': m.title, 'poster': m.posterUrl ?? ''});
                 Navigator.pop(context);
               }
             }))),
           ]);
         }
       ),
    );
  }
}