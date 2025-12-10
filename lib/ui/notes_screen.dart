import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../data/book_repository.dart'; // For filters
import '../data/database.dart';
import '../providers.dart';
import 'highlights_screen.dart'; // Will refactor to HighlightsTab
import 'character_library.dart'; // Will refactor to CharactersTab

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
    _tabController = TabController(length: 2, vsync: this);
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
        // If result is null, it might be dismissal or "All".
        // To distinguish, we can just assume if they picked specific item it returns T.
        // If they tapped "All", we pass 'null' conceptually but effectively we want to clear.
        // Simplest is: if result is passed (even null), we update.
        // But showModalBottomSheet returns null on dismissal.
        // So we might need a distinct "clear" object or check logic.
        // For now, let's assume they pick something or cancel.
        // Let's rely on the "onDeleted" of the active chip for clearing,
        // but here we just select.
        if (result != null) {
          onChanged(result);
        }
      },
    );
  }
}
