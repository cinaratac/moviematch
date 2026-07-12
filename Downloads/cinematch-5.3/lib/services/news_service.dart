import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttergirdi/models/news_article.dart';

class NewsService {
  NewsService._();

  static final NewsService instance = NewsService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<NewsArticle>> watchPublishedNews({int limit = 60}) {
    return _db
        .collection('public_news')
        .orderBy('publishedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(NewsArticle.fromFirestore)
              .where((article) => article.title.isNotEmpty)
              .toList(),
        );
  }

  Stream<NewsArticle?> watchArticle(String id) {
    return _db.collection('public_news').doc(id).snapshots().map((doc) {
      if (!doc.exists) return null;
      return NewsArticle.fromFirestore(doc);
    });
  }
}
