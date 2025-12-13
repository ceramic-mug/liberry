import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../providers.dart';
import '../data/remote/remote_book.dart';
import 'common/remote_book_tile.dart';
import '../data/database.dart'; // Local Book Entity
import '../data/book_collections.dart';
// import 'book_details_screen.dart'; // No longer needed here as tile handles it
import 'collections_screen.dart';

import 'offline_gutenberg_screen.dart';
import 'standard_ebooks_screen.dart';
import 'collection_details_screen.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final TextEditingController _searchController = TextEditingController();

  // State
  List<RemoteBook> _standardEbooks = [];
  List<RemoteBook> _gutenbergBooks = [];
  bool _isLoadingStandard = true;
  bool _isSearchingGutenberg = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // Intentionally empty - we don't auto-load content anymore per user request
  }

  Future<void> _loadStandardEbooks() async {
    // Standard Ebooks is now offline-first and doesn't support "New Releases" feed in the same way yet.
    // We just keep the list empty initially or when search is cleared.
    if (mounted) {
      setState(() {
        _standardEbooks = [];
        _isLoadingStandard = false;
      });
    }
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchQuery = '';
        _gutenbergBooks = [];
        // Reset to new releases if search is cleared
        _loadStandardEbooks();
      });
      return;
    }

    setState(() {
      _searchQuery = query;
      _isSearchingGutenberg = true;
      _isLoadingStandard = true;
    });

    // Search Standard Ebooks
    try {
      final localService = ref.read(localEbooksServiceProvider);
      final books = await localService.searchBooks(query);
      if (mounted) {
        setState(() {
          _standardEbooks = books;
          _isLoadingStandard = false;
        });
      }
    } catch (e) {
      print('Error searching Standard Ebooks: $e');
      if (mounted) {
        setState(() {
          _isLoadingStandard = false;
        });
      }
    }

    // Search Gutenberg Offline
    try {
      final offlineService = ref.read(offlineGutenbergServiceProvider);
      final rawResults = await offlineService.searchBooks(query);

      // Map raw map results to RemoteBook objects
      final List<RemoteBook> books = rawResults.map((map) {
        final id = map['id'] as int;
        return RemoteBook(
          title: map['title'] as String,
          author: map['author'] as String,
          coverUrl:
              'https://www.gutenberg.org/cache/epub/$id/pg$id.cover.medium.jpg',
          downloadUrl: 'https://www.gutenberg.org/ebooks/$id.epub.images',
          source: 'Project Gutenberg',
        );
      }).toList();

      if (mounted) {
        setState(() {
          _gutenbergBooks = books;
        });
      }
    } catch (e) {
      print('Error searching Gutenberg Offline: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Search failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSearchingGutenberg = false;
        });
      }
    }
  }

  void _searchCollectionBook(CollectionBook book) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _searchController.text = '${book.author} ${book.title}';
    _search();
  }

  @override
  Widget build(BuildContext context) {
    // Watch local book map directly
    final localBookMap = ref.watch(localBookMapProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            GestureDetector(
              onTap: () {
                // Switch to Library tab
                ref.read(navigationIndexProvider.notifier).setIndex(0);
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              behavior: HitTestBehavior.opaque,
              child: SvgPicture.asset('assets/icon.svg', height: 24),
            ),
            const SizedBox(width: 8),
            const Text('Discover Books'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search title, author...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _search();
                  },
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
          ),

          // Content
          Expanded(
            child: _isSearchingGutenberg || _searchQuery.isNotEmpty
                ? _buildSearchResults(localBookMap)
                : _buildDefaultContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(Map<String, Book> localBookMap) {
    if (_isLoadingStandard && _gutenbergBooks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_standardEbooks.isEmpty &&
        _gutenbergBooks.isEmpty &&
        !_isLoadingStandard &&
        !_isSearchingGutenberg) {
      return const Center(child: Text("No results found."));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_standardEbooks.isNotEmpty) ...[
          Text(
            "Standard Ebooks",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ..._standardEbooks.map(
            (book) => RemoteBookTile(
              book: book,
              isStandardEbook: true,
              localBookMap: localBookMap,
            ),
          ),
          const SizedBox(height: 24),
        ],

        if (_gutenbergBooks.isNotEmpty) ...[
          Text(
            "Project Gutenberg",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ..._gutenbergBooks.map(
            (book) => RemoteBookTile(
              book: book,
              isStandardEbook: false,
              localBookMap: localBookMap,
            ),
          ),
        ],

        if (_isSearchingGutenberg)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _buildDefaultContent() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // Top 100 Challenge Button
        // Top 100 Challenge Button
        _buildDiscoveryCard(
          title: BookCollectionsData.top100.title,
          subtitle: BookCollectionsData.top100.subtitle,
          icon: BookCollectionsData.top100.icon,
          accentColor: Theme.of(context).colorScheme.tertiary,
          lightBackgroundColor: Theme.of(
            context,
          ).colorScheme.tertiaryContainer.withValues(alpha: 0.4),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CollectionDetailsScreen(
                  collection: BookCollectionsData.top100,
                  onSearch: _searchCollectionBook,
                ),
              ),
            );
          },
        ),

        // Collections Button
        _buildDiscoveryCard(
          title: 'Collections',
          subtitle: 'Curated lists & series',
          icon: Icons.collections_bookmark_outlined,
          accentColor: Theme.of(context).colorScheme.primary,
          lightBackgroundColor: Theme.of(
            context,
          ).colorScheme.secondaryContainer.withValues(alpha: 0.4),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    CollectionsScreen(onSearch: _searchCollectionBook),
              ),
            );
          },
        ),

        // Standard Ebooks Button
        _buildDiscoveryCard(
          title: 'Standard Ebooks',
          subtitle: 'Browse the collection',
          icon: Icons.book_outlined,
          accentColor: Colors.blue.shade800,
          lightBackgroundColor: Colors.blue.shade50.withValues(alpha: 0.5),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const StandardEbooksScreen(),
              ),
            );
          },
        ),

        // Project Gutenberg Button
        _buildDiscoveryCard(
          title: 'Project Gutenberg',
          subtitle: '60,000+ free ebooks',
          icon: Icons.library_books_outlined,
          accentColor: Colors.orange.shade800,
          lightBackgroundColor: Colors.orange.shade50.withValues(alpha: 0.5),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const OfflineGutenbergScreen(),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDiscoveryCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required Color lightBackgroundColor,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      color: isDark ? Colors.transparent : lightBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isDark
            ? BorderSide(color: accentColor, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(icon, size: 28, color: accentColor),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
