import 'dart:io';

import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liberry/data/database.dart';
import 'package:liberry/data/sync/sync_database.dart';
import 'package:liberry/providers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:liberry/data/remote/remote_book.dart';
import 'package:uuid/uuid.dart';

final syncServiceProvider = Provider((ref) {
  final db = ref.watch(databaseProvider);
  return SyncService(db);
});

class SyncService {
  final AppDatabase _db;

  SyncService(this._db);

  Future<void> exportToSyncFile(File file) async {
    // SAFE SYNC EXPORT:
    // 1. Create a temporary file to write the fresh DB to.
    // 2. Clear/Fill that temp DB.
    // 3. Close it.
    // 4. Copy it over the target file (Safe atomic-ish replace).

    final tempDir = await getTemporaryDirectory();
    final tempFile = File(p.join(tempDir.path, 'temp_sync_export.db'));

    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    // Open SyncDatabase on the temp file
    // IMPORTANT: Use 'journal_mode=DELETE' to keep it in one file if possible (no WAL),
    // although Drift defaults might be WAL. For specific file transfer, simple is better.
    // But modifying journal mode in Drift requires setup.
    // For now, standard open is fine provided we close it properly.
    final syncDb = SyncDatabase(NativeDatabase(tempFile));

    try {
      // Create tables explicitly since it's a new file
      // Drift usually does this lazily, but we want to be sure before writing.
      // Accessing the database triggers creation.
      await syncDb.customStatement('PRAGMA user_version = 0');

      // 1. Insert into SyncDB (Temp)
      await syncDb.transaction(() async {
        // Fetch all local data
        final books = await _db.select(_db.books).get();
        final progress = await _db.select(_db.readingProgress).get();
        final characters = await _db.select(_db.characters).get();
        final quotes = await _db.select(_db.quotes).get();
        final notes = await _db.select(_db.bookNotes).get();

        // Insert Batch
        await syncDb.batch((batch) {
          batch.insertAll(
            syncDb.syncBooks,
            books.map(
              (b) => SyncBooksCompanion(
                id: Value(b.id),
                title: Value(b.title),
                author: Value(b.author),
                downloadUrl: Value(b.downloadUrl),
                group: Value(b.group),
                status: Value(b.status),
                rating: Value(b.rating),
                userNotes: Value(b.userNotes),
                sourceMetadata: Value(b.sourceMetadata),
                language: Value(b.language),
                publishedDate: Value(b.publishedDate),
                addedAt: Value(b.addedAt),
                updatedAt: Value(b.updatedAt),
                isDeleted: Value(b.isDeleted),
              ),
            ),
          );

          batch.insertAll(
            syncDb.syncReadingProgress,
            progress.map(
              (p) => SyncReadingProgressCompanion(
                id: Value(p.id),
                bookId: Value(p.bookId),
                cfi: Value(p.cfi),
                progressPercentage: Value(p.progressPercentage),
                lastReadAt: Value(p.lastReadAt),
                updatedAt: Value(p.updatedAt),
                isDeleted: Value(p.isDeleted),
              ),
            ),
          );

          batch.insertAll(
            syncDb.syncCharacters,
            characters.map(
              (c) => SyncCharactersCompanion(
                id: Value(c.id),
                name: Value(c.name),
                bio: Value(c.bio),
                originBookId: Value(c.originBookId),
                createdAt: Value(c.createdAt),
                updatedAt: Value(c.updatedAt),
                isDeleted: Value(c.isDeleted),
              ),
            ),
          );

          batch.insertAll(
            syncDb.syncQuotes,
            quotes.map(
              (q) => SyncQuotesCompanion(
                id: Value(q.id),
                textContent: Value(q.textContent),
                bookId: Value(q.bookId),
                characterId: Value(q.characterId),
                cfi: Value(q.cfi),
                createdAt: Value(q.createdAt),
                updatedAt: Value(q.updatedAt),
                isDeleted: Value(q.isDeleted),
              ),
            ),
          );

          batch.insertAll(
            syncDb.syncBookNotes,
            notes.map(
              (n) => SyncBookNotesCompanion(
                id: Value(n.id),
                bookId: Value(n.bookId),
                quoteId: Value(n.quoteId),
                content: Value(n.content),
                createdAt: Value(n.createdAt),
                updatedAt: Value(n.updatedAt),
                isDeleted: Value(n.isDeleted),
              ),
            ),
          );
        });
      });
    } finally {
      await syncDb.close();
    }

    // 2. Overwrite Target File
    // Ensure we copy strictly the bytes.
    try {
      // If target exists, delete it first to ensure clean write?
      // Or just copySync (overwrites).
      // Safest is copySync.
      tempFile.copySync(file.path);
    } catch (e) {
      print('Failed to copy temp sync file to target: $e');
      rethrow;
    } finally {
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> importFromSyncFile(File file) async {
    if (!await file.exists()) return;

    // SAFE SYNC IMPORT:
    // 1. Copy target file to temp location.
    // 2. Read from temp location.
    // 3. Delete temp.

    final tempDir = await getTemporaryDirectory();
    final tempFile = File(p.join(tempDir.path, 'temp_sync_import.db'));

    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    try {
      file.copySync(tempFile.path);
    } catch (e) {
      print('Failed to copy sync file to temp: $e');
      rethrow;
    }

    final syncDb = SyncDatabase(NativeDatabase(tempFile));

    try {
      // Check if valid by simple select
      // await syncDb.select(syncDb.syncBooks).get();

      // Fetch all remote data
      final remoteBooks = await syncDb.select(syncDb.syncBooks).get();
      final remoteProgress = await syncDb
          .select(syncDb.syncReadingProgress)
          .get();
      final remoteCharacters = await syncDb.select(syncDb.syncCharacters).get();
      final remoteQuotes = await syncDb.select(syncDb.syncQuotes).get();
      final remoteNotes = await syncDb.select(syncDb.syncBookNotes).get();

      // Merge Logic: Last Write Wins
      await _db.transaction(() async {
        await _mergeBooks(remoteBooks);
        await _mergeReadingProgress(remoteProgress);
        await _mergeCharacters(remoteCharacters);
        await _mergeQuotes(remoteQuotes);
        await _mergeBookNotes(remoteNotes);
      });

      // After merge, try to restore missing assets (covers)
      await _restoreMissingCovers();
    } catch (e) {
      print('Sync Error: $e');
      rethrow;
    } finally {
      await syncDb.close();
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> _restoreMissingCovers() async {
    final books = await _db.select(_db.books).get();
    final appDir = await getApplicationDocumentsDirectory();

    print('_restoreMissingCovers: Checking ${books.length} books...');

    // Collect all cover updates to apply in a single transaction
    final Map<String, String> coverUpdates = {}; // bookId -> newCoverPath

    for (final book in books) {
      // Check if cover is missing - either null/empty or file doesn't exist
      bool needsCoverRestore = false;

      if (book.coverPath == null || book.coverPath!.isEmpty) {
        needsCoverRestore = true;
        print('Book "${book.title}": No coverPath set');
      } else {
        final fullPath = p.isAbsolute(book.coverPath!)
            ? book.coverPath!
            : p.join(appDir.path, book.coverPath!);

        if (!File(fullPath).existsSync()) {
          needsCoverRestore = true;
          print('Book "${book.title}": Cover file missing at $fullPath');
        }
      }

      if (needsCoverRestore) {
        // Try to restore from sourceMetadata
        if (book.sourceMetadata != null && book.sourceMetadata!.isNotEmpty) {
          try {
            final json = jsonDecode(book.sourceMetadata!);
            final remoteBook = RemoteBook.fromJson(json);

            if (remoteBook.coverUrl != null &&
                remoteBook.coverUrl!.startsWith('http')) {
              print(
                'Restoring missing cover for "${book.title}" from ${remoteBook.coverUrl}',
              );

              final coversDir = Directory(p.join(appDir.path, 'covers'));
              if (!await coversDir.exists()) {
                await coversDir.create(recursive: true);
              }

              // Preserve original file extension from URL
              final urlPath = Uri.parse(remoteBook.coverUrl!).path;
              final originalExt = p.extension(urlPath).isNotEmpty
                  ? p.extension(urlPath)
                  : '.jpg'; // Default to jpg if no extension
              final coverFileName = '${const Uuid().v4()}$originalExt';
              final coverFile = File(p.join(coversDir.path, coverFileName));

              try {
                final request = await HttpClient().getUrl(
                  Uri.parse(remoteBook.coverUrl!),
                );
                final response = await request.close();
                await response.pipe(coverFile.openWrite());

                // Collect the update for batch apply later
                final newCoverPath = p.join('covers', coverFileName);
                coverUpdates[book.id] = newCoverPath;
                print(
                  'Downloaded cover to $newCoverPath (will update DB in batch)',
                );
              } catch (e) {
                print('Failed to download cover during restore: $e');
              }
            } else {
              print(
                'Book "${book.title}": No valid coverUrl in sourceMetadata',
              );
            }
          } catch (e) {
            print('Failed to parse sourceMetadata for cover restore: $e');
          }
        } else {
          print('Book "${book.title}": No sourceMetadata available');
        }
      }
    }

    // Apply all cover updates in a single transaction (one stream emission)
    if (coverUpdates.isNotEmpty) {
      print(
        'Applying ${coverUpdates.length} cover updates in single transaction...',
      );
      await _db.transaction(() async {
        for (final entry in coverUpdates.entries) {
          await (_db.update(_db.books)..where((t) => t.id.equals(entry.key)))
              .write(BooksCompanion(coverPath: Value(entry.value)));
        }
      });
      print('Cover updates applied.');
    }

    print('_restoreMissingCovers: Done');
  }

  Future<void> _mergeBooks(List<SyncBook> remoteBooks) async {
    for (final remote in remoteBooks) {
      final local = await (_db.select(
        _db.books,
      )..where((tbl) => tbl.id.equals(remote.id))).getSingleOrNull();

      if (local == null) {
        // Insert new
        if (!remote.isDeleted) {
          // We need to handle required columns that are missing from SyncBooks (filePath, coverPath)
          // For filePath, we can't really know it. But this is a "shell" book until downloaded.
          // We might need a placeholder or specific logic.
          // For now, let's assume filePath is empty string or some placeholder,
          // and we rely on downloadUrl to fetch it.
          // But 'filePath' is non-nullable.

          await _db
              .into(_db.books)
              .insert(
                BooksCompanion(
                  id: Value(remote.id),
                  title: Value(remote.title),
                  author: Value(remote.author),
                  filePath: Value(''), // Placeholder, needs re-download
                  coverPath: Value(null),
                  downloadUrl: Value(remote.downloadUrl),
                  group: Value(remote.group),
                  status: Value(remote.status),
                  rating: Value(remote.rating),
                  userNotes: Value(remote.userNotes),
                  sourceMetadata: Value(remote.sourceMetadata),
                  language: Value(remote.language),
                  publishedDate: Value(remote.publishedDate),
                  addedAt: Value(remote.addedAt),
                  updatedAt: Value(remote.updatedAt),
                  isDeleted: Value(remote.isDeleted),
                  isDownloaded: Value(false), // Mark as not downloaded
                ),
              );
        }
      } else {
        // Update if remote is newer
        if (remote.updatedAt.isAfter(local.updatedAt)) {
          await (_db.update(
            _db.books,
          )..where((tbl) => tbl.id.equals(local.id))).write(
            BooksCompanion(
              title: Value(remote.title),
              author: Value(remote.author),
              downloadUrl: Value(remote.downloadUrl),
              group: Value(remote.group),
              status: Value(remote.status),
              rating: Value(remote.rating),
              userNotes: Value(remote.userNotes),
              sourceMetadata: Value(remote.sourceMetadata),
              language: Value(remote.language),
              publishedDate: Value(remote.publishedDate),
              // addedAt: Value(remote.addedAt), // Don't overwrite addedAt usually?
              updatedAt: Value(remote.updatedAt),
              isDeleted: Value(remote.isDeleted),
            ),
          );
        }
      }
    }
  }

  Future<void> _mergeReadingProgress(
    List<SyncReadingProgressData> remoteProgress,
  ) async {
    for (final remote in remoteProgress) {
      final local = await (_db.select(
        _db.readingProgress,
      )..where((tbl) => tbl.id.equals(remote.id))).getSingleOrNull();
      if (local == null) {
        if (!remote.isDeleted) {
          await _db
              .into(_db.readingProgress)
              .insert(
                ReadingProgressCompanion(
                  id: Value(remote.id),
                  bookId: Value(remote.bookId),
                  cfi: Value(remote.cfi),
                  progressPercentage: Value(remote.progressPercentage),
                  lastReadAt: Value(remote.lastReadAt),
                  updatedAt: Value(remote.updatedAt),
                  isDeleted: Value(remote.isDeleted),
                ),
              );
        }
      } else {
        if (remote.updatedAt.isAfter(local.updatedAt)) {
          await (_db.update(
            _db.readingProgress,
          )..where((tbl) => tbl.id.equals(local.id))).write(
            ReadingProgressCompanion(
              cfi: Value(remote.cfi),
              progressPercentage: Value(remote.progressPercentage),
              lastReadAt: Value(remote.lastReadAt),
              updatedAt: Value(remote.updatedAt),
              isDeleted: Value(remote.isDeleted),
            ),
          );
        }
      }
    }
  }

  Future<void> _mergeCharacters(List<SyncCharacter> remoteCharacters) async {
    for (final remote in remoteCharacters) {
      final local = await (_db.select(
        _db.characters,
      )..where((tbl) => tbl.id.equals(remote.id))).getSingleOrNull();
      if (local == null) {
        if (!remote.isDeleted) {
          await _db
              .into(_db.characters)
              .insert(
                CharactersCompanion(
                  id: Value(remote.id),
                  name: Value(remote.name),
                  bio: Value(remote.bio),
                  originBookId: Value(remote.originBookId),
                  createdAt: Value(remote.createdAt),
                  updatedAt: Value(remote.updatedAt),
                  isDeleted: Value(remote.isDeleted),
                ),
              );
        }
      } else {
        if (remote.updatedAt.isAfter(local.updatedAt)) {
          await (_db.update(
            _db.characters,
          )..where((tbl) => tbl.id.equals(local.id))).write(
            CharactersCompanion(
              name: Value(remote.name),
              bio: Value(remote.bio),
              originBookId: Value(remote.originBookId),
              createdAt: Value(remote.createdAt),
              updatedAt: Value(remote.updatedAt),
              isDeleted: Value(remote.isDeleted),
            ),
          );
        }
      }
    }
  }

  Future<void> _mergeQuotes(List<SyncQuote> remoteQuotes) async {
    for (final remote in remoteQuotes) {
      final local = await (_db.select(
        _db.quotes,
      )..where((tbl) => tbl.id.equals(remote.id))).getSingleOrNull();
      if (local == null) {
        if (!remote.isDeleted) {
          await _db
              .into(_db.quotes)
              .insert(
                QuotesCompanion(
                  id: Value(remote.id),
                  textContent: Value(remote.textContent),
                  bookId: Value(remote.bookId),
                  characterId: Value(remote.characterId),
                  cfi: Value(remote.cfi),
                  createdAt: Value(remote.createdAt),
                  updatedAt: Value(remote.updatedAt),
                  isDeleted: Value(remote.isDeleted),
                ),
              );
        }
      } else {
        if (remote.updatedAt.isAfter(local.updatedAt)) {
          await (_db.update(
            _db.quotes,
          )..where((tbl) => tbl.id.equals(local.id))).write(
            QuotesCompanion(
              textContent: Value(remote.textContent),
              bookId: Value(remote.bookId),
              characterId: Value(remote.characterId),
              cfi: Value(remote.cfi),
              createdAt: Value(remote.createdAt),
              updatedAt: Value(remote.updatedAt),
              isDeleted: Value(remote.isDeleted),
            ),
          );
        }
      }
    }
  }

  Future<void> _mergeBookNotes(List<SyncBookNote> remoteNotes) async {
    for (final remote in remoteNotes) {
      final local = await (_db.select(
        _db.bookNotes,
      )..where((tbl) => tbl.id.equals(remote.id))).getSingleOrNull();
      if (local == null) {
        if (!remote.isDeleted) {
          await _db
              .into(_db.bookNotes)
              .insert(
                BookNotesCompanion(
                  id: Value(remote.id),
                  bookId: Value(remote.bookId),
                  quoteId: Value(remote.quoteId),
                  content: Value(remote.content),
                  createdAt: Value(remote.createdAt),
                  updatedAt: Value(remote.updatedAt),
                  isDeleted: Value(remote.isDeleted),
                ),
              );
        }
      } else {
        if (remote.updatedAt.isAfter(local.updatedAt)) {
          await (_db.update(
            _db.bookNotes,
          )..where((tbl) => tbl.id.equals(local.id))).write(
            BookNotesCompanion(
              bookId: Value(remote.bookId),
              quoteId: Value(remote.quoteId),
              content: Value(remote.content),
              createdAt: Value(remote.createdAt),
              updatedAt: Value(remote.updatedAt),
              isDeleted: Value(remote.isDeleted),
            ),
          );
        }
      }
    }
  }
}
