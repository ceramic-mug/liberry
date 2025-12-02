import 'package:dio/dio.dart';
import 'package:xml/xml.dart';
import 'remote_book.dart';

class OpdsService {
  final Dio _dio;
  static const String _feedUrl = 'https://standardebooks.org/feeds/opds';

  OpdsService(this._dio);

  Future<List<RemoteBook>> fetchNewReleases() async {
    try {
      final response = await _dio.get('$_feedUrl/new-releases');
      final document = XmlDocument.parse(response.data);
      final entries = document.findAllElements('entry');

      return entries.map((entry) {
        final title = entry.findElements('title').first.innerText;
        final author = entry
            .findElements('author')
            .first
            .findElements('name')
            .first
            .innerText;

        String? coverUrl;
        String? downloadUrl;

        for (final link in entry.findElements('link')) {
          final rel = link.getAttribute('rel');
          final href = link.getAttribute('href');
          final type = link.getAttribute('type');

          if (rel != null &&
              (rel.contains('image') || rel.contains('thumbnail'))) {
            coverUrl = href;
          } else if (rel != null &&
              rel.contains('acquisition') &&
              type != null &&
              type.contains('application/epub+zip')) {
            downloadUrl = href;
          }
        }

        return RemoteBook(
          title: title,
          author: author,
          coverUrl: coverUrl,
          downloadUrl: downloadUrl,
          source: 'Standard Ebooks',
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<RemoteBook>> searchBooks(String query) async {
    try {
      // Standard Ebooks requires the query to be quoted: "query"
      final quotedQuery = '"$query"';

      final response = await _dio.get(
        '$_feedUrl/all',
        queryParameters: {'query': quotedQuery},
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
        ),
      );
      final document = XmlDocument.parse(response.data);
      final entries = document.findAllElements('entry');

      return entries.map((entry) {
        final title = entry.findElements('title').first.innerText;

        // Author handling might be nested or multiple
        String author = 'Unknown';
        final authorElement = entry.findElements('author').firstOrNull;
        if (authorElement != null) {
          final nameElement = authorElement.findElements('name').firstOrNull;
          if (nameElement != null) {
            author = nameElement.innerText;
          }
        }

        String? coverUrl;
        String? downloadUrl;

        for (final link in entry.findElements('link')) {
          final rel = link.getAttribute('rel');
          final href = link.getAttribute('href');
          final type = link.getAttribute('type');

          if (rel != null &&
              (rel.contains('image') || rel.contains('thumbnail'))) {
            coverUrl = href;
          } else if (rel != null &&
              rel.contains('acquisition') &&
              type != null &&
              type.contains('application/epub+zip')) {
            downloadUrl = href;
          }
        }

        return RemoteBook(
          title: title,
          author: author,
          coverUrl: coverUrl,
          downloadUrl: downloadUrl,
          source: 'Standard Ebooks',
        );
      }).toList();
    } catch (e) {
      print('Standard Ebooks search error: $e');
      return [];
    }
  }
}
