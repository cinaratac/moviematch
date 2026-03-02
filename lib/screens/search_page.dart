import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Önbellek için
import 'package:cloud_functions/cloud_functions.dart';
// İlgili importlar
import '../screens/public_profile_screen.dart';
import '../screens/movie_detail_screen.dart';
import '../widgets/poster_image.dart'; 

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  
  String _searchText = '';
  Timer? _debounce;

  final List<String> _movieCategories = [
    'Bilim Kurgu', 'Aksiyon', 'Komedi', 'Romantik', 'Korku', 'Oscar Ödüllü', 'Anime', 'Klasikler'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) FocusScope.of(context).unfocus();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 960), () { 
      setState(() {
        _searchText = val.trim();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryGreen = const Color(0xFF2E7D32);
    
    final bgGradientStart = isDark ? const Color(0xFF0D2410) : const Color(0xFFE8F5E9);
    final bgGradientEnd = isDark ? const Color(0xFF000000) : Colors.white;

    return Scaffold(
      resizeToAvoidBottomInset: false, 
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 80,
        titleSpacing: 0,
        centerTitle: true,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 8),
              // Arama Çubuğu
              Container(
                height: 50,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: isDark ? Colors.grey[800]! : Colors.white,
                    width: 1
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  textAlignVertical: TextAlignVertical.center,
                  decoration: InputDecoration(
                    hintText: _tabController.index == 0 ? 'Film, dizi veya tür ara...' : 'Kullanıcı adı veya isim ara...',
                    hintStyle: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[400]),
                    prefixIcon: Icon(Icons.search, color: primaryGreen),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: Colors.grey[400], size: 20),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            height: 40,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: primaryGreen,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: primaryGreen.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              labelColor: Colors.white,
              unselectedLabelColor: isDark ? Colors.grey[400] : Colors.grey[600],
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              tabs: const [
                Tab(text: 'Filmler'),
                Tab(text: 'Kullanıcılar'),
              ],
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bgGradientStart, bgGradientEnd],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 150),
            child: TabBarView(
              controller: _tabController,
              children: [
                _MovieSearchTab(searchText: _searchText, categories: _movieCategories),
                _UserSearchTab(searchText: _searchText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// FİLM ARAMA SEKME İÇERİĞİ (GÜNCELLENDİ: SAYFALAMA EKLENDİ)
// -----------------------------------------------------------------------------
class _MovieSearchTab extends StatefulWidget {
  final String searchText;
  final List<String> categories;
  const _MovieSearchTab({required this.searchText, required this.categories});

  @override
  State<_MovieSearchTab> createState() => _MovieSearchTabState();
}

class _MovieSearchTabState extends State<_MovieSearchTab> {
  List<dynamic> _movies = [];
  List<Map<String, dynamic>> _recentMovies = []; // Önbellekteki filmler
  
  // -- Pagination State --
  bool _isLoading = false;
  bool _isLoadingMore = false; // Alttan yükleme durumu
  bool _hasMore = true;        // Daha fazla sayfa var mı?
  int _currentPage = 1;        // Şu anki sayfa
  String? _error;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadRecents();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Listenin sonuna 200 piksel kala yeni veriyi çek
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore && 
        !_isLoading &&
        _hasMore &&
        widget.searchText.isNotEmpty) { // Sadece arama yapılıyorken
      _loadMoreMovies();
    }
  }

  @override
  void didUpdateWidget(covariant _MovieSearchTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchText != oldWidget.searchText) {
      // Arama metni değişirse her şeyi sıfırla ve yeniden ara
      _searchMovies(widget.searchText);
    }
  }

  // --- ÖNBELLEK İŞLEMLERİ (FİLM) ---
  Future<void> _loadRecents() async {
    final sp = await SharedPreferences.getInstance();
    final List<String>? list = sp.getStringList('recent_movies_v1');
    if (list != null && mounted) {
      setState(() {
        _recentMovies = list.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
      });
    }
  }

  Future<void> _addRecent(Map<String, dynamic> movie) async {
    final item = {
      'id': movie['id'],
      'title': movie['title'],
      'poster_path': movie['poster_path'],
    };
    
    final sp = await SharedPreferences.getInstance();
    // Varsa eskisini sil (yukarı taşıyacağız)
    _recentMovies.removeWhere((e) => e['id'] == item['id']);
    // Başa ekle
    _recentMovies.insert(0, item);
    // Limit (örneğin son 10)
    if (_recentMovies.length > 10) _recentMovies.removeLast();
    
    await sp.setStringList('recent_movies_v1', _recentMovies.map((e) => jsonEncode(e)).toList());
    if (mounted) setState(() {});
  }

  Future<void> _removeRecent(int id) async {
    final sp = await SharedPreferences.getInstance();
    setState(() {
      _recentMovies.removeWhere((e) => e['id'] == id);
    });
    await sp.setStringList('recent_movies_v1', _recentMovies.map((e) => jsonEncode(e)).toList());
  }
  
  // --- API YARDIMCI FONKSİYONU ---
  Future<List<dynamic>> _fetchMoviesFromApi(String query, int page) async {
  final result = await FirebaseFunctions.instance
      .httpsCallable('searchMovies')
      .call({'query': query, 'page': page});
  
 
  final data = Map<String, dynamic>.from(result.data as Map);
  
  final List results = data['results'] ?? [];
  // Listedeki her bir elemanı da Map<String, dynamic> olarak dönüştürmek en güvenlisidir:
  return results.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

  // --- İLK ARAMA ---
  Future<void> _searchMovies(String query) async {
    if (query.isEmpty) {
      if (mounted) {
        setState(() { 
          _movies = []; 
          _error = null; 
          _isLoading = false;
          _hasMore = true;
          _currentPage = 1; 
        });
      }
      return;
    }

    setState(() { 
      _isLoading = true; 
      _error = null; 
      _movies = [];
      _currentPage = 1;
      _hasMore = true;
    });

    try {
      final results = await _fetchMoviesFromApi(query, 1);
      
      if (mounted) {
        setState(() {
          _movies = results;
          _isLoading = false;
          if (results.isEmpty) _hasMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  // --- DAHA FAZLA YÜKLE ---
  Future<void> _loadMoreMovies() async {
    if (_isLoadingMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final nextPage = _currentPage + 1;
      final results = await _fetchMoviesFromApi(widget.searchText, nextPage);

      if (mounted) {
        if (results.isEmpty) {
          setState(() => _hasMore = false);
        } else {
          setState(() {
            _movies.addAll(results); // Listeye ekle
            _currentPage = nextPage;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Yükleme hatası: $e")));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    
    // İlk yükleme (ve sayfa boşken) loading göster
    if (_isLoading && _movies.isEmpty) return const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)));
    
    // Arama yoksa ve geçmiş varsa geçmişi göster
    if (widget.searchText.isEmpty) {
      if (_recentMovies.isNotEmpty) {
        return _buildRecentList();
      }
      // Geçmiş de yoksa boş durmasın, kategori önerisi vs. eklenebilir ama şu anlık boş.
    }

    if (_error != null) return Center(child: Text("Hata: $_error"));
    
    // Arama yapılmış ama sonuç yok
    if (_movies.isEmpty && !_isLoading && widget.searchText.isNotEmpty) {
      return const Center(child: Text("Film bulunamadı.", style: TextStyle(color: Colors.grey)));
    }

    // ARAMA SONUÇLARI
    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            controller: _scrollController, // Scroll Controller Eklendi
            padding: const EdgeInsets.all(16),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, 
              childAspectRatio: 0.67, 
              crossAxisSpacing: 12, 
              mainAxisSpacing: 12
            ),
            itemCount: _movies.length,
            itemBuilder: (context, index) {
              final movie = _movies[index];
              final posterPath = movie['poster_path'];
              final posterUrl = (posterPath is String && posterPath.isNotEmpty) 
                  ? 'https://image.tmdb.org/t/p/w500$posterPath' : '';
              final title = movie['title'] ?? '';

              return InkWell(
                onTap: () {
                  // Tıklandığında önce kaydet, sonra git
                  _addRecent(movie);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MovieDetailScreen(
                        tmdbId: movie['id'],
                        title: title,
                        posterUrl: posterUrl.isNotEmpty ? posterUrl : null,
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PosterImage(posterUrl: posterUrl, title: title, fit: BoxFit.cover),
                      Positioned(
                        left: 0, right: 0, bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter, 
                              end: Alignment.topCenter, 
                              colors: [Colors.black87, Colors.transparent]
                            )
                          ),
                          child: Text(
                            title, 
                            maxLines: 2, 
                            overflow: TextOverflow.ellipsis, 
                            textAlign: TextAlign.center, 
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500)
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Alt Kısımda Yükleniyor Göstergesi
        if (_isLoadingMore)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Center(
              child: SizedBox(
                width: 24, 
                height: 24, 
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2E7D32))
              ),
            ),
          ),
      ],
    );
  }

  // GEÇMİŞ LİSTESİ WIDGET'I
  Widget _buildRecentList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryGreen = const Color(0xFF2E7D32);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Son Aramalar",
                style: TextStyle(
                  fontSize: 16, 
                  fontWeight: FontWeight.bold, 
                  color: isDark ? Colors.grey[400] : Colors.grey[700]
                ),
              ),
              GestureDetector(
                onTap: () async {
                  final sp = await SharedPreferences.getInstance();
                  await sp.remove('recent_movies_v1');
                  setState(() => _recentMovies.clear());
                },
                child: Text("Temizle", style: TextStyle(fontSize: 14, color: primaryGreen)),
              )
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _recentMovies.length,
            itemBuilder: (context, index) {
              final movie = _recentMovies[index];
              final posterPath = movie['poster_path'];
              final posterUrl = (posterPath != null && posterPath.toString().isNotEmpty)
                  ? 'https://image.tmdb.org/t/p/w200$posterPath' : null;

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: posterUrl != null 
                    ? Image.network(posterUrl, width: 40, height: 60, fit: BoxFit.cover)
                    : Container(width: 40, height: 60, color: Colors.grey[300], child: const Icon(Icons.movie, size: 20)),
                ),
                title: Text(movie['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => _removeRecent(movie['id']),
                ),
                onTap: () {
                  // Geçmişten tıklanınca tekrar detay aç
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MovieDetailScreen(
                        tmdbId: movie['id'],
                        title: movie['title'],
                        posterUrl: (posterPath != null) ? 'https://image.tmdb.org/t/p/w500$posterPath' : null,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// KULLANICI ARAMA SEKME İÇERİĞİ (DEĞİŞMEDİ)
// -----------------------------------------------------------------------------
class _UserSearchTab extends StatefulWidget {
  final String searchText;
  const _UserSearchTab({required this.searchText});

  @override
  State<_UserSearchTab> createState() => _UserSearchTabState();
}

class _UserSearchTabState extends State<_UserSearchTab> {
  List<Map<String, dynamic>> _results = [];
  List<Map<String, dynamic>> _recentUsers = []; // Önbellekteki kullanıcılar
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRecents();
  }

  @override
  void didUpdateWidget(covariant _UserSearchTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchText != oldWidget.searchText) {
      _searchUsers(widget.searchText);
    }
  }

  // --- ÖNBELLEK İŞLEMLERİ (KULLANICI) ---
  Future<void> _loadRecents() async {
    final sp = await SharedPreferences.getInstance();
    final List<String>? list = sp.getStringList('recent_users_v1');
    if (list != null && mounted) {
      setState(() {
        _recentUsers = list.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
      });
    }
  }

  Future<void> _addRecent(Map<String, dynamic> user) async {
    final item = {
      'uid': user['uid'],
      'displayName': user['displayName'],
      'username': user['username'],
      'photoURL': user['photoURL'],
      'letterboxdUsername': user['letterboxdUsername'],
    };
    
    final sp = await SharedPreferences.getInstance();
    _recentUsers.removeWhere((e) => e['uid'] == item['uid']);
    _recentUsers.insert(0, item);
    if (_recentUsers.length > 10) _recentUsers.removeLast();
    
    await sp.setStringList('recent_users_v1', _recentUsers.map((e) => jsonEncode(e)).toList());
    if (mounted) setState(() {});
  }

  Future<void> _removeRecent(String uid) async {
    final sp = await SharedPreferences.getInstance();
    setState(() {
      _recentUsers.removeWhere((e) => e['uid'] == uid);
    });
    await sp.setStringList('recent_users_v1', _recentUsers.map((e) => jsonEncode(e)).toList());
  }
  // ------------------------------------

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      if (mounted) setState(() { _results = []; _isLoading = false; });
      return;
    }

    setState(() => _isLoading = true);
    final qLc = query.toLowerCase();
    final List<Map<String, dynamic>> buffer = [];

    try {
      final db = FirebaseFirestore.instance;
      // Username (küçük harf) araması
      final qUser = await db.collection('users').orderBy('username_lc').startAt([qLc]).endAt(['$qLc\uf8ff']).limit(10).get();
      for (var doc in qUser.docs) {
        if (!buffer.any((e) => e['uid'] == doc.id)) buffer.add({'uid': doc.id, ...doc.data()});
      }
      
      // Display Name (küçük harf) araması
      if (buffer.length < 10) {
        final qName = await db.collection('users').orderBy('displayName_lc').startAt([qLc]).endAt(['$qLc\uf8ff']).limit(10).get();
        for (var doc in qName.docs) {
          if (!buffer.any((e) => e['uid'] == doc.id)) buffer.add({'uid': doc.id, ...doc.data()});
        }
      }

      final myUid = FirebaseAuth.instance.currentUser?.uid;
      if (myUid != null) buffer.removeWhere((element) => element['uid'] == myUid);

      if (mounted) setState(() { _results = buffer; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFF2E7D32)));
    
    // Arama yoksa ve geçmiş varsa geçmişi göster
    if (widget.searchText.isEmpty) {
      if (_recentUsers.isNotEmpty) {
        return _buildRecentList();
      }
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search_outlined, size: 80, color: Colors.grey.withOpacity(0.3)),
            const SizedBox(height: 16),
            const Text("Kullanıcıları keşfet", style: TextStyle(color: Colors.grey, fontSize: 16)),
            
          ],
        ),
      );
    }

    if (_results.isEmpty) return const Center(child: Text("Kullanıcı bulunamadı.", style: TextStyle(color: Colors.grey)));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      itemCount: _results.length,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemBuilder: (context, index) {
        final data = _results[index];
        return _buildUserResultCard(context, data, isRecent: false);
      },
    );
  }

  // Geçmiş Kullanıcı Listesi
  Widget _buildRecentList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryGreen = const Color(0xFF2E7D32);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Son Görüntülenenler",
                style: TextStyle(
                  fontSize: 16, 
                  fontWeight: FontWeight.bold, 
                  color: isDark ? Colors.grey[400] : Colors.grey[700]
                ),
              ),
              GestureDetector(
                onTap: () async {
                  final sp = await SharedPreferences.getInstance();
                  await sp.remove('recent_users_v1');
                  setState(() => _recentUsers.clear());
                },
                child: Text("Temizle", style: TextStyle(fontSize: 14, color: primaryGreen)),
              )
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _recentUsers.length,
            itemBuilder: (context, index) {
              final data = _recentUsers[index];
              return _buildUserResultCard(context, data, isRecent: true);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUserResultCard(BuildContext context, Map<String, dynamic> data, {required bool isRecent}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayName = data['displayName'] ?? 'İsimsiz';
    final username = data['username'] ?? '';
    final photoURL = data['photoURL'];
    final lbUser = data['letterboxdUsername'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.3 : 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(10),
        leading: GestureDetector(
          onTap: () {
             _addRecent(data);
             Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: data['uid'])));
          },
          child: CircleAvatar(
            radius: 28,
            backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
            backgroundImage: (photoURL != null && photoURL.toString().isNotEmpty) ? NetworkImage(photoURL) : null,
            child: (photoURL == null || photoURL.toString().isEmpty) ? const Icon(Icons.person, color: Colors.grey) : null,
          ),
        ),
        title: Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('@$username', style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w500)),
            if (lbUser != null && lbUser.toString().isNotEmpty) Text('Letterboxd: $lbUser', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ],
        ),
        // Eğer geçmiş listesiyse Çarpı butonu, değilse ok butonu
        trailing: isRecent 
          ? IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => _removeRecent(data['uid']),
            )
          : const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
        onTap: () {
          _addRecent(data);
          Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: data['uid'])));
        },
      ),
    );
  }
}