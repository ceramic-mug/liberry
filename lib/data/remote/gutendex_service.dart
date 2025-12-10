import 'package:dio/dio.dart';
import 'remote_book.dart';

class GutendexService {
  final Dio _dio;
  static const String _baseUrl = 'https://gutendex.com/books';

  GutendexService(this._dio);

  Future<GutendexFeed> fetchBooks({
    String? topic,
    String? search,
    String? sort,
    int? page,
    String? nextUrl,
  }) async {
    try {
      Response response;
      if (nextUrl != null) {
        response = await _dio.get(nextUrl);
      } else {
        final queryParams = <String, dynamic>{};
        if (topic != null) queryParams['topic'] = topic;
        if (search != null) queryParams['search'] = search;
        if (sort != null) queryParams['sort'] = sort;
        if (page != null) queryParams['page'] = page;

        response = await _dio.get(_baseUrl, queryParameters: queryParams);
      }

      final data = response.data;
      final results = data['results'] as List;
      final next = data['next'] as String?;

      final books = results.map((json) {
        final title = json['title'] as String;
        final authors = json['authors'] as List;
        final author = authors.isNotEmpty
            ? authors.first['name'] as String
            : 'Unknown';

        final formats = json['formats'] as Map<String, dynamic>;
        final coverUrl =
            formats['image/jpeg'] as String? ?? formats['image/png'] as String?;

        // Find best epub format
        String? downloadUrl = formats['application/epub+zip'] as String?;
        // If no epub, check for other formats if needed, but we focus on epub

        return RemoteBook(
          title: title,
          author: author,
          coverUrl: coverUrl,
          downloadUrl: downloadUrl,
          source: 'Project Gutenberg',
        );
      }).toList();

      return GutendexFeed(books: books, next: next);
    } catch (e) {
      print('Gutendex error: $e');
      return GutendexFeed(books: [], next: null);
    }
  }

  // Legacy wrapper for compatibility if needed, or remove if unused elsewhere
  Future<List<RemoteBook>> searchBooks(String query) async {
    final feed = await fetchBooks(search: query);
    return feed.books;
  }
}

class GutendexFeed {
  final List<RemoteBook> books;
  final String? next;

  GutendexFeed({required this.books, this.next});
}
