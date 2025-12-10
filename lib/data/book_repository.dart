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

  Future<void> addBook(String filePath, {String? remoteCoverUrl}) async {
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
          ),
        );
  }

  Stream<List<Book>> watchAllBooks() {
    return _db.select(_db.books).watch().asyncMap((books) async {
      return await _resolveBookPaths(books);
    });
  }

  Future<bool> isBookDownloaded(String title) async {
    final query = _db.select(_db.books)
      ..where((tbl) => tbl.title.lower().equals(title.toLowerCase()));
    final result = await query.getSingleOrNull();
    return result != null;
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
    await (_db.delete(_db.books)..where((t) => t.id.equals(id))).go();
    await (_db.delete(
      _db.readingProgress,
    )..where((t) => t.bookId.equals(id))).go();
    await (_db.delete(_db.quotes)..where((t) => t.bookId.equals(id))).go();
  }

  Future<String> addHighlight(String bookId, String text, String cfi) async {
    print(
      "BookRepository: Adding highlight for book $bookId. Text: ${text.substring(0, 10)}...",
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
    return (_db.select(
      _db.quotes,
    )..where((t) => t.bookId.equals(bookId))).watch();
  }

  Future<List<Quote>> getHighlights(String bookId) async {
    print("BookRepository: Fetching highlights for book $bookId");
    final results = await (_db.select(
      _db.quotes,
    )..where((t) => t.bookId.equals(bookId))).get();
    print("BookRepository: Found ${results.length} highlights");
    return results;
  }

  Future<void> assignQuoteToCharacter(String quoteId, String? characterId) {
    return (_db.update(_db.quotes)..where((t) => t.id.equals(quoteId))).write(
      QuotesCompanion(characterId: Value(characterId)),
    );
  }

  Future<void> deleteHighlight(String id) {
    return (_db.delete(_db.quotes)..where((t) => t.id.equals(id))).go();
  }

  Future<void> updateBook(String id, BooksCompanion companion) {
    return (_db.update(
      _db.books,
    )..where((t) => t.id.equals(id))).write(companion);
  }

  Future<void> setBookReadStatus(String id, bool isRead) {
    return updateBook(id, BooksCompanion(isRead: Value(isRead)));
  }

  Future<void> setBookGroup(String id, String group) {
    return updateBook(id, BooksCompanion(group: Value(group)));
  }

  Future<void> offloadBook(String id) async {
    // 1. Get book to find file path
    final book = await (_db.select(
      _db.books,
    )..where((t) => t.id.equals(id))).getSingle();

    // 2. Delete local file if it exists and is not an http link (just in case)
    if (await File(book.filePath).exists()) {
      await File(book.filePath).delete();
      print('Offloaded book: Deleted file at ${book.filePath}');
    }

    // 3. Update DB
    await updateBook(
      id,
      const BooksCompanion(
        group: Value('bookshelf'),
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
                  t.title.lower().contains(lowerQuery) |
                  t.author.lower().contains(lowerQuery),
            ))
            .get();

    // 2. Search Highlights
    final quoteResults = await (_db.select(
      _db.quotes,
    )..where((t) => t.textContent.lower().contains(lowerQuery))).get();

    final bookIdsFromQuotes = quoteResults.map((q) => q.bookId).toSet();

    // Combine
    final additionalBooks = await (_db.select(
      _db.books,
    )..where((t) => t.id.isIn(bookIdsFromQuotes))).get();

    final allBooks = {...bookResults, ...additionalBooks}.toList();

    // Re-resolve paths (needed for covers etc in UI)
    return _resolveBookPaths(allBooks);
  }
}
