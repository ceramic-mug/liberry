import 'package:drift/drift.dart';

part 'sync_database.g.dart';

// Sync Table Definitions - Mirroring AppDatabase but excluding local paths

class SyncBooks extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  // Exclude: coverPath, filePath (Local only)
  TextColumn get downloadUrl =>
      text().nullable()(); // Essential for re-download path

  // Metadata & State
  TextColumn get group => text().nullable()(); // 'desk' or 'bookshelf'
  TextColumn get status => text().withDefault(const Constant('not_started'))();
  IntColumn get rating => integer().nullable()();
  TextColumn get userNotes => text().nullable()(); // Legacy
  TextColumn get sourceMetadata => text().nullable()();
  TextColumn get language => text().nullable()();
  DateTimeColumn get publishedDate => dateTime().nullable()();

  // Sync Meta
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncReadingProgress extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get bookId =>
      text()(); // No foreign key constraint for loose coupling in sync file? Or keep it? keeping it is safer for integrity within the sync file.
  TextColumn get cfi => text()();
  RealColumn get progressPercentage =>
      real().withDefault(const Constant(0.0))();
  DateTimeColumn get lastReadAt => dateTime().withDefault(currentDateAndTime)();

  // Sync Meta
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncCharacters extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get bio => text().nullable()();
  // Exclude: imagePath (Local only)
  TextColumn get originBookId => text()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // Sync Meta
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncQuotes extends Table {
  TextColumn get id => text()();
  TextColumn get textContent => text()();
  TextColumn get bookId => text()();
  TextColumn get characterId => text().nullable()();
  TextColumn get cfi => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // Sync Meta
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncBookNotes extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text()();
  TextColumn get quoteId => text().nullable()();
  TextColumn get content => text()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // Sync Meta
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    SyncBooks,
    SyncReadingProgress,
    SyncCharacters,
    SyncQuotes,
    SyncBookNotes,
  ],
)
class SyncDatabase extends _$SyncDatabase {
  // We don't open the connection in the constructor typicaly for a dynamic file.
  // We'll use a specific constructor for opening on a file.
  SyncDatabase(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 1;
}
