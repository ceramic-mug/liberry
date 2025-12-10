import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/remote/opds_models.dart';
import '../data/remote/remote_book.dart';
import '../providers.dart';
import 'discover_screen.dart'; // For RemoteBookTile

enum SortBy { title, author }

class OpdsCatalogScreen extends ConsumerStatefulWidget {
  final String title;
  final String? initialUrl;
  final OpdsEntryKind initialViewType;
  final bool showStandardEbooksTabs;
  // New params
  final bool showAppBar;
  final WidgetBuilder? headerBuilder;

  const OpdsCatalogScreen({
    super.key,
    required this.title,
    this.initialUrl,
    this.initialViewType = OpdsEntryKind.navigation,
    this.showStandardEbooksTabs = false,
    this.showAppBar = true,
    this.headerBuilder,
  });

  @override
  ConsumerState<OpdsCatalogScreen> createState() => _OpdsCatalogScreenState();
}

class _OpdsCatalogScreenState extends ConsumerState<OpdsCatalogScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Cache for feeds
  OpdsFeed? _subjectsFeed;
  OpdsFeed? _authorsFeed;
  OpdsFeed? _currentFeed;
  bool _isLoading = true;
  String? _error;

  // Filter & Sort State
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  SortBy _sortBy = SortBy.title; // Default sort by title
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.showStandardEbooksTabs) {
      _tabController = TabController(length: 2, vsync: this);
      _loadStandardEbooksRootFeeds();
    } else {
      _tabController = TabController(length: 1, vsync: this);
      if (widget.initialUrl != null) {
        _loadFeed(widget.initialUrl!);
      } else {
        _isLoading = false;
        _error = "No URL provided";
      }
    }
  }

  // Allow Parent to reload by key if needed, or we just expose a method
  void reload() {
    if (widget.initialUrl != null && !widget.showStandardEbooksTabs) {
      _loadFeed(widget.initialUrl!);
    }
  }

  Future<void> _loadFeed(String url) async {
    setState(() {
      _isLoading = true;
      _currentFeed = null;
      _error = null;
    });

    try {
      final feed = await ref.read(opdsServiceProvider).fetchFeed(url);
      if (mounted) {
        setState(() {
          _currentFeed = feed;
          _isLoading = false;
          // Scroll to top on new feed load (pagination)
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(0);
          }
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

  Future<void> _loadStandardEbooksRootFeeds() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final service = ref.read(opdsServiceProvider);
      final subjects = await service.fetchSubjects();
      final authors = await service.fetchAuthors();

      if (mounted) {
        setState(() {
          _subjectsFeed = subjects;
          _authorsFeed = authors;
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

  List<OpdsEntry> _getFilteredAndSortedEntries(List<OpdsEntry> entries) {
    // 1. Filter
    var filtered = entries;
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = entries.where((entry) {
        final titleMatch = entry.title.toLowerCase().contains(query);
        bool authorMatch = false;
        if (entry is OpdsAcquisitionEntry) {
          authorMatch = entry.author.toLowerCase().contains(query);
        }
        // Check content for nav entries as it might contain author
        if (entry is OpdsNavigationEntry) {
          authorMatch = entry.content.toLowerCase().contains(query);
        }
        return titleMatch || authorMatch;
      }).toList();
    }

    // 2. Sort
    filtered.sort((a, b) {
      switch (_sortBy) {
        case SortBy.title:
          return a.title.compareTo(b.title);
        case SortBy.author:
          String authorA = '';
          String authorB = '';
          if (a is OpdsAcquisitionEntry) authorA = a.author;
          if (b is OpdsAcquisitionEntry) authorB = b.author;
          if (a is OpdsNavigationEntry) authorA = a.content;
          if (b is OpdsNavigationEntry) authorB = b.content;

          final authorComp = authorA.compareTo(authorB);
          if (authorComp != 0) return authorComp;
          return a.title.compareTo(b.title);
      }
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showStandardEbooksTabs) {
      // Standard Ebooks Mode
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [_buildSortButton()],
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Subjects'),
              Tab(text: 'Authors'),
            ],
          ),
        ),
        body: Column(
          children: [
            _buildSearchBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildFeedView(_subjectsFeed),
                  _buildFeedView(_authorsFeed),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Generic Mode
    final content = Column(
      children: [
        if (widget.headerBuilder != null) widget.headerBuilder!(context),
        _buildSearchBar(),
        Expanded(child: _buildFeedView(_currentFeed)),
      ],
    );

    if (widget.showAppBar) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [_buildSortButton()],
        ),
        body: content,
      );
    } else {
      // No AppBar, just return content (useful for embedding in Tabs)
      return content;
    }
  }

  Widget _buildSortButton() {
    return PopupMenuButton<SortBy>(
      icon: const Icon(Icons.sort),
      onSelected: (SortBy result) {
        setState(() {
          _sortBy = result;
        });
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<SortBy>>[
        const PopupMenuItem<SortBy>(
          value: SortBy.title,
          child: Text('Sort by Title'),
        ),
        const PopupMenuItem<SortBy>(
          value: SortBy.author,
          child: Text('Sort by Author'),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Filter list...',
          prefixIcon: const Icon(Icons.filter_list),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 0,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                    });
                  },
                )
              : null,
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
      ),
    );
  }

  Widget _buildFeedView(OpdsFeed? feed) {
    if (_isLoading && feed == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && feed == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                if (widget.showStandardEbooksTabs) {
                  _loadStandardEbooksRootFeeds();
                } else if (widget.initialUrl != null) {
                  _loadFeed(widget.initialUrl!);
                }
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (feed == null) {
      return const SizedBox.shrink();
    }

    // Apply filtering and sorting
    final processedEntries = _getFilteredAndSortedEntries(feed.entries);

    // Separate "Filter" entries (Gutenberg specific) from "Book" entries
    final filterEntries = <OpdsEntry>[];
    final bookEntries = <OpdsEntry>[];

    for (var entry in processedEntries) {
      if (['Authors', 'Bookshelves', 'Subjects'].contains(entry.title)) {
        filterEntries.add(entry);
      } else {
        bookEntries.add(entry);
      }
    }

    if (processedEntries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text('No entries found.'),
        ),
      );
    }

    // Check for "Single Book Detail" feed pattern (common in Gutenberg leaf nodes)
    if (bookEntries.length == 1 &&
        bookEntries.first is OpdsAcquisitionEntry &&
        widget.title != 'Search Results') {
      return _buildDetailView(bookEntries.first as OpdsAcquisitionEntry);
    }

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        if (filterEntries.isNotEmpty)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 120, // Height for the filter row
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                scrollDirection: Axis.horizontal,
                itemCount: filterEntries.length,
                itemBuilder: (context, index) {
                  final entry = filterEntries[index];
                  // Render as a smaller distinct card/tile
                  OpdsNavigationEntry? navEntry;
                  if (entry is OpdsNavigationEntry) navEntry = entry;

                  return Card(
                    margin: const EdgeInsets.only(right: 12),
                    elevation: 2,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        if (navEntry != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => OpdsCatalogScreen(
                                title: entry.title,
                                initialUrl: navEntry!.link,
                              ),
                            ),
                          );
                        }
                      },
                      child: Container(
                        width: 140,
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (navEntry?.thumbnail != null)
                              Expanded(
                                child: Image.network(
                                  navEntry!.thumbnail!,
                                  fit: BoxFit.contain,
                                ),
                              )
                            else
                              const Icon(Icons.list_alt, size: 32),
                            const SizedBox(height: 8),
                            Text(
                              entry.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

        SliverPadding(
          padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              if (index == bookEntries.length) {
                // Next page button logic
                if (feed.nextLink != null) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: ElevatedButton(
                      onPressed: () {
                        _loadFeed(feed.nextLink!);
                      },
                      child: const Text('Next Page'),
                    ),
                  );
                } else {
                  return const SizedBox.shrink();
                }
              }

              final entry = bookEntries[index];

              if (entry is OpdsNavigationEntry) {
                // Gutenberg structure: Navigation entries pointing to /ebooks/ID are books.
                // Render as Book Tile if it has a thumbnail OR if it looks like a book pointer.
                final isGutenbergBook = entry.link.contains('/ebooks/');

                if (entry.thumbnail != null || isGutenbergBook) {
                  final mockBook = RemoteBook(
                    title: entry.title,
                    author: entry.content,
                    coverUrl: entry.thumbnail,
                    downloadUrl: null,
                    source: 'Project Gutenberg',
                  );

                  return GestureDetector(
                    onTap: () {
                      // For Random feed, these are "Deep Links" to book details
                      // We can try to fetch the detail view directly or use the smart detail view logic
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => OpdsCatalogScreen(
                            title: entry.title,
                            initialUrl: entry.link,
                          ),
                        ),
                      );
                    },
                    child: AbsorbPointer(
                      child: RemoteBookTile(
                        book: mockBook,
                        isStandardEbook: false,
                      ),
                    ),
                  );
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 0,
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                  child: ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(entry.title),
                    subtitle:
                        (entry.content.isNotEmpty &&
                            !entry.content.contains('Standard Ebooks'))
                        ? Text(
                            entry.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          )
                        : null,
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => OpdsCatalogScreen(
                            title: entry.title,
                            initialUrl: entry.link,
                          ),
                        ),
                      );
                    },
                  ),
                );
              } else if (entry is OpdsAcquisitionEntry) {
                return RemoteBookTile(
                  book: entry.toRemoteBook(),
                  isStandardEbook:
                      entry.epubUrl?.contains('standardebooks') ?? false,
                );
              }
              return const SizedBox.shrink();
            }, childCount: bookEntries.length + (feed.nextLink != null ? 1 : 0)),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailView(OpdsAcquisitionEntry book) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Cover
          Container(
            width: 150,
            height: 225,
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: book.coverUrl != null || book.thumbnail != null
                  ? Image.network(
                      book.coverUrl ?? book.thumbnail!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey,
                        child: const Icon(Icons.book, size: 50),
                      ),
                    )
                  : Container(
                      color: Colors.grey,
                      child: const Icon(Icons.book, size: 50),
                    ),
            ),
          ),
          const SizedBox(height: 24),

          // Title & Author
          Text(
            book.title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            book.author,
            style: TextStyle(
              fontSize: 18,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // Download Actions
          if (book.epubBestUrl != null || book.epubUrl != null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.download),
                label: const Text('Download EPUB'),
                onPressed: () async {
                  final url = book.epubBestUrl ?? book.epubUrl;
                  if (url == null) return;

                  try {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Downloading...')),
                    );

                    await ref
                        .read(downloadManagerProvider)
                        .downloadBook(
                          url,
                          book.title,
                          coverUrl: book.coverUrl ?? book.thumbnail,
                        );

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Download complete!')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Download failed: $e')),
                      );
                    }
                  }
                },
              ),
            ),

          const SizedBox(height: 24),

          // Description
          if (book.summary != null) ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Description',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
            const SizedBox(height: 8),
            Text(book.summary!, style: const TextStyle(height: 1.5)),
          ],
        ],
      ),
    );
  }
}
