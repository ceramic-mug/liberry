import 'dart:io';
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
              Text(
                'Highlights',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Center(child: Text('No highlights yet.')),
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
