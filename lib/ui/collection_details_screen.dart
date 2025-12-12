import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database.dart'; // For Book
import '../data/book_collections.dart';
import '../data/remote/remote_book.dart';
import '../providers.dart';
import 'common/remote_book_tile.dart';

class CollectionDetailsScreen extends ConsumerStatefulWidget {
  final BookCollection collection;
  final void Function(CollectionBook) onSearch;

  const CollectionDetailsScreen({
    super.key,
    required this.collection,
    required this.onSearch,
  });

  @override
  ConsumerState<CollectionDetailsScreen> createState() =>
      _CollectionDetailsScreenState();
}

class _CollectionDetailsScreenState
    extends ConsumerState<CollectionDetailsScreen> {
  // Map to store resolved books: CollectionBook generic object -> Resolved RemoteBook
  final Map<CollectionBook, RemoteBook> _resolvedBooks = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _resolveBooks();
  }

  String _cleanTitleForSearch(String title) {
    // 1. Remove content within parentheses
    var cleaned = title.replaceAll(
      RegExp(r'\(.*?\)', caseSensitive: false),
      '',
    );

    // 2. Remove subtitle after colon
    if (cleaned.contains(':')) {
      cleaned = cleaned.split(':').first;
    }

    // 3. Replace common punctuation with space to avoid "word1-word2" or "Mr.Smith" issues
    cleaned = cleaned.replaceAll(RegExp(r'[.\-,]'), ' ');

    // 4. Collapse multiple spaces
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');

    return cleaned.trim();
  }

  bool _authorsMatch(String localAuthor, String remoteAuthor) {
    if (localAuthor.isEmpty || remoteAuthor.isEmpty) return false;

    // Normalize: lower case, replace dots/punctuation with SPACE to separate initials
    // e.g. "J.R.R.Tolkien" -> "j r r tolkien"
    final cleanLocal = localAuthor.toLowerCase().replaceAll(
      RegExp(r'[.,]'),
      ' ',
    );
    final cleanRemote = remoteAuthor.toLowerCase().replaceAll(
      RegExp(r'[.,]'),
      ' ',
    );

    // Check basic containment (if one is substring of other after cleaning)
    // Warning: "Poe" is in "Porter"?
    // But we usually have full names.
    if (cleanRemote.contains(cleanLocal.trim()) ||
        cleanLocal.contains(cleanRemote.trim()))
      return true;

    // Tokenize
    // Allow tokens of length 1 only if they are initials?
    // Actually, simply splitting by space and ignoring empty is safest.
    // If we filter too much, we lose "Li Po".
    // "J R R Tolkien" -> J, R, R, Tolkien.
    // "Tolkien, J. R. R." -> Tolkien, J, R, R.
    // Intersection will be 4 items. Matches perfectly.
    // "D.H. Lawrence" -> "d h lawrence".
    // "Lawrence, D. H." -> "lawrence d h".
    // Match.
    // "H. G. Wells" -> "h g wells".
    // "Herbert George Wells" -> "herbert george wells".
    // Intersection: "wells" (1 item).
    // Local size: 3 (h g wells). Remote size: 3.
    // 1 < 3.
    // So "H.G. Wells" would NOT match "Herbert George Wells" if we require FULL subset.
    // But "Wells" is significant.

    final localTokens = cleanLocal
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toSet();
    final remoteTokens = cleanRemote
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toSet();

    if (localTokens.isEmpty || remoteTokens.isEmpty) return false;

    // Robust check:
    // If we have a significant specific name match (length > 3), that's usually good enough for "same book".
    // e.g. "Dostoevsky" is unique enough in the context of "Crime and Punishment".
    // But "Smith" is not.

    final intersection = localTokens.intersection(remoteTokens);

    // If any token with length > 3 matches, we assume match?
    // "John Smith" vs "Jane Smith". Match "Smith". Bad.
    // "Ivan Turgenev" vs "Turgenev". Match "Turgenev". Good.

    // Strict subset check is best for Initials vs Full Name IF we have initials on both sides.
    // But we might have "H.G. Wells" vs "Herbert George Wells".
    // Let's filter out single letters for the "Significant subset" check.

    final localSig = localTokens.where((t) => t.length > 2).toSet();
    final remoteSig = remoteTokens.where((t) => t.length > 2).toSet();
    final intersectSig = intersection.where((t) => t.length > 2).toSet();

    if (localSig.isNotEmpty && remoteSig.isNotEmpty) {
      // If significant parts match reasonably well
      // e.g. "Ivan Turgenev" (sig: Ivan, Turgenev). "Turgenev" (sig: Turgenev).
      // Intersect: Turgenev.
      // It covers all of Remote's significant tokens.
      if (intersectSig.length >= remoteSig.length ||
          intersectSig.length >= localSig.length) {
        return true;
      }
    }

    // Fallback: use all tokens (including initials) logic
    return intersection.length >= localTokens.length ||
        intersection.length >= remoteTokens.length;
  }

  Future<void> _resolveBooks() async {
    final localService = ref.read(localEbooksServiceProvider);
    final offlineGutenbergService = ref.read(offlineGutenbergServiceProvider);

    await Future.wait(
      widget.collection.books.map((book) async {
        try {
          RemoteBook? bestMatch;

          // Use cleaned title for search query to avoid issues with punctuation/subtitles
          final searchTitle = _cleanTitleForSearch(book.title);

          // 1. Try Standard Ebooks first
          // Note: Local search is cheap, we can try exact title first, then cleaned title if needed?
          // Or just cleaned title. Cleaned title is safer for "finding" the book.
          // e.g. "Frankenstein" finds "Frankenstein; Or, The Modern Prometheus" usually.

          var seResults = await localService.searchBooks(searchTitle);
          if (seResults.isEmpty && searchTitle != book.title) {
            // Fallback: try original if cleaned failed (unlikely but possible if regex ate too much)
            seResults = await localService.searchBooks(book.title);
          }

          if (seResults.isNotEmpty) {
            try {
              bestMatch = seResults.firstWhere(
                (remote) => _authorsMatch(book.author, remote.author),
              );
            } catch (e) {
              // No author match
            }
          }

          // 2. Try Offline Gutenberg
          if (bestMatch == null) {
            try {
              // Helper to search and map
              Future<List<RemoteBook>> searchOffline(String q) async {
                final results = await offlineGutenbergService.searchBooks(q);
                return results.map((map) {
                  final id = map['id'] as int;
                  return RemoteBook(
                    title: map['title'] as String,
                    author: map['author'] as String,
                    coverUrl:
                        'https://www.gutenberg.org/cache/epub/$id/pg$id.cover.medium.jpg',
                    downloadUrl:
                        'https://www.gutenberg.org/ebooks/$id.epub.images',
                    source: 'Project Gutenberg',
                  );
                }).toList();
              }

              var pgResults = await searchOffline(searchTitle);
              if (pgResults.isEmpty && searchTitle != book.title) {
                pgResults = await searchOffline(book.title);
              }

              if (pgResults.isNotEmpty) {
                try {
                  bestMatch = pgResults.firstWhere(
                    (remote) => _authorsMatch(book.author, remote.author),
                  );
                } catch (e) {
                  // No specific author match
                }
              }
            } catch (e) {
              // Offline search failed
            }
          }

          if (bestMatch != null && mounted) {
            setState(() {
              _resolvedBooks[book] = bestMatch!;
            });
          }
        } catch (e) {
          // General failure
        }
      }),
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final localBookMap = ref.watch(localBookMapProvider);
    final Map<String, List<CollectionBook>> groupedBooks = {};
    if (widget.collection.books.any((b) => b.group != null)) {
      for (var b in widget.collection.books) {
        final group = b.group ?? 'Other';
        if (!groupedBooks.containsKey(group)) {
          groupedBooks[group] = [];
        }
        groupedBooks[group]!.add(b);
      }
    } else {
      groupedBooks[''] = widget.collection.books;
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.collection.title)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _buildHeader(context),
          if (_isLoading && _resolvedBooks.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: CircularProgressIndicator(),
              ),
            ),

          ...groupedBooks.entries.map((entry) {
            final groupTitle = entry.key;
            final books = entry.value;

            if (groupTitle.isEmpty) {
              return Column(
                children: books
                    .map((b) => _buildBookTile(b, localBookMap))
                    .toList(),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
                  child: Text(
                    groupTitle,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                ...books.map((b) {
                  if (_resolvedBooks.containsKey(b)) {
                    final remoteBook = _resolvedBooks[b]!;
                    return RemoteBookTile(
                      book: remoteBook,
                      isStandardEbook: remoteBook.source == 'Standard Ebooks',
                      localBookMap: localBookMap,
                    );
                  } else {
                    return _CollectionBookTile(
                      book: b,
                      onSearch: widget.onSearch,
                    );
                  }
                }).toList(),
              ],
            );
          }),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildBookTile(CollectionBook book, Map<String, Book>? localBookMap) {
    if (_resolvedBooks.containsKey(book)) {
      final remoteBook = _resolvedBooks[book]!;
      return RemoteBookTile(
        book: remoteBook,
        isStandardEbook: remoteBook.source == 'Standard Ebooks',
        localBookMap: localBookMap,
      );
    } else {
      return _CollectionBookTile(book: book, onSearch: widget.onSearch);
    }
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: widget.collection.color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              widget.collection.icon,
              size: 48,
              color: widget.collection.color,
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.collection.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.collection.subtitle,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionBookTile extends ConsumerWidget {
  final CollectionBook book;
  final void Function(CollectionBook) onSearch;

  const _CollectionBookTile({required this.book, required this.onSearch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<bool>(
      future: ref.read(bookRepositoryProvider).isBookDownloaded(book.title),
      builder: (context, snapshot) {
        final isInLibrary = snapshot.data ?? false;

        final List<String> subtitleParts = [];
        if (book.metadata.isNotEmpty) {
          book.metadata.forEach((k, v) {
            subtitleParts.add('$k: $v');
          });
        }

        final subtitle = subtitleParts.join(' • ');

        return Card(
          elevation: 0,
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
          child: ListTile(
            title: Text(
              book.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(book.author),
                if (subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            trailing: isInLibrary
                ? const Icon(Icons.check_circle, color: Colors.green)
                : const Icon(Icons.search),
            onTap: () {
              if (!isInLibrary) {
                onSearch(book);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('You already have this book!')),
                );
              }
            },
          ),
        );
      },
    );
  }
}
