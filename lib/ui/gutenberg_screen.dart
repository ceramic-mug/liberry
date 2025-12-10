import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'gutendex_book_list_screen.dart';

import '../data/local/author_data.dart';

class GutenbergScreen extends ConsumerStatefulWidget {
  const GutenbergScreen({super.key});

  @override
  ConsumerState<GutenbergScreen> createState() => _GutenbergScreenState();
}

class _GutenbergScreenState extends ConsumerState<GutenbergScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  String? _selectedLetter;

  // Curated Collections (User Requested)
  final List<String> _subjects = [
    'Animals',
    'Children',
    'Countries',
    'Crime',
    'Education',
    'Fiction',
    'History',
    'Law',
    'Music',
    'Periodicals',
    'Psychology',
    'Religion',
    'Science',
    'Technology',
    'Wars',
  ];

  // _authors is now replaced by AuthorData.authors
  // We use a getter to filter
  List<String> _getFilteredAuthors() {
    if (_selectedLetter == null) {
      return AuthorData.authors;
    }
    return AuthorData.authors
        .where((author) => author.toUpperCase().startsWith(_selectedLetter!))
        .toList();
  }

  Widget _buildFilterChip(String label, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            if (label == 'All') {
              _selectedLetter = null;
            } else {
              _selectedLetter = label;
            }
          });
        },
        selectedColor: Theme.of(context).colorScheme.primaryContainer,
        checkmarkColor: Theme.of(context).colorScheme.primary,
        labelStyle: TextStyle(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {}); // Rebuild to toggle FAB visibility
    });
  }

  void _navigateToSubject(String subject) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GutendexBookListScreen(
          title: subject,
          topic: subject.toLowerCase(),
        ),
      ),
    );
  }

  void _navigateToAuthor(String author) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            GutendexBookListScreen(title: author, searchQuery: author),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Project Gutenberg'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Random'),
            Tab(text: 'Subjects'),
            Tab(text: 'Authors'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Random (with Reshuffle)
          // We need a key to reload the catalog
          GutendexBookListScreen(
            key: ValueKey('random_$_randomKey'),
            title: 'Random Books',
            sort: 'random',
          ),

          // Subjects
          _buildGridList(_subjects, (subject) => _navigateToSubject(subject)),

          // Authors (with Search)
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search authors...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                  ),
                  onSubmitted: (value) {
                    if (value.isNotEmpty) {
                      _navigateToAuthor(value);
                    }
                  },
                ),
              ),
              // A-Z Filter
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    _buildFilterChip('All', _selectedLetter == null),
                    ...List.generate(26, (index) {
                      final letter = String.fromCharCode(65 + index);
                      return _buildFilterChip(
                        letter,
                        _selectedLetter == letter,
                      );
                    }),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _selectedLetter == null
                        ? 'Popular Authors'
                        : 'Authors starting with $_selectedLetter',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _buildGridList(
                  _getFilteredAuthors(), // Use the filtered list
                  (author) => _navigateToAuthor(author),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: () {
                setState(() {
                  _randomKey++;
                });
              },
              label: const Text('Reshuffle'),
              icon: const Icon(Icons.casino),
            )
          : null,
    );
  }

  int _randomKey = 0;

  Widget _buildGridList(List<String> items, Function(String) onTap) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.5,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          elevation: 0,
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onTap(item),
            child: Center(
              child: Text(
                item,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },
    );
  }
}
