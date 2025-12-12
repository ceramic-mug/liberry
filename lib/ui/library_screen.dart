import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import '../providers.dart';
import 'book_details_screen.dart';

enum SortOption { title, author, dateAdded, rating }

class LibraryScreen extends ConsumerStatefulWidget {
  final VoidCallback onNavigateToDiscover;

  const LibraryScreen({super.key, required this.onNavigateToDiscover});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _searchQuery = '';
  bool _isSearching = false;
  SortOption _sortOption = SortOption.dateAdded;
  final TextEditingController _searchController = TextEditingController();
  Set<String> _statusFilters = {};
  final Set<String> _selectedBookIds = {};

  bool get _isSelectionMode => _selectedBookIds.isNotEmpty;

  void _toggleSelection(Book book) {
    setState(() {
      if (_selectedBookIds.contains(book.id)) {
        _selectedBookIds.remove(book.id);
      } else {
        _selectedBookIds.add(book.id);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedBookIds.clear();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Book> _sortBooks(List<Book> books) {
    switch (_sortOption) {
      case SortOption.title:
        return books..sort((a, b) => a.title.compareTo(b.title));
      case SortOption.author:
        return books
          ..sort((a, b) => (a.author ?? '').compareTo(b.author ?? ''));
      case SortOption.rating:
        return books..sort((a, b) {
          final ratingA = a.rating ?? 0;
          final ratingB = b.rating ?? 0;
          return ratingB.compareTo(ratingA); // Descending (5 -> 0)
        });
      case SortOption.dateAdded:
      default:
        return books..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    }
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Filter by Status',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('Not Started'),
                          selected: _statusFilters.contains('not_started'),
                          onSelected: (selected) {
                            setModalState(() {
                              setState(() {
                                if (selected) {
                                  _statusFilters.add('not_started');
                                } else {
                                  _statusFilters.remove('not_started');
                                }
                              });
                            });
                          },
                        ),
                        FilterChip(
                          label: const Text('Reading'),
                          selected: _statusFilters.contains('reading'),
                          onSelected: (selected) {
                            setModalState(() {
                              setState(() {
                                if (selected) {
                                  _statusFilters.add('reading');
                                } else {
                                  _statusFilters.remove('reading');
                                }
                              });
                            });
                          },
                        ),
                        FilterChip(
                          label: const Text('Read'),
                          selected: _statusFilters.contains('read'),
                          onSelected: (selected) {
                            setModalState(() {
                              setState(() {
                                if (selected) {
                                  _statusFilters.add('read');
                                } else {
                                  _statusFilters.remove('read');
                                }
                              });
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _statusFilters.clear();
                            });
                            Navigator.pop(context);
                          },
                          child: const Text('Clear All'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final booksAsyncValue = ref.watch(allBooksProvider);
    final booksList = booksAsyncValue.asData?.value ?? [];
    final downloadableCount = booksList
        .where(
          (b) =>
              _selectedBookIds.contains(b.id) &&
              !b.isDownloaded &&
              b.downloadUrl != null,
        )
        .length;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: _isSelectionMode
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _clearSelection,
                )
              : null,
          title: _isSelectionMode
              ? Text('${_selectedBookIds.length} selected')
              : _isSearching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search title, author...',
                    border: InputBorder.none,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                )
              : Row(
                  children: [
                    SvgPicture.asset('assets/icon.svg', height: 24),
                    const SizedBox(width: 8),
                    const Text('Library'),
                  ],
                ),
          centerTitle: false,
          titleSpacing: _isSelectionMode ? 0 : 16,
          actions: [
            if (_isSelectionMode) ...[
              if (downloadableCount > 0)
                IconButton(
                  icon: const Icon(Icons.cloud_download),
                  tooltip: 'Download Selected',
                  onPressed: _confirmDownloadSelected,
                ),
              IconButton(
                icon: const Icon(Icons.swap_horiz),
                tooltip: 'Move Selected',
                onPressed: _showMoveOptions,
              ),
              IconButton(
                icon: const Icon(Icons.cloud_off),
                tooltip: 'Offload',
                onPressed: _confirmOffloadSelected,
              ),
              IconButton(
                icon: const Icon(Icons.delete),
                tooltip: 'Delete',
                onPressed: _confirmDeleteSelected,
              ),
            ] else if (_isSearching)
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _isSearching = false;
                    _searchQuery = '';
                    _searchController.clear();
                  });
                },
              )
            else ...[
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () {
                  setState(() {
                    _isSearching = true;
                  });
                },
              ),
              IconButton(
                icon: Icon(
                  Icons.filter_list,
                  color: _statusFilters.isNotEmpty
                      ? Theme.of(context).primaryColor
                      : null,
                ),
                onPressed: _showFilterDialog,
              ),
              PopupMenuButton<SortOption>(
                icon: const Icon(Icons.sort),
                onSelected: (SortOption result) =>
                    setState(() => _sortOption = result),
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<SortOption>>[
                      const PopupMenuItem<SortOption>(
                        value: SortOption.title,
                        child: Text('Title'),
                      ),
                      const PopupMenuItem<SortOption>(
                        value: SortOption.author,
                        child: Text('Author'),
                      ),
                      const PopupMenuItem<SortOption>(
                        value: SortOption.dateAdded,
                        child: Text('Date Added'),
                      ),
                      const PopupMenuItem<SortOption>(
                        value: SortOption.rating,
                        child: Text('Rating'),
                      ),
                    ],
              ),
            ],
          ],
          bottom: _isSearching
              ? null
              : const TabBar(
                  tabs: [
                    Tab(text: 'Desk'),
                    Tab(text: 'Bookshelf'),
                  ],
                ),
        ),
        body: booksAsyncValue.when(
          data: (allBooks) {
            var books = allBooks;

            // 0. Filter by Status (Global)
            if (_statusFilters.isNotEmpty) {
              books = books.where((b) {
                // If filtering by 'read', also check legacy isRead
                if (_statusFilters.contains('read') &&
                    (b.status == 'read' || b.isRead)) {
                  return true;
                }
                return _statusFilters.contains(b.status);
              }).toList();
            }

            // 1. Search Mode
            if (_isSearching) {
              if (_searchQuery.isNotEmpty) {
                final query = _searchQuery.toLowerCase();
                books = books.where((b) {
                  return b.title.toLowerCase().contains(query) ||
                      (b.author?.toLowerCase().contains(query) ?? false);
                }).toList();
                books = _sortBooks(books);
              }

              if (books.isEmpty) {
                return const Center(child: Text("No results found."));
              }
              return _buildBookGrid(books);
            }

            // 2. Tab Mode
            // Split and Sort
            // Desk: group is 'desk' or legacy 'reading' or null
            final deskBooks = _sortBooks(
              books
                  .where(
                    (b) =>
                        b.group == 'desk' ||
                        b.group == 'reading' ||
                        b.group == null,
                  )
                  .toList(),
            );
            // Bookshelf: group is 'bookshelf' or legacy 'read'
            final bookshelf = _sortBooks(
              books
                  .where((b) => b.group == 'bookshelf' || b.group == 'read')
                  .toList(),
            );

            return TabBarView(
              children: [
                // Desk Tab - Keep as Grid
                deskBooks.isEmpty
                    ? _buildEmptyState("No books on your Desk.")
                    : _buildBookGrid(deskBooks),

                // Bookshelf Tab - Switch to List/Spine view
                bookshelf.isEmpty
                    ? _buildEmptyState("Bookshelf is empty.")
                    : _buildBookList(bookshelf),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) => Center(child: Text('Error: $e')),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: widget.onNavigateToDiscover,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(message, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: widget.onNavigateToDiscover,
            child: const Text('Discover Books'),
          ),
        ],
      ),
    );
  }

  Widget _buildBookGrid(List<Book> books, {ScrollPhysics? startPhysics}) {
    // If physics is NeverScrollable, we need shrinkWrap true
    final isScrollable = startPhysics == null;

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      shrinkWrap: !isScrollable,
      physics: startPhysics,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        childAspectRatio: 0.55,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        return BookItem(
          book: book,
          isSelected: _selectedBookIds.contains(book.id),
          isSelectionMode: _isSelectionMode,
          onToggleSelection: () => _toggleSelection(book),
        );
      },
    );
  }

  Widget _buildBookList(List<Book> books) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        return BookSpineItem(
          book: book,
          isSelected: _selectedBookIds.contains(book.id),
          isSelectionMode: _isSelectionMode,
          onToggleSelection: () => _toggleSelection(book),
        );
      },
    );
  }

  void _showMoveOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.table_restaurant),
                title: const Text('Move to Desk'),
                onTap: () {
                  Navigator.pop(context);
                  _moveSelectedBooks('reading'); // 'reading' is aka Desk
                },
              ),
              ListTile(
                leading: const Icon(Icons.shelves),
                title: const Text('Move to Bookshelf'),
                onTap: () {
                  Navigator.pop(context);
                  _moveSelectedBooks('bookshelf');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _moveSelectedBooks(String group) async {
    final bookRepo = ref.read(bookRepositoryProvider);
    final count = _selectedBookIds.length;
    for (final id in _selectedBookIds) {
      await bookRepo.setBookGroup(id, group);
    }
    _clearSelection();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Moved $count books.')));
    }
  }

  Future<void> _confirmDownloadSelected() async {
    final bookRepo = ref.read(bookRepositoryProvider);
    final selectedBooks =
        (await bookRepo.getAllBooks()) // Inefficient but safe for now
            .where(
              (b) =>
                  _selectedBookIds.contains(b.id) &&
                  !b.isDownloaded &&
                  b.downloadUrl != null,
            )
            .toList();

    if (selectedBooks.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No downloadable books selected.')),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download Selected Books?'),
        content: Text(
          'This will download ${selectedBooks.length} books to your device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Download'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final downloadManager = ref.read(downloadManagerProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Starting download of ${selectedBooks.length} books...',
            ),
          ),
        );
      }
      _clearSelection();

      // Download sequentially to avoid overwhelming
      for (final book in selectedBooks) {
        try {
          await downloadManager.redownloadBook(book.id);
        } catch (e) {
          debugPrint('Failed to download book ${book.id}: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Downloads finished.')));
      }
    }
  }

  Future<void> _confirmOffloadSelected() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Offload Selected Books?'),
        content: Text(
          'This will remove the local files for ${_selectedBookIds.length} books to save space. Metadata will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Offload'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final bookRepo = ref.read(bookRepositoryProvider);
      final count = _selectedBookIds.length;
      for (final id in _selectedBookIds) {
        await bookRepo.offloadBook(id);
      }
      _clearSelection();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Offloaded $count books.')));
      }
    }
  }

  Future<void> _confirmDeleteSelected() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Selected Books?'),
        content: Text(
          'Are you sure you want to completely delete ${_selectedBookIds.length} books? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final bookRepo = ref.read(bookRepositoryProvider);
      final count = _selectedBookIds.length;
      for (final id in _selectedBookIds) {
        await bookRepo.deleteBook(id);
      }
      _clearSelection();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Deleted $count books.')));
      }
    }
  }
}

class BookItem extends ConsumerWidget {
  final Book book;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback? onToggleSelection;

  const BookItem({
    super.key,
    required this.book,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.onToggleSelection,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        if (isSelectionMode) {
          onToggleSelection?.call();
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => BookDetailsScreen(book: book),
            ),
          );
        }
      },
      onLongPress: () {
        if (!isSelectionMode) {
          onToggleSelection?.call();
        } else {
          _showOptionsDialog(context, ref, book);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BookCoverImage(book: book),
                  if (!book.isDownloaded)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.cloud_download,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  if (book.status == 'read' || book.isRead)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  if (book.status == 'reading')
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.9),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.auto_stories,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  if (book.status == 'not_started')
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.9),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.book,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  if (isSelected)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.check_circle,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          if (book.author != null)
            Text(
              book.author!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontSize: 11),
            ),
        ],
      ),
    );
  }
}

class BookSpineItem extends ConsumerWidget {
  final Book book;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback? onToggleSelection;

  const BookSpineItem({
    super.key,
    required this.book,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.onToggleSelection,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        if (isSelectionMode) {
          onToggleSelection?.call();
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => BookDetailsScreen(book: book),
            ),
          );
        }
      },
      onLongPress: () {
        if (!isSelectionMode) {
          onToggleSelection?.call();
        } else {
          _showOptionsDialog(context, ref, book);
        }
      },
      child: Container(
        height: 60, // Fixed height for spine effect
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).primaryColor.withOpacity(0.1)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(4),
          border: Border(
            left: BorderSide(
              color: Theme.of(context).primaryColor.withOpacity(0.5),
              width: 4,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            // Tiny cover preview
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: BookCoverImage(book: book),
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 16),
              Icon(Icons.check_circle, color: Theme.of(context).primaryColor),
            ],
            const SizedBox(width: 16),
            // Title and Author
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (book.author != null)
                    Text(
                      book.author!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(fontSize: 12),
                    ),
                ],
              ),
            ),
            if (book.status == 'read' || book.isRead) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: const Icon(Icons.check, size: 14, color: Colors.white),
              ),
            ] else if (book.status == 'reading') ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.9),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_stories,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ] else if (book.status == 'not_started') ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.9),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: const Icon(Icons.book, size: 14, color: Colors.white),
              ),
            ],
            if (!book.isDownloaded)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.cloud_download, size: 20, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }
}

// Extracted for reuse between Grid and Spine views
class BookCoverImage extends StatelessWidget {
  final Book book;

  const BookCoverImage({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: _resolveCoverPath(book.coverPath),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return book.isDownloaded
              ? Image.file(snapshot.data!, fit: BoxFit.fill)
              : ColorFiltered(
                  colorFilter: const ColorFilter.mode(
                    Colors.grey,
                    BlendMode.saturation,
                  ),
                  child: Image.file(snapshot.data!, fit: BoxFit.fill),
                );
        }
        return Container(
          color: Colors.grey[200],
          child: const Center(child: Icon(Icons.book, color: Colors.grey)),
        );
      },
    );
  }

  Future<File?> _resolveCoverPath(String? path) async {
    if (path == null) return null;
    try {
      final file = File(path);
      if (await file.exists()) return file;

      final docsDir = await getApplicationDocumentsDirectory();
      if (!p.isAbsolute(path)) {
        final fullPath = p.join(docsDir.path, path);
        if (await File(fullPath).exists()) return File(fullPath);
      }
      final filename = p.basename(path);
      final newPath = p.join(docsDir.path, 'covers', filename);
      if (await File(newPath).exists()) return File(newPath);
    } catch (e) {
      return null;
    }
    return null;
  }
}

void _showOptionsDialog(BuildContext context, WidgetRef ref, Book book) {
  showModalBottomSheet(
    context: context,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.shelves),
              title: Text(
                book.group == 'bookshelf'
                    ? 'Move to Desk'
                    : 'Move to Bookshelf',
              ),
              onTap: () {
                Navigator.pop(context);
                ref
                    .read(bookRepositoryProvider)
                    .setBookGroup(
                      book.id,
                      book.group == 'bookshelf' ? 'reading' : 'bookshelf',
                    );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text(
                'Delete Book',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context, ref, book);
              },
            ),
          ],
        ),
      );
    },
  );
}

void _confirmDelete(BuildContext context, WidgetRef ref, Book book) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete Book'),
      content: Text('Are you sure you want to delete "${book.title}"?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            ref.read(bookRepositoryProvider).deleteBook(book.id);
          },
          child: const Text('Delete', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}
