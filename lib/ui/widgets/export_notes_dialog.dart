import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

import '../../data/book_repository.dart';
import '../../data/character_repository.dart';
import '../../data/database.dart';
import '../../providers.dart';

enum ExportFilter { all, book, author }

enum ExportFormat { txt, csv }

class ExportNotesDialog extends ConsumerStatefulWidget {
  const ExportNotesDialog({super.key});

  @override
  ConsumerState<ExportNotesDialog> createState() => _ExportNotesDialogState();
}

class _ExportNotesDialogState extends ConsumerState<ExportNotesDialog> {
  bool _includeHighlights = true;
  bool _includeCharacters = true;
  bool _includeNotes = true;

  ExportFilter _filterMode = ExportFilter.all;
  ExportFormat _exportFormat = ExportFormat.txt;

  String? _selectedBookId;
  String? _selectedAuthor;

  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    final bookRepo = ref.watch(bookRepositoryProvider);

    return AlertDialog(
      title: const Text('Export Notes'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Content',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            CheckboxListTile(
              title: const Text('Highlights'),
              value: _includeHighlights,
              onChanged: (v) => setState(() => _includeHighlights = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              title: const Text('Characters'),
              value: _includeCharacters,
              onChanged: (v) => setState(() => _includeCharacters = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              title: const Text('Notes & Journal'),
              value: _includeNotes,
              onChanged: (v) => setState(() => _includeNotes = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const Divider(),
            const Text(
              'Filter By',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<ExportFilter>(
              value: _filterMode,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: ExportFilter.all,
                  child: Text('All Content'),
                ),
                DropdownMenuItem(
                  value: ExportFilter.book,
                  child: Text('Specific Book'),
                ),
                DropdownMenuItem(
                  value: ExportFilter.author,
                  child: Text('Specific Author'),
                ),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _filterMode = val;
                    // Reset sub-selections when changing mode
                    if (val == ExportFilter.all) {
                      _selectedBookId = null;
                      _selectedAuthor = null;
                    }
                  });
                }
              },
            ),
            if (_filterMode != ExportFilter.all) ...[
              const SizedBox(height: 12),
              StreamBuilder<List<Book>>(
                stream: bookRepo.watchAllBooks(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox(
                      height: 48,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final books = snapshot.data!;

                  if (_filterMode == ExportFilter.book) {
                    // Unique books
                    return DropdownButtonFormField<String>(
                      value: _selectedBookId,
                      hint: const Text('Select Book'),
                      isExpanded: true,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      items: books.map((b) {
                        return DropdownMenuItem(
                          value: b.id,
                          child: Text(b.title, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (val) => setState(() => _selectedBookId = val),
                    );
                  } else {
                    // Filter Mode Author
                    final authors = books
                        .map((b) => b.author)
                        .where((a) => a != null)
                        .toSet()
                        .cast<String>()
                        .toList();
                    authors.sort();

                    return DropdownButtonFormField<String>(
                      value: _selectedAuthor,
                      hint: const Text('Select Author'),
                      isExpanded: true,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      items: authors.map((a) {
                        return DropdownMenuItem(value: a, child: Text(a));
                      }).toList(),
                      onChanged: (val) => setState(() => _selectedAuthor = val),
                    );
                  }
                },
              ),
            ],
            const Divider(),
            const Text('Format', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<ExportFormat>(
                    title: const Text('TXT'),
                    value: ExportFormat.txt,
                    groupValue: _exportFormat,
                    onChanged: (v) =>
                        setState(() => _exportFormat = v ?? ExportFormat.txt),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                Expanded(
                  child: RadioListTile<ExportFormat>(
                    title: const Text('CSV'),
                    value: ExportFormat.csv,
                    groupValue: _exportFormat,
                    onChanged: (v) =>
                        setState(() => _exportFormat = v ?? ExportFormat.csv),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isExporting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isExporting ? null : _handleExport,
          child: _isExporting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Export'),
        ),
      ],
    );
  }

  Future<void> _handleExport() async {
    // Validate selection
    if (!_includeHighlights && !_includeCharacters && !_includeNotes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one content type.'),
        ),
      );
      return;
    }

    if (_filterMode == ExportFilter.book && _selectedBookId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a book.')));
      return;
    }

    if (_filterMode == ExportFilter.author && _selectedAuthor == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select an author.')));
      return;
    }

    setState(() {
      _isExporting = true;
    });

    try {
      final bookRepo = ref.read(bookRepositoryProvider);
      final charRepo = ref.read(characterRepositoryProvider);

      // Fetch Data
      // We will fetch ALL data and then filter in memory for simplicity,
      // or use stream/future queries if available.
      // Repos usually return streams. We want a snapshot.

      final allBooks = await bookRepo.watchAllBooks().first;
      final bookMap = {for (var b in allBooks) b.id: b};

      // Helper to check if a book matches current filter
      bool matchesFilter(String bookId) {
        final book = bookMap[bookId];
        if (book == null) return false;

        if (_filterMode == ExportFilter.all) return true;
        if (_filterMode == ExportFilter.book) return bookId == _selectedBookId;
        if (_filterMode == ExportFilter.author)
          return book.author == _selectedAuthor;
        return false;
      }

      final StringBuffer buffer = StringBuffer();
      final List<List<String>> csvRows = [];

      // Add Headers for CSV
      if (_exportFormat == ExportFormat.csv) {
        csvRows.add([
          'Type',
          'Book Title',
          'Author',
          'Content/Name',
          'Extra Info/Bio',
          'Date',
        ]);
      }

      // 1. Highlights
      if (_includeHighlights) {
        // Wait, bookRepo might not have watchAllQuotes directly exposed?
        // SyncService accessed db.select(db.quotes).
        // HighlightsTab used charRepo.watchAllQuotesWithBooks.

        final quotesWithBooks = await charRepo
            .watchAllQuotesWithBooks('')
            .first;

        // Filter
        final filteredQuotes = quotesWithBooks
            .where((q) => matchesFilter(q.book.id))
            .toList();

        if (_exportFormat == ExportFormat.txt) {
          if (filteredQuotes.isNotEmpty) {
            buffer.writeln('=== HIGHLIGHTS ===');
            buffer.writeln();
            for (var item in filteredQuotes) {
              buffer.writeln('"${item.quote.textContent}"');
              buffer.writeln(
                '- ${item.book.title} (${item.book.author ?? "Unknown"})',
              );
              buffer.writeln(
                'Date: ${DateFormat.yMMMd().format(item.quote.createdAt)}',
              );
              buffer.writeln();
            }
            buffer.writeln('----------------------------------------');
            buffer.writeln();
          }
        } else {
          for (var item in filteredQuotes) {
            csvRows.add([
              'Highlight',
              item.book.title,
              item.book.author ?? '',
              item.quote.textContent,
              '', // Extra
              item.quote.createdAt.toIso8601String(),
            ]);
          }
        }
      }

      // 2. Characters
      if (_includeCharacters) {
        // characterRepo.watchCharactersWithFilteredBooks
        // But we can just use watchAllCharacters and filter manually since we have bookMap
        final characters = await charRepo.watchAllCharacters().first;

        final filteredChars = characters
            .where((c) => matchesFilter(c.originBookId))
            .toList();

        if (_exportFormat == ExportFormat.txt) {
          if (filteredChars.isNotEmpty) {
            buffer.writeln('=== CHARACTERS ===');
            buffer.writeln();
            for (var char in filteredChars) {
              final book = bookMap[char.originBookId];
              buffer.writeln('Name: ${char.name}');
              if (book != null) buffer.writeln('Book: ${book.title}');
              if (char.bio != null && char.bio!.isNotEmpty)
                buffer.writeln('Bio: ${char.bio}');
              buffer.writeln();
            }
            buffer.writeln('----------------------------------------');
            buffer.writeln();
          }
        } else {
          for (var char in filteredChars) {
            final book = bookMap[char.originBookId];
            csvRows.add([
              'Character',
              book?.title ?? '',
              book?.author ?? '',
              char.name,
              char.bio ?? '',
              char.createdAt.toIso8601String(),
            ]);
          }
        }
      }

      // 3. Notes
      if (_includeNotes) {
        final notes = await bookRepo.watchAllNotes().first;
        final filteredNotes = notes
            .where((n) => matchesFilter(n.bookId))
            .toList();

        if (_exportFormat == ExportFormat.txt) {
          if (filteredNotes.isNotEmpty) {
            buffer.writeln('=== NOTES & JOURNAL ===');
            buffer.writeln();
            for (var note in filteredNotes) {
              final book = bookMap[note.bookId];
              buffer.writeln('Note: ${note.content}');
              if (book != null) buffer.writeln('Book: ${book.title}');
              buffer.writeln(
                'Date: ${DateFormat.yMMMd().format(note.createdAt)}',
              );
              buffer.writeln();
            }
            buffer.writeln('----------------------------------------');
            buffer.writeln();
          }
        } else {
          for (var note in filteredNotes) {
            final book = bookMap[note.bookId];
            csvRows.add([
              'Note',
              book?.title ?? '',
              book?.author ?? '',
              note.content,
              '',
              note.createdAt.toIso8601String(),
            ]);
          }
        }
      }

      // Generate File
      final String fileContent = _exportFormat == ExportFormat.txt
          ? buffer.toString()
          : _generateCsv(csvRows);

      final tempDir = await getTemporaryDirectory();
      final ext = _exportFormat == ExportFormat.txt ? 'txt' : 'csv';
      final file = File('${tempDir.path}/liberry_export.${ext}');
      await file.writeAsString(fileContent);

      if (!mounted) return;

      // Share
      final result = await Share.shareXFiles([
        XFile(file.path),
      ], text: 'Liberry Export');

      if (mounted) {
        Navigator.pop(context); // Close dialog
        if (result.status == ShareResultStatus.success) {
          // Maybe show toast? Share plugin usually handles UI.
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  String _generateCsv(List<List<String>> rows) {
    // Simple CSV generator handling quotes
    // CSV rules: if field contains comma, quote, or newline, wrap in quotes.
    // Escape existing quotes with double quotes.
    final buffer = StringBuffer();
    for (var row in rows) {
      buffer.writeln(row.map(_escapeCsvField).join(','));
    }
    return buffer.toString();
  }

  String _escapeCsvField(String field) {
    if (field.contains(',') || field.contains('"') || field.contains('\n')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }
}
