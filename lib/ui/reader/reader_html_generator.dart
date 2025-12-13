import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:liberry/data/database.dart';
import 'reader_models.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

class ReaderHtmlGenerator {
  /// Process raw chapter content (sanitization, pruning, Gutenberg fixes)
  /// Returns the HTML body content ready for injection.
  static String processChapterContent(
    String content, {
    String? startAnchor,
    String? endAnchor,
    bool isGutenberg = false,
  }) {
    // FIX: Project Gutenberg and other XHTML epubs often use self-closing divs.
    String processedContent = content.replaceAllMapped(
      RegExp(r'''<div([^>]*)/>'''),
      (match) => '<div${match.group(1)}></div>',
    );

    // Fallback detection
    final bool effectiveIsGutenberg =
        isGutenberg ||
        content.contains('Project Gutenberg') ||
        content.contains('www.gutenberg.org') ||
        content.contains('Ebookmaker') ||
        content.contains('pgepub.css') ||
        content.contains('pgmonospaced') ||
        content.contains('x-ebookmaker');

    // Prune content if anchors are provided
    if (startAnchor != null || endAnchor != null) {
      processedContent = _pruneHtml(processedContent, startAnchor, endAnchor);
    }

    if (effectiveIsGutenberg) {
      // Aggressive sanitization for Project Gutenberg
      processedContent = processedContent.replaceAll(
        RegExp(
          r'''<link[^>]*rel=['"]?stylesheet['"]?[^>]*>''',
          caseSensitive: false,
        ),
        '',
      );
      processedContent = processedContent.replaceAll(
        RegExp(r'''\sstyle=['"][^'"]*['"]''', caseSensitive: false),
        '',
      );
      processedContent = processedContent.replaceAll(
        RegExp(r'''\sclass=['"][^'"]*['"]''', caseSensitive: false),
        '',
      );
      processedContent = processedContent.replaceAll(
        RegExp(r'''<p>\s*(?:<br\s*/?>\s*)+\s*</p>''', caseSensitive: false),
        '',
      );
    }

    // Ensure we only return the body content (inner HTML)
    // This allows the caller to wrap it in a container without creating invalid nested HTML structures
    return extractBody(processedContent);
  }

  static Future<String> generateHtml(
    String content, {
    required ReaderTheme theme,
    required double fontSize,
    required String fontFamily,
    required ReaderScrollMode scrollMode,
    required int currentChapterIndex,
    String initialProgress = '',
    List<Quote> highlights = const [],
    int spineIndex = 0,
    List<Map<String, dynamic>> anchors = const [],
    String? scrollToAnchor,
    String? startAnchor,
    String? endAnchor,
    bool isGutenberg = false,
    bool isInteractionLocked = false,
    double sideMargin = 20.0,
    bool twoColumnEnabled = false,
  }) async {
    // 1. Process Content
    String processedContent = processChapterContent(
      content,
      startAnchor: startAnchor,
      endAnchor: endAnchor,
      isGutenberg: isGutenberg,
    );

    // 2. Load Assets
    final css = await rootBundle.loadString('assets/reader/reader.css');
    final js = await rootBundle.loadString('assets/reader/reader.js');
    final template = await rootBundle.loadString('assets/reader/template.html');

    // 3. Prepare Config
    String bgColor = '#ffffff';
    String textColor = '#000000';
    String selectionColor = 'rgba(33, 150, 243, 0.3)';
    String highlightColor = 'rgba(255, 235, 59, 0.4)';
    String highlightBorder = 'rgba(253, 216, 53, 0.8)';

    switch (theme) {
      case ReaderTheme.light:
        bgColor = '#ffffff';
        textColor = '#000000';
        break;
      case ReaderTheme.dark:
        bgColor = '#121212';
        textColor = '#e0e0e0';
        selectionColor = 'rgba(64, 196, 255, 0.3)';
        highlightColor = 'rgba(253, 216, 53, 0.3)';
        break;
      case ReaderTheme.sepia:
        bgColor = '#f4ecd8';
        textColor = '#5b4636';
        break;
    }

    // Prepare Highlights
    final highlightsJson = jsonEncode(
      highlights
          .where((h) {
            if (h.cfi == null) return false;
            try {
              final Map<String, dynamic> cfiMap = jsonDecode(h.cfi!);
              final int? highlightChapterIndex = cfiMap['chapterIndex'] is int
                  ? cfiMap['chapterIndex']
                  : int.tryParse(cfiMap['chapterIndex'].toString());

              return highlightChapterIndex == currentChapterIndex;
            } catch (e) {
              return false;
            }
          })
          .map((h) {
            return {'id': h.id, 'cfi': h.cfi};
          })
          .toList(),
    );

    // Config JS injection
    final configJs =
        '''
      window.currentSpineIndex = $spineIndex;
      window.chapterAnchors = ${jsonEncode(anchors)};
      window.initialScrollAnchor = ${jsonEncode(scrollToAnchor)};
      window.initialProgress = ${jsonEncode(initialProgress)};
      window.highlightData = $highlightsJson;
      // Pre-set vars for CSS
      document.documentElement.style.setProperty('--bg-color', '$bgColor');
      document.documentElement.style.setProperty('--text-color', '$textColor');
      document.documentElement.style.setProperty('--font-family', '${escapeForJs(fontFamily)}');
      document.documentElement.style.setProperty('--font-size', '${fontSize}%');
      document.documentElement.style.setProperty('--selection-color', '$selectionColor');
      document.documentElement.style.setProperty('--highlight-color', '$highlightColor');
      document.documentElement.style.setProperty('--highlight-border', '$highlightBorder');
      
      // New Settings
      document.documentElement.style.setProperty('--side-margin', '${sideMargin}px');
    ''';

    // 4. Inject
    String bodyClasses = '';
    if (scrollMode == ReaderScrollMode.vertical) {
      bodyClasses = 'mode-vertical';
    } else {
      bodyClasses = 'mode-horizontal';
      if (twoColumnEnabled) {
        bodyClasses += ' two-column-enabled';
      }
    }

    String finalHtml = template
        .replaceAll('/* {{CSS_CONTENT}} */', css)
        .replaceAll('{{BODY_CLASSES}}', bodyClasses)
        .replaceAll('{{CHAPTER_INDEX}}', currentChapterIndex.toString())
        .replaceAll('{{CHAPTER_CONTENT}}', processedContent)
        .replaceAll('/* {{CONFIG_JS}} */', configJs)
        .replaceAll('/* {{READER_JS}} */', '''
          $js
          // Trigger initial alignment check
          if (window.onContentChanged) window.onContentChanged();
          // Also set up a periodic check for the first second to catch layout settling
          /*
          var checkCount = 0;
          var interval = setInterval(function() {
             // Alignment removed
             checkCount++;
             if (checkCount > 5) clearInterval(interval);
          }, 200);
          */
        ''');

    return finalHtml;
  }

  static String _pruneHtml(
    String html,
    String? startAnchor,
    String? endAnchor,
  ) {
    try {
      final document = html_parser.parse(html);
      final body = document.body;
      if (body == null) return html;

      if (startAnchor != null) {
        final startElement = document.getElementById(startAnchor);
        if (startElement != null) {
          _removePrecedingSiblings(startElement, body);
        }
      }

      if (endAnchor != null) {
        final endElement = document.getElementById(endAnchor);
        if (endElement != null) {
          _removeFollowingSiblings(endElement, body);
          endElement.remove();
        }
      }

      return document.outerHtml;
    } catch (e) {
      print('Error pruning HTML: $e');
      return html;
    }
  }

  static void _removePrecedingSiblings(dom.Element element, dom.Element root) {
    var current = element;
    while (current != root && current.parent != null) {
      final parent = current.parent!;
      final siblings = parent.nodes.toList();
      final index = siblings.indexOf(current);
      if (index > 0) {
        for (int i = 0; i < index; i++) {
          siblings[i].remove();
        }
      }
      current = parent;
    }
  }

  static void _removeFollowingSiblings(dom.Element element, dom.Element root) {
    var current = element;
    while (current != root && current.parent != null) {
      final parent = current.parent!;
      final siblings = parent.nodes.toList();
      final index = siblings.indexOf(current);
      if (index != -1 && index < siblings.length - 1) {
        for (int i = index + 1; i < siblings.length; i++) {
          siblings[i].remove();
        }
      }
      current = parent;
    }
  }

  static String extractBody(String html) {
    final bodyMatch = RegExp(
      r'<body[^>]*>(.*?)</body>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(html);
    return bodyMatch?.group(1) ?? html;
  }

  static String escapeForJs(String text) {
    return text
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '');
  }
}
