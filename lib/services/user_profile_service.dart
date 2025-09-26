import 'package:cloud_firestore/cloud_firestore.dart';

/// Stores a user's film taste signals that we compute from Letterboxd and in‑app actions.
/// Keep this model intentionally permissive so we can evolve it without schema migrations.
class TasteProfile {
  /// Canonical Letterboxd usernames we pulled data from (for provenance/debugging)
  final String? letterboxdUsername;

  /// Film IDs or slugs the user loved (e.g., 5★)
  final List<String> loved; // deduped

  /// Film IDs or slugs the user strongly disliked (e.g., 0.5★ or 1★)
  final List<String> disliked; // deduped

  /// Optional poster URL map for quick rendering: key = filmId or slug, value = posterUrl
  final Map<String, String> posters;

  /// Optional dense vector for similarity search (size may vary)
  final List<double>? vector;

  /// Last time we computed this profile (epoch millis)
  final int? computedAtMs;

  const TasteProfile({
    this.letterboxdUsername,
    this.loved = const [],
    this.disliked = const [],
    this.posters = const {},
    this.vector,
    this.computedAtMs,
  });

  /// Normalizes a film key (id or slug) for stable comparisons
  static String _norm(String v) => (v).trim().toLowerCase();

  /// Deduplicate while preserving insertion order
  static List<String> _dedupe(Iterable<String> items) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in items) {
      final k = _norm(raw);
      if (k.isEmpty) continue;
      if (seen.add(k)) out.add(k);
    }
    return out;
  }

  /// CopyWith helper
  TasteProfile copyWith({
    String? letterboxdUsername,
    List<String>? loved,
    List<String>? disliked,
    Map<String, String>? posters,
    List<double>? vector,
    int? computedAtMs,
  }) {
    return TasteProfile(
      letterboxdUsername: letterboxdUsername ?? this.letterboxdUsername,
      loved: _dedupe(loved ?? this.loved),
      disliked: _dedupe(disliked ?? this.disliked),
      posters: (posters ?? this.posters).map((k, v) => MapEntry(_norm(k), v)),
      vector: vector ?? this.vector,
      computedAtMs: computedAtMs ?? this.computedAtMs,
    );
  }

  /// Serialize to Firestore-friendly map
  Map<String, dynamic> toMap() {
    final lovedClean = _dedupe(loved);
    final dislikedClean = _dedupe(disliked);
    final allowed = {...lovedClean, ...dislikedClean};
    final postersClean = {
      for (final entry in posters.entries)
        if (allowed.contains(_norm(entry.key))) _norm(entry.key): entry.value,
    };

    return {
      if (letterboxdUsername != null) 'letterboxdUsername': letterboxdUsername,
      'loved': lovedClean,
      'disliked': dislikedClean,
      'posters': postersClean,
      if (vector != null) 'vector': vector,
      if (computedAtMs != null) 'computedAtMs': computedAtMs,
    };
  }

  /// Deserialize from Firestore map
  static TasteProfile fromMap(Map<String, dynamic> data) {
    final lovedRaw = data['loved'];
    final dislikedRaw = data['disliked'];
    final postersRaw = data['posters'];
    final vectorRaw = data['vector'];

    List<String> _stringList(dynamic v) {
      if (v is Iterable) {
        final seen = <String>{};
        final out = <String>[];
        for (final e in v) {
          final s = (e?.toString() ?? '').trim();
          if (s.isEmpty) continue;
          final norm = _norm(s);
          if (seen.add(norm)) out.add(norm);
        }
        return out;
      }
      return <String>[];
    }

    Map<String, String> _stringMap(dynamic v) {
      if (v is Map) {
        return v.map((k, val) => MapEntry(k.toString(), val?.toString() ?? ''));
      }
      return <String, String>{};
    }

    List<double>? _doubleList(dynamic v) {
      if (v is Iterable) {
        final list = v.map((e) {
          if (e is num) return e.toDouble();
          final parsed = double.tryParse(e.toString());
          return parsed ?? 0.0;
        }).toList();
        return list;
      }
      return null;
    }

    final tp = TasteProfile(
      letterboxdUsername: (data['letterboxdUsername'] as String?)?.trim(),
      loved: _stringList(lovedRaw),
      disliked: _stringList(dislikedRaw),
      posters: _stringMap(postersRaw),
      vector: _doubleList(vectorRaw),
      computedAtMs: (data['computedAtMs'] is num)
          ? (data['computedAtMs'] as num).toInt()
          : int.tryParse('${data['computedAtMs'] ?? ''}'),
    );
    // normalize + dedupe + align posters
    final lovedClean = _dedupe(tp.loved);
    final dislikedClean = _dedupe(tp.disliked);
    final allowed = {...lovedClean, ...dislikedClean};
    final postersClean = {
      for (final e in tp.posters.entries)
        if (allowed.contains(_norm(e.key))) _norm(e.key): e.value,
    };
    return tp.copyWith(
      loved: lovedClean,
      disliked: dislikedClean,
      posters: postersClean,
    );
  }

  /// Create from raw lists (will be normalized & deduped)
  factory TasteProfile.fromLists({
    String? letterboxdUsername,
    Iterable<String> loved = const [],
    Iterable<String> disliked = const [],
    Map<String, String> posters = const {},
    List<double>? vector,
    int? computedAtMs,
  }) {
    final lovedClean = _dedupe(loved);
    final dislikedClean = _dedupe(disliked);
    final allowed = {...lovedClean, ...dislikedClean};
    final postersClean = {
      for (final entry in posters.entries)
        if (allowed.contains(_norm(entry.key))) _norm(entry.key): entry.value,
    };
    return TasteProfile(
      letterboxdUsername: letterboxdUsername,
      loved: lovedClean,
      disliked: dislikedClean,
      posters: postersClean,
      vector: vector,
      computedAtMs: computedAtMs ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Merge two profiles (A ∪ B). Posters prefer `other` then `this`.
  TasteProfile merge(TasteProfile other) {
    final lovedMerged = _dedupe([...loved, ...other.loved]);
    final dislikedMerged = _dedupe([...disliked, ...other.disliked]);
    final postersMerged = Map<String, String>.from(posters);
    postersMerged.addAll(other.posters.map((k, v) => MapEntry(_norm(k), v)));
    return copyWith(
      loved: lovedMerged,
      disliked: dislikedMerged,
      posters: postersMerged,
      vector: other.vector ?? vector,
      computedAtMs: (other.computedAtMs ?? 0) > (computedAtMs ?? 0)
          ? other.computedAtMs
          : computedAtMs,
    );
  }

  /// Mutators for incremental updates
  TasteProfile addLoved(String filmKey, {String? posterUrl}) {
    final key = _norm(filmKey);
    final nextLoved = _dedupe([...loved, key]);
    final nextPosters = Map<String, String>.from(posters);
    if (posterUrl != null && posterUrl.isNotEmpty) nextPosters[key] = posterUrl;
    return copyWith(loved: nextLoved, posters: nextPosters);
  }

  TasteProfile addDisliked(String filmKey, {String? posterUrl}) {
    final key = _norm(filmKey);
    final nextDisliked = _dedupe([...disliked, key]);
    final nextPosters = Map<String, String>.from(posters);
    if (posterUrl != null && posterUrl.isNotEmpty) nextPosters[key] = posterUrl;
    return copyWith(disliked: nextDisliked, posters: nextPosters);
  }

  /// Convenience empties
  static const empty = TasteProfile();
}

/// Firestore service for persisting/loading a user's TasteProfile.
/// Uses the top-level `userTasteProfiles/{uid}` document for each user (matches current Firestore rules).
class UserProfileService {
  UserProfileService._();
  static final UserProfileService instance = UserProfileService._();

  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  /// Reference to top-level `tasteProfiles/{uid}` document
  DocumentReference<Map<String, dynamic>> _tasteRef(String uid) {
    // Use top-level collection for simpler querying & matching
    return _fs.collection('userTasteProfiles').doc(uid);
  }

  /// Reference to root `users/{uid}` for cross-collection mirrors (matching queries)
  DocumentReference<Map<String, dynamic>> _usersRef(String uid) {
    return _fs.collection('users').doc(uid);
  }

  /// Mirror five-star (loved) keys into users/{uid}.fiveStarKeys for visibility
  Future<void> _mirrorFiveStarKeysToUsers({
    required String uid,
    required List<String> fiveStarKeys,
  }) async {
    final clean = _normKeys(fiveStarKeys);
    await _usersRef(uid).set({
      'fiveStarKeys': clean,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Mirror a minimal subset into `users/{uid}` so matching code that queries
  /// `favoritesKeys` can work without reading the full taste profile.
  Future<void> _mirrorFavoritesKeysToUsers({
    required String uid,
    required List<String> lovedKeys,
    String? letterboxdUsername,
  }) async {
    final cleanLoved = _normKeys(lovedKeys);
    if (cleanLoved.isEmpty && letterboxdUsername == null) return;

    final payload = <String, dynamic>{
      if (letterboxdUsername != null) 'letterboxdUsername': letterboxdUsername,
      if (cleanLoved.isNotEmpty) 'favoritesKeys': cleanLoved,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _usersRef(uid).set(payload, SetOptions(merge: true));
  }

  /// Save/merge a profile. Adds a server timestamp.
  Future<void> saveTasteProfile({
    required String uid,
    required TasteProfile profile,
  }) async {
    final map = profile.toMap();
    map['updatedAt'] = FieldValue.serverTimestamp();
    await _tasteRef(uid).set(map, SetOptions(merge: true));
    // Mirror loved keys + LB username for matching queries that use `users/{uid}`
    await _mirrorFavoritesKeysToUsers(
      uid: uid,
      lovedKeys: profile.loved,
      letterboxdUsername: profile.letterboxdUsername,
    );
    await _mirrorFiveStarKeysToUsers(uid: uid, fiveStarKeys: profile.loved);
  }

  /// Patch specific fields without rewriting the whole doc.
  Future<void> patchTasteProfile({
    required String uid,
    List<String>? loved,
    List<String>? disliked,
    Map<String, String>? posters,
    List<double>? vector,
    int? computedAtMs,
    String? letterboxdUsername,
  }) async {
    final update = <String, dynamic>{};
    if (loved != null) update['loved'] = loved;
    if (disliked != null) update['disliked'] = disliked;
    if (posters != null) update['posters'] = posters;
    if (vector != null) update['vector'] = vector;
    if (computedAtMs != null) update['computedAtMs'] = computedAtMs;
    if (letterboxdUsername != null)
      update['letterboxdUsername'] = letterboxdUsername;
    update['updatedAt'] = FieldValue.serverTimestamp();
    if (update.isEmpty) return;
    await _tasteRef(uid).set(update, SetOptions(merge: true));

    // If loved or username changed, mirror minimal data for matching
    await _mirrorFavoritesKeysToUsers(
      uid: uid,
      lovedKeys: loved ?? const <String>[],
      letterboxdUsername: letterboxdUsername,
    );
    if (loved != null) {
      await _mirrorFiveStarKeysToUsers(uid: uid, fiveStarKeys: loved);
    }
  }

  /// Load once. Returns `TasteProfile.empty` if none exists.
  Future<TasteProfile> loadTasteProfile(String uid) async {
    final snap = await _tasteRef(uid).get();
    final data = snap.data();
    if (data == null) return TasteProfile.empty;
    try {
      return TasteProfile.fromMap(data);
    } catch (_) {
      return TasteProfile.empty;
    }
  }

  /// Stream updates. Emits `TasteProfile.empty` if deleted/missing.
  Stream<TasteProfile> watchTasteProfile(String uid) {
    return _tasteRef(uid).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return TasteProfile.empty;
      try {
        return TasteProfile.fromMap(data);
      } catch (_) {
        return TasteProfile.empty;
      }
    });
  }

  /// Convenience: upsert Letterboxd username on the root user doc
  /// and mirror it into the taste profile for easier reads.
  Future<void> setLetterboxdUsername({
    required String uid,
    required String username,
  }) async {
    final clean = username.trim();
    final batch = _fs.batch();
    final userRef = _fs.collection('users').doc(uid);
    batch.set(userRef, {
      'letterboxdUsername': clean,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.set(_tasteRef(uid), {
      'letterboxdUsername': clean,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  // ---- Convenience helpers to persist Letterboxd-derived data ----

  /// Normalize & dedupe a list of film keys (ids or slugs)
  List<String> _normKeys(Iterable<String> keys) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in keys) {
      final k = (raw).trim().toLowerCase();
      if (k.isEmpty) continue;
      if (seen.add(k)) out.add(k);
    }
    return out;
  }

  /// Merge poster map while only keeping posters for keys we actually store.
  Map<String, String> _mergePosters({
    required Map<String, String> base,
    required Map<String, String> incoming,
    required Set<String> allowedKeys,
  }) {
    final out = Map<String, String>.from(base);
    for (final e in incoming.entries) {
      final k = (e.key).trim().toLowerCase();
      final v = (e.value).toString();
      if (k.isEmpty || v.isEmpty) continue;
      if (allowedKeys.contains(k)) out[k] = v;
    }
    return out;
  }

  /// Upsert full taste profile from freshly scraped Letterboxd data.
  /// Use this after you fetch 5★ (loved) and 0.5★/1★ (disliked).
  Future<void> saveFromLetterboxd({
    required String uid,
    String? username,
    List<String> lovedKeys = const [],
    List<String> dislikedKeys = const [],
    Map<String, String> posters = const {},
    int? computedAtMs,
    bool merge = true,
  }) async {
    // Load current to merge (if requested)
    final current = merge ? await loadTasteProfile(uid) : TasteProfile.empty;

    final lovedClean = _normKeys(lovedKeys);
    final dislikedClean = _normKeys(dislikedKeys);
    final allowed = {...lovedClean, ...dislikedClean}.toSet();

    // Compose a new profile from incoming
    final incoming = TasteProfile.fromLists(
      letterboxdUsername: username ?? current.letterboxdUsername,
      loved: lovedClean,
      disliked: dislikedClean,
      posters: posters,
      vector: current.vector, // keep any existing vector
      computedAtMs: computedAtMs ?? DateTime.now().millisecondsSinceEpoch,
    );

    // Merge with current (keeps older items too if `merge` is true)
    final merged = merge ? current.merge(incoming) : incoming;

    // Ensure posters only for keys we keep
    final mergedAllowed = {...merged.loved, ...merged.disliked}.toSet();
    final cleanedPosters = _mergePosters(
      base: merged.posters,
      incoming: posters,
      allowedKeys: mergedAllowed,
    );

    final finalProfile = merged.copyWith(
      posters: cleanedPosters,
      letterboxdUsername: username ?? merged.letterboxdUsername,
      computedAtMs: computedAtMs ?? merged.computedAtMs,
    );

    await saveTasteProfile(uid: uid, profile: finalProfile);
  }

  /// Incrementally add loved items (e.g., a new 5★) without overwriting others.
  Future<void> addLovedKeys({
    required String uid,
    required List<String> filmKeys,
    Map<String, String> posters = const {},
  }) async {
    final current = await loadTasteProfile(uid);
    final incoming = _normKeys(filmKeys);
    final next = current.copyWith(
      loved: TasteProfile._dedupe([...current.loved, ...incoming]),
      posters: _mergePosters(
        base: current.posters,
        incoming: posters,
        allowedKeys: {
          ...current.loved,
          ...current.disliked,
          ...incoming,
        }.toSet(),
      ),
      computedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await saveTasteProfile(uid: uid, profile: next);
  }

  /// Incrementally add disliked items (e.g., new 0.5★ / 1★) without overwriting others.
  Future<void> addDislikedKeys({
    required String uid,
    required List<String> filmKeys,
    Map<String, String> posters = const {},
  }) async {
    final current = await loadTasteProfile(uid);
    final incoming = _normKeys(filmKeys);
    final next = current.copyWith(
      disliked: TasteProfile._dedupe([...current.disliked, ...incoming]),
      posters: _mergePosters(
        base: current.posters,
        incoming: posters,
        allowedKeys: {
          ...current.loved,
          ...current.disliked,
          ...incoming,
        }.toSet(),
      ),
      computedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await saveTasteProfile(uid: uid, profile: next);
  }

  /// Clear the taste profile document (keeps the doc but empties lists/posters).
  Future<void> clearTasteProfile(String uid) async {
    await _tasteRef(uid).set({
      'loved': <String>[],
      'disliked': <String>[],
      'posters': <String, String>{},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
