import 'dart:io';
import 'package:drift/drift.dart';
import 'package:epubx/epubx.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;
import 'database.dart';

class BookRepository {
  final AppDatabase _db;

  BookRepository(this._db);

  Future<String> addBook(
    String filePath, {
    String? remoteCoverUrl,
    String? downloadUrl,
    String? sourceMetadata,
  }) async {
    File file = File(filePath);

    // If path is relative, resolve it against documents directory
    if (!p.isAbsolute(filePath)) {
      final appDir = await getApplicationDocumentsDirectory();
      file = File(p.join(appDir.path, filePath));
    }

    if (!await file.exists()) {
      throw Exception('File not found: ${file.path}');
    }

    final bytes = await file.readAsBytes();
    EpubBook? epubBook;
    try {
      epubBook = await EpubReader.readBook(bytes);
    } catch (e) {
      // Fallback to basic info if parsing fails
      print('EPUB parsing failed: $e');
    }

    final title = epubBook?.Title ?? p.basename(filePath);
    final author = epubBook?.Author;

    String? coverPath;

    // 1. Try to download remote cover if provided
    if (remoteCoverUrl != null) {
      print('Attempting to download remote cover: $remoteCoverUrl');
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final coversDir = Directory(p.join(appDir.path, 'covers'));
        if (!await coversDir.exists()) {
          await coversDir.create(recursive: true);
        }

        final coverFileName = '${const Uuid().v4()}.png';
        final coverFile = File(p.join(coversDir.path, coverFileName));

        // Download the image
        final request = await HttpClient().getUrl(Uri.parse(remoteCoverUrl));
        final response = await request.close();
        await response.pipe(coverFile.openWrite());

        coverPath = p.join('covers', coverFileName);
        print('Downloaded and saved remote cover to: $coverPath');
      } catch (e) {
        print('Failed to download remote cover: $e');
      }
    }

    // 2. If no remote cover (or download failed), try extraction from EPUB
    if (coverPath == null) {
      // Try to get cover image
      img.Image? coverImage = epubBook?.CoverImage;

      // Fallback: Look for image with 'cover' in filename
      if (coverImage == null && epubBook?.Content?.Images != null) {
        print('CoverImage is null, trying fallback...');
        try {
          final images = epubBook!.Content!.Images!;
          print('Available images: ${images.keys.toList()}'); // Debugging line

          var coverKey = images.keys.firstWhere(
            (key) => key.toLowerCase().contains('cover'),
            orElse: () => '',
          );

          // If no 'cover' found, try to find the largest image (likely the high-res cover)
          if (coverKey.isEmpty && images.isNotEmpty) {
            print('No "cover" filename found. Searching for largest image...');
            int maxSize = 0;
            for (final entry in images.entries) {
              final size = entry.value.Content?.length ?? 0;
              if (size > maxSize) {
                maxSize = size;
                coverKey = entry.key;
              }
            }
            print(
              'Selected largest image as cover: $coverKey ($maxSize bytes)',
            );
          }

          if (coverKey.isNotEmpty) {
            print('Found fallback cover image: $coverKey');
            final coverContent = images[coverKey];
            if (coverContent != null) {
              coverImage = img.decodeImage(
                Uint8List.fromList(coverContent.Content!),
              );
            }
          }
        } catch (e) {
          print('Fallback cover extraction failed: $e');
        }
      }

      if (coverImage != null) {
        print('Found cover image (original or fallback)');
        try {
          final appDir = await getApplicationDocumentsDirectory();
          final coversDir = Directory(p.join(appDir.path, 'covers'));
          if (!await coversDir.exists()) {
            await coversDir.create(recursive: true);
          }

          final coverFileName = '${const Uuid().v4()}.png';
          final coverFile = File(p.join(coversDir.path, coverFileName));

          // Encode image to PNG
          final coverBytes = img.encodePng(coverImage);
          await coverFile.writeAsBytes(coverBytes);
          // Store relative path
          coverPath = p.join('covers', coverFileName);
          print('Saved cover to: $coverPath');
        } catch (e) {
          // Ignore cover error for now
          print('Error saving cover: $e');
        }
      } else {
        print('No cover image found in EPUB (even after fallback)');
      }
    }

    final id = const Uuid().v4();
    await _db
        .into(_db.books)
        .insert(
          BooksCompanion.insert(
            id: id,
            title: title,
            filePath: filePath,
            author: Value(author),
            coverPath: Value(coverPath),
            downloadUrl: Value(downloadUrl),
            sourceMetadata: Value(sourceMetadata),
          ),
        );
    return id;
  }

  Future<List<Book>> getAllBooks() async {
    final books = await (_db.select(
      _db.books,
    )..where((t) => t.isDeleted.equals(false))).get();
    return _resolveBookPaths(books);
  }

  Stream<List<Book>> watchAllBooks() {
    return (_db.select(
      _db.books,
    )..where((t) => t.isDeleted.equals(false))).watch().asyncMap((books) async {
      return await _resolveBookPaths(books);
    });
  }

  Future<bool> isBookDownloaded(String title) async {
    final query = _db.select(_db.books)
      ..where(
        (tbl) =>
            tbl.title.lower().equals(title.toLowerCase()) &
            tbl.isDeleted.equals(false),
      );
    final result = await query.getSingleOrNull();
    return result != null;
  }

  Future<Book?> getBook(String id) async {
    final books = await (_db.select(
      _db.books,
    )..where((t) => t.id.equals(id) & t.isDeleted.equals(false))).get();
    if (books.isEmpty) return null;
    return (await _resolveBookPaths(books)).first;
  }

  Future<List<Book>> _resolveBookPaths(List<Book> books) async {
    final appDir = await getApplicationDocumentsDirectory();
    final docsPath = appDir.path;

    return books.map((book) {
      // Check if path is already absolute (legacy support)
      if (p.isAbsolute(book.filePath)) {
        // Optional: Check existence and try to rescue if missing (legacy migration)
        final file = File(book.filePath);
        if (!file.existsSync()) {
          final basename = p.basename(book.filePath);
          final newPath = p.join(docsPath, basename);
          if (File(newPath).existsSync()) {
            return book.copyWith(filePath: newPath);
          }
        }
        return book;
      }

      // It's relative (just filename), so prepend docs dir
      return book.copyWith(filePath: p.join(docsPath, book.filePath));
    }).toList();
  }

  Future<void> saveReadingProgress(String bookId, String cfi) async {
    // Check if progress exists
    final progress = await (_db.select(
      _db.readingProgress,
    )..where((tbl) => tbl.bookId.equals(bookId))).getSingleOrNull();

    if (progress != null) {
      await (_db.update(
        _db.readingProgress,
      )..where((tbl) => tbl.bookId.equals(bookId))).write(
        ReadingProgressCompanion(
          cfi: Value(cfi),
          lastReadAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } else {
      await _db
          .into(_db.readingProgress)
          .insert(
            ReadingProgressCompanion.insert(
              id: const Uuid().v4(),
              bookId: bookId,
              cfi: cfi,
              lastReadAt: Value(DateTime.now()),
            ),
          );
    }
  }

  Future<String?> getReadingProgress(String bookId) async {
    final progress = await (_db.select(
      _db.readingProgress,
    )..where((tbl) => tbl.bookId.equals(bookId))).getSingleOrNull();
    return progress?.cfi;
  }

  Future<void> deleteBook(String id) async {
    // 1. Fetch book to get file paths (for optional file cleanup)
    final book = await getBook(id);
    if (book != null) {
      final appDir = await getApplicationDocumentsDirectory();

      // 2. Delete EPUB file
      try {
        String filePath = book.filePath;
        if (!p.isAbsolute(filePath)) {
          filePath = p.join(appDir.path, filePath);
        }
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
          print('Deleted book file: $filePath');
        }
      } catch (e) {
        print('Error deleting book file: $e');
      }

      // 3. Delete Cover image
      if (book.coverPath != null) {
        try {
          String coverPath = book.coverPath!;
          if (!p.isAbsolute(coverPath)) {
            coverPath = p.join(appDir.path, coverPath);
          }
          final coverFile = File(coverPath);
          if (await coverFile.exists()) {
            await coverFile.delete();
            print('Deleted cover file: $coverPath');
          }
        } catch (e) {
          print('Error deleting cover file: $e');
        }
      }
    }

    // 4. Soft Delete: Update isDeleted = true and updatedAt = now
    final now = DateTime.now();

    await (_db.update(_db.books)..where((t) => t.id.equals(id))).write(
      BooksCompanion(isDeleted: Value(true), updatedAt: Value(now)),
    );

    // Recursively soft-delete related data?
    // SyncService typically syncs these tables independently, so we should probably soft-delete them too.
    await (_db.update(
      _db.readingProgress,
    )..where((t) => t.bookId.equals(id))).write(
      ReadingProgressCompanion(isDeleted: Value(true), updatedAt: Value(now)),
    );

    await (_db.update(_db.quotes)..where((t) => t.bookId.equals(id))).write(
      QuotesCompanion(isDeleted: Value(true), updatedAt: Value(now)),
    );

    await (_db.update(_db.bookNotes)..where((t) => t.bookId.equals(id))).write(
      BookNotesCompanion(isDeleted: Value(true), updatedAt: Value(now)),
    );
  }

  Future<String> addHighlight(String bookId, String text, String cfi) async {
    print(
      "BookRepository: Adding highlight for book $bookId. Text: ${text.length > 10 ? text.substring(0, 10) : text}...",
    );
    final id = const Uuid().v4();
    await _db
        .into(_db.quotes)
        .insert(
          QuotesCompanion.insert(
            id: id,
            textContent: text,
            bookId: bookId,
            cfi: Value(cfi),
            // characterId is now nullable, so we don't pass it
          ),
        );
    print("BookRepository: Highlight added with ID $id");
    return id;
  }

  Stream<List<Quote>> watchHighlightsForBook(String bookId) {
    return (_db.select(_db.quotes)
          ..where((t) => t.bookId.equals(bookId) & t.isDeleted.equals(false)))
        .watch();
  }

  Future<List<Quote>> getHighlights(String bookId) async {
    print("BookRepository: Fetching highlights for book $bookId");
    final results = await (_db.select(
      _db.quotes,
    )..where((t) => t.bookId.equals(bookId) & t.isDeleted.equals(false))).get();
    print("BookRepository: Found ${results.length} highlights");
    return results;
  }

  Future<void> updateHighlightCharacter(String quoteId, String? characterId) {
    return (_db.update(_db.quotes)..where((t) => t.id.equals(quoteId))).write(
      QuotesCompanion(
        characterId: Value(characterId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // Alias for backward compatibility
  Future<void> assignQuoteToCharacter(String quoteId, String? characterId) =>
      updateHighlightCharacter(quoteId, characterId);

  Future<void> deleteHighlight(String id) {
    return (_db.update(_db.quotes)..where((t) => t.id.equals(id))).write(
      QuotesCompanion(isDeleted: Value(true), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> updateBook(String id, BooksCompanion companion) {
    return (_db.update(_db.books)..where((t) => t.id.equals(id))).write(
      companion.copyWith(updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> updateBookStatus(String id, String status) {
    return updateBook(
      id,
      BooksCompanion(
        status: Value(status),
        isRead: Value(status == 'read'), // Sync legacy field
      ),
    );
  }

  Future<void> updateBookFile(String id, String filePath, bool isDownloaded) {
    return updateBook(
      id,
      BooksCompanion(
        filePath: Value(filePath),
        isDownloaded: Value(isDownloaded),
      ),
    );
  }

  Future<void> updateBookLocation(String id, String location) {
    return updateBook(id, BooksCompanion(group: Value(location)));
  }

  // Legacy alias, forwarding to new location logic
  Future<void> setBookGroup(String id, String group) {
    return updateBookLocation(id, group);
  }

  // Legacy alias, forwarding to new status logic (boolean to string)
  Future<void> setBookReadStatus(String id, bool isRead) {
    return updateBookStatus(id, isRead ? 'read' : 'reading');
  }

  Future<void> offloadBook(String id) async {
    // 1. Get book to find file path
    final book = await (_db.select(
      _db.books,
    )..where((t) => t.id.equals(id))).getSingle();

    // Resolve path if it's relative
    String fullPath = book.filePath;
    if (!p.isAbsolute(fullPath)) {
      final appDir = await getApplicationDocumentsDirectory();
      fullPath = p.join(appDir.path, fullPath);
    }

    // 2. Delete local file if it exists
    final file = File(fullPath);
    if (await file.exists()) {
      await file.delete();
      print('Offloaded book: Deleted file at $fullPath');
    } else {
      print('Offloaded book: File not found at $fullPath (already deleted?)');
    }

    // 3. Update DB
    await updateBook(
      id,
      const BooksCompanion(
        group: Value('bookshelf'), // Move to bookshelf
        // Keep status! Don't reset to 'not_started' so we don't lose reading state.
        isDownloaded: Value(false),
      ),
    );
  }

  Future<List<Book>> searchBooks(String query) async {
    final lowerQuery = query.toLowerCase();

    // Simple search implementation
    // For more complex search (highlights), might need more advanced query or multiple steps

    // 1. Search Titles & Authors
    final bookResults =
        await (_db.select(_db.books)..where(
              (t) =>
                  (t.title.lower().contains(lowerQuery) |
                      t.author.lower().contains(lowerQuery)) &
                  t.isDeleted.equals(false),
            ))
            .get();

    // 2. Search Highlights
    final quoteResults =
        await (_db.select(_db.quotes)..where(
              (t) =>
                  t.textContent.lower().contains(lowerQuery) &
                  t.isDeleted.equals(false),
            ))
            .get();

    final bookIdsFromQuotes = quoteResults.map((q) => q.bookId).toSet();

    // Combine
    final additionalBooks =
        await (_db.select(_db.books)..where(
              (t) => t.id.isIn(bookIdsFromQuotes) & t.isDeleted.equals(false),
            ))
            .get();

    final allBooks = {...bookResults, ...additionalBooks}.toList();

    // Re-resolve paths (needed for covers etc in UI)
    return _resolveBookPaths(allBooks);
  }

  // Note Management
  Stream<List<BookNote>> watchNotesForBook(String bookId) {
    return (_db.select(_db.bookNotes)
          ..where((t) => t.bookId.equals(bookId) & t.isDeleted.equals(false))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Stream<List<BookNote>> watchAllNotes() {
    return (_db.select(_db.bookNotes)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Future<void> addBookNote(String bookId, String content, {String? quoteId}) {
    return _db
        .into(_db.bookNotes)
        .insert(
          BookNotesCompanion.insert(
            id: const Uuid().v4(),
            bookId: bookId,
            quoteId: Value(quoteId),
            content: content,
            createdAt: Value(DateTime.now()),
          ),
        );
  }

  // Alias for backward compatibility
  Future<void> addNote(String bookId, String content) =>
      addBookNote(bookId, content);

  Future<void> deleteNote(String noteId) {
    return (_db.update(_db.bookNotes)..where((t) => t.id.equals(noteId))).write(
      BookNotesCompanion(
        isDeleted: Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> updateNote(String noteId, String content) {
    return (_db.update(_db.bookNotes)..where((t) => t.id.equals(noteId))).write(
      BookNotesCompanion(
        content: Value(content),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> updateNoteQuote(String noteId, String? quoteId) {
    return (_db.update(_db.bookNotes)..where((t) => t.id.equals(noteId))).write(
      BookNotesCompanion(
        quoteId: Value(quoteId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
