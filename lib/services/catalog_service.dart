import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer';

class CatalogService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String canonicalKeyFromTmdb(int tmdbId) => 'tmdb:$tmdbId';

  // Private helpers for slugification and normalized title
  static String _slugify(String input) {
    var slug = input
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'[\s_]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug;
  }

  static String _normTitle(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
  }

  Future<void> upsertFromTmdb(Map<String, dynamic> movie) async {
    try {
      // 1) Extract fields
      final int tmdbId = movie['id'];
      final String? imdbId = movie['imdb_id'];
      final String? title = movie['title'];
      final String? posterPath = movie['poster_path'];
      final String? releaseDate = movie['release_date'];
      final int? year = releaseDate != null && releaseDate.length >= 4
          ? int.tryParse(releaseDate.substring(0, 4))
          : null;
      final String? posterUrl = posterPath != null
          ? 'https://image.tmdb.org/t/p/w500$posterPath'
          : null;
      final String? titleLc = title != null ? _normTitle(title) : null;
      String? primaryId;
      // 2) Try to find existing doc
      DocumentSnapshot? foundDoc;
      // a) by tmdbId
      var query = await _db
          .collection('catalog_films')
          .where('tmdbId', isEqualTo: tmdbId)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        foundDoc = query.docs.first;
      }
      // b) by imdbId
      if (foundDoc == null && imdbId != null) {
        var q2 = await _db
            .collection('catalog_films')
            .where('imdbId', isEqualTo: imdbId)
            .limit(1)
            .get();
        if (q2.docs.isNotEmpty) {
          foundDoc = q2.docs.first;
        }
      }
      // c) by (titleLc, year)
      if (foundDoc == null && titleLc != null && year != null) {
        var q3 = await _db
            .collection('catalog_films')
            .where('titleLc', isEqualTo: titleLc)
            .where('year', isEqualTo: year)
            .limit(1)
            .get();
        if (q3.docs.isNotEmpty) {
          foundDoc = q3.docs.first;
        }
      }
      if (foundDoc != null) {
        primaryId = foundDoc.id;
      } else {
        // 3) If not found, generate film:<slug>
        if (title != null) {
          String slug = _slugify(title);
          String candidateId = 'film:$slug';
          var docSnap = await _db
              .collection('catalog_films')
              .doc(candidateId)
              .get();
          if (docSnap.exists) {
            // If a different film is implied (i.e., tmdbId, imdbId, or year does not match), fallback to year
            final data = docSnap.data();
            bool conflict = false;
            if (data != null) {
              if ((data['tmdbId'] != null && data['tmdbId'] != tmdbId) ||
                  (imdbId != null &&
                      data['imdbId'] != null &&
                      data['imdbId'] != imdbId) ||
                  (year != null &&
                      data['year'] != null &&
                      data['year'] != year)) {
                conflict = true;
              }
            }
            if (conflict && year != null && year > 0) {
              candidateId = 'film:$slug-$year';
            }
          }
          primaryId = candidateId;
        } else {
          // fallback: use tmdb:<id>
          primaryId = canonicalKeyFromTmdb(tmdbId);
        }
      }
      // 4) Upsert with required fields
      final Map<String, dynamic> data = {
        if (title != null) 'title': title,
        if (year != null) 'year': year,
        if (posterUrl != null) 'posterUrl': posterUrl,
        'tmdbId': tmdbId,
        if (imdbId != null) 'imdbId': imdbId,
        if (titleLc != null) 'titleLc': titleLc,
        'canonicalKey': primaryId,
        'source': 'tmdb',
        'aliases': FieldValue.arrayUnion([
          'tmdb:$tmdbId',
          if (imdbId != null) 'imdb:$imdbId',
        ]),
      };
      await _db
          .collection('catalog_films')
          .doc(primaryId)
          .set(data, SetOptions(merge: true));
    } catch (e, st) {
      log('Error in upsertFromTmdb: $e', stackTrace: st);
    }
  }

  Future<void> upsertFromLetterboxd(
    Map<String, dynamic> lbFilm, {
    int? tmdbId,
  }) async {
    try {
      // 1) Build primaryId as film:<lbSlug> if provided, else slugify title
      String? primaryId;
      String? lbSlug = lbFilm['lbSlug'];
      String? title = lbFilm['title'];
      int? year = lbFilm['year'];
      String? imdbId = lbFilm['imdbId'];
      String? posterUrl = lbFilm['posterUrl'];
      String? titleLc = title != null ? _normTitle(title) : null;
      if (lbSlug != null && lbSlug.toString().isNotEmpty) {
        primaryId = 'film:$lbSlug';
      } else if (title != null) {
        primaryId = 'film:${_slugify(title)}';
      } else {
        // fallback: random doc
        primaryId = null;
      }
      // 2) Upsert into that doc
      if (primaryId == null) {
        log('Cannot upsert Letterboxd film without slug or title');
        return;
      }
      final aliases = <String>[
        if (tmdbId != null) 'tmdb:$tmdbId',
        if (imdbId != null) 'imdb:$imdbId',
      ];
      final data = <String, dynamic>{
        if (tmdbId != null) 'tmdbId': tmdbId,
        if (imdbId != null) 'imdbId': imdbId,
        if (title != null) 'title': title,
        if (year != null) 'year': year,
        if (posterUrl != null) 'posterUrl': posterUrl,
        if (titleLc != null) 'titleLc': titleLc,
        'canonicalKey': primaryId,
        'source': 'letterboxd',
        'aliases': FieldValue.arrayUnion(aliases),
      };
      await _db
          .collection('catalog_films')
          .doc(primaryId)
          .set(data, SetOptions(merge: true));
    } catch (e, st) {
      log('Error in upsertFromLetterboxd: $e', stackTrace: st);
    }
  }

  Future<Map<String, dynamic>?> getFilmByCanonical(String canonicalKey) async {
    try {
      final doc = await _db.collection('catalog_films').doc(canonicalKey).get();
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e, st) {
      log('Error in getFilmByCanonical: $e', stackTrace: st);
      return null;
    }
  }

 

  Future<List<Map<String, dynamic>>> getFilmsByKeys(List<String> keys) async {
    final List<Map<String, dynamic>> results = [];
    try {
      if (keys.isEmpty) return results;
      
      // Firestore 'whereIn' limiti 10'dur.
      final batchSize = 10;
      
      // Tüm sorguları (Future) bu listede toplayacağız
      final List<Future<QuerySnapshot<Map<String, dynamic>>>> futures = [];

      for (var i = 0; i < keys.length; i += batchSize) {
        final chunk = keys.sublist(
          i,
          i + batchSize > keys.length ? keys.length : i + batchSize,
        );
        
        // Sorguyu başlatıyoruz ama 'await' ile beklemiyoruz, listeye atıyoruz.
        futures.add(
          _db.collection('catalog_films')
             .where(FieldPath.documentId, whereIn: chunk)
             .get()
        );
      }
      
      // BURASI ÖNEMLİ: Tüm sorguların aynı anda bitmesini bekliyoruz (Paralel İstek)
      final snapshots = await Future.wait(futures);
      
      for (final snap in snapshots) {
        for (final doc in snap.docs) {
          final data = doc.data();
          // ID eşleştirmesi için döküman ID'sini veriye ekliyoruz
          data['docId'] = doc.id; 
          results.add(data);
        }
      }
    } catch (e, st) {
      log('Error in getFilmsByKeys: $e', stackTrace: st);
    }
    return results;
  }
}
