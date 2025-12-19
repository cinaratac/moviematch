import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/feed_service.dart';
import '../services/user_cache_service.dart';

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
      
      // 1. Postları Çek
      QuerySnapshot<Map<String, dynamic>> postSnapshot;
      if (initial) {
        // Paralel olarak beğeni ve takiplerimi de çek
        if (userId != null) {
          final results = await Future.wait([
             FeedService.instance.fetchInitial(limit: _pageSize),
             FeedService.instance.fetchUserLikedPostIds(userId),
             FeedService.instance.fetchUserFollowingIds(userId),
          ]);
          postSnapshot = results[0] as QuerySnapshot<Map<String, dynamic>>;
          myLikedPostIds = results[1] as Set<String>;
          myFollowingUserIds = results[2] as Set<String>;
        } else {
          postSnapshot = await FeedService.instance.fetchInitial(limit: _pageSize);
        }
      } else {
        // HATA VEREN SATIR ARTIK DÜZELMİŞ OLACAK
        postSnapshot = await FeedService.instance.fetchMore(lastDoc: _lastDoc!, limit: _pageSize);
      }

      final newDocs = postSnapshot.docs;
      
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
      debugPrint("Feed Error: $e");
    } finally {
      isLoading = false;
      isLoadingMore = false;
      notifyListeners();
    }
  }

  // UI'dan gelen aksiyonlar
  void toggleLike(String postId, bool isLiked) {
    if (isLiked) myLikedPostIds.add(postId);
    else myLikedPostIds.remove(postId);
    
    FeedService.instance.toggleLike(postId: postId, like: isLiked);
  }

  Future<void> followUser(String targetUid) async {
    myFollowingUserIds.add(targetUid);
    notifyListeners();
    await FeedService.instance.followUser(targetUid);
    await FeedService.instance.notifyFollow(toUid: targetUid);
  }

  void removePost(String postId) {
    posts.removeWhere((doc) => doc.id == postId);
    notifyListeners();
  }
}