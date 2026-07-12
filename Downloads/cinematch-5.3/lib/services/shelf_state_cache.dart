import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttergirdi/models/custom_list.dart';

/// Uygulama genelinde tek in-memory shelf cache.
/// movie_action_sheet, movie_detail_screen ve diğer ekranlar buradan okur.
class ShelfStateCache {
  static final ShelfStateCache instance = ShelfStateCache._();
  ShelfStateCache._();

  // uid → field → Set<normalizedKey>
  final Map<String, Map<String, Set<String>>> _data = {};

  // uid → List<CustomList>
  final Map<String, List<CustomList>> _lists = {};

  // -------------------------------------------------------------------------
  bool hasData(String uid) => _data.containsKey(uid);

  Set<String> get(String uid, String field) =>
      _data[uid]?[field] ?? const {};

  void updateAll(String uid, Map<String, dynamic> data) {
    _data[uid] = {
      'watchedKeys':   _toSet(data['watchedKeys']),
      'watchlistKeys': _toSet(data['watchlistKeys']),
      'favoritesKeys': _toSet(data['favoritesKeys']),
      'fiveStarKeys':  _toSet(data['fiveStarKeys']),
      'dislikedKeys':  _toSet(data['dislikedKeys']),
    };
  }

  List<CustomList> getLists(String uid) => _lists[uid] ?? [];
  void setLists(String uid, List<CustomList> lists) => _lists[uid] = lists;

  // Optimistic update — UI anında tepki verir, Firestore bitmesini beklemez
  void optimisticAdd(String uid, String field, String key) {
    _data.putIfAbsent(uid, () => {}).putIfAbsent(field, () => {}).add(key);
  }

  void optimisticRemove(String uid, String field, String key) {
    _data[uid]?[field]?.remove(key);
  }

  // -------------------------------------------------------------------------
  static Set<String> _toSet(dynamic raw) {
    if (raw == null) return {};
    return List<dynamic>.from(raw as List)
        .map((e) => e.toString().trim().toLowerCase())
        .toSet();
  }

  // Firestore doc'tan direkt güncelle (listener callback'lerinde kullan)
  void applyDoc(String uid, DocumentSnapshot doc) {
    if (!doc.exists) return;
    updateAll(uid, (doc.data() as Map<String, dynamic>?) ?? {});
  }
}