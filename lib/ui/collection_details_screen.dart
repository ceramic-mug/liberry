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
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    // 5. Remove leading articles (The, A, An)
    // matches "The ", "A ", "An " at the start
    final articleRegex = RegExp(r'^(the|a|an)\s+', caseSensitive: false);
    if (articleRegex.hasMatch(cleaned)) {
      cleaned = cleaned.replaceFirst(articleRegex, '');
    }

    return cleaned.trim();
  }

  bool _authorsMatch(String localAuthor, String remoteAuthor) {
    if (localAuthor.isEmpty || remoteAuthor.isEmpty) return false;

    // Handle "Unknown" / "Anonymous" explicitly
    if (localAuthor.toLowerCase() == 'unknown' ||
        localAuthor.toLowerCase() == 'anonymous' ||
        remoteAuthor.toLowerCase() == 'unknown' ||
        remoteAuthor.toLowerCase() == 'anonymous') {
      return true;
    }

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
    if (cleanRemote.contains(cleanLocal.trim()) ||
        cleanLocal.contains(cleanRemote.trim()))
      return true;

    final localTokens = cleanLocal
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toSet();
    final remoteTokens = cleanRemote
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toSet();

    if (localTokens.isEmpty || remoteTokens.isEmpty) return false;

    final intersection = localTokens.intersection(remoteTokens);
    final localSig = localTokens.where((t) => t.length > 2).toSet();
    final remoteSig = remoteTokens.where((t) => t.length > 2).toSet();
    final intersectSig = intersection.where((t) => t.length > 2).toSet();

    if (localSig.isNotEmpty && remoteSig.isNotEmpty) {
      // If we have at least one significant token match (e.g. "Poe", "Hammett", "Dostoevsky")
      // And the titles matched (which is the context where this is called),
      // that is usually sufficient.
      // We previously required covering one SIDE's entire set of sig tokens.
      // But "Edgar Allan Poe" vs "Poe" -> "Poe" covers "Poe".
      // "Dashiell Hammett" vs "Hammett" -> "Hammett" match.

      if (intersectSig.isNotEmpty) return true;
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

          // Use custom search term if provided, otherwise clean the title
          final searchTitle =
              book.customSearchTerm ?? _cleanTitleForSearch(book.title);

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

    // Calculate stats
    int read = 0;
    int reading = 0;
    int notStarted = 0;

    for (final book in widget.collection.books) {
      // Try to find matching local book
      Book? match;
      // Simple title matching often suffices for library lookup
      try {
        match = localBookMap.values.firstWhere(
          (b) =>
              b.title.toLowerCase() == book.title.toLowerCase() ||
              (b.title.toLowerCase().contains(book.title.toLowerCase()) &&
                  b.author?.toLowerCase().contains(book.author.toLowerCase()) ==
                      true),
        );
      } catch (_) {}

      if (match != null) {
        if (match.status == 'read' || match.isRead) {
          read++;
        } else if (match.status == 'reading') {
          reading++;
        } else {
          notStarted++;
        }
      } else {
        notStarted++;
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.collection.title)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _buildHeader(context, read, reading, notStarted),
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
                      localBookMap: localBookMap,
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
      return _CollectionBookTile(
        book: book,
        onSearch: widget.onSearch,
        localBookMap: localBookMap,
      );
    }
  }

  Widget _buildHeader(
    BuildContext context,
    int read,
    int reading,
    int notStarted,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0),
      child: Column(
        children: [
          Row(
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
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
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
          // Stats Row
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatChip(context, 'Read', read, Colors.green),
              _buildStatChip(context, 'Reading', reading, Colors.blue),
              _buildStatChip(context, 'Not Started', notStarted, Colors.grey),
            ],
          ),
          const Divider(height: 32),
        ],
      ),
    );
  }

  Widget _buildStatChip(
    BuildContext context,
    String label,
    int count,
    Color color,
  ) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _CollectionBookTile extends ConsumerWidget {
  final CollectionBook book;
  final void Function(CollectionBook) onSearch;
  final Map<String, Book>? localBookMap;

  const _CollectionBookTile({
    required this.book,
    required this.onSearch,
    required this.localBookMap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Try to find matching local book
    Book? localBook;
    try {
      localBook = localBookMap?.values.firstWhere(
        (b) =>
            b.title == book.title ||
            (b.title.contains(book.title) &&
                b.author != null &&
                b.author!.contains(book.author)),
      );
    } catch (_) {}

    final isInLibrary = localBook != null;
    final isRead =
        isInLibrary && (localBook.status == 'read' || localBook.isRead);
    final isReading = isInLibrary && localBook.status == 'reading';

    final List<String> subtitleParts = [];
    if (book.metadata.isNotEmpty) {
      book.metadata.forEach((k, v) {
        subtitleParts.add('$k: $v');
      });
    }

    final subtitle = subtitleParts.join(' • ');

    Color baseColor;
    if (isRead) {
      baseColor = Colors.green;
    } else if (isReading) {
      baseColor = Colors.blue;
    } else if (isInLibrary) {
      // Not Started
      baseColor = Colors.grey;
    } else {
      baseColor = Theme.of(context).colorScheme.onSurfaceVariant;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 0,
      color: isDark
          ? Colors.transparent
          : (isInLibrary
                ? baseColor.withValues(alpha: 0.15)
                : Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isDark
            ? BorderSide(
                color: isInLibrary
                    ? baseColor
                    : baseColor.withValues(alpha: 0.3), // Subtler for unowned
                width: 2,
              )
            : BorderSide.none,
      ),
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
            ? _buildStatusChip(context, isRead, isReading)
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
  }

  Widget _buildStatusChip(BuildContext context, bool isRead, bool isReading) {
    String label;
    Color color;
    Color textColor;

    if (isRead) {
      label = 'Read';
      color = Colors.green.withOpacity(0.2);
      textColor = Colors.green.shade800;
    } else if (isReading) {
      label = 'Reading';
      color = Colors.blue.withOpacity(0.2);
      textColor = Colors.blue.shade800;
    } else {
      label = 'Not Started';
      color = Colors.grey.withOpacity(0.2);
      textColor = Colors.grey.shade800;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
