import 'dart:convert';
import 'package:flutter/services.dart';
import '../../data/remote/opds_models.dart';
import '../remote/remote_book.dart';

class LocalEbooksService {
  static const String _baseUrl = 'https://standardebooks.org/feeds/opds';

  Map<String, OpdsFeed> _feedCache = {};
  bool _isInitialized = false;

  List<OpdsAcquisitionEntry> _allBooks = [];

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      final jsonString = await rootBundle.loadString(
        'assets/standard_ebooks.json',
      );
      final Map<String, dynamic> db = json.decode(jsonString);

      // Build the cache
      if (db['subjects'] != null) {
        _indexFeed('$_baseUrl/subjects', db['subjects']);
      }
      if (db['authors'] != null) {
        _indexFeed('$_baseUrl/authors', db['authors']);
      }

      _isInitialized = true;
    } catch (e) {
      print('Error initializing LocalEbooksService: $e');
      // Fallback or rethrow?
      // Since this is critical for the feature, we should probably let the UI handle the error if fetch fails.
    }
  }

  void _indexFeed(String url, Map<String, dynamic> jsonFeed) {
    final title = jsonFeed['title'] as String? ?? 'Untitled';
    final entriesList = jsonFeed['entries'] as List<dynamic>? ?? [];

    List<OpdsEntry> entries = [];

    for (var entryJson in entriesList) {
      final type = entryJson['type'];
      final title = entryJson['title'] ?? 'Unknown';
      final id = entryJson['id'] ?? 'unknown';

      if (type == 'navigation') {
        final link = entryJson['link'] as String?;
        final content = entryJson['content'] as String? ?? '';

        if (link != null) {
          entries.add(
            OpdsNavigationEntry(
              title: title,
              id: id,
              content: content,
              link: link,
            ),
          );

          // Recursively index sub-feed if present (my crawler might have embedded it?)
          // My crawler plan said: "parsed['feed'] = sub_feed"
          if (entryJson['feed'] != null) {
            _indexFeed(link, entryJson['feed']);
          }
        }
      } else if (type == 'acquisition') {
        final book = OpdsAcquisitionEntry(
          title: title,
          id: id,
          author: entryJson['author'] ?? 'Unknown',
          summary: entryJson['summary'],
          coverUrl: entryJson['coverUrl'],
          epubUrl: entryJson['downloadUrl'],
          epubBestUrl: entryJson['downloadUrl'],
        );
        entries.add(book);
        _allBooks.add(book);
      }
    }

    _feedCache[url] = OpdsFeed(
      title: title,
      entries: entries,
      // Offline DB typically flattens pagination, so no nextLink usually
      nextLink: null,
    );
  }

  Future<OpdsFeed> fetchFeed(String url) async {
    await init();
    final feed = _feedCache[url];
    if (feed == null) {
      throw Exception('Feed not found in local database: $url');
    }
    return feed;
  }

  Future<OpdsFeed> fetchSubjects() async {
    return fetchFeed('$_baseUrl/subjects');
  }

  Future<OpdsFeed> fetchAuthors() async {
    return fetchFeed('$_baseUrl/authors');
  }

  // Search is a bit different now - we can search the entire index!
  // Or just rely on the client-side filter in the UI?
  // The UI currently filters the *current list*.
  // The global search in Discover screen searches *online*.
  // To replace Discover search, we'd need to index ALL books.
  // We can do that during init.

  Future<List<RemoteBook>> searchBooks(String query) async {
    await init();
    if (query.isEmpty) return [];

    final lowerQuery = query.toLowerCase();

    // Simple linear search over all cached books
    // In a real app with thousands of books, this is fast enough in Dart?
    // Standard Ebooks is ~1000 books. Should be instantaneous.

    // Use a set to avoid duplicates (books appear in both subjects and authors)
    final Set<String> seenIds = {};
    final List<RemoteBook> results = [];

    for (var book in _allBooks) {
      if (seenIds.contains(book.id)) continue;

      if (book.title.toLowerCase().contains(lowerQuery) ||
          book.author.toLowerCase().contains(lowerQuery)) {
        seenIds.add(book.id);
        results.add(book.toRemoteBook());
      }
    }

    return results;
  }
}
