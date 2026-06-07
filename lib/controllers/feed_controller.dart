import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/feed_service.dart';
import '../services/user_cache_service.dart';
import '../services/blocking_service.dart';

class FeedController extends ChangeNotifier {
  // Durum değişkenleri
  bool isLoading = true;
  bool isLoadingMore = false;
  bool hasMore = true;

  // DÜZELTME BURADA: Listeyi ve _lastDoc'u spesifik tipte tanımlıyoruz
  List<DocumentSnapshot<Map<String, dynamic>>> posts = [];

  // Etkileşim verileri
  Set<String> myLikedPostIds = {};
  Set<String> myFollowingUserIds = {};

  // DÜZELTME BURADA: <Map<String, dynamic>> ekledik
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;

  final int _pageSize = 20;

  // Başlatıcı
  Future<void> init() async {
    isLoading = true;
    notifyListeners();
    await _loadData(initial: true);
  }

  Future<void> refresh() async {
    await _loadData(initial: true);
  }

  Future<void> loadMore() async {
    if (isLoadingMore || !hasMore) return;
    isLoadingMore = true;
    notifyListeners();
    await _loadData(initial: false);
  }

  Future<void> _loadData({required bool initial}) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      // Yeni: Engellenenleri tutacağımız değişken
      Set<String> blockedUserIds = {};

      QuerySnapshot<Map<String, dynamic>> postSnapshot;
      if (initial) {
        if (userId != null) {
          final results = await Future.wait([
            FeedService.instance.fetchInitial(limit: _pageSize),
            FeedService.instance.fetchUserLikedPostIds(userId),
            FeedService.instance.fetchUserFollowingIds(userId),
            // YENİ SERVİS KULLANIMI: Engellenen ID'leri çek
            BlockingService.instance.getBlockedAndBlockerIds(userId),
          ]);
          
          postSnapshot = results[0] as QuerySnapshot<Map<String, dynamic>>;
          myLikedPostIds = results[1] as Set<String>;
          myFollowingUserIds = results[2] as Set<String>;
          blockedUserIds = results[3] as Set<String>; // Listeyi aldık
        } else {
          postSnapshot = await FeedService.instance.fetchInitial(limit: _pageSize);
        }
      } else {
        postSnapshot = await FeedService.instance.fetchMore(
          lastDoc: _lastDoc!,
          limit: _pageSize,
        );
        // Sayfalama (loadMore) durumunda da engellenenleri tekrar çekmek isteyebilirsin
        // veya sınıf değişkeni olarak tutup orada saklayabilirsin.
        if (userId != null) {
            blockedUserIds = await BlockingService.instance.getBlockedAndBlockerIds(userId);
        }
      }

      // YENİ: Engellenen kullanıcıların gönderilerini filtrele
      var newDocs = postSnapshot.docs;
      if (blockedUserIds.isNotEmpty) {
        newDocs = newDocs.where((doc) {
          final authorId = doc.data()['authorId'] as String?;
          return !blockedUserIds.contains(authorId);
        }).toList();
      }

      // 2. Kullanıcı Verilerini Cache'e Yükle
      final authorIds = newDocs
          .map((d) => d.data()['authorId'] as String?)
          .where((id) => id != null)
          .cast<String>()
          .toList();
      await UserCacheService.instance.fetchUsers(authorIds);

      // 3. Listeyi Güncelle
      if (initial) {
        posts = newDocs;
      } else {
        posts.addAll(newDocs);
      }

      _lastDoc = newDocs.isNotEmpty ? newDocs.last : _lastDoc;
      hasMore = newDocs.length == _pageSize;
    } catch (e) {
    } finally {
      isLoading = false;
      isLoadingMore = false;
      notifyListeners();
    }
  }

  // UI'dan gelen aksiyonlar
  void toggleLike(String postId, bool isLiked) {
    if (isLiked)
      myLikedPostIds.add(postId);
    else
      myLikedPostIds.remove(postId);

    FeedService.instance.toggleLike(postId: postId, like: isLiked);
  }

  Future<void> followUser(String targetUid) async {
    myFollowingUserIds.add(targetUid);
    notifyListeners();
    await FeedService.instance.followUser(targetUid);
  }

  void removePost(String postId) {
    posts.removeWhere((doc) => doc.id == postId);
    notifyListeners();
  }
}
