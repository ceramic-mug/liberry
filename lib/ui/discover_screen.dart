import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/remote/remote_book.dart';
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
    _loadStandardEbooks();
  }

  Future<void> _loadStandardEbooks() async {
    try {
      final opdsService = ref.read(opdsServiceProvider);
      final books = await opdsService.fetchNewReleases();
      if (mounted) {
        setState(() {
          _standardEbooks = books;
          _isLoadingStandard = false;
        });
      }
    } catch (e) {
      print('Error loading Standard Ebooks: $e');
      if (mounted) {
        setState(() {
          _isLoadingStandard = false;
        });
      }
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
      final opdsService = ref.read(opdsServiceProvider);
      final books = await opdsService.searchBooks(query);
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

  List<RemoteBook> get _filteredStandardEbooks {
    // If we are searching, _standardEbooks already contains the search results
    // If not searching, it contains new releases
    return _standardEbooks;
  }

  @override
  Widget build(BuildContext context) {
    final filteredStandard = _filteredStandardEbooks;

    return Scaffold(
      appBar: AppBar(title: const Text('Discover Books')),
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
                // Standard Ebooks Section
                if (_isLoadingStandard)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (filteredStandard.isNotEmpty) ...[
                  _buildSectionHeader(
                    'Standard Ebooks',
                    'High quality, carefully formatted',
                  ),
                  ...filteredStandard.map(
                    (book) => RemoteBookTile(book: book, isStandardEbook: true),
                  ),
                  const SizedBox(height: 24),
                ],

                // Gutenberg Section
                if (_searchQuery.isNotEmpty) ...[
                  _buildSectionHeader(
                    'Project Gutenberg',
                    'Vast library of free ebooks',
                  ),
                  if (_isSearchingGutenberg)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_gutenbergBooks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('No results found on Project Gutenberg.'),
                    )
                  else
                    ..._gutenbergBooks.map(
                      (book) =>
                          RemoteBookTile(book: book, isStandardEbook: false),
                    ),
                ] else if (!_isLoadingStandard && filteredStandard.isEmpty) ...[
                  const Center(child: Text('Search to find books.')),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
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
          child: book.coverUrl != null
              ? Image.network(
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
                )
              : Container(
                  width: 50,
                  height: 75,
                  color: Colors.grey,
                  child: const Icon(Icons.book),
                ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.download),
          onPressed: () async {
            if (book.downloadUrl == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No download link available.')),
              );
              return;
            }

            try {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Downloading...')));

              await ref
                  .read(downloadManagerProvider)
                  .downloadBook(
                    book.downloadUrl!,
                    book.title,
                    coverUrl: book.coverUrl,
                  );

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Download complete!')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
              }
            }
          },
        ),
      ),
    );
  }
}
