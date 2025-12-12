import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'package:uuid/uuid.dart';

part 'database.g.dart';

class Books extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  TextColumn get coverPath => text().nullable()();
  TextColumn get filePath => text()();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();

  // New columns for Library v2
  TextColumn get group =>
      text().nullable()(); // Now represents 'location': 'desk' or 'bookshelf'
  TextColumn get status => text().withDefault(
    const Constant('not_started'),
  )(); // 'not_started', 'reading', 'read'
  BoolColumn get isRead => boolean().withDefault(
    const Constant(false),
  )(); // Keeping for legacy/backup, but 'status' should be primary
  IntColumn get rating => integer().nullable()(); // 0-5
  TextColumn get userNotes => text().nullable()();
  TextColumn get downloadUrl => text().nullable()();
  TextColumn get sourceMetadata => text().nullable()();
  TextColumn get language => text().nullable()();
  DateTimeColumn get publishedDate => dateTime().nullable()();
  BoolColumn get isDownloaded => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class ReadingProgress extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get bookId => text().references(Books, #id)();
  TextColumn get cfi => text()(); // Current reading position
  RealColumn get progressPercentage =>
      real().withDefault(const Constant(0.0))();
  DateTimeColumn get lastReadAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Characters extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get name => text()();
  TextColumn get bio => text().nullable()();
  TextColumn get imagePath => text().nullable()();
  TextColumn get originBookId => text().references(Books, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Quotes extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get textContent =>
      text()(); // 'text' is a reserved word in some SQL, safer to use textContent
  TextColumn get bookId => text().references(Books, #id)();
  TextColumn get characterId => text().nullable().references(Characters, #id)();
  TextColumn get cfi => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class BookNotes extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get bookId => text().references(Books, #id)();
  TextColumn get quoteId =>
      text().nullable().references(Quotes, #id)(); // Link to highlight
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Books, ReadingProgress, Characters, Quotes, BookNotes])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 9; // Updated to 9

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.createTable(characters);
          await m.createTable(quotes);
        }
        if (from < 3) {
          // Previous attempt to fix schema, might have been skipped or failed.
        }
        if (from < 4) {
          // Fix for NOT NULL constraint on character_id in quotes table.
          // SQLite doesn't support altering column nullability.
          // We must recreate the table.

          // 1. Rename existing table
          await m.issueCustomQuery('ALTER TABLE quotes RENAME TO quotes_old');

          // 2. Create new table with correct schema (nullable character_id)
          await m.createTable(quotes);

          // 3. Copy data from old table to new table
          await m.issueCustomQuery(
            'INSERT INTO quotes (id, text_content, book_id, character_id, cfi, created_at) '
            'SELECT id, text_content, book_id, character_id, cfi, created_at FROM quotes_old',
          );

          // 4. Drop old table
          await m.issueCustomQuery('DROP TABLE quotes_old');
        }
        if (from < 5) {
          // Add new columns to Books table
          await m.addColumn(books, books.group);
          await m.addColumn(books, books.isRead);
          await m.addColumn(books, books.rating);
          await m.addColumn(books, books.userNotes);
          await m.addColumn(books, books.downloadUrl);
          await m.addColumn(books, books.sourceMetadata);
          await m.addColumn(books, books.language);
          await m.addColumn(books, books.publishedDate);
          await m.addColumn(books, books.isDownloaded);
        }
        if (from < 6) {
          // Add BookNotes table
          await m.createTable(bookNotes);

          // Iterate over all books and migrate userNotes to BookNotes
          final allBooks = await select(books).get();
          for (final book in allBooks) {
            if (book.userNotes != null && book.userNotes!.isNotEmpty) {
              await into(bookNotes).insert(
                BookNotesCompanion.insert(
                  id: Uuid().v4(),
                  bookId: book.id,
                  content: book.userNotes!,
                  createdAt: Value(
                    DateTime.now(),
                  ), // Or book.addedAt if better? DateTime.now() is safer.
                ),
              );
            }
          }
        }
        if (from < 7) {
          // Add quoteId to BookNotes
          await m.addColumn(bookNotes, bookNotes.quoteId);
        }
        if (from < 8) {
          // Add status column
          await m.addColumn(books, books.status);

          // Migration logic for status and location
          final allBooks = await select(books).get();
          for (final book in allBooks) {
            String newStatus = 'not_started';
            String newGroup = 'desk'; // Default location

            // Check existing 'group' (legacy location/status mix)
            final oldGroup = book.group;
            final isRead = book.isRead;

            if (oldGroup == 'read' || isRead) {
              newStatus = 'read';
              newGroup = 'bookshelf';
            } else if (oldGroup == 'bookshelf') {
              newStatus =
                  'not_started'; // Assume not started if just on bookshelf, or could be 'reading' but seemingly 'desk' is reading
              newGroup = 'bookshelf';
            } else if (oldGroup == 'reading' || oldGroup == null) {
              newStatus = 'reading';
              newGroup = 'desk';
            }

            await (update(books)..where((t) => t.id.equals(book.id))).write(
              BooksCompanion(status: Value(newStatus), group: Value(newGroup)),
            );
          }
        }
        if (from < 9) {
          // Add updatedAt and isDeleted columns
          final now = DateTime.now();
          final nowMillis =
              now.millisecondsSinceEpoch ~/
              1000; // Seconds for Drift Integer Storage (default)

          // Helper to add columns manually to avoid "non-constant default" error with currentDateAndTime
          Future<void> addSyncColumns(String tableName) async {
            // updated_at: INTEGER NOT NULL DEFAULT 0
            await m.issueCustomQuery(
              'ALTER TABLE $tableName ADD COLUMN updated_at INTEGER NOT NULL DEFAULT $nowMillis',
            );
            // is_deleted: INTEGER NOT NULL DEFAULT 0 (boolean is integer 0/1)
            // Drift booleans are integers. Default false = 0.
            await m.issueCustomQuery(
              'ALTER TABLE $tableName ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
            );
          }

          await addSyncColumns('books');
          await addSyncColumns('reading_progress');
          await addSyncColumns('characters');
          await addSyncColumns('quotes');
          await addSyncColumns('book_notes');

          // No need to manually update rows because we set the DEFAULT to 'nowMillis' (current timestamp)
          // valid for the moment of migration.
        }
      },
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'db.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
