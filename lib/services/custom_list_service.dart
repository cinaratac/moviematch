import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/custom_list.dart';

class CustomListService {
  CustomListService._();
  static final instance = CustomListService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // --- LİSTE OLUŞTUR ---
  Future<void> createList(String title, String description, {bool isPublic = true}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final ref = _db.collection('custom_lists').doc();
    await ref.set({
      'id': ref.id,
      'ownerId': user.uid,
      'ownerName': user.displayName ?? 'Kullanıcı',
      'title': title,
      'description': description,
      'isPublic': isPublic,
      'movieCount': 0,
      'likeCount': 0,
      'coverImageUrl': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // --- LİSTEYE FİLM EKLE ---
  Future<void> addMovieToList(String listId, Map<String, dynamic> movie) async {
    final listRef = _db.collection('custom_lists').doc(listId);
    // TMDB ID'yi döküman ID'si yapıyoruz ki aynı film iki kere eklenmesin
    final itemRef = listRef.collection('items').doc(movie['id'].toString());

    await _db.runTransaction((tx) async {
      final itemSnap = await tx.get(itemRef);
      if (!itemSnap.exists) {
        // Film yoksa ekle
        tx.set(itemRef, {
          'id': movie['id'],
          'title': movie['title'],
          'poster': movie['poster'] ?? movie['poster_path'],
          'addedAt': FieldValue.serverTimestamp(),
        });
        
        // Liste sayacını ve kapak fotoğrafını güncelle
        tx.update(listRef, {
          'movieCount': FieldValue.increment(1),
          'coverImageUrl': movie['poster'] ?? movie['poster_path'], // Son eklenen kapak olur
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  // --- LİSTEDEN FİLM SİL ---
  Future<void> removeMovieFromList(String listId, String movieId) async {
    final listRef = _db.collection('custom_lists').doc(listId);
    final itemRef = listRef.collection('items').doc(movieId);

    await _db.runTransaction((tx) async {
      final itemSnap = await tx.get(itemRef);
      if (itemSnap.exists) {
        tx.delete(itemRef);
        tx.update(listRef, {
          'movieCount': FieldValue.increment(-1),
        });
      }
    });
  }
  
  // --- LİSTEYİ SİL ---
  Future<void> deleteList(String listId) async {
    await _db.collection('custom_lists').doc(listId).delete();
  }

  // --- KULLANICININ LİSTELERİNİ GETİR ---
  Stream<List<CustomList>> getUserLists(String uid) {
    return _db.collection('custom_lists')
        .where('ownerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((qs) => qs.docs.map((d) => CustomList.fromFirestore(d)).toList());
  }
  
  // --- LİSTE İÇERİĞİNİ GETİR ---
  Stream<QuerySnapshot> getListItems(String listId) {
      return _db.collection('custom_lists')
          .doc(listId)
          .collection('items')
          .orderBy('addedAt', descending: true)
          .snapshots();
  }
  Future<List<CustomList>> fetchDiscoveryLists() async {
    try {
      // Not: Firestore'da "random" sorgusu pahalıdır. 
      // Bu yüzden son 50 listeyi çekip telefon tarafında karıştırmak daha performanslıdır.
      
      // Eğer listeler 'custom_lists' adında ana bir koleksiyonda tutuluyorsa:
      QuerySnapshot snapshot = await _db
          .collection('custom_lists') // Koleksiyon adın farklıysa burayı güncelle (örn: 'lists')
          .where('isPublic', isEqualTo: true)
          .orderBy('createdAt', descending: true) // En yeniler
          .limit(20) // Havuzu geniş tutuyoruz
          .get();

      List<CustomList> allLists = snapshot.docs
          .map((doc) => CustomList.fromFirestore(doc))
          .toList();

      // Listeyi karıştır (Shuffle)
      allLists.shuffle();

      // İlk 6 tanesini al (eğer 6'dan az ise hepsini al)
      return allLists.take(6).toList();
    } catch (e) {
      return [];
    }
  }
}