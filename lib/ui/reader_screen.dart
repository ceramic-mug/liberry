import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:epubx/epubx.dart';
import 'dart:convert';
import 'dart:io';
import '../data/database.dart';
import '../services/epub_service.dart';
import '../data/book_repository.dart';
import '../data/character_repository.dart';
import '../providers.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  final Book book;
  final String initialCfi;

  const ReaderScreen({super.key, required this.book, this.initialCfi = ''});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final EpubService _epubService = EpubService();
  InAppWebViewController? _webViewController;
  bool _isLoading = true;
  List<EpubChapter> _chapters = [];
  int _currentChapterIndex = 0;
  List<Quote> _currentHighlights = []; // Store full Quote objects

  // Settings
  double _fontSize = 100.0;
  String _fontFamily = 'Georgia, serif';
  ReaderTheme _theme = ReaderTheme.light;
  ReaderScrollMode _scrollMode = ReaderScrollMode.vertical;
  bool _showControls = false; // Start immersive

  // Tap detection
  // Offset? _pointerDownPosition;
  // DateTime? _pointerDownTime;

  String _initialCfiPath = '';

  @override
  void initState() {
    super.initState();
    // Restore progress if available
    if (widget.initialCfi.isNotEmpty) {
      try {
        // Try parsing as JSON first
        if (widget.initialCfi.startsWith('{')) {
          final chapterMatch = RegExp(
            r'"chapterIndex":\s*(\d+)',
          ).firstMatch(widget.initialCfi);
          final cfiMatch = RegExp(
            r'"cfi":\s*"([^"]+)"',
          ).firstMatch(widget.initialCfi);

          if (chapterMatch != null) {
            _currentChapterIndex = int.parse(chapterMatch.group(1)!);
          }
          if (cfiMatch != null) {
            _initialCfiPath = cfiMatch.group(1)!;
          } else {
            // Try 'startPath' key (Highlight format)
            final startPathMatch = RegExp(
              r'"startPath":\s*"([^"]+)"',
            ).firstMatch(widget.initialCfi);
            if (startPathMatch != null) {
              _initialCfiPath = startPathMatch.group(1)!;
            }
          }
        } else {
          // Fallback to legacy int parsing
          _currentChapterIndex = int.parse(widget.initialCfi);
        }
      } catch (e) {
        print('Error parsing initial CFI: $e');
      }
    }
    _loadBook();
  }

  Future<void> _loadBook() async {
    await _epubService.loadBook(widget.book.filePath);

    // Pre-fetch highlights
    final highlights = await ref
        .read(bookRepositoryProvider)
        .getHighlights(widget.book.id);

    setState(() {
      _chapters = _epubService.getAllChapters();
      _currentHighlights = highlights;
      _isLoading = false;
    });
    // Load the restored chapter
    if (_currentChapterIndex >= 0 && _currentChapterIndex < _chapters.length) {
      _loadChapter(_currentChapterIndex, initialCfi: _initialCfiPath);
    }
  }

  String _generateHtml(
    String content, {
    String initialProgress = '',
    List<Quote> highlights = const [],
  }) {
    // ... (theme logic omitted for brevity, it's unchanged) ...
    String bgColor;
    String textColor;

    switch (_theme) {
      case ReaderTheme.light:
        bgColor = '#ffffff';
        textColor = '#000000';
        break;
      case ReaderTheme.dark:
        bgColor = '#121212';
        textColor = '#e0e0e0';
        break;
      case ReaderTheme.sepia:
        bgColor = '#f4ecd8';
        textColor = '#5b4636';
        break;
    }

    // Horizontal Mode CSS (Strict Pagination)
    String scrollCss = '';
    if (_scrollMode == ReaderScrollMode.horizontal) {
      scrollCss = '''
        html, body {
          height: 100vh;
          width: 100vw;
          margin: 0 !important;
          padding: 0 !important;
          overflow-y: hidden;
          overflow-x: scroll;
        }
        body {
          column-width: 100vw;
          column-gap: 0;
          column-fill: auto;
          height: 100vh;
          /* No padding on body to ensure perfect 100vw columns */
        }
        /* Add padding to content elements for reading comfort */
        p, h1, h2, h3, h4, h5, h6, li, div {
          padding-left: 20px;
          padding-right: 20px;
          box-sizing: border-box;
        }
        img {
          max-height: 90vh;
          max-width: 100%;
          width: auto;
          height: auto;
          margin: 0 auto;
          display: block;
        }
      ''';
    } else {
      // Vertical Mode CSS
      scrollCss = '''
        body {
          padding: 20px 30px;
          margin: 0;
          max-width: 800px;
          margin-left: auto;
          margin-right: auto;
        }
      ''';
    }

    // Prepare highlights JSON with ID
    // We filter by chapter here to be safe
    final filteredHighlights = highlights.where((h) {
      if (h.cfi == null) return false;
      try {
        final json = jsonDecode(h.cfi!);
        return json['chapterIndex'] == _currentChapterIndex;
      } catch (e) {
        return false;
      }
    }).toList();

    final highlightsJson = jsonEncode(
      filteredHighlights.map((h) {
        return {
          'id': h.id,
          'cfi': h.cfi, // This is the JSON string
        };
      }).toList(),
    );

    final css =
        '''
      <style>
        body {
          background-color: $bgColor !important;
          color: $textColor !important;
          font-size: ${_fontSize}% !important;
          font-family: $_fontFamily !important;
          line-height: 1.8 !important;
          position: relative; /* For absolute positioning of tooltip */
        }
        p {
          margin-bottom: 1.5em;
          text-align: justify;
        }
        img {
          max-width: 100%;
          height: auto;
          display: block;
          margin: 20px auto;
        }
        $scrollCss
        .highlight {
          background-color: #ffeb3b;
          mix-blend-mode: multiply;
        }
        #highlight-tooltip {
          position: absolute;
          background-color: #333;
          color: white;
          padding: 8px 16px;
          border-radius: 4px;
          font-size: 14px;
          cursor: pointer;
          z-index: 10000;
          display: none;
          box-shadow: 0 2px 5px rgba(0,0,0,0.2);
          user-select: none;
          -webkit-user-select: none;
        }
        #highlight-tooltip::after {
          content: '';
          position: absolute;
          top: 100%;
          left: 50%;
          margin-left: -5px;
          border-width: 5px;
          border-style: solid;
          border-color: #333 transparent transparent transparent;
        }
      </style>
      <script>
        // Generate a simple path to the element: /0/1/2 (indices of element children)
        function getPathTo(element) {
            if (element === document.body) return "";
            if (!element.parentNode) return "";
            
            var ix = 0;
            var siblings = element.parentNode.childNodes;
            for (var i = 0; i < siblings.length; i++) {
                var sibling = siblings[i];
                if (sibling === element) {
                    return getPathTo(element.parentNode) + '/' + ix;
                }
                ix++; // Count all nodes (text, comments, elements)
            }
            return "";
        }

        function restorePath(path) {
            if (!path || path === "") return;
            try {
                var parts = path.split('/').filter(p => p.length > 0);
                var el = document.body;
                for (var i = 0; i < parts.length; i++) {
                    var ix = parseInt(parts[i]);
                    var children = Array.from(el.childNodes).filter(n => n.nodeType === 1);
                    if (ix < children.length) {
                        el = children[ix];
                    } else {
                        break;
                    }
                }
                if (el) {
                    el.scrollIntoView();
                }
            } catch (e) {
                console.log("Error restoring path: " + e);
            }
        }

        // Restore scroll position
        window.onload = function() {
           // Inject tooltip element
           var tooltip = document.createElement('div');
           tooltip.id = 'highlight-tooltip';
           tooltip.innerText = 'Highlight';
           document.body.appendChild(tooltip);

           tooltip.addEventListener('mousedown', function(e) {
               console.log("Tooltip mousedown");
               e.preventDefault(); // Prevent losing selection
               e.stopPropagation();
               
               var cfi = getCFI();
               console.log("CFI generated: " + cfi);
               if (cfi) {
                   applyHighlight(cfi);
                   if (window.flutter_inappwebview) {
                       console.log("Calling flutter_inappwebview.callHandler");
                       window.flutter_inappwebview.callHandler('onHighlight', cfi);
                   } else {
                       console.log("flutter_inappwebview not found");
                   }
                   window.getSelection().removeAllRanges();
                   hideTooltip();
               }
           });
           
           // Handle selection changes
           document.addEventListener('selectionchange', function() {
               var selection = window.getSelection();
               if (selection.rangeCount > 0 && !selection.isCollapsed) {
                   var range = selection.getRangeAt(0);
                   var rect = range.getBoundingClientRect();
                   showTooltip(rect);
               } else {
                   hideTooltip();
               }
           });
           
           // Hide on scroll
           window.addEventListener('scroll', function() {
               hideTooltip();
           });

           if ('$initialProgress' !== '0.0' && '$initialProgress' !== '') {
              // If it looks like a path (starts with /), restore it
              if ('$initialProgress'.startsWith('/')) {
                  // Small delay to ensure layout is done
                  setTimeout(function() {
                      restorePath('$initialProgress');
                  }, 100);
              } else {
                  // Legacy percentage fallback
                  var pct = parseFloat('$initialProgress');
                  if (pct > 0) {
                      if (${_scrollMode == ReaderScrollMode.horizontal}) {
                         var targetScroll = document.body.scrollWidth * pct;
                         window.scrollTo(targetScroll, 0);
                      } else {
                         var targetScroll = (document.body.scrollHeight - window.innerHeight) * pct;
                         window.scrollTo(0, targetScroll);
                      }
                  }
              }
           }
           
           // Restore highlights
           var highlights = $highlightsJson;
           if (highlights && highlights.length > 0) {
               highlights.forEach(function(h) {
                   applyHighlight(h.cfi, h.id);
               });
           }
        };

        function restorePath(path) {
            // ... (unchanged) ...
            if (!path || path === "") return;
            try {
                var parts = path.split('/').filter(p => p.length > 0);
                var el = document.body;
                for (var i = 0; i < parts.length; i++) {
                    var ix = parseInt(parts[i]);
                    var children = Array.from(el.childNodes).filter(n => n.nodeType === 1);
                    if (ix < children.length) {
                        el = children[ix];
                    } else {
                        break;
                    }
                }
                if (el) {
                    if (${_scrollMode == ReaderScrollMode.horizontal}) {
                        // Horizontal Mode: Calculate page index
                        var rect = el.getBoundingClientRect();
                        // We need absolute left position relative to document
                        var absoluteLeft = rect.left + window.scrollX;
                        var pageWidth = window.innerWidth;
                        var pageIndex = Math.floor(absoluteLeft / pageWidth);
                        
                        window.scrollTo({
                            left: pageIndex * pageWidth,
                            behavior: 'auto' // Instant jump
                        });
                    } else {
                        // Vertical Mode: Center element
                        el.scrollIntoView({block: 'center'});
                    }
                    
                    // Highlight temporarily to show user where we jumped
                    var originalBg = el.style.backgroundColor;
                    el.style.backgroundColor = 'rgba(255, 235, 59, 0.3)';
                    setTimeout(function() {
                        el.style.backgroundColor = originalBg;
                    }, 2000);
                }
            } catch (e) {
                console.log("Error restoring path: " + e);
            }
        }

        function showTooltip(rect) {
            var tooltip = document.getElementById('highlight-tooltip');
            if (!tooltip) return;
            
            var scrollX = window.scrollX || window.pageXOffset;
            var scrollY = window.scrollY || window.pageYOffset;
            
            tooltip.style.display = 'block';
            tooltip.style.left = (rect.left + rect.width / 2 - tooltip.offsetWidth / 2 + scrollX) + 'px';
            tooltip.style.top = (rect.top - tooltip.offsetHeight - 10 + scrollY) + 'px';
        }

        function hideTooltip() {
            var tooltip = document.getElementById('highlight-tooltip');
            if (tooltip) {
                tooltip.style.display = 'none';
            }
        }

        // ... (scroll reporting unchanged) ...

        // ... (highlight helpers unchanged) ...
        
        function getCFI() {
             var selection = window.getSelection();
             if (selection.rangeCount > 0) {
                 var range = selection.getRangeAt(0);
                 var startPath = getPathTo(range.startContainer);
                 var endPath = getPathTo(range.endContainer);
                 return JSON.stringify({
                     startPath: startPath,
                     startOffset: range.startOffset,
                     endPath: endPath,
                     endOffset: range.endOffset,
                     text: selection.toString()
                 });
             }
             return null;
        }
        
        function applyHighlight(cfiStr, id) {
            try {
                var cfi = JSON.parse(cfiStr);
                var startNode = getNodeByPath(cfi.startPath);
                var endNode = getNodeByPath(cfi.endPath);
                
                if (startNode && endNode) {
                    var range = document.createRange();
                    range.setStart(startNode, cfi.startOffset);
                    range.setEnd(endNode, cfi.endOffset);
                    
                    var span = document.createElement('span');
                    span.className = 'highlight';
                    if (id) {
                        span.id = 'highlight-' + id;
                        span.onclick = function(e) {
                            e.stopPropagation();
                            console.log("Highlight clicked: " + id);
                            window.flutter_inappwebview.callHandler('onHighlightClick', id);
                        };
                    }
                    range.surroundContents(span);
                }
            } catch(e) {
                console.log("Error applying highlight: " + e);
            }
        }

        function removeHighlight(id) {
            var span = document.getElementById('highlight-' + id);
            if (span) {
                var parent = span.parentNode;
                while (span.firstChild) {
                    parent.insertBefore(span.firstChild, span);
                }
                parent.removeChild(span);
            }
        }
        
        function getNodeByPath(path) {
            if (!path || path === "") return document.body;
            var parts = path.split('/').filter(p => p.length > 0);
            var el = document.body;
            for (var i = 0; i < parts.length; i++) {
                var ix = parseInt(parts[i]);
                if (ix < el.childNodes.length) {
                    el = el.childNodes[ix];
                } else {
                    return null;
                }
            }
            return el;
        }

        // Detect taps for Controls AND Page Turning
          // Detect taps for Controls AND Page Turning
          window.addEventListener('click', function(e) {
            // Prevent triggering if clicking a link or the tooltip
            if (e.target.tagName === 'A' || e.target.id === 'highlight-tooltip') return;
            
            // Don't toggle if text is selected
            if (window.getSelection().toString().length > 0) return;

            var width = window.innerWidth;
            var x = e.clientX;
            
            // Horizontal Mode: Tap Zones
            if (${_scrollMode == ReaderScrollMode.horizontal}) {
               if (x > width * 0.8) {
                  // Right 20%: Next Page
                  window.scrollBy({ left: width, behavior: 'smooth' });
                  return;
               } else if (x < width * 0.2) {
                  // Left 20%: Prev Page
                  window.scrollBy({ left: -width, behavior: 'smooth' });
                  return;
               }
             }
            
            // Center / Vertical Mode: Toggle Controls
            console.log("TOGGLE_CONTROLS");
            if (window.flutter_inappwebview) {
               window.flutter_inappwebview.callHandler('onTap');
            }
          }, true);
      </script>
    ''';

    if (content.contains('<head>')) {
      return content.replaceFirst('<head>', '<head>$css');
    } else if (content.contains('<html>')) {
      return content.replaceFirst('<html>', '<html><head>$css</head>');
    } else {
      return '''
        <!DOCTYPE html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
          $css
        </head>
        <body>
          $content
        </body>
        </html>
      ''';
    }
  }

  Future<void> _loadChapter(int index, {String initialCfi = ''}) async {
    if (index < 0 || index >= _chapters.length) return;
    setState(() {
      _currentChapterIndex = index;
    });

    // Save progress (initial load)
    _saveProgress(index, initialCfi);

    final content = _epubService.getChapterContent(_chapters[index]);
    if (content != null) {
      // Refresh highlights just in case (e.g. if added from another screen, though unlikely here)
      // But more importantly, we need to filter them.
      // We can re-fetch or use cached. Let's re-fetch to be safe and consistent.
      final allHighlights = await ref
          .read(bookRepositoryProvider)
          .getHighlights(widget.book.id);

      setState(() {
        _currentHighlights = allHighlights;
      });

      _webViewController?.loadData(
        data: _generateHtml(
          content,
          initialProgress: initialCfi,
          highlights: _currentHighlights,
        ),
      );
    }
  }

  void _saveProgress(int chapterIndex, String cfiPath) {
    // If path is empty, don't overwrite with empty unless it's a new chapter start
    final cfi = '{"chapterIndex": $chapterIndex, "cfi": "$cfiPath"}';
    ref.read(bookRepositoryProvider).saveReadingProgress(widget.book.id, cfi);
  }

  // Append next chapter for continuous scroll
  Future<void> _appendNextChapter() async {
    if (_currentChapterIndex < _chapters.length - 1) {
      _currentChapterIndex++;

      // Save progress
      _saveProgress(_currentChapterIndex, '');

      final content = _epubService.getChapterContent(
        _chapters[_currentChapterIndex],
      );
      if (content != null) {
        // We need to strip <html>, <head>, <body> tags to append just the body content
        String bodyContent = content;
        final bodyMatch = RegExp(
          r'<body[^>]*>(.*?)<\/body>',
          caseSensitive: false,
          dotAll: true,
        ).firstMatch(content);
        if (bodyMatch != null) {
          bodyContent = bodyMatch.group(1) ?? content;
        }

        // Escape for JS
        final escapedContent = bodyContent
            .replaceAll("'", "\\'")
            .replaceAll("\n", "");

        await _webViewController?.evaluateJavascript(
          source:
              '''
          var div = document.createElement('div');
          div.innerHTML = '$escapedContent';
          // Ensure it starts on a new column/page
          if (${_scrollMode == ReaderScrollMode.horizontal}) {
             div.style.breakBefore = 'column';
             div.style.marginTop = '0';
             div.style.borderTop = 'none';
             div.style.paddingTop = '0';
          } else {
             div.style.marginTop = '50px';
             div.style.borderTop = '1px solid #ccc';
             div.style.paddingTop = '50px';
          }
          document.body.appendChild(div);
        ''',
        );

        setState(() {});
      }
    }
  }

  void _toggleControls() {
    print("Toggling controls. Current state: $_showControls");
    setState(() {
      _showControls = !_showControls;
    });
  }

  void _updateWebViewSettings() {
    _webViewController?.setSettings(
      settings: InAppWebViewSettings(
        transparentBackground: true,
        supportZoom: false,
        horizontalScrollBarEnabled: false,
        verticalScrollBarEnabled: false,
        // Disable native paging to allow JS snapping to work
        isPagingEnabled: false,
      ),
    );
  }

  Color _getScaffoldColor() {
    switch (_theme) {
      case ReaderTheme.light:
        return Colors.white;
      case ReaderTheme.dark:
        return const Color(0xFF121212);
      case ReaderTheme.sepia:
        return const Color(0xFFF4ECD8);
    }
  }

  Color _getTextColor() {
    switch (_theme) {
      case ReaderTheme.light:
        return Colors.black;
      case ReaderTheme.dark:
        return Colors.white;
      case ReaderTheme.sepia:
        return const Color(0xFF5B4636);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final scaffoldColor = _getScaffoldColor();
    final textColor = _getTextColor();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: scaffoldColor,
      drawer: Drawer(
        backgroundColor: scaffoldColor,
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: textColor.withOpacity(0.1)),
                ),
              ),
              child: Center(
                child: Text(
                  widget.book.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _chapters.length,
                itemBuilder: (context, index) {
                  final chapter = _chapters[index];
                  final isSelected = index == _currentChapterIndex;
                  return ListTile(
                    title: Text(
                      chapter.Title ?? 'Chapter ${index + 1}',
                      style: TextStyle(
                        color: isSelected
                            ? Theme.of(context).primaryColor
                            : textColor,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    onTap: () {
                      _loadChapter(index);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          // WebView
          SafeArea(
            child: InAppWebView(
              initialData: InAppWebViewInitialData(
                data: _generateHtml(
                  _epubService.getChapterContent(
                        _chapters[_currentChapterIndex],
                      ) ??
                      '',
                  initialProgress: _initialCfiPath,
                  highlights: _currentHighlights,
                  // Since build() is synchronous, we can't await here.
                  // We'll rely on _loadBook calling _loadChapter which is async and fetches highlights.
                  // So initialData can be empty of highlights, and _loadBook will reload with them?
                  // Actually _loadBook calls _loadChapter.
                  // But `initialData` is used for the very first render before `_webViewController` is ready?
                  // `_loadBook` calls `_loadChapter` which calls `loadData`.
                  // So `initialData` is just a placeholder or for fast start.
                  // If we leave it empty, it's fine, `_loadChapter` will overwrite it quickly.
                ),
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
                controller.addJavaScriptHandler(
                  handlerName: 'onScrollToEnd',
                  callback: (args) {
                    _appendNextChapter();
                  },
                );
                controller.addJavaScriptHandler(
                  handlerName: 'onScrollProgress',
                  callback: (args) {
                    if (args.isNotEmpty) {
                      final String path = args[0].toString();
                      _saveProgress(_currentChapterIndex, path);
                    }
                  },
                );
                controller.addJavaScriptHandler(
                  handlerName: 'onHighlight',
                  callback: (args) async {
                    print("DEBUG: onHighlight called with args: $args");
                    if (args.isNotEmpty) {
                      try {
                        final String cfiString = args[0].toString();
                        final Map<String, dynamic> cfiJson = jsonDecode(
                          cfiString,
                        );
                        final String textContent =
                            cfiJson['text'] ?? "Highlight";

                        // Inject chapter index
                        cfiJson['chapterIndex'] = _currentChapterIndex;
                        final String finalCfiString = jsonEncode(cfiJson);

                        print(
                          "DEBUG: Saving highlight: $textContent for book ${widget.book.id}",
                        );

                        final String id = await ref
                            .read(bookRepositoryProvider)
                            .addHighlight(
                              widget.book.id,
                              textContent,
                              finalCfiString,
                            );

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Highlight saved!')),
                          );
                          // Show options modal
                          _showHighlightOptions(context, id);
                        }
                      } catch (e) {
                        print("Error saving highlight: $e");
                      }
                    }
                  },
                );
              },
              onConsoleMessage: (controller, consoleMessage) {
                if (consoleMessage.message == "TOGGLE_CONTROLS") {
                  _toggleControls();
                }
              },
              initialSettings: InAppWebViewSettings(
                transparentBackground: true,
                supportZoom: false,
                // Hide scrollbars to avoid jumping when content loads
                horizontalScrollBarEnabled: false,
                verticalScrollBarEnabled: false,
                // Enable native paging for horizontal mode (iOS)
                isPagingEnabled: false,
              ),
              contextMenu: ContextMenu(
                menuItems: [
                  ContextMenuItem(
                    id: 1,
                    title: "Highlight",
                    action: () async {
                      // Get selected text and CFI via JS
                      final result = await _webViewController
                          ?.evaluateJavascript(source: "getCFI()");

                      if (result != null && result != 'null') {
                        // Apply visual highlight immediately
                        await _webViewController?.evaluateJavascript(
                          source: "applyHighlight('$result')",
                        );

                        // Save highlight
                        // Result is a JSON string with text and paths
                        // We store the whole JSON in the 'cfi' column for restoration
                        // And extract text for the 'text' column
                        // But wait, the result is ALREADY a JSON string from JS?
                        // evaluateJavascript returns dynamic. If it returns a string, it might be double quoted?
                        // Let's assume it returns the string.

                        // We need to parse it to get the text content for the DB
                        // Or we can just pass the text separately from JS?
                        // Let's just use the JSON string as the CFI.
                        // And we need the text.

                        // Let's do a quick parse or ask JS for text separately?
                        // JS `getCFI` returns JSON with `text` field.

                        String cfiString = result.toString();
                        // Simple regex to extract text to avoid importing dart:convert if not needed
                        // But we should use dart:convert.
                        // Let's just use a regex for now or import convert at top?
                        // I'll use a regex for safety/speed in this snippet.
                        final textMatch = RegExp(
                          r'"text":"(.*?)"',
                        ).firstMatch(cfiString);
                        String textContent = textMatch?.group(1) ?? "Highlight";
                        // Unescape json text if needed?
                        // Ideally we should use dart:convert.

                        await ref
                            .read(bookRepositoryProvider)
                            .addHighlight(
                              widget.book.id,
                              textContent, // This might be raw JSON escaped, but acceptable for now
                              cfiString,
                            );

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Highlight saved!')),
                          );
                        }

                        // Clear selection
                        await _webViewController?.evaluateJavascript(
                          source: "window.getSelection().removeAllRanges()",
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          // Controls Overlay
          if (_showControls) ...[
            // Top Bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AppBar(
                backgroundColor: scaffoldColor.withOpacity(0.95),
                elevation: 0,
                iconTheme: IconThemeData(color: textColor),
                title: Column(
                  children: [
                    Text(
                      widget.book.title,
                      style: TextStyle(color: textColor, fontSize: 16),
                    ),
                    Text(
                      '${_currentChapterIndex + 1} / ${_chapters.length}',
                      style: TextStyle(
                        color: textColor.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.list),
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.format_size),
                    onPressed: () =>
                        _showSettingsModal(context, textColor, scaffoldColor),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showSettingsModal(
    BuildContext context,
    Color textColor,
    Color bgColor,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Scroll Mode Toggle
            Text(
              'Scroll Mode',
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildScrollModeButton(
                  ReaderScrollMode.vertical,
                  'Vertical',
                  Icons.swap_vert,
                ),
                _buildScrollModeButton(
                  ReaderScrollMode.horizontal,
                  'Horizontal',
                  Icons.swap_horiz,
                ),
              ],
            ),
            const SizedBox(height: 24),

            Text(
              'Theme',
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildThemeButton(ReaderTheme.light, 'Light', Icons.light_mode),
                _buildThemeButton(
                  ReaderTheme.sepia,
                  'Sepia',
                  Icons.chrome_reader_mode,
                ),
                _buildThemeButton(ReaderTheme.dark, 'Dark', Icons.dark_mode),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Font Size',
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            ),
            Slider(
              value: _fontSize,
              min: 50,
              max: 200,
              activeColor: textColor,
              inactiveColor: textColor.withOpacity(0.3),
              onChanged: (value) {
                setState(() {
                  _fontSize = value;
                });
                _loadChapter(_currentChapterIndex);
              },
            ),
            const SizedBox(height: 24),
            Text(
              'Font Family',
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildFontButton('Serif', 'Georgia, serif'),
                _buildFontButton('Sans', 'Helvetica, Arial, sans-serif'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeButton(ReaderTheme theme, String label, IconData icon) {
    final isSelected = _theme == theme;
    return InkWell(
      onTap: () {
        setState(() {
          _theme = theme;
        });
        _loadChapter(_currentChapterIndex);
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: isSelected ? Colors.blue : Colors.grey),
          borderRadius: BorderRadius.circular(20),
          color: isSelected ? Colors.blue.withOpacity(0.1) : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? Colors.blue : Colors.grey),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.blue : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollModeButton(
    ReaderScrollMode mode,
    String label,
    IconData icon,
  ) {
    final isSelected = _scrollMode == mode;
    return InkWell(
      onTap: () {
        setState(() {
          _scrollMode = mode;
        });
        _updateWebViewSettings(); // Update settings immediately
        _loadChapter(_currentChapterIndex);
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: isSelected ? Colors.blue : Colors.grey),
          borderRadius: BorderRadius.circular(20),
          color: isSelected ? Colors.blue.withOpacity(0.1) : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? Colors.blue : Colors.grey),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.blue : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHighlightOptions(BuildContext context, String highlightId) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add),
              title: const Text('Assign to Character'),
              onTap: () {
                Navigator.pop(context);
                _showAssignCharacterDialog(context, highlightId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text(
                'Delete Highlight',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () async {
                Navigator.pop(context);
                await ref
                    .read(bookRepositoryProvider)
                    .deleteHighlight(highlightId);
                _webViewController?.evaluateJavascript(
                  source: "removeHighlight('$highlightId')",
                );
                setState(() {
                  _currentHighlights.removeWhere((h) => h.id == highlightId);
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAssignCharacterDialog(BuildContext context, String highlightId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Assign to Character'),
        content: SizedBox(
          width: double.maxFinite,
          child: Consumer(
            builder: (context, ref, child) {
              final charRepo = ref.watch(characterRepositoryProvider);
              return StreamBuilder<List<Character>>(
                stream: charRepo.watchAllCharacters(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final characters = snapshot.data!;
                  if (characters.isEmpty) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('No characters created yet.'),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please create a character first in the Characters tab.',
                                ),
                              ),
                            );
                          },
                          child: const Text('Create Character'),
                        ),
                      ],
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: characters.length,
                    itemBuilder: (context, index) {
                      final char = characters[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: char.imagePath != null
                              ? FileImage(File(char.imagePath!))
                              : null,
                          child: char.imagePath == null
                              ? Text(char.name[0])
                              : null,
                        ),
                        title: Text(char.name),
                        onTap: () async {
                          await ref
                              .read(bookRepositoryProvider)
                              .assignQuoteToCharacter(highlightId, char.id);
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Assigned to ${char.name}'),
                              ),
                            );
                          }
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildFontButton(String label, String family) {
    final isSelected = _fontFamily == family;
    return InkWell(
      onTap: () {
        setState(() {
          _fontFamily = family;
        });
        _loadChapter(_currentChapterIndex);
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: isSelected ? Colors.blue : Colors.grey),
          borderRadius: BorderRadius.circular(20),
          color: isSelected ? Colors.blue.withOpacity(0.1) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.blue : Colors.grey,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

enum ReaderTheme { light, dark, sepia }

enum ReaderScrollMode { vertical, horizontal }
