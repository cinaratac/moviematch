import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';

class SearchProfilesScreen extends StatefulWidget {
  const SearchProfilesScreen({super.key});

  @override
  State<SearchProfilesScreen> createState() => _SearchProfilesScreenState();
}

class _SearchProfilesScreenState extends State<SearchProfilesScreen> {
  final _controller = TextEditingController();
  final _fs = FirebaseFirestore.instance;
  Timer? _debounce;

  String _query = '';
  bool _isLoading = false;
  List<Map<String, dynamic>> _results = [];

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() {
        _query = v.trim();
      });
      _runSearch();
    });
  }

  Future<void> _runSearch() async {
    final q = _query;
    if (q.isEmpty) {
      setState(() {
        _results = [];
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final List<Map<String, dynamic>> buf = [];

      // 1) letterboxdUsername = tam eşleşme
      final r1 = await _fs
          .collection('users')
          .where('letterboxdUsername', isEqualTo: q)
          .limit(10)
          .get();
      for (final d in r1.docs) {
        buf.add({'uid': d.id, ...?d.data()});
      }

      // 2) email = tam eşleşme (eğer email'i users doc’una yazıyorsan)
      // (Yazmıyorsan bu kısmı silebilirsin ya da eklemeyi düşünebilirsin)
      final r2 = await _fs
          .collection('users')
          .where('email', isEqualTo: q)
          .limit(10)
          .get();
      for (final d in r2.docs) {
        if (!buf.any((e) => e['uid'] == d.id)) {
          buf.add({'uid': d.id, ...?d.data()});
        }
      }

      // 3) displayName prefix arama (Ali -> Ali*, alfabetik)
      // Not: Bu sorgu için Firestore bazen indeks isteyebilir; link verir.
      final r3 = await _fs
          .collection('users')
          .orderBy('displayName')
          .startAt([q])
          .endAt(['$q\uf8ff'])
          .limit(10)
          .get();
      for (final d in r3.docs) {
        if (!buf.any((e) => e['uid'] == d.id)) {
          buf.add({'uid': d.id, ...?d.data()});
        }
      }

      setState(() {
        _results = buf;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Arama hatası: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kullanıcı Ara')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Letterboxd kullanıcı adı / görünen ad / e-posta',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _runSearch(),
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _results.isEmpty
                ? const Center(child: Text('Sonuç yok'))
                : ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final it = _results[i];
                      final displayName = (it['displayName'] ?? '') as String;
                      final lb = (it['letterboxdUsername'] ?? '') as String;
                      final photoURL = (it['photoURL'] ?? '') as String;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: photoURL.isNotEmpty
                              ? NetworkImage(photoURL)
                              : null,
                          child: photoURL.isEmpty
                              ? Text(
                                  displayName.isNotEmpty
                                      ? displayName[0].toUpperCase()
                                      : '?',
                                )
                              : null,
                        ),
                        title: Text(
                          displayName.isNotEmpty ? displayName : '(İsimsiz)',
                        ),
                        subtitle: Text(
                          lb.isNotEmpty ? '@$lb' : 'Letterboxd bağlı değil',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  PublicProfileScreen(uid: it['uid'] as String),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
