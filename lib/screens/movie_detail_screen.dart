import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';

class MovieDetailScreen extends StatefulWidget {
  final int tmdbId;
  final String? title;
  final String? posterUrl;

  const MovieDetailScreen({
    super.key,
    required this.tmdbId,
    this.title,
    this.posterUrl,
  });

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  // BURAYA KENDİ TMDB API ANAHTARINI GİR
  static const String _apiKey = 'YOUR_TMDB_API_KEY'; 
  static const String _baseUrl = 'https://api.themoviedb.org/3';

  Map<String, dynamic>? _movieData;
  List<dynamic> _cast = [];
  List<dynamic> _crew = [];
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    try {
      // Film Detayları ve Kredi Bilgileri (Oyuncular/Yönetmen)
      final url = Uri.parse('$_baseUrl/movie/${widget.tmdbId}?api_key=$_apiKey&language=tr-TR&append_to_response=credits,release_dates');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _movieData = data;
          _cast = data['credits']['cast'] ?? [];
          _crew = data['credits']['crew'] ?? [];
          _loading = false;
        });
      } else {
        throw Exception('API Hatası');
      }
    } catch (e) {
      debugPrint('Film detayı çekilemedi: $e');
      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
  }

  String get _director {
    final d = _crew.firstWhere((m) => m['job'] == 'Director', orElse: () => null);
    return d != null ? d['name'] : 'Bilinmiyor';
  }

  String get _rating => _movieData != null 
      ? (_movieData!['vote_average'] as num).toStringAsFixed(1) 
      : '-';

  String get _runtime {
    if (_movieData == null) return '';
    final mins = _movieData!['runtime'] as int?;
    if (mins == null || mins == 0) return '';
    final h = mins ~/ 60;
    final m = mins % 60;
    return '${h}s ${m}dk';
  }

  String get _year {
    if (_movieData == null) return '';
    final date = _movieData!['release_date'] as String?;
    if (date == null || date.length < 4) return '';
    return date.substring(0, 4);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final textColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
            child: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // 1. ARKA PLAN (Blur Efekti)
          if (widget.posterUrl != null)
            Positioned.fill(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(imageUrl: widget.posterUrl!, fit: BoxFit.cover),
                  BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Container(color: bgColor.withOpacity(0.85)),
                  ),
                ],
              ),
            ),

          // 2. İÇERİK
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_hasError || _movieData == null)
            Center(child: Text("Detaylar yüklenemedi", style: TextStyle(color: textColor)))
          else
            SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 60, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // POSTER & BAŞLIK ALANI
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Poster
                      Hero(
                        tag: 'poster_${widget.tmdbId}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: CachedNetworkImage(
                            imageUrl: widget.posterUrl ?? '',
                            width: 140,
                            height: 210,
                            fit: BoxFit.cover,
                            errorWidget: (_,__,___) => Container(color: Colors.grey, width: 140, height: 210),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      
                      // Bilgiler
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _movieData!['title'],
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor, height: 1.2),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: [
                                if(_year.isNotEmpty) _buildTag(_year, isDark),
                                if(_runtime.isNotEmpty) _buildTag(_runtime, isDark),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Puan
                            Row(
                              children: [
                                const Icon(Icons.star_rounded, color: Colors.amber, size: 28),
                                const SizedBox(width: 4),
                                Text(
                                  _rating,
                                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: textColor),
                                ),
                                Text(
                                  '/10',
                                  style: TextStyle(fontSize: 14, color: textColor.withOpacity(0.6), height: 2),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Yönetmen:\n$_director",
                              style: TextStyle(fontSize: 14, color: textColor.withOpacity(0.8), height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 30),

                  // ÖZET
                  Text("Özet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 8),
                  Text(
                    _movieData!['overview'] ?? 'Özet bulunamadı.',
                    style: TextStyle(fontSize: 15, color: textColor.withOpacity(0.8), height: 1.6),
                  ),

                  const SizedBox(height: 30),

                  // OYUNCULAR
                  Text("Oyuncular", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 110,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _cast.length > 10 ? 10 : _cast.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 16),
                      itemBuilder: (context, index) {
                        final actor = _cast[index];
                        final photo = actor['profile_path'];
                        return Column(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: Colors.grey.shade800,
                              backgroundImage: photo != null 
                                ? NetworkImage('https://image.tmdb.org/t/p/w200$photo') 
                                : null,
                              child: photo == null ? const Icon(Icons.person) : null,
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: 70,
                              child: Text(
                                actor['name'],
                                maxLines: 2,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.9)),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTag(String text, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black87)),
    );
  }
}