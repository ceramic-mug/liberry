import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';
import 'remote_book.dart';
import 'opds_models.dart';

class OpdsService {
  final Dio _dio;
  static const String _baseUrl = 'https://standardebooks.org/feeds/opds';
  String? _authHeader;

  OpdsService(this._dio);

  void setCredentials(String username, String password) {
    final bytes = utf8.encode('$username:$password');
    final base64Str = base64.encode(bytes);
    _authHeader = 'Basic $base64Str';
  }

  Future<OpdsFeed> fetchFeed(String url) async {
    try {
      final options = Options(
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          if (_authHeader != null && url.contains('standardebooks.org'))
            'Authorization': _authHeader,
        },
      );

      final response = await _dio.get(url, options: options);
      final document = XmlDocument.parse(response.data);

      final titleElement = document.findAllElements('title').firstOrNull;
      final feedTitle = titleElement?.innerText ?? 'Library';

      final nextLinkElement = document
          .findAllElements('link')
          .firstWhere(
            (element) => element.getAttribute('rel') == 'next',
            orElse: () => XmlElement(XmlName('dummy')),
          );

      String? nextLink;
      if (nextLinkElement.name.local != 'dummy') {
        final href = nextLinkElement.getAttribute('href');
        if (href != null) {
          nextLink = Uri.parse(url).resolve(href).toString();
        }
      }

      final entryElements = document.findAllElements('entry');
      final entries = <OpdsEntry>[];

      for (var entry in entryElements) {
        final title = entry.findElements('title').first.innerText;
        final id = entry.findElements('id').first.innerText;

        // Determine entry type based on links
        bool isAcquisition = false;
        String? coverUrl;
        String? thumbnail;
        String? epubUrl;
        String? epubBestUrl;
        String? navigationLink;

        for (final link in entry.findElements('link')) {
          final rel = link.getAttribute('rel');
          final href = link.getAttribute('href');
          final type = link.getAttribute('type');

          if (rel == null || href == null) continue;

          // Resolve relative URLs
          String absoluteHref;
          if (href.startsWith('data:')) {
            absoluteHref = href;
          } else {
            absoluteHref = Uri.parse(url).resolve(href).toString();
          }

          if (rel.contains('image')) {
            coverUrl = absoluteHref;
          } else if (rel.contains('thumbnail')) {
            thumbnail = absoluteHref;
          } else if (rel.contains('acquisition') &&
              type != null &&
              type.contains('application/epub+zip')) {
            isAcquisition = true;
            if (absoluteHref.contains('compatible')) {
              epubUrl = absoluteHref;
            } else {
              // Prefer 'advanced' or others if compatible isn't found/preferred logic
              epubBestUrl = absoluteHref;
            }
            // Fallback if we haven't found a "best" one yet
            epubUrl ??= absoluteHref;
          } else if ((rel.contains('subsection') ||
              type?.contains('opds-catalog') == true)) {
            // It's navigation
            navigationLink = absoluteHref;
          }
        }

        if (isAcquisition) {
          String author = 'Unknown';
          final authorElement = entry.findElements('author').firstOrNull;
          if (authorElement != null) {
            final nameElement = authorElement.findElements('name').firstOrNull;
            if (nameElement != null) {
              author = nameElement.innerText;
            }
          }

          final summaryElement = entry.findElements('summary').firstOrNull;
          final summary = summaryElement?.innerText;

          entries.add(
            OpdsAcquisitionEntry(
              title: title,
              id: id,
              author: author,
              summary: summary,
              coverUrl: coverUrl,
              thumbnail: thumbnail,
              epubUrl: epubUrl,
              epubBestUrl: epubBestUrl,
            ),
          );
        } else if (navigationLink != null) {
          final contentElement = entry.findElements('content').firstOrNull;
          final content = contentElement?.innerText ?? '';

          entries.add(
            OpdsNavigationEntry(
              title: title,
              id: id,
              content: content,
              link: navigationLink,
              thumbnail: thumbnail,
            ),
          );
        }
      }

      return OpdsFeed(title: feedTitle, entries: entries, nextLink: nextLink);
    } catch (e) {
      print('Error fetching OPDS feed: $e');
      rethrow;
    }
  }

  Future<List<RemoteBook>> fetchNewReleases() async {
    // Legacy method support - wraps new fetchFeed
    try {
      final feed = await fetchFeed('$_baseUrl/new-releases');
      return feed.entries
          .whereType<OpdsAcquisitionEntry>()
          .map((e) => e.toRemoteBook())
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<OpdsFeed> fetchSubjects() async {
    return fetchFeed('$_baseUrl/subjects');
  }

  Future<OpdsFeed> fetchAuthors() async {
    return fetchFeed('$_baseUrl/authors');
  }

  Future<List<RemoteBook>> searchBooks(String query) async {
    try {
      final quotedQuery = '"$query"';
      final response = await _dio.get(
        '$_baseUrl/all',
        queryParameters: {'query': quotedQuery},
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            if (_authHeader != null) 'Authorization': _authHeader,
          },
        ),
      );
      // ... (rest of search parsing could be refactored to use generic parse if XML structure is same,
      // but keeping it simple for now as it returns List<RemoteBook> directly)
      // Actually checking the search response, it IS an OPDS feed. So we can use fetchFeed and convert.

      final document = XmlDocument.parse(response.data);
      // Reuse logic via extraction? For now just keeping existing working logic but adding auth header
      // ... actually, let's just minimal touch on searchBooks to add auth header as requested in plan

      final entries = document.findAllElements('entry');

      return entries.map((entry) {
        final title = entry.findElements('title').first.innerText;

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
