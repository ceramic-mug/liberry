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

  @override
  Widget build(BuildContext context) {
    final bookRepo = ref.watch(bookRepositoryProvider);
    final booksStream = bookRepo.watchAllBooks();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: _isSearching
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
          titleSpacing: 16,
          actions: [
            if (_isSearching)
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
        body: StreamBuilder<List<Book>>(
          stream: booksStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            var books = snapshot.data!;

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
        return BookItem(book: book);
      },
    );
  }

  Widget _buildBookList(List<Book> books) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        return BookSpineItem(book: book);
      },
    );
  }
}

class BookItem extends ConsumerWidget {
  final Book book;

  const BookItem({super.key, required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BookDetailsScreen(book: book),
          ),
        );
      },
      onLongPress: () {
        _showOptionsDialog(context, ref, book);
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

  const BookSpineItem({super.key, required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BookDetailsScreen(book: book),
          ),
        );
      },
      onLongPress: () {
        _showOptionsDialog(context, ref, book);
      },
      child: Container(
        height: 60, // Fixed height for spine effect
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(
            4,
          ), // Slightly rounded corners like a spine
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
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: const Text(
                  'READ',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ),
            ] else if (book.status == 'reading') ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: const Text(
                  'READING',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
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
