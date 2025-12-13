import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';
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

  Stream<List<QuoteWithBook>> watchAllQuotesWithBooks(
    String query, {
    String? bookId,
    String? author,
  }) {
    final queryLower = query.toLowerCase();

    // Start with a join
    final joinedQuery = (_db.select(_db.quotes).join([
      innerJoin(_db.books, _db.books.id.equalsExp(_db.quotes.bookId)),
    ]));

    // Apply filters
    joinedQuery.where(
      _db.quotes.textContent.lower().contains(queryLower) |
          _db.books.title.lower().contains(queryLower),
    );

    if (bookId != null) {
      joinedQuery.where(_db.quotes.bookId.equals(bookId));
    }

    if (author != null) {
      joinedQuery.where(_db.books.author.equals(author));
    }

    joinedQuery.orderBy([OrderingTerm(expression: _db.books.title)]);

    return joinedQuery.watch().asyncMap((rows) async {
      final appDir = await getApplicationDocumentsDirectory();
      final docsPath = appDir.path;

      return rows.map((row) {
        var book = row.readTable(_db.books);

        // Resolve Path Logic (Duplicate of BookRepository)
        if (p.isAbsolute(book.filePath)) {
          final file = File(book.filePath);
          if (!file.existsSync()) {
            final basename = p.basename(book.filePath);
            final newPath = p.join(docsPath, basename);
            if (File(newPath).existsSync()) {
              book = book.copyWith(filePath: newPath);
            }
          }
        } else {
          book = book.copyWith(filePath: p.join(docsPath, book.filePath));
        }

        return QuoteWithBook(row.readTable(_db.quotes), book);
      }).toList();
    });
  }

  Stream<List<CharacterWithBook>> watchCharactersWithFilteredBooks(
    String query, {
    String? bookId,
    String? author,
  }) {
    final queryLower = query.toLowerCase();

    // Join Characters with Books to allow filtering by book/author
    final joinedQuery = _db.select(_db.characters).join([
      innerJoin(_db.books, _db.books.id.equalsExp(_db.characters.originBookId)),
    ]);

    // Apply text search filter (Name or Bio)
    joinedQuery.where(
      _db.characters.name.lower().contains(queryLower) |
          _db.characters.bio.lower().contains(queryLower),
    );

    // Apply Book ID Filter
    if (bookId != null) {
      joinedQuery.where(_db.characters.originBookId.equals(bookId));
    }

    // Apply Author Filter
    if (author != null) {
      joinedQuery.where(_db.books.author.equals(author));
    }

    joinedQuery.orderBy([OrderingTerm(expression: _db.characters.name)]);

    return joinedQuery.watch().asyncMap((rows) async {
      final appDir = await getApplicationDocumentsDirectory();
      final docsPath = appDir.path;

      return rows.map((row) {
        var book = row.readTable(_db.books);

        // Resolve Path Logic
        if (p.isAbsolute(book.filePath)) {
          final file = File(book.filePath);
          if (!file.existsSync()) {
            final basename = p.basename(book.filePath);
            final newPath = p.join(docsPath, basename);
            if (File(newPath).existsSync()) {
              book = book.copyWith(filePath: newPath);
            }
          }
        } else {
          book = book.copyWith(filePath: p.join(docsPath, book.filePath));
        }

        return CharacterWithBook(row.readTable(_db.characters), book);
      }).toList();
    });
  }
}

class QuoteWithBook {
  final Quote quote;
  final Book book;

  QuoteWithBook(this.quote, this.book);
}

class CharacterWithBook {
  final Character character;
  final Book book;

  CharacterWithBook(this.character, this.book);
}
