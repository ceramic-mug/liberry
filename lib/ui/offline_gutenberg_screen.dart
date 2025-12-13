import 'package:flutter/material.dart';
import '../data/database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/remote/remote_book.dart';
import '../providers.dart';
import 'common/remote_book_tile.dart';
import 'author_books_screen.dart';

class OfflineGutenbergScreen extends ConsumerStatefulWidget {
  const OfflineGutenbergScreen({super.key});

  @override
  ConsumerState<OfflineGutenbergScreen> createState() =>
      _OfflineGutenbergScreenState();
}

class _OfflineGutenbergScreenState extends ConsumerState<OfflineGutenbergScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _globalSearchController = TextEditingController();

  // Tab 1: Random
  List<RemoteBook> _randomBooks = [];
  bool _isLoadingRandom = true;

  // Tab 3: Authors
  List<String> _allAuthors = [];
  List<String> _filteredAuthors = [];
  final TextEditingController _authorFilterController = TextEditingController();
  bool _isLoadingAuthors = true;

  // Search
  bool _isSearching = false;
  List<RemoteBook> _searchResults = [];
  bool _isLoadingSearch = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // 2 Tabs: Random, Authors
    _tabController = TabController(length: 2, vsync: this);
    _loadRandomBooks();
    _loadAuthors();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _globalSearchController.dispose();
    _authorFilterController.dispose();
    super.dispose();
  }

  Future<void> _loadAuthors() async {
    setState(() => _isLoadingAuthors = true);
    try {
      final service = ref.read(offlineGutenbergServiceProvider);
      final authors = await service.getAllAuthors();
      if (mounted) {
        setState(() {
          _allAuthors = authors;
          _filteredAuthors = authors;
          _isLoadingAuthors = false;
        });
      }
    } catch (e) {
      print("Error loading authors: $e");
      if (mounted) setState(() => _isLoadingAuthors = false);
    }
  }

  void _filterAuthors(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredAuthors = _allAuthors;
      } else {
        _filteredAuthors = _allAuthors
            .where((a) => a.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  Future<void> _loadRandomBooks() async {
    if (!mounted) return;
    setState(() {
      _isLoadingRandom = true;
    });

    try {
      final service = ref.read(offlineGutenbergServiceProvider);
      // Limit to 10 as requested
      final results = await service.getRandomBooks(limit: 10);
      final books = _mapResultsToBooks(results);

      if (mounted) {
        setState(() {
          _randomBooks = books;
          _isLoadingRandom = false;
        });
      }
    } catch (e) {
      print("Random load error: $e");
      if (mounted) {
        setState(() => _isLoadingRandom = false);
      }
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _searchQuery = '';
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _isLoadingSearch = true;
      _searchQuery = query;
    });

    try {
      final service = ref.read(offlineGutenbergServiceProvider);
      final results = await service.searchBooks(query);
      final books = _mapResultsToBooks(results);

      if (mounted) {
        setState(() {
          _searchResults = books;
          _isLoadingSearch = false;
        });
      }
    } catch (e) {
      print("Search error: $e");
      if (mounted) {
        setState(() => _isLoadingSearch = false);
      }
    }
  }

  List<RemoteBook> _mapResultsToBooks(List<Map<String, dynamic>> results) {
    return results.map((data) {
      final id = data['id'] as int;
      return RemoteBook(
        title: data['title'] as String,
        author: data['author'] as String,
        coverUrl:
            "https://www.gutenberg.org/cache/epub/$id/pg$id.cover.medium.jpg",
        downloadUrl: "https://www.gutenberg.org/ebooks/$id.epub.images",
        source: 'Project Gutenberg',
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final localBookMap = ref.watch(localBookMapProvider);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _globalSearchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                ),
                style: const TextStyle(color: Colors.black, fontSize: 18),
                onSubmitted: _performSearch,
              )
            : const Text('Project Gutenberg'),
        actions: [
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _globalSearchController.clear();
                _performSearch('');
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                setState(() {
                  _isSearching = true;
                });
              },
            ),
        ],
        bottom: !_isSearching
            ? TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Random'),
                  Tab(text: 'Authors'),
                ],
              )
            : null,
      ),
      body: _isSearching
          ? _buildSearchResults(localBookMap)
          : TabBarView(
              controller: _tabController,
              children: [_buildRandomTab(localBookMap), _buildAuthorsTab()],
            ),
      floatingActionButton: (!_isSearching && _tabController.index == 0)
          ? FloatingActionButton.extended(
              onPressed: _loadRandomBooks,
              label: const Text('Shuffle'),
              icon: const Icon(Icons.shuffle),
            )
          : null,
    );
  }

  Widget _buildSearchResults(Map<String, Book> localBookMap) {
    if (_isLoadingSearch) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchResults.isEmpty) {
      return Center(child: Text('No results for "$_searchQuery"'));
    }
    return ListView.builder(
      itemCount: _searchResults.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        return RemoteBookTile(
          book: _searchResults[index],
          isStandardEbook: false,
          localBookMap: localBookMap,
        );
      },
    );
  }

  Widget _buildRandomTab(Map<String, Book> localBookMap) {
    if (_isLoadingRandom) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.builder(
      itemCount: _randomBooks.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        return RemoteBookTile(
          book: _randomBooks[index],
          isStandardEbook: false,
          localBookMap: localBookMap,
        );
      },
    );
  }

  Widget _buildAuthorsTab() {
    if (_isLoadingAuthors) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Filter Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _authorFilterController,
            decoration: InputDecoration(
              hintText: 'Filter authors...',
              prefixIcon: const Icon(Icons.filter_list),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 0,
              ),
              suffixIcon: _authorFilterController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _authorFilterController.clear();
                          _filterAuthors('');
                        });
                      },
                    )
                  : null,
            ),
            onChanged: _filterAuthors,
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _filteredAuthors.length,
            itemBuilder: (context, index) {
              final author = _filteredAuthors[index];
              return Card(
                elevation: 0,
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(author),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AuthorBooksScreen(authorName: author),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
