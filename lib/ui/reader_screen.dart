import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:epubx/epubx.dart';
import '../data/database.dart';
import '../services/epub_service.dart';
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

  // Settings
  double _fontSize = 100.0;
  String _fontFamily = 'Georgia, serif';
  ReaderTheme _theme = ReaderTheme.light;
  ReaderScrollMode _scrollMode = ReaderScrollMode.vertical;
  bool _showControls = false; // Start immersive

  // Tap detection
  Offset? _pointerDownPosition;
  DateTime? _pointerDownTime;

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
    setState(() {
      _chapters = _epubService.getAllChapters();
      _isLoading = false;
    });
    // Load the restored chapter
    if (_currentChapterIndex >= 0 && _currentChapterIndex < _chapters.length) {
      _loadChapter(_currentChapterIndex, initialCfi: _initialCfiPath);
    }
  }

  String _generateHtml(String content, {String initialProgress = ''}) {
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

    final css =
        '''
      <style>
        body {
          background-color: $bgColor !important;
          color: $textColor !important;
          font-size: ${_fontSize}% !important;
          font-family: $_fontFamily !important;
          line-height: 1.8 !important;
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
                if (sibling.nodeType === 1) { // Element
                    ix++;
                }
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
           if ('$initialProgress' !== '0.0' && '$initialProgress' !== '') {
              // If it looks like a path (starts with /), restore it
              if ('$initialProgress'.startsWith('/')) {
                  restorePath('$initialProgress');
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
        };

        // Throttled scroll reporter
        var lastScrollTime = 0;
        function reportScroll() {
           var now = Date.now();
           if (now - lastScrollTime < 1000) return; // Report every 1s max
           lastScrollTime = now;
           
           // Find first visible element
           var all = document.body.getElementsByTagName("*");
           var visibleEl = null;
           for (var i=0; i<all.length; i++) {
               var rect = all[i].getBoundingClientRect();
               if (rect.top >= 0 && rect.top < window.innerHeight) {
                   visibleEl = all[i];
                   break;
               }
           }
           
           if (visibleEl) {
               var path = getPathTo(visibleEl);
               window.flutter_inappwebview.callHandler('onScrollProgress', path);
           }
        }

        // Detect scroll end for vertical continuous scrolling
        window.onscroll = function(ev) {
          reportScroll();
          
          if ((window.innerHeight + window.scrollY) >= document.body.offsetHeight - 100) {
             window.flutter_inappwebview.callHandler('onScrollToEnd');
          }
        };

        // Horizontal Snapping & Scroll End Detection
        if (${_scrollMode == ReaderScrollMode.horizontal}) {
           var isScrolling = false;
           
           window.addEventListener('scroll', function() {
              reportScroll();
              
              // Check for end of chapter
              if ((window.innerWidth + window.scrollX) >= document.body.scrollWidth - 10) {
                 window.flutter_inappwebview.callHandler('onScrollToEnd');
              }
           });

           // Snap to page on touch end
           window.addEventListener('touchend', function() {
              setTimeout(function() {
                  var scrollLeft = window.scrollX;
                  var pageWidth = window.innerWidth;
                  var targetPage = Math.round(scrollLeft / pageWidth);
                  var targetScroll = targetPage * pageWidth;
                  
                  window.scrollTo({
                      left: targetScroll,
                      behavior: 'smooth'
                  });
              }, 50);
           });
        }
        
        // Detect taps for Controls AND Page Turning
        window.addEventListener('click', function(e) {
          // Prevent triggering if clicking a link
          if (e.target.tagName === 'A') return;
          
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

  void _loadChapter(int index, {String initialCfi = ''}) {
    if (index < 0 || index >= _chapters.length) return;
    setState(() {
      _currentChapterIndex = index;
    });

    // Save progress (initial load)
    _saveProgress(index, initialCfi);

    final content = _epubService.getChapterContent(_chapters[index]);
    if (content != null) {
      _webViewController?.loadData(
        data: _generateHtml(content, initialProgress: initialCfi),
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
            child: Listener(
              onPointerDown: (event) {
                _pointerDownPosition = event.position;
                _pointerDownTime = DateTime.now();
              },
              onPointerUp: (event) {
                final upPosition = event.position;
                final upTime = DateTime.now();

                final distance = (_pointerDownPosition != null)
                    ? (upPosition - _pointerDownPosition!).distance
                    : 0.0;
                final duration = (_pointerDownTime != null)
                    ? upTime.difference(_pointerDownTime!).inMilliseconds
                    : 0;

                // If tap is short and didn't move much, treat as a toggle tap
                if (distance < 20 && duration < 300) {
                  _toggleControls();
                }
              },
              child: InAppWebView(
                initialData: InAppWebViewInitialData(
                  data: _generateHtml(
                    _epubService.getChapterContent(
                          _chapters[_currentChapterIndex],
                        ) ??
                        '',
                    initialProgress: _initialCfiPath,
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
                        // Get selected text via JS
                        final selectedText = await _webViewController
                            ?.evaluateJavascript(
                              source: "window.getSelection().toString()",
                            );

                        if (selectedText != null &&
                            selectedText.toString().isNotEmpty) {
                          // Save highlight
                          await ref
                              .read(bookRepositoryProvider)
                              .addHighlight(
                                widget.book.id,
                                selectedText.toString(),
                                _currentChapterIndex
                                    .toString(), // Use chapter index as CFI for now
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
