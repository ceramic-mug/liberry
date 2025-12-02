import 'dart:io';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database.dart';
import '../providers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'reader_screen.dart';

class BookDetailsScreen extends ConsumerStatefulWidget {
  final Book book;

  const BookDetailsScreen({super.key, required this.book});

  @override
  ConsumerState<BookDetailsScreen> createState() => _BookDetailsScreenState();
}

class _BookDetailsScreenState extends ConsumerState<BookDetailsScreen> {
  bool _isDarkMode = false;

  @override
  Widget build(BuildContext context) {
    final bookRepo = ref.watch(bookRepositoryProvider);
    final book = widget.book;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Book Details'),
        actions: [
          IconButton(
            icon: Icon(_isDarkMode ? Icons.dark_mode : Icons.light_mode),
            onPressed: () {
              setState(() {
                _isDarkMode = !_isDarkMode;
              });
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover and Info Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cover Image
                  Container(
                    width: 120,
                    height: 180,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 5,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: FutureBuilder<File?>(
                      future: _resolveCoverPath(book.coverPath),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data != null) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              snapshot.data!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.book, size: 50),
                            ),
                          );
                        }
                        return const Icon(Icons.book, size: 50);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          style: Theme.of(context).textTheme.titleLarge,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          book.author ?? 'Unknown Author',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () async {
                            // Resolve file path dynamically
                            String filePath = book.filePath;
                            final file = File(filePath);

                            if (!await file.exists()) {
                              // Try to find it in Documents directory by filename
                              try {
                                final docsDir =
                                    await getApplicationDocumentsDirectory();
                                final filename = p.basename(filePath);
                                final newPath = p.join(docsDir.path, filename);
                                final newFile = File(newPath);

                                if (await newFile.exists()) {
                                  print("Found file at new path: $newPath");
                                  filePath = newPath;
                                } else {
                                  print(
                                    "File not found at original or new path.",
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'File not found: $filename',
                                        ),
                                      ),
                                    );
                                  }
                                  return;
                                }
                              } catch (e) {
                                print("Error resolving path: $e");
                              }
                            }

                            final cfi = await bookRepo.getReadingProgress(
                              book.id,
                            );

                            if (context.mounted) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ReaderScreen(
                                    book: book,
                                    initialCfi: cfi ?? '',
                                  ),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.menu_book),
                          label: const Text('Read'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // File Path (Debug info, maybe hide later)
              Text(
                'File: ${book.filePath}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
              const Divider(height: 32),
              // Placeholders for future features
              // Highlights Section
              StreamBuilder<List<Quote>>(
                stream: bookRepo.watchHighlightsForBook(book.id),
                builder: (context, snapshot) {
                  final highlights = snapshot.data ?? [];

                  return ExpansionTile(
                    title: Text(
                      'Highlights',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: Text(
                      '${highlights.length} highlights',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    initiallyExpanded: false,
                    childrenPadding: EdgeInsets.zero,
                    tilePadding: EdgeInsets.zero,
                    children: [
                      if (highlights.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text('No highlights yet.'),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: highlights.length,
                          itemBuilder: (context, index) {
                            final highlight = highlights[index];
                            return InkWell(
                              onTap: () => _showHighlightDetails(
                                context,
                                highlight,
                                book,
                              ),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 2,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 3,
                                      height: 30,
                                      color: Theme.of(context).primaryColor,
                                      margin: const EdgeInsets.only(right: 12),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '"${highlight.textContent}"',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              height: 1.3,
                                            ),
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            DateFormat.yMMMd().format(
                                              highlight.createdAt,
                                            ),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Characters',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Center(child: Text('No characters tagged.')),
            ],
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
        initialChildSize: 0.4,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
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
              const SizedBox(height: 16),
              if (highlight.characterId != null)
                // We would need to fetch character name here or have it joined.
                // For now, let's just show "Assigned to Character" or fetch it?
                // Since we don't have the character object readily available without a join,
                // we can skip showing the name for now or do a quick fetch.
                // Let's skip complex fetching for this iteration to keep it simple.
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

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context); // Close modal
                    // Navigate to reader
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ReaderScreen(
                          book: book,
                          initialCfi: highlight.cfi ?? '',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Go to Page'),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () async {
                    await ref
                        .read(bookRepositoryProvider)
                        .deleteHighlight(highlight.id);
                    if (context.mounted) {
                      Navigator.pop(context); // Close modal
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Highlight deleted')),
                      );
                    }
                  },
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text(
                    'Delete Highlight',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<File?> _resolveCoverPath(String? path) async {
    if (path == null) return null;

    // Check if it's an absolute path (legacy)
    final file = File(path);
    if (await file.exists()) return file;

    try {
      final docsDir = await getApplicationDocumentsDirectory();

      // If path is relative (e.g. "covers/uuid.png"), join it
      if (!p.isAbsolute(path)) {
        final fullPath = p.join(docsDir.path, path);
        final fullFile = File(fullPath);
        if (await fullFile.exists()) return fullFile;
      }

      // Fallback: try to find by basename in covers dir
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
