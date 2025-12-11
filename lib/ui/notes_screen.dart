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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
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
    final bookRepo = ref.watch(bookRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            SvgPicture.asset('assets/icon.svg', height: 24),
            const SizedBox(width: 8),
            const Text('Notes'),
          ],
        ),
        bottom: TabBar(
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
          // Search and Filter Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search...',
                    filled: true,
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
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
                const SizedBox(height: 12),
                StreamBuilder<List<Book>>(
                  stream: bookRepo.watchAllBooks(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox.shrink();
                    final books = snapshot.data!;
                    final authors = books
                        .map((b) => b.author)
                        .where((a) => a != null)
                        .toSet() // Unique
                        .cast<String>()
                        .toList();
                    authors.sort();

                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          // Book Filter
                          _buildFilterChip<String>(
                            label: 'Book',
                            value: _selectedBookId,
                            items: books,
                            itemLabel: (b) => b.title,
                            itemValue: (b) => b.id,
                            onChanged: (val) {
                              setState(() {
                                _selectedBookId = val;
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          // Author Filter
                          _buildFilterChip<String>(
                            label: 'Author',
                            value: _selectedAuthor,
                            items: authors,
                            itemLabel: (a) => a,
                            itemValue: (a) => a,
                            onChanged: (val) {
                              setState(() {
                                _selectedAuthor = val;
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
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

  Widget _buildFilterChip<T>({
    required String label,
    required T? value,
    required List<dynamic> items,
    required String Function(dynamic) itemLabel,
    required T Function(dynamic) itemValue,
    required ValueChanged<T?> onChanged,
  }) {
    // If a value is selected, show a FilterChip that can be cleared
    if (value != null) {
      // Find the label for the selected value
      String displayLabel = label;
      try {
        final selectedItem = items.firstWhere(
          (i) => itemValue(i) == value,
          orElse: () => null,
        );
        if (selectedItem != null) {
          displayLabel = itemLabel(selectedItem);
        }
      } catch (e) {
        // ignore
      }

      return FilterChip(
        label: Text(
          displayLabel,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        selected: true,
        onSelected: (bool selected) {
          if (!selected) onChanged(null); // Clear filter
        },
        onDeleted: () => onChanged(null),
      );
    }

    // Otherwise show an ActionChip that opens a selector
    return ActionChip(
      avatar: const Icon(Icons.filter_list, size: 16),
      label: Text(label),
      onPressed: () async {
        final result = await showModalBottomSheet<T>(
          context: context,
          builder: (context) => ListView.builder(
            itemCount: items.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return ListTile(
                  title: Text(
                    'All ${label}s',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onTap: () => Navigator.pop(context, null),
                );
              }
              final item = items[index - 1];
              return ListTile(
                title: Text(itemLabel(item)),
                onTap: () => Navigator.pop(context, itemValue(item)),
              );
            },
          ),
        );
        if (result != null) {
          onChanged(result);
        }
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
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
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
                        const SizedBox(height: 4),
                        Text(
                          note.content,
                          style: const TextStyle(fontSize: 15),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
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
