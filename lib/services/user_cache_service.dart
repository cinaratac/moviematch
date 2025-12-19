import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class CachedUser {
  final String uid;
  final String displayName;
  final String handle;
  final String photoURL;

  CachedUser({
    required this.uid,
    required this.displayName,
    required this.handle,
    required this.photoURL,
  });
}

class UserCacheService {
  UserCacheService._();
  static final UserCacheService instance = UserCacheService._();

  // Hafızadaki önbellek (RAM)
  final Map<String, CachedUser> _cache = {};
  
  // Aynı anda aynı kullanıcı için birden fazla istek atılmasını önlemek için
  final Map<String, Future<CachedUser?>> _pendingRequests = {};

  CachedUser? getFromCache(String uid) => _cache[uid];

  /// Tekil kullanıcı getir (Önce cache, yoksa sunucu)
  Future<CachedUser?> getUser(String uid) async {
    if (_cache.containsKey(uid)) return _cache[uid];

    if (_pendingRequests.containsKey(uid)) {
      return _pendingRequests[uid];
    }

    final future = _fetchUser(uid);
    _pendingRequests[uid] = future;
    
    final result = await future;
    _pendingRequests.remove(uid);
    return result;
  }

  /// Toplu kullanıcı getir (Feed için optimize edildi)
  Future<void> fetchUsers(List<String> uids) async {
    final missingUids = uids.where((id) => !_cache.containsKey(id)).toSet().toList();
    if (missingUids.isEmpty) return;

    // Firestore 'whereIn' limiti 10'dur. Parçalara bölüyoruz.
    for (var i = 0; i < missingUids.length; i += 10) {
      final end = (i + 10 < missingUids.length) ? i + 10 : missingUids.length;
      final chunk = missingUids.sublist(i, end);

      try {
        final qs = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get(const GetOptions(source: Source.serverAndCache));

        for (var doc in qs.docs) {
          final data = doc.data();
          final user = _mapToCachedUser(doc.id, data);
          _cache[doc.id] = user;
        }
      } catch (e) {
        debugPrint('UserCache Error: $e');
      }
    }
  }

  Future<CachedUser?> _fetchUser(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!doc.exists) return null;
      final user = _mapToCachedUser(uid, doc.data() ?? {});
      _cache[uid] = user;
      return user;
    } catch (e) {
      return null;
    }
  }

  CachedUser _mapToCachedUser(String uid, Map<String, dynamic> data) {
    final name = (data['displayName'] ?? '').toString();
    final username = (data['username'] ?? '').toString();
    final lb = (data['letterboxdUsername'] ?? '').toString();
    
    String handle = '';
    if (username.isNotEmpty) handle = '@$username';
    else if (lb.isNotEmpty) handle = '@$lb';

    return CachedUser(
      uid: uid,
      displayName: name.isNotEmpty ? name : 'Kullanıcı',
      handle: handle,
      photoURL: (data['photoURL'] ?? '').toString(),
    );
  }
}