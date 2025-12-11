import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../data/remote/remote_book.dart';
import '../data/book_collections.dart';
import 'collections_screen.dart';
import 'gutenberg_screen.dart';
import 'standard_ebooks_screen.dart';
import 'download_splash_screen.dart';

import '../providers.dart';

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

    // Search Gutenberg
    try {
      final gutendexService = ref.read(gutendexServiceProvider);
      final books = await gutendexService.searchBooks(query);
      if (mounted) {
        setState(() {
          _gutenbergBooks = books;
        });
      }
    } catch (e) {
      print('Error searching Gutenberg: $e');
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
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            SvgPicture.asset('assets/icon.svg', height: 24),
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

          // Results
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                if (_searchQuery.isEmpty) ...[
                  // Standard Ebooks Button
                  Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    elevation: 0,
                    color: Colors.blue.shade50.withOpacity(
                      0.5,
                    ), // Subtle blue tint
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const StandardEbooksScreen(),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Icon(
                              Icons.book_outlined,
                              size: 28,
                              color: Colors.blue.shade800,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Standard Ebooks',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                  Text(
                                    'Browse the collection',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.7),
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
                              ).colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Project Gutenberg Button
                  Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    elevation: 0,
                    color: Colors.orange.shade50.withOpacity(0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const GutenbergScreen(),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Icon(
                              Icons.library_books_outlined,
                              size: 28,
                              color: Colors.orange.shade800,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Project Gutenberg',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                  Text(
                                    '60,000+ free ebooks',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.7),
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
                              ).colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Collections Button
                  Card(
                    margin: const EdgeInsets.only(bottom: 24),
                    elevation: 0,
                    color: Theme.of(
                      context,
                    ).colorScheme.secondaryContainer.withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CollectionsScreen(
                              onSearch: _searchCollectionBook,
                            ),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Icon(
                              Icons.collections_bookmark_outlined,
                              size: 28,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Collections',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                  Text(
                                    'Curated lists & series',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.7),
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
                              ).colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],

                // Gutenberg Search Results
                if (_searchQuery.isNotEmpty) ...[
                  _buildSectionHeader(
                    'Search Results', // Changed from Project Gutenberg to be more generic since we search both
                    'Books from Standard Ebooks & Project Gutenberg',
                  ),
                  // Show Standard Ebooks search results first
                  if (_isLoadingStandard)
                    const Center(child: CircularProgressIndicator())
                  else
                    ..._standardEbooks.map(
                      (book) =>
                          RemoteBookTile(book: book, isStandardEbook: true),
                    ),

                  if (_isSearchingGutenberg)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_gutenbergBooks.isNotEmpty)
                    ..._gutenbergBooks.map(
                      (book) =>
                          RemoteBookTile(book: book, isStandardEbook: false),
                    ),

                  if (!_isLoadingStandard &&
                      !_isSearchingGutenberg &&
                      _standardEbooks.isEmpty &&
                      _gutenbergBooks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(child: Text('No results found.')),
                    ),
                ],

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0, top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const Divider(),
        ],
      ),
    );
  }
}

class RemoteBookTile extends ConsumerWidget {
  final RemoteBook book;
  final bool isStandardEbook;

  const RemoteBookTile({
    super.key,
    required this.book,
    this.isStandardEbook = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget imageWidget;
    if (book.coverUrl != null) {
      if (book.coverUrl!.startsWith('data:')) {
        try {
          // Extract base64 data
          final base64String = book.coverUrl!.split(',').last;
          final bytes = base64Decode(base64String);
          imageWidget = Image.memory(
            bytes,
            width: 50,
            height: 75,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              width: 50,
              height: 75,
              color: Colors.grey,
              child: const Icon(Icons.book),
            ),
          );
        } catch (e) {
          imageWidget = Container(
            width: 50,
            height: 75,
            color: Colors.grey,
            child: const Icon(Icons.broken_image),
          );
        }
      } else {
        imageWidget = Image.network(
          book.coverUrl!,
          width: 50,
          height: 75,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            width: 50,
            height: 75,
            color: Colors.grey,
            child: const Icon(Icons.book),
          ),
        );
      }
    } else {
      imageWidget = Container(
        width: 50,
        height: 75,
        color: Colors.grey,
        child: const Icon(Icons.book),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      child: ListTile(
        contentPadding: const EdgeInsets.all(8),
        title: Text(
          book.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(book.author),
            if (isStandardEbook)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Standard Ebooks',
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
          ],
        ),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: imageWidget,
        ),
        trailing: book.downloadUrl != null
            ? IconButton(
                icon: const Icon(Icons.download),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => DownloadSplashScreen(book: book),
                      fullscreenDialog: true,
                    ),
                  );
                },
              )
            : null,
      ),
    );
  }
}
