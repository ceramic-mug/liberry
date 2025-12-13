import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../book_journal_screen.dart';
import '../reader_screen.dart';
import 'link_note_dialog.dart';

class HighlightDetailsSheet extends ConsumerWidget {
  final Quote highlight;
  final Book book;
  final bool showGoToPage;
  final VoidCallback? onHighlightDeleted;

  const HighlightDetailsSheet({
    super.key,
    required this.highlight,
    required this.book,
    this.showGoToPage = true,
    this.onHighlightDeleted,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DraggableScrollableSheet(
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
                const SizedBox(height: 8),
                Text(
                  book.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '"${highlight.textContent}"',
                  style: const TextStyle(fontSize: 16, height: 1.5),
                ),
                const SizedBox(height: 16),
                if (highlight.characterId != null) ...[
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
                    // Copy
                    IconButton.filledTonal(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: highlight.textContent),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Copied to clipboard'),
                            ),
                          );
                          Navigator.pop(context);
                        }
                      },
                      icon: const Icon(Icons.copy),
                      tooltip: 'Copy',
                    ),

                    // Share
                    IconButton.filledTonal(
                      onPressed: () {
                        // "Highlight Text" - [Author], [Book title]
                        final textToShare =
                            '"${highlight.textContent}"\n- ${book.author}, ${book.title}';
                        Share.share(textToShare);
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.share),
                      tooltip: 'Share',
                    ),

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
                            .deleteHighlight(highlight.id);
                        onHighlightDeleted?.call();
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
                if (book.isDownloaded && showGoToPage)
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
    );
  }

  void _showAssignCharacterDialog(
    BuildContext context,
    WidgetRef ref,
    Quote highlight,
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
                              .assignQuoteToCharacter(highlight.id, char.id);
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
