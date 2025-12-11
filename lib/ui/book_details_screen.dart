import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../data/database.dart';
import '../data/book_repository.dart';
import '../data/character_repository.dart'; // Added for character management
import '../providers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'reader_screen.dart';
import 'book_journal_screen.dart';
import 'character_library.dart';
import 'widgets/link_note_dialog.dart';

class BookDetailsScreen extends ConsumerStatefulWidget {
  final Book book;

  const BookDetailsScreen({super.key, required this.book});

  @override
  ConsumerState<BookDetailsScreen> createState() => _BookDetailsScreenState();
}

class _BookDetailsScreenState extends ConsumerState<BookDetailsScreen> {
  int _rating = 0;

  @override
  void initState() {
    super.initState();
    _rating = widget.book.rating ?? 0;
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _updateRating(int rating) {
    setState(() => _rating = rating);
    ref
        .read(bookRepositoryProvider)
        .updateBook(
          widget.book.id,
          BooksCompanion(rating: drift.Value(rating)),
        );
  }

  void _updateLocation(String location) {
    // Optimistic update if needed, but StreamBuilder should be fast enough given local DB
    ref
        .read(bookRepositoryProvider)
        .updateBookLocation(widget.book.id, location);
  }

  void _updateStatus(String status) {
    ref.read(bookRepositoryProvider).updateBookStatus(widget.book.id, status);
  }

  void _showLocationSelector(Book book) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.table_restaurant), // Desk
                title: const Text('Desk'),
                trailing:
                    (book.group == 'desk' ||
                        book.group == 'reading' ||
                        book.group == null)
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  _updateLocation('desk');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.shelves),
                title: const Text('Bookshelf'),
                trailing: (book.group == 'bookshelf' || book.group == 'read')
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  _updateLocation('bookshelf');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showStatusSelector(Book book) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        // Handle compilation error if status doesn't exist yet via safe access or comment
        // Assuming codegen will run:
        final currentStatus = book.status;

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.cancel_outlined),
                title: const Text('Not Started'),
                trailing: currentStatus == 'not_started'
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  _updateStatus('not_started');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.menu_book),
                title: const Text('Reading'),
                trailing: currentStatus == 'reading'
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  _updateStatus('reading');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.check_circle),
                title: const Text('Read'),
                trailing: currentStatus == 'read' || book.isRead
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  _updateStatus('read');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, Book book) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Book'),
        content: Text(
          'Are you sure you want to delete "${book.title}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Close details screen
              await ref.read(bookRepositoryProvider).deleteBook(book.id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddCharacterDialog(String bookId) async {
    final nameController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Character'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            hintText: 'Character Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (nameController.text.trim().isNotEmpty) {
                await ref
                    .read(characterRepositoryProvider)
                    .createCharacter(
                      name: nameController.text.trim(),
                      originBookId: bookId,
                    );
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showAssignCharacterDialog(
    BuildContext context,
    WidgetRef ref,
    Quote quote,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Assign to Character'),
        content: SizedBox(
          width: double.maxFinite,
          child: Consumer(
            builder: (context, ref, child) {
              final charRepo = ref.watch(characterRepositoryProvider);
              return StreamBuilder<List<Character>>(
                stream: charRepo.watchAllCharacters(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final characters = snapshot.data!;
                  if (characters.isEmpty) {
                    return const Text('No characters created yet.');
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: characters.length,
                    itemBuilder: (context, index) {
                      final char = characters[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: char.imagePath != null
                              ? FileImage(File(char.imagePath!))
                              : null,
                          child: char.imagePath == null
                              ? Text(char.name[0])
                              : null,
                        ),
                        title: Text(char.name),
                        onTap: () async {
                          await ref
                              .read(bookRepositoryProvider)
                              .assignQuoteToCharacter(quote.id, char.id);
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Assigned to ${char.name}'),
                              ),
                            );
                          }
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookRepo = ref.watch(bookRepositoryProvider);
    return StreamBuilder<List<Book>>(
      stream: bookRepo.watchAllBooks().map(
        (books) => books.where((b) => b.id == widget.book.id).toList(),
      ),
      builder: (context, snapshot) {
        final book = (snapshot.data?.isNotEmpty == true)
            ? snapshot.data!.first
            : widget.book;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Details'),
            centerTitle: true,
            actions: [
              IconButton(
                icon: Icon(
                  book.status == 'read'
                      ? Icons.check_circle
                      : Icons.check_circle_outline,
                  color: book.status == 'read' ? Colors.green : null,
                ),
                tooltip: 'Change Status',
                onPressed: () => _showStatusSelector(book),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'delete') {
                    _confirmDelete(context, book);
                  } else if (value == 'location') {
                    _showLocationSelector(book);
                  }
                },
                itemBuilder: (BuildContext context) => [
                  const PopupMenuItem(
                    value: 'location',
                    child: Row(
                      children: [
                        Icon(Icons.place, color: Colors.grey),
                        SizedBox(width: 8),
                        Text('Move to...'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: Colors.red),
                        SizedBox(width: 8),
                        Text(
                          'Delete Book',
                          style: TextStyle(color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(book),
                const SizedBox(height: 20),
                _buildActionRow(book),
                const SizedBox(height: 24),
                _buildSectionTitle('Highlights'),
                _buildHighlightsList(bookRepo, book),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildSectionTitle('Characters', padding: EdgeInsets.zero),
                    IconButton(
                      icon: const Icon(Icons.person_add_alt_1, size: 20),
                      onPressed: () => _showAddCharacterDialog(book.id),
                      tooltip: 'Add Character',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildCharactersList(book),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(Book book) {
    String locationLabel = 'Desk';
    IconData locationIcon = Icons.table_restaurant;
    Color locationColor = Colors.blue;

    if (book.group == 'bookshelf' || book.group == 'read') {
      locationLabel = 'Bookshelf';
      locationIcon = Icons.shelves;
      locationColor = Colors.amber;
    }

    String statusLabel = 'Not Started';
    IconData statusIcon = Icons.cancel_outlined;
    Color statusColor = Colors.grey;

    // Use safe access or conditional until codegen
    final status = book.status;

    if (status == 'reading') {
      statusLabel = 'Reading';
      statusIcon = Icons.menu_book;
      statusColor = Colors.blue;
    } else if (status == 'read') {
      statusLabel = 'Read';
      statusIcon = Icons.check_circle;
      statusColor = Colors.green;
    } else {
      // Not started
      statusLabel = 'Not Started';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Compact Cover
        Hero(
          tag: 'book_cover_${book.id}',
          child: Container(
            width: 100,
            height: 150,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: FutureBuilder<File?>(
              future: _resolveCoverPath(book.coverPath),
              builder: (context, snapshot) {
                Widget image;
                if (snapshot.hasData && snapshot.data != null) {
                  image = Image.file(snapshot.data!, fit: BoxFit.cover);
                } else {
                  image = const Center(
                    child: Icon(Icons.book, size: 40, color: Colors.grey),
                  );
                }

                if (!book.isDownloaded) {
                  image = ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                      Colors.grey,
                      BlendMode.saturation,
                    ),
                    child: image,
                  );
                }

                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: image,
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Info Column
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                book.title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  height: 1.2,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                book.author ?? 'Unknown Author',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              // Rating
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (index) {
                  return GestureDetector(
                    onTap: () => _updateRating(index + 1),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 2.0),
                      child: Icon(
                        index < _rating ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 20,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Location Chip
                  InkWell(
                    onTap: () => _showLocationSelector(book),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: locationColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: locationColor.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(locationIcon, size: 14, color: locationColor),
                          const SizedBox(width: 4),
                          Text(
                            locationLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: locationColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Status Chip
                  InkWell(
                    onTap: () => _showStatusSelector(book),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: statusColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 14, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Metadata Chips
                  if (book.language != null)
                    _buildChip(book.language!, Icons.language),
                  if (book.publishedDate != null)
                    _buildChip(
                      DateFormat.y().format(book.publishedDate!),
                      Icons.calendar_today,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow(Book book) {
    return Row(
      children: [
        // Primary Action: Read
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: book.isDownloaded
                ? () async {
                    String filePath = book.filePath;
                    final file = File(filePath);
                    if (!await file.exists()) {
                      // Attempt recovery logic omitted for brevity, keeping simple for now
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("File not found")),
                        );
                      }
                      return;
                    }
                    if (context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ReaderScreen(book: book),
                        ),
                      );
                    }
                  }
                : null, // TODO: Handle download/restore
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.menu_book_rounded),
            label: const Text('Read'),
          ),
        ),
        const SizedBox(width: 12),
        // Secondary Action: Journal
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      BookJournalScreen(bookId: book.id, bookTitle: book.title),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('Journal'),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, {EdgeInsets? padding}) {
    return Padding(
      padding: padding ?? const EdgeInsets.only(bottom: 12.0),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildHighlightsList(BookRepository bookRepo, Book book) {
    return StreamBuilder<List<Quote>>(
      stream: bookRepo.watchHighlightsForBook(book.id),
      builder: (context, snapshot) {
        final highlights = snapshot.data ?? [];
        if (highlights.isEmpty) {
          return _buildEmptyState('No highlights yet');
        }

        final displayCount = highlights.length > 5 ? 5 : highlights.length;

        return Column(
          children: [
            ...List.generate(displayCount, (index) {
              final highlight = highlights[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    left: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.5),
                      width: 3,
                    ),
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 0,
                  ),
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text(
                    highlight.textContent,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, height: 1.3),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      DateFormat.MMMd().format(highlight.createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  onTap: () => _showHighlightDetails(context, highlight, book),
                ),
              );
            }),
            if (highlights.length > 5)
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => BookJournalScreen(
                        bookId: book.id,
                        bookTitle: book.title,
                        initialTab: 1, // Highlights tab
                      ),
                    ),
                  );
                },
                child: Text('View all ${highlights.length} highlights'),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCharactersList(Book book) {
    final charRepo = ref.watch(characterRepositoryProvider);
    return StreamBuilder<List<CharacterWithBook>>(
      // Using searchCharacters to get list, filtering by bookId in repository would be cleaner
      // But for now reusable method:
      stream: charRepo.watchCharactersWithFilteredBooks('', bookId: book.id),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 50,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final characters = snapshot.data!;

        if (characters.isEmpty) {
          return _buildEmptyState('No characters created');
        }

        return SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: characters.length,
            separatorBuilder: (c, i) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final char = characters[index].character;
              return InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          CharacterDetailScreen(character: char, book: book),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      backgroundImage: char.imagePath != null
                          ? FileImage(File(char.imagePath!))
                          : null,
                      child: char.imagePath == null
                          ? Text(
                              char.name.isNotEmpty
                                  ? char.name[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                fontSize: 24,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 64,
                      child: Text(
                        char.name,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
        ),
      ),
      child: Center(
        child: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  void _showHighlightDetails(BuildContext context, Quote highlight, Book book) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.45,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: StreamBuilder<List<BookNote>>(
            stream: ref.read(bookRepositoryProvider).watchNotesForBook(book.id),
            builder: (context, snapshot) {
              final notes = snapshot.data ?? [];
              final linkedNote = notes.cast<BookNote?>().firstWhere(
                (n) => n?.quoteId == highlight.id,
                orElse: () => null,
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Highlight Details',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '"${highlight.textContent}"',
                    style: const TextStyle(fontSize: 16, height: 1.5),
                  ),
                  const SizedBox(height: 24),

                  // Unified Icon Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Character Link Button
                      IconButton.filledTonal(
                        onPressed: () {
                          Navigator.pop(context);
                          _showAssignCharacterDialog(context, ref, highlight);
                        },
                        icon: Icon(
                          highlight.characterId != null
                              ? Icons.person
                              : Icons.person_add,
                        ),
                        tooltip: highlight.characterId != null
                            ? 'Assigned to Character'
                            : 'Assign Character',
                        // Note: Logic to actually assign is missing in BookDetails for existing characters in the snippet?
                        // I will leave it as `onPressed: (){}` placeholder if I can't find the method,
                        // or better: just don't show it if it's not ready?
                        // But the user asked for it.
                        // I will assume for this specific file I focus on Journal, but I will put the icon there.
                      ),

                      // Journal Link Button
                      IconButton.filledTonal(
                        onPressed: () {
                          if (linkedNote != null) {
                            // If linked, maybe go to it?
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => BookJournalScreen(
                                  bookId: book.id,
                                  bookTitle: book.title,
                                  initialTab: 0,
                                ),
                              ),
                            );
                          } else {
                            showDialog(
                              context: context,
                              builder: (context) => LinkNoteDialog(
                                bookId: book.id,
                                highlight: highlight,
                              ),
                            );
                          }
                        },
                        icon: Icon(
                          linkedNote != null
                              ? Icons.history_edu
                              : Icons.edit_note,
                        ), // Icons.history_edu is good for Journal
                        tooltip: linkedNote != null
                            ? 'View Journal Entry'
                            : 'Link to Journal Entry',
                        style: IconButton.styleFrom(
                          backgroundColor: linkedNote != null
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                          foregroundColor: linkedNote != null
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : null,
                        ),
                      ),

                      // Delete Button (Icon only now to match)
                      IconButton.filledTonal(
                        onPressed: () async {
                          await ref
                              .read(bookRepositoryProvider)
                              .deleteHighlight(highlight.id);
                          if (context.mounted) Navigator.pop(context);
                        },
                        icon: const Icon(Icons.delete),
                        tooltip: 'Delete Highlight',
                        style: IconButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.errorContainer,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  if (book.isDownloaded)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(context); // Close modal

                          int? chapterIndex;
                          String? cfi;

                          if (highlight.cfi != null) {
                            try {
                              final Map<String, dynamic> data = jsonDecode(
                                highlight.cfi!,
                              );
                              if (data.containsKey('chapterIndex')) {
                                chapterIndex = data['chapterIndex'] is int
                                    ? data['chapterIndex']
                                    : int.tryParse(
                                        data['chapterIndex'].toString(),
                                      );
                              }

                              if (data.containsKey('startPath')) {
                                cfi = jsonEncode({
                                  'path': data['startPath'],
                                  'offset': data['startOffset'] ?? 0,
                                });
                              } else {
                                cfi = highlight.cfi;
                              }
                            } catch (e) {
                              print("Error parsing helper cfi: $e");
                            }
                          }

                          // Navigate to reader
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ReaderScreen(
                                book: book,
                                initialChapterIndex: chapterIndex,
                                initialCfi: cfi,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Go to Page'),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<File?> _resolveCoverPath(String? path) async {
    if (path == null) return null;

    final file = File(path);
    if (await file.exists()) return file;

    try {
      final docsDir = await getApplicationDocumentsDirectory();

      if (!p.isAbsolute(path)) {
        final fullPath = p.join(docsDir.path, path);
        final fullFile = File(fullPath);
        if (await fullFile.exists()) return fullFile;
      }

      final filename = p.basename(path);
      final newPath = p.join(docsDir.path, 'covers', filename);
      final newFile = File(newPath);
      if (await newFile.exists()) return newFile;
    } catch (e) {
      // Ignore
    }
    return null;
  }
}
