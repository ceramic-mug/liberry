import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/remote/opds_models.dart';
import '../providers.dart';
import 'discover_screen.dart'; // For RemoteBookTile

enum SortBy { title, author }

class StandardEbooksScreen extends ConsumerStatefulWidget {
  final String title;
  final String? initialUrl;
  final OpdsEntryKind initialViewType;

  const StandardEbooksScreen({
    super.key,
    this.title = 'Standard Ebooks',
    this.initialUrl,
    this.initialViewType = OpdsEntryKind.navigation,
  });

  @override
  ConsumerState<StandardEbooksScreen> createState() =>
      _StandardEbooksScreenState();
}

class _StandardEbooksScreenState extends ConsumerState<StandardEbooksScreen>
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

  @override
  void initState() {
    super.initState();
    // If we have an initial URL, we are in a drill-down view (not the main root)
    if (widget.initialUrl != null) {
      _loadFeed(widget.initialUrl!);
      _tabController = TabController(length: 1, vsync: this);
    } else {
      // Root view has Subjects and Authors tabs
      _tabController = TabController(length: 2, vsync: this);
      _loadRootFeeds();
    }
  }

  Future<void> _loadFeed(String url) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final feed = await ref.read(localEbooksServiceProvider).fetchFeed(url);
      if (mounted) {
        setState(() {
          _currentFeed = feed;
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

  Future<void> _loadRootFeeds() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final service = ref.read(localEbooksServiceProvider);
      // Load both in parallel-ish or just one by one.
      // Actually, we process tabs, so let's load Subjects first as it's the first tab.
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
          // Fallback to title if not books or authors match
          final authorComp = authorA.compareTo(authorB);
          if (authorComp != 0) return authorComp;
          return a.title.compareTo(b.title);
      }
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    // If it's a drill-down view
    if (widget.initialUrl != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [_buildSortButton()],
        ),
        body: Column(
          children: [
            _buildSearchBar(),
            Expanded(child: _buildFeedView(_currentFeed)),
          ],
        ),
      );
    }

    // Root view
    return Scaffold(
      appBar: AppBar(
        title: const Text('Standard Ebooks'),
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
            ElevatedButton(
              onPressed: () {
                if (widget.initialUrl != null) {
                  _loadFeed(widget.initialUrl!);
                } else {
                  _loadRootFeeds();
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

    // Only show "Next Page" if we haven't filtered (paging breaks with filtering usually, or at least makes it confusing)
    // Actually, paging is for the *feed*. Filter is local.
    // If I filter a page, I might want to load next page to find more.
    // But for now, let's keep it simple.

    return ListView.builder(
      padding: const EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 16,
      ), // Top padding handled by Column spacing
      itemCount: processedEntries.length + (feed.nextLink != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == processedEntries.length) {
          // Next page button
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: () {
                // Push next page
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => StandardEbooksScreen(
                      title: feed.title,
                      initialUrl: feed.nextLink,
                    ),
                  ),
                );
              },
              child: const Text('Next Page'),
            ),
          );
        }

        final entry = processedEntries[index];

        if (entry is OpdsNavigationEntry) {
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            elevation: 0,
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
            child: ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(entry.title),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => StandardEbooksScreen(
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
            isStandardEbook: true,
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}
