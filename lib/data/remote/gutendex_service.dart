import 'package:dio/dio.dart';
import 'remote_book.dart';

class GutendexService {
  final Dio _dio;
  static const String _baseUrl = 'https://gutendex.com/books';

  GutendexService(this._dio);

  Future<List<RemoteBook>> searchBooks(String query) async {
    try {
      final response = await _dio.get(
        _baseUrl,
        queryParameters: {'search': query},
      );
      final data = response.data;
      final results = data['results'] as List;

      return results.map((json) {
        final title = json['title'] as String;
        final authors = json['authors'] as List;
        final author = authors.isNotEmpty
            ? authors.first['name'] as String
            : 'Unknown';

        final formats = json['formats'] as Map<String, dynamic>;
        final coverUrl = formats['image/jpeg'] as String?;
        final downloadUrl = formats['application/epub+zip'] as String?;

        return RemoteBook(
          title: title,
          author: author,
          coverUrl: coverUrl,
          downloadUrl: downloadUrl,
          source: 'Project Gutenberg',
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }
}
