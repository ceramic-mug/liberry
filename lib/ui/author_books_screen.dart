import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/remote/remote_book.dart';
import '../providers.dart';
import 'common/remote_book_tile.dart';

class AuthorBooksScreen extends ConsumerStatefulWidget {
  final String authorName;

  const AuthorBooksScreen({super.key, required this.authorName});

  @override
  ConsumerState<AuthorBooksScreen> createState() => _AuthorBooksScreenState();
}

class _AuthorBooksScreenState extends ConsumerState<AuthorBooksScreen> {
  bool _isLoading = true;
  List<RemoteBook> _books = [];

  @override
  void initState() {
    super.initState();
    _loadAuthorBooks();
  }

  Future<void> _loadAuthorBooks() async {
    try {
      final service = ref.read(offlineGutenbergServiceProvider);
      // reusing searchBooks for now as it provides FTS
      final results = await service.searchBooks(widget.authorName);

      final books = results.map((data) {
        final id = data['id'] as int;
        return RemoteBook(
          title: data['title'] as String,
          author: data['author'] as String,
          coverUrl:
              "https://www.gutenberg.org/cache/epub/$id/pg$id.cover.medium.jpg",
          downloadUrl: "https://www.gutenberg.org/ebooks/$id.epub.images",
          source: 'Project Gutenberg',
        );
      }).toList();

      if (mounted) {
        setState(() {
          _books = books;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      print("Error loading author books: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final localBookMap = ref.watch(localBookMapProvider);

    return Scaffold(
      appBar: AppBar(title: Text(widget.authorName)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _books.isEmpty
          ? Center(child: Text('No books found for "${widget.authorName}"'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _books.length,
              itemBuilder: (context, index) {
                return RemoteBookTile(
                  book: _books[index],
                  isStandardEbook: false,
                  localBookMap: localBookMap,
                );
              },
            ),
    );
  }
}
