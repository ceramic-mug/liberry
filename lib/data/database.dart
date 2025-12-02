import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'database.g.dart';

class Books extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  TextColumn get coverPath => text().nullable()();
  TextColumn get filePath => text()();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();

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

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Books, ReadingProgress, Characters, Quotes])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 4; // Increment schema version

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
          // Note: We need to handle the case where character_id might be missing in old data if we just select all.
          // But since old schema had it as NOT NULL (presumably), it should be there.
          // However, if we are inserting new data with NULL, we want the new table to allow it.
          // The copy should work fine.
          await m.issueCustomQuery(
            'INSERT INTO quotes (id, text_content, book_id, character_id, cfi, created_at) '
            'SELECT id, text_content, book_id, character_id, cfi, created_at FROM quotes_old',
          );

          // 4. Drop old table
          await m.issueCustomQuery('DROP TABLE quotes_old');
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
