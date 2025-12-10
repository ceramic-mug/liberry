import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/remote/remote_book.dart';
import '../providers.dart';
import 'discover_screen.dart'; // Reuse RemoteBookTile

class GutendexBookListScreen extends ConsumerStatefulWidget {
  final String title;
  final String? topic;
  final String? searchQuery;
  final String? sort;

  const GutendexBookListScreen({
    super.key,
    required this.title,
    this.topic,
    this.searchQuery,
    this.sort,
  });

  @override
  ConsumerState<GutendexBookListScreen> createState() =>
      _GutendexBookListScreenState();
}

class _GutendexBookListScreenState
    extends ConsumerState<GutendexBookListScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _currentQuery = '';
  final List<RemoteBook> _books = [];
  String? _nextUrl;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentQuery = widget.searchQuery ?? '';
    _searchController.text = _currentQuery;
    _fetchBooks();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _currentQuery = query;
      _books.clear();
      _nextUrl = null;
      _isLoading = true;
    });
    _fetchBooks();
  }

  void _onScroll() {
    // If we are in "Random" mode (limit set), disable infinite scroll
    if (widget.sort == 'random') return;

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && !_isLoadingMore && _nextUrl != null) {
        _fetchMoreBooks();
      }
    }
  }

  Future<void> _fetchBooks() async {
    if (mounted) setState(() => _error = null);

    try {
      final service = ref.read(gutendexServiceProvider);

      // Random Logic: Pick a random page if sorting by random to ensure variety
      int? page;
      if (widget.sort == 'random') {
        // approx 2000 pages of content
        page = DateTime.now().millisecondsSinceEpoch % 2000 + 1;
      }

      final feed = await service.fetchBooks(
        topic: widget.topic,
        search: _currentQuery.isNotEmpty ? _currentQuery : null,
        sort: widget.sort == 'random'
            ? 'popular'
            : widget.sort, // random sort is stable, use popular + random page
        page: page,
      );

      if (mounted) {
        setState(() {
          if (widget.sort == 'random') {
            // User requested max 10
            _books.addAll(feed.books.take(10));
            _nextUrl = null; // Disable pagination for random view
          } else {
            _books.addAll(feed.books);
            _nextUrl = feed.next;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchMoreBooks() async {
    if (_nextUrl == null) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final service = ref.read(gutendexServiceProvider);
      // Fetch using nextUrl directly
      final feed = await service.fetchBooks(nextUrl: _nextUrl);

      if (mounted) {
        setState(() {
          _books.addAll(feed.books);
          _nextUrl = feed.next;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          // Optionally show snackbar for pagination error
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search in ${widget.title}...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _currentQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
        ),
        onSubmitted: _onSearchChanged,
        textInputAction: TextInputAction.search,
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _books.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _books.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _fetchBooks, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_books.isEmpty) {
      return const Center(child: Text('No books found.'));
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
      ), // Search bar has its own padding
      itemCount: _books.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _books.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final book = _books[index];
        return RemoteBookTile(
          book: book,
          isStandardEbook: false, // It's Gutenberg
        );
      },
    );
  }
}
