import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../data/database.dart';
import '../data/character_repository.dart';
import 'dart:io';
import 'reader_screen.dart';
import 'book_journal_screen.dart'; // Added
import 'widgets/link_note_dialog.dart';
import '../providers.dart';

class HighlightsTab extends ConsumerWidget {
  final String searchQuery;
  final String? bookId;
  final String? author;

  const HighlightsTab({
    super.key,
    required this.searchQuery,
    this.bookId,
    this.author,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final charRepo = ref.watch(characterRepositoryProvider);

    return StreamBuilder<List<QuoteWithBook>>(
      stream: charRepo.watchAllQuotesWithBooks(
        searchQuery,
        bookId: bookId,
        author: author,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final quotes = snapshot.data!;
        if (quotes.isEmpty) {
          return Center(
            child: Text(
              searchQuery.isEmpty ? 'No highlights yet.' : 'No matches found.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: quotes.length,
          itemBuilder: (context, index) {
            final item = quotes[index];
            return InkWell(
              onTap: () => _showHighlightDetails(context, ref, item),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 4,
                          height: 40,
                          color: Theme.of(
                            context,
                          ).primaryColor, // Highlight color
                          margin: const EdgeInsets.only(right: 12),
                        ),
                        Expanded(
                          child: Text(
                            '"${item.quote.textContent}"',
                            style: const TextStyle(
                              fontSize: 14, // Smaller font
                              // No italics
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.book, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.book.title,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          DateFormat.yMMMd().format(item.quote.createdAt),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
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

  void _showHighlightDetails(
    BuildContext context,
    WidgetRef ref,
    QuoteWithBook item,
  ) {
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
            stream: ref
                .read(bookRepositoryProvider)
                .watchNotesForBook(item.book.id),
            builder: (context, snapshot) {
              final notes = snapshot.data ?? [];
              final linkedNote = notes.cast<BookNote?>().firstWhere(
                (n) => n?.quoteId == item.quote.id,
                orElse: () => null,
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Highlight Details',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.book.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '"${item.quote.textContent}"',
                    style: const TextStyle(fontSize: 16, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  if (item.quote.characterId != null) ...[
                    // We can resolve character name if needed, but for now simple indicator
                    const Row(
                      children: [
                        Icon(Icons.person, size: 16, color: Colors.grey),
                        SizedBox(width: 8),
                        Text(
                          'Assigned to a character',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Unified Icon Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Character Link Button
                      IconButton.filledTonal(
                        onPressed: () {
                          Navigator.pop(context);
                          _showAssignCharacterDialog(context, ref, item);
                        },
                        icon: Icon(
                          item.quote.characterId != null
                              ? Icons.person
                              : Icons.person_add,
                        ),
                        tooltip: item.quote.characterId != null
                            ? 'Assigned to Character'
                            : 'Assign Character',
                      ),

                      // Journal Link Button
                      IconButton.filledTonal(
                        onPressed: () {
                          if (linkedNote != null) {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => BookJournalScreen(
                                  bookId: item.book.id,
                                  bookTitle: item.book.title,
                                  initialTab: 0,
                                ),
                              ),
                            );
                          } else {
                            showDialog(
                              context: context,
                              builder: (context) => LinkNoteDialog(
                                bookId: item.book.id,
                                highlight: item.quote,
                              ),
                            );
                          }
                        },
                        icon: Icon(
                          linkedNote != null
                              ? Icons.history_edu
                              : Icons.edit_note,
                        ),
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

                      // Delete Button
                      IconButton.filledTonal(
                        onPressed: () async {
                          await ref
                              .read(bookRepositoryProvider)
                              .deleteHighlight(item.quote.id);
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

                  const SizedBox(height: 16),
                  if (item.book.isDownloaded)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(context); // Close modal

                          int? chapterIndex;
                          String? cfi;

                          if (item.quote.cfi != null) {
                            try {
                              final Map<String, dynamic> data = jsonDecode(
                                item.quote.cfi!,
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
                                cfi = item.quote.cfi;
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
                                book: item.book,
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

  void _showAssignCharacterDialog(
    BuildContext context,
    WidgetRef ref,
    QuoteWithBook item,
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
                              .assignQuoteToCharacter(item.quote.id, char.id);
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
}
