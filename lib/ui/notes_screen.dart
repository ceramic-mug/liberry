import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../data/book_repository.dart'; // For filters
import '../data/database.dart';
import '../providers.dart';
import 'highlights_screen.dart'; // Will refactor to HighlightsTab
import 'character_library.dart'; // Will refactor to CharactersTab
import 'widgets/link_note_dialog.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  // Feature: Filter by Book or Author
  // Unlike Library (Status), Notes filters are dynamic (Book ID / Author Name).
  String? _selectedBookId;
  String? _selectedAuthor;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _isSearching
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _isSearching = false;
                    _searchQuery = '';
                    _searchController.clear();
                  });
                },
              )
            : null,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search notes...',
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
                  const Text('Notes'),
                ],
              ),
        centerTitle: false,
        titleSpacing: _isSearching ? 0 : 16,
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
            PopupMenuButton(
              icon: const Icon(Icons.tune),
              tooltip: 'Options',
              itemBuilder: (context) => [
                PopupMenuItem(
                  child: ListTile(
                    leading: const Icon(Icons.search),
                    title: const Text('Search'),
                    contentPadding: EdgeInsets.zero,
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _isSearching = true;
                      });
                    },
                  ),
                ),
                PopupMenuItem(
                  child: ListTile(
                    leading: Icon(
                      Icons.filter_list,
                      color:
                          (_selectedBookId != null || _selectedAuthor != null)
                          ? Theme.of(context).primaryColor
                          : null,
                    ),
                    title: const Text('Filter'),
                    contentPadding: EdgeInsets.zero,
                    onTap: () {
                      Navigator.pop(context);
                      _showFilterDialog();
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
        bottom: _isSearching
            ? null
            : TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Highlights'),
                  Tab(text: 'Characters'),
                  Tab(text: 'Journal'),
                ],
              ),
      ),
      body: Column(
        children: [
          // Search and Filter Bar removed (moved to AppBar)
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                HighlightsTab(
                  searchQuery: _searchQuery,
                  bookId: _selectedBookId,
                  author: _selectedAuthor,
                ),
                CharactersTab(
                  searchQuery: _searchQuery,
                  bookId: _selectedBookId,
                  author: _selectedAuthor,
                ),
                JournalTab(
                  searchQuery: _searchQuery,
                  bookId: _selectedBookId,
                  author: _selectedAuthor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterDialog() {
    final bookRepo = ref.read(bookRepositoryProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.5,
              minChildSize: 0.3,
              maxChildSize: 0.9,
              builder: (context, scrollController) => Column(
                children: [
                  AppBar(
                    title: const Text('Filter Notes'),
                    leading: const CloseButton(),
                    actions: [
                      TextButton(
                        onPressed: () {
                          // Clear filters
                          setState(() {
                            _selectedBookId = null;
                            _selectedAuthor = null;
                          });
                          setModalState(() {}); // Refresh modal UI
                        },
                        child: const Text('Clear All'),
                      ),
                    ],
                  ),
                  Expanded(
                    child: StreamBuilder<List<Book>>(
                      stream: bookRepo.watchAllBooks(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final books = snapshot.data!;
                        final authors = books
                            .map((b) => b.author)
                            .where((a) => a != null)
                            .toSet()
                            .cast<String>()
                            .toList();
                        authors.sort();

                        return ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          children: [
                            const Text(
                              'By Book',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: books.map((book) {
                                final isSelected = _selectedBookId == book.id;
                                return FilterChip(
                                  label: Text(book.title),
                                  selected: isSelected,
                                  onSelected: (selected) {
                                    setState(() {
                                      _selectedBookId = selected
                                          ? book.id
                                          : null;
                                    });
                                    setModalState(() {});
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'By Author',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: authors.map((author) {
                                final isSelected = _selectedAuthor == author;
                                return FilterChip(
                                  label: Text(author),
                                  selected: isSelected,
                                  onSelected: (selected) {
                                    setState(() {
                                      _selectedAuthor = selected
                                          ? author
                                          : null;
                                    });
                                    setModalState(() {});
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class JournalTab extends ConsumerWidget {
  final String searchQuery;
  final String? bookId;
  final String? author;

  const JournalTab({
    super.key,
    required this.searchQuery,
    this.bookId,
    this.author,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookRepo = ref.watch(bookRepositoryProvider);
    // Observe all notes
    final notesStream = bookRepo.watchAllNotes();
    // Start observing books to filter by author if needed
    final booksStream = bookRepo.watchAllBooks();

    return StreamBuilder<List<BookNote>>(
      stream: notesStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        var notes = snapshot.data!;

        return StreamBuilder<List<Book>>(
          stream: booksStream,
          builder: (context, bookSnapshot) {
            if (!bookSnapshot.hasData) return const SizedBox();
            final books = bookSnapshot.data!;
            final bookMap = {for (var b in books) b.id: b};

            // Filter
            if (bookId != null) {
              notes = notes.where((n) => n.bookId == bookId).toList();
            }

            if (author != null) {
              notes = notes.where((n) {
                final book = bookMap[n.bookId];
                return book?.author == author;
              }).toList();
            }

            if (searchQuery.isNotEmpty) {
              final q = searchQuery.toLowerCase();
              notes = notes.where((n) {
                final contentMatch = n.content.toLowerCase().contains(q);
                // Also match book title if possible
                final book = bookMap[n.bookId];
                final titleMatch =
                    book?.title.toLowerCase().contains(q) ?? false;
                return contentMatch || titleMatch;
              }).toList();
            }

            if (notes.isEmpty) {
              return const Center(child: Text('No journal entries found.'));
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: notes.length,
              itemBuilder: (context, index) {
                final note = notes[index];
                final book = bookMap[note.bookId];
                final isLinked = note.quoteId != null;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (book != null)
                              Expanded(
                                child: Text(
                                  book.title,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: Theme.of(context).primaryColor,
                                      ),
                                ),
                              ),
                            IconButton(
                              icon: Icon(
                                isLinked
                                    ? Icons.highlight
                                    : Icons
                                          .highlight_alt, // or just Icons.highlight for both with different color?
                                // User asked for "highlighter icon".
                                // Icons.highlight is standard. Icons.border_color is sometimes used.
                                // Let's use Icons.highlight.
                                color: isLinked
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey,
                              ),
                              tooltip: isLinked
                                  ? 'Linked to highlight'
                                  : 'Link to highlight',
                              onPressed: () {
                                if (isLinked) {
                                  // Ask to unlink
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Unlink Highlight?'),
                                      content: const Text(
                                        'Do you want to unlink this journal entry from the highlight?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () async {
                                            Navigator.pop(context);
                                            await ref
                                                .read(bookRepositoryProvider)
                                                .updateNoteQuote(note.id, null);
                                          },
                                          child: const Text('Unlink'),
                                        ),
                                      ],
                                    ),
                                  );
                                } else {
                                  if (book != null) {
                                    showDialog(
                                      context: context,
                                      builder: (context) => LinkNoteDialog(
                                        bookId: book.id,
                                        note: note,
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                        // Small spacing
                        const SizedBox(height: 0),
                        Text(
                          note.content,
                          style: const TextStyle(fontSize: 15),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Text(
                            // Using a simple date format directly if intl is not imported in this scope,
                            // but likely it is available or we can use substring.
                            // Assuming Intl is available or using simple toString for safety if unsure.
                            // Actually `intl` is not imported in original snippet, so I should be careful.
                            // I'll assume I can add valid import or just use simple string.
                            // Ideally imports are added.
                            note.createdAt.toString().split('.')[0],
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
