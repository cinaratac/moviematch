import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/feed_service.dart';
import '../services/user_cache_service.dart';
import '../services/blocking_service.dart';

class FeedController extends ChangeNotifier {
  // SINGLETON MİMARİSİ: Tüm uygulama boyunca tek bir instance olacak
  static final FeedController instance = FeedController._internal();
  FeedController._internal();

  bool isInitialized = false;

  // --- POPÜLER AKIŞ DEĞİŞKENLERİ ---
  bool isLoading = true;
  bool isLoadingMore = false;
  bool hasMore = true;
  List<DocumentSnapshot<Map<String, dynamic>>> posts = [];

  // --- TAKİP EDİLENLER AKIŞI DEĞİŞKENLERİ ---
  bool isFollowingLoading = true;
  bool isFollowingInitialized = false;
  List<DocumentSnapshot<Map<String, dynamic>>> followingPosts = [];

  // Etkileşim verileri (İki akışta da ortak kullanılır)
  Set<String> myLikedPostIds = {};
  Set<String> myFollowingUserIds = {};

  Set<String> _blockedUserIds = {};
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  final int _pageSize = 20;

  // ==========================================
  // 1. POPÜLER AKIŞ METOTLARI
  // ==========================================
  Future<void> init() async {
    // Daha önce yüklendiyse (veya yükleme ekranında yüklendiyse) tekrar çekme!
    if (isInitialized && posts.isNotEmpty) return;
    isLoading = true;
    notifyListeners();
    await _loadData(initial: true);
    isInitialized = true;
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
      QuerySnapshot<Map<String, dynamic>> postSnapshot;

      if (initial) {
        if (userId != null) {
          final results = await Future.wait([
            FeedService.instance.fetchInitial(limit: _pageSize),
            FeedService.instance.fetchUserLikedPostIds(userId),
            FeedService.instance.fetchUserFollowingIds(userId),
            BlockingService.instance.getBlockedAndBlockerIds(userId),
          ]);
          
          postSnapshot = results[0] as QuerySnapshot<Map<String, dynamic>>;
          myLikedPostIds = results[1] as Set<String>;
          myFollowingUserIds = results[2] as Set<String>;
          _blockedUserIds = results[3] as Set<String>;
        } else {
          postSnapshot = await FeedService.instance.fetchInitial(limit: _pageSize);
        }
      } else {
        postSnapshot = await FeedService.instance.fetchMore(lastDoc: _lastDoc!, limit: _pageSize);
      }

      var newDocs = postSnapshot.docs;
      if (_blockedUserIds.isNotEmpty) {
        newDocs = newDocs.where((doc) {
          final authorId = doc.data()['authorId'] as String?;
          return !_blockedUserIds.contains(authorId);
        }).toList();
      }

      final authorIds = newDocs.map((d) => d.data()['authorId'] as String?).where((id) => id != null).cast<String>().toList();
      await UserCacheService.instance.fetchUsers(authorIds);

      if (initial) {
        posts = newDocs;
      } else {
        posts.addAll(newDocs);
      }

      _lastDoc = newDocs.isNotEmpty ? newDocs.last : _lastDoc;
      hasMore = newDocs.length == _pageSize;
    } catch (e) {
      debugPrint("LoadData Error: $e");
    } finally {
      isLoading = false;
      isLoadingMore = false;
      notifyListeners();
    }
  }

  // ==========================================
  // 2. TAKİP EDİLENLER AKIŞI METOTLARI
  // ==========================================
  Future<void> initFollowing() async {
    if (isFollowingInitialized && followingPosts.isNotEmpty) return;
    isFollowingLoading = true;
    notifyListeners();
    await _loadFollowingData();
    isFollowingInitialized = true;
  }

  Future<void> refreshFollowing() async {
    await _loadFollowingData();
  }

  Future<void> _loadFollowingData() async {
    try {
      final me = FirebaseAuth.instance.currentUser?.uid;
      if (me == null) {
        followingPosts = [];
        return;
      }

      final interactionsFuture = Future.wait([
        FeedService.instance.fetchUserLikedPostIds(me),
        FeedService.instance.fetchUserFollowingIds(me),
      ]);

      final feedQs = await FirebaseFirestore.instance
          .collection('feeds').doc(me).collection('user_feed')
          .orderBy('createdAt', descending: true).limit(20).get();

      List<DocumentSnapshot<Map<String, dynamic>>> finalItems = [];

      if (feedQs.docs.isNotEmpty) {
        final postIds = feedQs.docs.map((d) => d.data()['postId'] as String).toList();
        
        if (postIds.isNotEmpty) {
           List<Future<QuerySnapshot<Map<String, dynamic>>>> postFutures = [];
           for (var i = 0; i < postIds.length; i += 10) {
              final chunk = postIds.sublist(i, (i + 10 > postIds.length) ? postIds.length : i + 10);
              postFutures.add(FirebaseFirestore.instance.collection('posts').where(FieldPath.documentId, whereIn: chunk).get());
           }
           
           final postResults = await Future.wait(postFutures);
           for (var qs in postResults) {
             finalItems.addAll(qs.docs);
           }
           
           finalItems.sort((a, b) {
              final ta = (a.data()?['createdAt'] as Timestamp?)?.toDate();
              final tb = (b.data()?['createdAt'] as Timestamp?)?.toDate();
              if (ta == null) return 1; if (tb == null) return -1;
              return tb.compareTo(ta); 
           });
        }
      } else {
        final followingQs = await FirebaseFirestore.instance.collection('users').doc(me).collection('following').limit(200).get();
        final uids = followingQs.docs.map((d) => d.id).toList();

        if (uids.isNotEmpty) {
          List<Future<QuerySnapshot<Map<String, dynamic>>>> futures = [];
          for (var i = 0; i < uids.length; i += 10) {
            final chunk = uids.sublist(i, (i + 10 > uids.length) ? uids.length : i + 10);
            futures.add(FirebaseFirestore.instance.collection('posts').where('authorId', whereIn: chunk).orderBy('createdAt', descending: true).limit(5).get());
          }
          final results = await Future.wait(futures);
          for (var qs in results) {
            finalItems.addAll(qs.docs);
          }
          finalItems.sort((a, b) {
            final ta = (a.data()?['createdAt'] as Timestamp?)?.toDate();
            final tb = (b.data()?['createdAt'] as Timestamp?)?.toDate();
            if (ta == null) return 1; if (tb == null) return -1;
            return tb.compareTo(ta); 
          });
          finalItems = finalItems.take(20).toList();
        }
      }

      final uids = <String>{};
      for(var d in finalItems) {
        final u = d.data();
        final id = u?['authorId'] as String?;
        if(id != null) uids.add(id);
      }
      if(uids.isNotEmpty) {
        await UserCacheService.instance.fetchUsers(uids.toList());
      }

      final interactionResults = await interactionsFuture;
      myLikedPostIds = interactionResults[0];
      myFollowingUserIds = interactionResults[1];

      followingPosts = finalItems;
    } catch (e) {
      debugPrint("LoadFollowingData Error: $e");
    } finally {
      isFollowingLoading = false;
      notifyListeners();
    }
  }

  // ==========================================
  // 3. ORTAK ETKİLEŞİM METOTLARI
  // ==========================================
  void toggleLike(String postId, bool isLiked) {
    if (isLiked) {
      myLikedPostIds.add(postId);
    } else {
      myLikedPostIds.remove(postId);
    }
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

  void removeFollowingPost(String postId) {
    followingPosts.removeWhere((doc) => doc.id == postId);
    notifyListeners();
  }
}