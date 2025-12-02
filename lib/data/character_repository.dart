import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'database.dart';

class CharacterRepository {
  final AppDatabase _db;

  CharacterRepository(this._db);

  // --- Characters ---

  Future<String> createCharacter({
    required String name,
    required String originBookId,
    String? bio,
    String? imagePath,
  }) async {
    final id = const Uuid().v4();
    await _db
        .into(_db.characters)
        .insert(
          CharactersCompanion.insert(
            id: id,
            name: name,
            originBookId: originBookId,
            bio: Value(bio),
            imagePath: Value(imagePath),
          ),
        );
    return id;
  }

  Future<void> updateCharacter(Character character) async {
    await _db.update(_db.characters).replace(character);
  }

  Future<void> deleteCharacter(String id) async {
    await (_db.delete(_db.characters)..where((t) => t.id.equals(id))).go();
  }

  Stream<List<Character>> watchAllCharacters() {
    return (_db.select(
      _db.characters,
    )..orderBy([(t) => OrderingTerm(expression: t.name)])).watch();
  }

  Future<Character?> getCharacter(String id) {
    return (_db.select(
      _db.characters,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Stream<List<Character>> searchCharacters(String query) {
    return (_db.select(
      _db.characters,
    )..where((t) => t.name.contains(query) | t.bio.contains(query))).watch();
  }

  // --- Quotes ---

  Future<void> addQuote({
    required String text,
    required String bookId,
    required String characterId,
    String? cfi,
  }) async {
    await _db
        .into(_db.quotes)
        .insert(
          QuotesCompanion.insert(
            id: const Uuid().v4(),
            textContent: text,
            bookId: bookId,
            characterId: Value(characterId),
            cfi: Value(cfi),
          ),
        );
  }

  Stream<List<Quote>> watchQuotesForCharacter(String characterId) {
    return (_db.select(
      _db.quotes,
    )..where((t) => t.characterId.equals(characterId))).watch();
  }

  Stream<List<QuoteWithBook>> watchAllQuotesWithBooks(String query) {
    final joinedQuery =
        (_db.select(
          _db.quotes,
        )..where((t) => t.textContent.contains(query))).join([
          innerJoin(_db.books, _db.books.id.equalsExp(_db.quotes.bookId)),
        ]);

    joinedQuery.orderBy([OrderingTerm(expression: _db.books.title)]);

    return joinedQuery.watch().map((rows) {
      return rows.map((row) {
        return QuoteWithBook(
          row.readTable(_db.quotes),
          row.readTable(_db.books),
        );
      }).toList();
    });
  }
}

class QuoteWithBook {
  final Quote quote;
  final Book book;

  QuoteWithBook(this.quote, this.book);
}
