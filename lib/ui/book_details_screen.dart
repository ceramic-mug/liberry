import 'dart:io';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
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
  late TextEditingController _notesController;
  int _rating = 0;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(text: widget.book.userNotes);
    _rating = widget.book.rating ?? 0;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _saveNotes() {
    final newNotes = _notesController.text;
    if (newNotes != widget.book.userNotes) {
      ref
          .read(bookRepositoryProvider)
          .updateBook(
            widget.book.id,
            BooksCompanion(userNotes: drift.Value(newNotes)),
          );
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Notes saved')));
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

  void _toggleStatus(String? newGroup) {
    if (newGroup == null) return;
    ref.read(bookRepositoryProvider).setBookGroup(widget.book.id, newGroup);

    if (newGroup == 'bookshelf') {
      // Ask to offload
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Offload Book?'),
          content: const Text(
            'Moving to Bookshelf can offload the book file to save space. You can keep the file if you prefer.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Keep file
              },
              child: const Text('Keep File'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await ref
                    .read(bookRepositoryProvider)
                    .offloadBook(widget.book.id);
                if (context.mounted) setState(() {});
              },
              child: const Text('Offload (Delete File)'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookRepo = ref.watch(bookRepositoryProvider);
    // Watch specific book to get updates
    return StreamBuilder<List<Book>>(
      stream: bookRepo.watchAllBooks().map(
        (books) => books.where((b) => b.id == widget.book.id).toList(),
      ),
      builder: (context, snapshot) {
        final book = (snapshot.data?.isNotEmpty == true)
            ? snapshot.data!.first
            : widget.book;

        // Update local state if external change (optional, but good practice)
        if (snapshot.hasData) {
          if (_notesController.text != book.userNotes) {
            // only update if not focused to avoid typing glitch, or just let user save manually
            // _notesController.text = book.userNotes ?? '';
          }
        }

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
                                child: book.isDownloaded
                                    ? Image.file(
                                        snapshot.data!,
                                        fit: BoxFit.cover,
                                      )
                                    : ColorFiltered(
                                        colorFilter: const ColorFilter.mode(
                                          Colors.grey,
                                          BlendMode.saturation,
                                        ),
                                        child: Image.file(
                                          snapshot.data!,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                              );
                            }
                            return const Center(
                              child: Icon(Icons.book, size: 50),
                            );
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

                            // Action Button
                            if (book.isDownloaded)
                              FilledButton.icon(
                                onPressed: () async {
                                  String filePath = book.filePath;
                                  final file = File(filePath);

                                  if (!await file.exists()) {
                                    // Try to recover path logic
                                    final docsDir =
                                        await getApplicationDocumentsDirectory();
                                    final filename = p.basename(filePath);
                                    final newPath = p.join(
                                      docsDir.path,
                                      filename,
                                    );
                                    if (await File(newPath).exists()) {
                                      filePath = newPath;
                                    } else {
                                      if (context.mounted)
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text("File not found"),
                                          ),
                                        );
                                      return;
                                    }
                                  }

                                  if (context.mounted) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            ReaderScreen(book: book),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.menu_book),
                                label: const Text('Read'),
                              )
                            else
                              OutlinedButton.icon(
                                onPressed:
                                    null, // Disabled for now, as re-download logic is complex
                                icon: const Icon(Icons.cloud_off),
                                label: const Text('Offloaded'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Organization Section
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Status"),
                            DropdownButton<String>(
                              value: book.group == 'bookshelf'
                                  ? 'bookshelf'
                                  : 'reading',
                              underline: Container(),
                              items: const [
                                DropdownMenuItem(
                                  value: 'reading',
                                  child: Text("Currently Reading"),
                                ),
                                DropdownMenuItem(
                                  value: 'bookshelf',
                                  child: Text("Bookshelf"),
                                ),
                              ],
                              onChanged: _toggleStatus,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Metadata Dump
                        if (book.language != null || book.publishedDate != null)
                          Row(
                            children: [
                              if (book.language != null)
                                Chip(
                                  label: Text(book.language!),
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                ),
                              if (book.language != null)
                                const SizedBox(width: 8),
                              if (book.publishedDate != null)
                                Text(
                                  "Pub: ${DateFormat.yMMMd().format(book.publishedDate!)}",
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Notes Section
                  const Text(
                    "Notes",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Add your personal notes here...',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.save),
                        onPressed: _saveNotes,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // File Path (Debug info, maybe hide later)
                  // Removed as requested
                  // Text('File: ${book.filePath}', style: const TextStyle(color: Colors.grey, fontSize: 10)),
                  const Divider(height: 32),

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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 3,
                                          height: 30,
                                          color: Theme.of(context).primaryColor,
                                          margin: const EdgeInsets.only(
                                            right: 12,
                                          ),
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
                  const SizedBox(height: 24),
                  Text(
                    'Rating',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: List.generate(5, (index) {
                      return InkWell(
                        onTap: () => _updateRating(index + 1),
                        child: Icon(
                          index < _rating ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                          size: 28,
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
              if (book.isDownloaded)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context); // Close modal
                      // Navigate to reader
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ReaderScreen(book: book),
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
