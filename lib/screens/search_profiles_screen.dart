import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  static const _kRecentKey = 'recent_searches_v1';
  static const _kRecentLimit = 10;
  List<String> _recents = [];

  String _query = '';
  bool _isLoading = false;
  List<Map<String, dynamic>> _results = [];

  Future<void> _loadRecents() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final list = sp.getStringList(_kRecentKey) ?? const [];
      if (!mounted) return;
      setState(() {
        _recents = list;
      });
    } catch (_) {
      // ignore storage errors silently
    }
  }

  Future<void> _pushRecent(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final lc = q.toLowerCase();
      final next = List<String>.from(_recents);
      next.removeWhere((e) => e.toLowerCase() == lc);
      next.insert(0, q);
      if (next.length > _kRecentLimit) {
        next.removeRange(_kRecentLimit, next.length);
      }
      await sp.setStringList(_kRecentKey, next);
      if (!mounted) return;
      setState(() {
        _recents = next;
      });
    } catch (_) {
      // ignore storage errors silently
    }
  }

  Future<void> _clearRecents() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_kRecentKey);
      if (!mounted) return;
      setState(() {
        _recents = [];
      });
    } catch (_) {
      // ignore
    }
  }

  void _pushUnique(
    List<Map<String, dynamic>> buf,
    QueryDocumentSnapshot<Map<String, dynamic>> d,
  ) {
    if (!buf.any((e) => e['uid'] == d.id)) {
      buf.add({'uid': d.id, ...d.data()});
    }
  }

  @override
  void initState() {
    super.initState();
    _loadRecents();
  }

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
    final q = _query.trim();
    final qLc = q.toLowerCase();
    if (q.isNotEmpty) {
      await _pushRecent(q);
    }
    if (q.isEmpty) {
      try {
        // Try: createdAt desc
        final snap = await _fs
            .collection('users')
            .orderBy('createdAt', descending: true)
            .limit(20)
            .get();
        final recents = [
          for (final d in snap.docs) {'uid': d.id, ...d.data()},
        ];
        if (mounted) {
          setState(() {
            _results = recents;
          });
        }
      } catch (_) {
        try {
          // Fallback: updatedAt desc
          final snap2 = await _fs
              .collection('users')
              .orderBy('updatedAt', descending: true)
              .limit(20)
              .get();
          final recents2 = [
            for (final d in snap2.docs) {'uid': d.id, ...d.data()},
          ];
          if (mounted) {
            setState(() {
              _results = recents2;
            });
          }
        } catch (_) {
          // Last resort: no order (avoids index requirements)
          final snap3 = await _fs.collection('users').limit(20).get();
          final recents3 = [
            for (final d in snap3.docs) {'uid': d.id, ...d.data()},
          ];
          if (mounted) {
            setState(() {
              _results = recents3;
            });
          }
        }
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final List<Map<String, dynamic>> buf = [];

      // 1) letterboxdUsername exact (lc)
      try {
        final rLb = await _fs
            .collection('users')
            .where('letterboxdUsername_lc', isEqualTo: qLc)
            .limit(10)
            .get();
        for (final d in rLb.docs) {
          _pushUnique(buf, d);
        }
      } catch (_) {
        // Fallback: small scan and filter client-side
        final snap = await _fs.collection('users').limit(100).get();
        for (final d in snap.docs) {
          final lb = (d.data()['letterboxdUsername'] ?? '')
              .toString()
              .toLowerCase();
          if (lb == qLc) _pushUnique(buf, d);
        }
      }

      // 2) email exact (if present on user doc)
      try {
        final rEmail = await _fs
            .collection('users')
            .where('email', isEqualTo: q)
            .limit(10)
            .get();
        for (final d in rEmail.docs) {
          _pushUnique(buf, d);
        }
      } catch (_) {
        /* ignore */
      }

      // 3) username exact (lc)
      try {
        final rUx = await _fs
            .collection('users')
            .where('username_lc', isEqualTo: qLc)
            .limit(10)
            .get();
        for (final d in rUx.docs) {
          _pushUnique(buf, d);
        }
      } catch (_) {
        final snap = await _fs.collection('users').limit(100).get();
        for (final d in snap.docs) {
          final u = (d.data()['username'] ?? '').toString().toLowerCase();
          if (u == qLc) _pushUnique(buf, d);
        }
      }

      // 3b) username exact (case-sensitive) — in case username_lc is missing
      try {
        final rUxCs = await _fs
            .collection('users')
            .where('username', isEqualTo: q)
            .limit(10)
            .get();
        for (final d in rUxCs.docs) {
          _pushUnique(buf, d);
        }
      } catch (_) {
        /* ignore */
      }

      // 4) username prefix (lc) with fallback
      try {
        final rUp = await _fs
            .collection('users')
            .orderBy('username_lc')
            .startAt([qLc])
            .endAt(['$qLc\uf8ff'])
            .limit(10)
            .get();
        for (final d in rUp.docs) {
          _pushUnique(buf, d);
        }
      } catch (_) {
        final snap = await _fs.collection('users').limit(400).get();
        for (final d in snap.docs) {
          final u = (d.data()['username'] ?? '').toString().toLowerCase();
          if (u.startsWith(qLc)) _pushUnique(buf, d);
        }
      }

      // 4b) displayName exact (case-sensitive) — if displayName_lc not populated
      try {
        final rDnEq = await _fs
            .collection('users')
            .where('displayName', isEqualTo: q)
            .limit(10)
            .get();
        for (final d in rDnEq.docs) {
          _pushUnique(buf, d);
        }
      } catch (_) {
        /* ignore */
      }

      // 5) displayName prefix (lc) with fallback
      try {
        final rDp = await _fs
            .collection('users')
            .orderBy('displayName_lc')
            .startAt([qLc])
            .endAt(['$qLc\uf8ff'])
            .limit(10)
            .get();
        for (final d in rDp.docs) {
          _pushUnique(buf, d);
        }
      } catch (_) {
        final snap = await _fs.collection('users').limit(400).get();
        for (final d in snap.docs) {
          final dn = (d.data()['displayName'] ?? '').toString().toLowerCase();
          if (dn.startsWith(qLc)) _pushUnique(buf, d);
        }
      }

      if (mounted) {
        setState(() {
          _results = buf;
        });
      }
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
          if (_recents.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.history, size: 18),
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _recents.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (context, i) {
                          final term = _recents[i];
                          return ActionChip(
                            label: Text(
                              term,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onPressed: () {
                              _controller.text = term;
                              _onChanged(term);
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Temizle',
                    icon: const Icon(Icons.close),
                    onPressed: _clearRecents,
                  ),
                ],
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
                      final Map<String, dynamic> it = _results[i];
                      final username = (it['username'] ?? '') as String;
                      final displayName = (it['displayName'] ?? '') as String;
                      final lb = (it['letterboxdUsername'] ?? '') as String;
                      final photoURL = (it['photoURL'] ?? '') as String;

                      String title = username.isNotEmpty
                          ? username
                          : (displayName.isNotEmpty
                                ? displayName
                                : (lb.isNotEmpty ? '@$lb' : '—'));
                      final fallbackLetter =
                          (username.isNotEmpty
                                  ? username[0]
                                  : (displayName.isNotEmpty
                                        ? displayName[0]
                                        : (lb.isNotEmpty ? lb[0] : '?')))
                              .toUpperCase();

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: photoURL.isNotEmpty
                              ? NetworkImage(photoURL)
                              : null,
                          child: photoURL.isEmpty ? Text(fallbackLetter) : null,
                        ),
                        title: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          lb.isNotEmpty ? '@$lb' : 'Letterboxd bağlı değil',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
