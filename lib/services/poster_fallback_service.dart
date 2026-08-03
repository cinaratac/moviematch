import 'package:cloud_functions/cloud_functions.dart';

class PosterFallbackService {
  PosterFallbackService._();

  static final PosterFallbackService instance = PosterFallbackService._();

  final Map<String, String> _resolvedCache = {};

  bool _looksValid(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final value = url.trim();
    if (!(value.startsWith('http://') || value.startsWith('https://'))) {
      return false;
    }
    if (value.contains('empty-poster') || value.contains('null')) return false;
    if (value.contains('ltrbxd.com')) return false;
    return true;
  }

  Future<String?> resolvePosterUrl({
    String? existing,
    int? tmdbId,
    String? imdbId,
    String? title,
    int? year,
    bool ignoreExisting = false,
  }) async {
    final cacheKey = [
      tmdbId?.toString() ?? '',
      imdbId?.trim() ?? '',
      title?.toLowerCase().trim() ?? '',
      year?.toString() ?? '',
    ].join('|');
    final cached = _resolvedCache[cacheKey];
    if (cached != null) return cached;

    if (!ignoreExisting && _looksValid(existing)) {
      if (cacheKey.replaceAll('|', '').isNotEmpty) {
        _resolvedCache[cacheKey] = existing!.trim();
      }
      return existing;
    }

    if ((tmdbId == null || tmdbId <= 0) &&
        (imdbId == null || imdbId.trim().isEmpty) &&
        (title == null || title.trim().isEmpty)) {
      return null;
    }

    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('resolveCatalogMovie')
          .call({
            if (tmdbId != null && tmdbId > 0) 'tmdbId': tmdbId,
            if (imdbId != null && imdbId.trim().isNotEmpty)
              'imdbId': imdbId.trim(),
            if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
            if (year != null && year > 0) 'year': year,
          });
      final data = Map<String, dynamic>.from(response.data as Map);
      final posterUrl = data['posterUrl']?.toString().trim();
      if (data['ok'] != true || !_looksValid(posterUrl)) return null;
      if (cacheKey.replaceAll('|', '').isNotEmpty) {
        _resolvedCache[cacheKey] = posterUrl!;
      }
      return posterUrl;
    } catch (_) {
      return null;
    }
  }
}
