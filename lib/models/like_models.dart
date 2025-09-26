import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore: likes/{pairId}
class LikeDoc {
  final String id; // pairId
  final String a; // sorted lower UID
  final String b; // sorted higher UID
  final bool aLiked;
  final bool bLiked;
  final bool aPass;
  final bool bPass;
  final DateTime? updatedAt;

  const LikeDoc({
    required this.id,
    required this.a,
    required this.b,
    required this.aLiked,
    required this.bLiked,
    required this.aPass,
    required this.bPass,
    required this.updatedAt,
  });

  factory LikeDoc.fromSnap(DocumentSnapshot<Map<String, dynamic>> snap) {
    final m = snap.data() ?? const <String, dynamic>{};
    return LikeDoc(
      id: snap.id,
      a: (m['a'] ?? '') as String,
      b: (m['b'] ?? '') as String,
      aLiked: (m['aLiked'] ?? false) as bool,
      bLiked: (m['bLiked'] ?? false) as bool,
      aPass: (m['aPass'] ?? false) as bool,
      bPass: (m['bPass'] ?? false) as bool,
      updatedAt: (m['updatedAt'] is Timestamp)
          ? (m['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  bool get bothLiked => aLiked && bLiked;
}

/// Firestore: matches/{pairId}
class MatchDoc {
  final String id; // pairId
  final List<String> uids; // [a, b]
  final int commonFavoritesCount;
  final int commonFiveStarsCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const MatchDoc({
    required this.id,
    required this.uids,
    required this.commonFavoritesCount,
    required this.commonFiveStarsCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MatchDoc.fromSnap(DocumentSnapshot<Map<String, dynamic>> snap) {
    final m = snap.data() ?? const <String, dynamic>{};
    return MatchDoc(
      id: snap.id,
      uids: List<String>.from(m['uids'] ?? const <String>[]),
      commonFavoritesCount: (m['commonFavoritesCount'] ?? 0) as int,
      commonFiveStarsCount: (m['commonFiveStarsCount'] ?? 0) as int,
      createdAt: (m['createdAt'] is Timestamp)
          ? (m['createdAt'] as Timestamp).toDate()
          : null,
      updatedAt: (m['updatedAt'] is Timestamp)
          ? (m['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }
}

/// (Opsiyonel) chats/{matchId}/messages/{mid}
class ChatMessageDoc {
  final String id;
  final String authorId;
  final String text;
  final DateTime? createdAt;

  const ChatMessageDoc({
    required this.id,
    required this.authorId,
    required this.text,
    required this.createdAt,
  });

  factory ChatMessageDoc.fromSnap(DocumentSnapshot<Map<String, dynamic>> snap) {
    final m = snap.data() ?? const <String, dynamic>{};
    return ChatMessageDoc(
      id: snap.id,
      authorId: (m['authorId'] ?? '') as String,
      text: (m['text'] ?? '') as String,
      createdAt: (m['createdAt'] is Timestamp)
          ? (m['createdAt'] as Timestamp).toDate()
          : null,
    );
  }
}
