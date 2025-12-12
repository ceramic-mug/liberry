import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

class OfflineGutenbergService {
  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'gutenberg_optimized.db');

    // Check if DB exists. If not, copy from assets.
    final exists = await databaseExists(path);

    if (!exists) {
      print("Creating new copy of Gutenberg DB from assets...");
      try {
        await Directory(dirname(path)).create(recursive: true);

        // Load from assets
        ByteData data = await rootBundle.load("assets/gutenberg_optimized.db");
        List<int> bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );

        // Write to file system
        await File(path).writeAsBytes(bytes, flush: true);
        print("Database copied successfully");
      } catch (e) {
        print("Error copying database: $e");
        // Re-throw so we know it failed, or handle gracefully?
        // If it fails, openDatabase might fail or create an empty one.
      }
    } else {
      print("Opening existing Gutenberg DB");
    }

    return await openDatabase(path, readOnly: true);
  }

  // The Search Function
  Future<List<Map<String, dynamic>>> searchBooks(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      final db = await database;

      // Sanitize query for FTS5 (remove special syntax chars if needed)
      // FTS syntax: "austen*" matches "austen" and "austens"
      final sanitized = query.replaceAll(RegExp(r'[^a-zA-Z0-9 ]'), '');
      if (sanitized.isEmpty) return [];

      // Query using MATCH
      // Using simple formatting: title OR author matches query*
      final results = await db.rawQuery(
        '''
        SELECT rowid as id, title, author 
        FROM books_fts 
        WHERE books_fts MATCH ? 
        ORDER BY rank 
        LIMIT 50
      ''',
        ['"$sanitized"*'],
      ); // Enquote and add wildcards for prefix matching

      return results;
    } catch (e) {
      print("Search error: $e");
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getRandomBooks({int limit = 50}) async {
    try {
      final db = await database;
      // We query the main 'books' table for random access as it's faster/easier for this than FTS
      final results = await db.rawQuery(
        'SELECT id, title, author FROM books ORDER BY RANDOM() LIMIT ?',
        [limit],
      );
      return results;
    } catch (e) {
      print("Random search error: $e");
      return [];
    }
  }
}
