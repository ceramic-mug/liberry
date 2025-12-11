import 'dart:convert';
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

  static String generateHtml(
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
  }) {
    String processedContent = processChapterContent(
      content,
      startAnchor: startAnchor,
      endAnchor: endAnchor,
      isGutenberg: isGutenberg,
    );

    String bgColor;
    String textColor;

    switch (theme) {
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

    // Horizontal Mode CSS (Strict Pagination via JS)
    String scrollCss = '';
    if (scrollMode == ReaderScrollMode.horizontal) {
      scrollCss = '''
        html, body {
          height: 100%;
          width: 100%;
          margin: 0;
          padding: 0;
          overflow: hidden; /* Strict lock on window */
        }
        #reader-content {
          /* The Scroll Container */
          height: 100vh;
          width: 100vw;
          overflow: hidden; /* Programmatic scroll only */
          
          /* CSS Columns */
          column-width: 100vw;
          column-gap: 0;
          column-fill: auto;
          
          margin: 0;
          padding: 40px 0;
          box-sizing: border-box;
        }
        
        /* Hide Scrollbars */
        ::-webkit-scrollbar {
            display: none;
        }
        
        .chapter-container {
            break-before: always;
        }

        /* Add padding to content elements for reading comfort */
        p, h1, h2, h3, h4, h5, h6, li, div {
          padding-left: 20px;
          padding-right: 20px;
          box-sizing: border-box;
        }
        
        img {
          max-height: 90vh; /* Leave room for margins */
          max-width: calc(100vw - 40px);
          width: auto;
          height: auto;
          margin: 0 auto;
          display: block;
          object-fit: contain;
          break-inside: avoid;
        }
      ''';
    } else {
      // Vertical Mode CSS
      scrollCss = '''
        body {
          padding: 50px 30px 40px 30px !important;
          margin: 0 auto !important;
          max-width: 800px !important;
          box-sizing: border-box !important;
          overflow-x: hidden !important;
        }
        img, video, svg {
          max-width: 100%;
          height: auto;
        }
      ''';
    }

    // ... (Highlights setup same) ...

    // ... (Arrow HTML same) ...

    // ... (inject CSS string ... same)

    // ... (Rest of HTML wrapping) ...

    // Prepare highlights JSON with ID, filtering by current chapter
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
              print('Error parsing highlight CFI for filtering: $e');
              return false;
            }
          })
          .map((h) {
            return {
              'id': h.id,
              'cfi': h.cfi, // This is the JSON string
            };
          })
          .toList(),
    );

    // Serialize anchors for user interactions
    final anchorsJson = jsonEncode(anchors);

    // Arrow HTML - Only relevant for vertical or end of book, usually handled by native UI in horizontal but we keep it
    const arrowHtml = '''
      <div id="next-chapter-btn" onclick="window.flutter_inappwebview.callHandler('onNextChapter')" class="next-chapter-button" style="margin-top: auto; padding: 40px 0; text-align: center; cursor: pointer; opacity: 0.5; transition: opacity 0.3s; break-inside: avoid;">
         <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1" stroke-linecap="round" stroke-linejoin="round">
           <path d="M7 13l5 5 5-5M7 6l5 5 5-5"/>
         </svg>
      </div>
    ''';

    final css =
        '''
      <style>
        html {
          box-sizing: border-box;
          overflow-x: hidden;
          height: 100%; /* Ensure html is at least 100% height */
        }
        *, *:before, *:after {
          box-sizing: inherit;
        }
        body {
          background-color: transparent !important;
          color: $textColor !important;
          font-size: ${fontSize}% ;
          font-family: $fontFamily !important;
          line-height: 1.8 !important;
          position: relative;
          -webkit-touch-callout: none !important; /* Attempt to suppress system menu */
          -webkit-user-select: text !important; /* Allow selection */
          user-select: text !important;
          -webkit-text-size-adjust: 100%;
          /* width: 100%;  <-- specific width handled inscrollCss */
          
          /* Flexbox for sticky footer behavior in Vert, Block in Horiz */
          min-height: 100%;
          ${scrollMode == ReaderScrollMode.vertical ? 'display: flex; flex-direction: column;' : 'display: block;'}
        }
        $scrollCss
        
        /* Selection Styles */
        ::selection {
            background-color: ${theme == ReaderTheme.dark ? 'rgba(64, 196, 255, 0.5)' : 'rgba(33, 150, 243, 0.3)'};
            color: inherit;
        }
        /* Suppress on all elements by default to fix 'select whole page' bug */
        * {
          -webkit-touch-callout: none !important;
          -webkit-user-select: none;
          user-select: none;
        }
        
        /* Re-enable selection on text content specifically */
        p, div, span, h1, h2, h3, h4, h5, h6, li, blockquote, a {
            -webkit-user-select: text !important;
            user-select: text !important;
            cursor: text;
        }
        
        /* Force global font settings to override ANY book defaults */
        body * {
            font-family: inherit !important;
            font-size: inherit !important;
            line-height: inherit !important;
            max-width: 100% !important;
            box-sizing: border-box !important;
        }
        
        body {
            opacity: 1;
            transition: opacity 0.2s ease-in;
        }
        body.loading {
            opacity: 0;
        }

        /* Specific formatting for text blocks */
        p, div, span, li, blockquote, a {
            white-space: normal !important; /* Force normal wrapping (fixes OCR line breaks) */
            word-wrap: break-word !important;
            margin-top: 0 !important;
            margin-bottom: 1em !important;
        }
        
        pre {
            white-space: pre-wrap !important;
        }
        
        h1 { font-size: 2em !important; margin-left: 0 !important; margin-right: 0 !important; }
        h2 { font-size: 1.5em !important; margin-left: 0 !important; margin-right: 0 !important; }
        h3 { font-size: 1.17em !important; margin-left: 0 !important; margin-right: 0 !important; }
        h4 { font-size: 1em !important; margin-left: 0 !important; margin-right: 0 !important; }
        h5 { font-size: 0.83em !important; margin-left: 0 !important; margin-right: 0 !important; }
        h6 { font-size: 0.67em !important; margin-left: 0 !important; margin-right: 0 !important; }
          /* Custom Menu */
          /* Custom Menu & Highlight Menu */
        #custom-menu, #highlight-menu {
            all: initial;
            position: absolute;
            background-color: #1a1a1a !important; /* Force Opaque */
            border-radius: 18px;
            padding: 8px;
            display: none;
            grid-template-columns: 43px 43px;
            grid-template-rows: 43px 43px;
            gap: 8px;
            z-index: 2147483647 !important;
            pointer-events: auto !important;
            box-shadow: 0 6px 24px rgba(0,0,0,0.6), 0 0 0 1px rgba(255,255,255,0.15);
            width: 110px; 
            height: 110px;
            
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, Helvetica, Arial, sans-serif !important;
            box-sizing: border-box !important;
            
            /* Isolation to force new stacking context on top */
            isolation: isolate; 
            
            /* Animation - NO TRANSFORM to avoid stacking issues with selection */
            opacity: 0;
            transition: opacity 0.1s ease-out;
        }
        
        #custom-menu.visible, #highlight-menu.visible {
            display: grid !important;
            opacity: 1;
        }

        #custom-menu *, #highlight-menu * {
            box-sizing: border-box !important;
            -webkit-user-select: none !important;
            user-select: none !important;
            
            /* CRITICAL: Override global 'body *' wildcards to prevent book settings from breaking menu */
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, Helvetica, Arial, sans-serif !important;
            font-size: 16px !important; 
            line-height: 1 !important;
            letter-spacing: normal !important;
            max-width: none !important;
        }
        
        .menu-item {
            color: #ffffff;
            padding: 0;
            margin: 0;
            cursor: pointer;
            display: flex;
            align-items: center;
            justify-content: center;
            background-color: #2c2c2c;
            border-radius: 10px;
            transition: background-color 0.1s;
            width: 100%;
            height: 100%;
            position: relative;
        }
        .menu-item:hover {
            background-color: #3d3d3d;
        }
        .menu-item:active {
            background-color: #505050;
            transform: scale(0.96);
        }
        
        /* First item (Highlight) spans full width in 3-item layout (Main Menu) */
        #btn-highlight {
            grid-column: span 2;
        }

        .menu-item svg {
            width: 22px; 
            height: 22px;
            fill: #ffffff; 
            display: block;
            margin: 0; 
        }

        /* Trash Icon for Highlight Menu */
        #btn-delete svg {
            fill: #ff5252; /* Red for delete */
        }

        /* Solid Tail */
        #custom-menu::after, #highlight-menu::after {
            content: '';
            position: absolute;
            bottom: -6px;
            left: 50%;
            margin-left: -6px;
            width: 0;
            height: 0;
            border-left: 6px solid transparent;
            border-right: 6px solid transparent;
            border-top: 6px solid #1a1a1a;
        }
        
        #custom-menu.below::after, #highlight-menu.below::after {
            bottom: auto;
            top: -6px;
            border-top: none;
            border-bottom: 6px solid #1a1a1a;
        }
        
        .highlight {
            background-color: ${theme == ReaderTheme.dark ? 'rgba(253, 216, 53, 0.4)' : 'rgba(255, 235, 59, 0.4)'};
            cursor: pointer;
            border-bottom: 2px solid ${theme == ReaderTheme.dark ? 'rgba(253, 216, 53, 0.8)' : 'rgba(253, 216, 53, 0.8)'}; 
            color: inherit;
        }
      </style>
      <script type="text/javascript">
      /* <![CDATA[ */
        // Injected Data
        let currentSpineIndex = $spineIndex;
        const chapterAnchors = $anchorsJson; // [{id: 'p1', chapterIndex: 5}, ...]
        const initialScrollAnchor = ${jsonEncode(scrollToAnchor)};
        const initialProgress = ${jsonEncode(initialProgress)};
        
        window.onerror = function(message, source, lineno, colno, error) {
            console.log("JS ERROR: " + message + " at " + lineno + ":" + colno);
        };

        console.log("JS STARTING - Spine Index: " + currentSpineIndex);
        var interactionLocked = false;
        var inputBlocked = false; // New global to completely block input

        window.setInteractionLocked = function(locked) {
            interactionLocked = locked;
            console.log("Interaction Locked: " + locked);
        }
        
        window.setInputBlocked = function(blocked) {
            inputBlocked = blocked;
            console.log("Input Blocked: " + blocked);
        }

        window.setTheme = function(textColor, bgColor) {
            console.log("Setting Theme: Text=" + textColor + " Bg=" + bgColor);
            document.body.style.setProperty('color', textColor, 'important');
            if (bgColor) {
                 document.body.style.setProperty('background-color', bgColor, 'important');
                 // Also attempt to override html background if needed
                 document.documentElement.style.setProperty('background-color', bgColor, 'important');
            }
        };
        
        window.setFontFamily = function(family) {
            console.log("Setting Font Family: " + family);
            document.body.style.setProperty('font-family', family, 'important');
        };
      </script>
      <script>
        // Polyfill console.log to send to Flutter
        var oldLog = console.log;
        console.log = function(message) {
            if (window.flutter_inappwebview) {
                window.flutter_inappwebview.callHandler('consoleLog', message);
            }
            oldLog.apply(console, arguments);
        };

        function getPathTo(element) {
            // Text Node?
            if (element.nodeType === 3) {
                 // Proceed to logic below which handles index among siblings
            } else if (element.nodeType === 1 && element.id && element.id !== '') {
                 return '//*[@id="' + element.id + '"]';
            }
            
            if (element === document.body) return element.tagName;
            if (!element.parentNode) return "";
            
            var siblings = element.parentNode.childNodes;
            var ix = 0;
            for (var i = 0; i < siblings.length; i++) {
                var sibling = siblings[i];
                if (sibling === element) {
                    var parentPath = getPathTo(element.parentNode);
                    return parentPath === "/" ? "" + ix : parentPath + "/" + ix;
                }
                if (sibling.nodeType === 1 || sibling.nodeType === 3) ix++; // Only count element and text nodes
            }
            return null;
        }

        function getNodeByPath(path) {
            if (!path || path === "/" || path === "") return document.body;

            var el = document.body;
            var parts = path.split('/');
            
            // Check for ID at the start
            // Pattern: //*[@id="SOME_ID"]...
            // Note: We must double-escape backslashes for Dart string interpolation
            var idMatch = path.match(/^\\/\\/\\*\\[@id="([^"]+)"\\]/);
            if (idMatch && idMatch[1]) {
                var id = idMatch[1];
                var foundEl = document.getElementById(id);
                if (foundEl) {
                    el = foundEl;
                    // Remove the ID part from the path to process remaining children
                    // path = //*[@id="foo"]/1/2
                    // valid rest = /1/2
                    var suffix = path.substring(idMatch[0].length);
                    parts = suffix.split('/').filter(function(p) { return p !== ""; });
                } else {
                    console.log("Element with ID " + id + " not found, falling back to body traversal.");
                    // Fallback to full traversal if ID not found? 
                    // Usually implies ID mismatch or changed DOM.
                    // For now, let's try to continue from body if parts allows, but usually ID is root.
                    // If ID fails, the path is likely invalid for this DOM.
                    return null;
                }
            } else {
                 // No ID, standard root traversal
                 // parts are already split above
            }
            
            for (var i = 0; i < parts.length; i++) {
                if (parts[i] === "") continue; 
                var ix = parseInt(parts[i]);
                if (isNaN(ix)) continue;
                
                // Find ix-th sibling of interest
                var found = null;
                var currentIx = 0;
                for (var j = 0; j < el.childNodes.length; j++) {
                    var sibling = el.childNodes[j];
                    if (sibling.nodeType === 1 || sibling.nodeType === 3) {
                         if (currentIx === ix) {
                             found = sibling;
                             break;
                         }
                         currentIx++;
                    }
                }
                
                if (found) {
                    el = found;
                } else {
                    console.log("Node not found for path " + path + " at index " + ix);
                    return null;
                }
            }
            return el;
        }

        function restorePath(pathData) {
            console.log("Attempting to restore: " + pathData);
            if (!pathData || pathData === "") return;
            
            try {
                var path = pathData;
                var offset = 0;
                var isPrecise = false;
                
                // Parse JSON if applicable
                if (pathData.trim().startsWith('{')) {
                    try {
                        var json = JSON.parse(pathData);
                        path = json.path;
                        offset = json.offset || 0;
                        isPrecise = true;
                    } catch (e) {
                         console.log("Error parsing path JSON: " + e);
                    }
                }
                
                // Legacy check
                if (!path.includes('/')) {
                     console.log("Path is legacy (percent): " + path);
                    return; 
                }

                var el = getNodeByPath(path);
                
                if (el) {
                    var nodeName = el.nodeType === 3 ? "TEXT" : el.tagName;
                    var textContent = el.textContent ? el.textContent.substring(0, 20) : "";
                    console.log("Restoring Node found: " + nodeName + " '" + textContent + "' offset: " + offset);
                    
                    // Determine Rect
                    var rect;
                    
                    if (isPrecise && el.nodeType === 3) {
                         // Create range for specific character position
                         try {
                            var range = document.createRange();
                            // Ensure offset is valid
                            if (offset > el.textContent.length) offset = el.textContent.length;
                            range.setStart(el, offset);
                            range.setEnd(el, offset); // Collapsed range at point
                            
                            // range.getBoundingClientRect() gives 0 width but valid x/y
                            // However, getClientRects() is safer for wrapped lines
                            var rects = range.getClientRects();
                            if (rects.length > 0) {
                                rect = rects[0];
                            } else {
                                rect = range.getBoundingClientRect();
                            }
                         } catch (e) {
                             console.log("Range creation failed: " + e); 
                             // Fallback
                             var r = document.createRange();
                             r.selectNode(el);
                             rect = r.getBoundingClientRect();
                         }
                    } else {
                        // Element or fallback
                         if (el.nodeType === 3) {
                             var range = document.createRange();
                             range.selectNode(el);
                             rect = range.getBoundingClientRect();
                         } else {
                             rect = el.getBoundingClientRect();
                         }
                    }

                    // Check Mode
                    if (${scrollMode == ReaderScrollMode.horizontal}) {
                         var container = document.getElementById('reader-content');
                         var currentScroll = container ? container.scrollLeft : window.scrollX;
                         
                         // Visual Left absolute distance from start of content
                         var visualLeft = rect.left + currentScroll;
                         
                         // Snap to page
                         // Ensure we don't round down if we are EXACTLY on edge, but floor handles that.
                         // But if rect.left is e.g. -0.5, it might be page -1? No rect.left is viewport relative.
                         var pageIndex = Math.floor(visualLeft / window.innerWidth);
                         var targetScroll = pageIndex * window.innerWidth;
                         
                         console.log("Restoring Horizontal: RectLeft=" + rect.left + " CurScroll=" + currentScroll + " VisualLeft=" + visualLeft + " Page=" + pageIndex + " Target=" + targetScroll);
                         
                         if (container) {
                             container.scrollLeft = targetScroll;
                         } else {
                             window.scrollTo(targetScroll, 0);
                         }
                    } else {
                        // Vertical Mode
                        if (rect) {
                             // Scroll so rect.top aligns with top (plus some padding?)
                             // window.scrollTo(0, window.scrollY + rect.top - 60); 
                             // Wait, rect.top is relative to viewport.
                             // Absolute Y = window.scrollY + rect.top.
                             // We probed at 60. So we want to put it at 60.
                             var targetY = window.scrollY + rect.top - 60;
                             window.scrollTo(0, targetY);
                        } else {
                            if (el.nodeType === 3 && el.parentNode) { 
                                el.parentNode.scrollIntoView(true); 
                            } else {
                                el.scrollIntoView(true);
                            }
                        }
                    }
                } else {
                    console.log("Node NOT found for path: " + path);
                }
            } catch (e) { console.log("Error restoring path: " + e); }
        }

        const icons = {
          highlight: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04c.39-.39.39-1.02 0-1.41l-2.34-2.34c-.39-.39-1.02-.39-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z"/></svg>',
          assign: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/></svg>',
          copy: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z"/></svg>',
          delete: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>',
          note: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04c.39-.39.39-1.02 0-1.41l-2.34-2.34c-.39-.39-1.02-.39-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z"/></svg>' // Reuse pen or used document? Let's use document text.
          // Better note icon:
          // note: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z"/></svg>'
        };

        // Global state
        let observer;
        
        function init() {
           console.log("Initializing Reader...");
            // Inject Menu
            var menu = document.createElement('div');
            menu.id = 'custom-menu';
            menu.innerHTML = `
              <div class="menu-item" id="btn-highlight" style="grid-column: span 2;">
                \${icons.highlight}
              </div>
              <div class="menu-item" id="btn-assign">
                \${icons.assign}
              </div>
              <div class="menu-item" id="btn-copy">
                \${icons.copy}
              </div>
             `;
            // Adjust Main Menu Grid (2x2, highlight spans top)
            menu.style.gridTemplateColumns = '43px 43px';
            menu.style.gridTemplateRows = '43px 43px';
            menu.style.height = '110px'; 
            menu.style.width = '110px'; 
            document.body.appendChild(menu);
            
            // Highlight Context Menu
            var hlMenu = document.createElement('div');
            hlMenu.id = 'highlight-menu';
            hlMenu.style.cssText = menu.style.cssText; 
            hlMenu.innerHTML = `
              <div class="menu-item" id="btn-hl-assign">
                \${icons.assign}
              </div>
              <div class="menu-item" id="btn-hl-note">
                \${icons.note}
              </div>
              <div class="menu-item" id="btn-delete">
                \${icons.delete}
              </div>
            `;
            // Adjust Highlight Menu Grid (1x3)
            hlMenu.style.gridTemplateColumns = '1fr 1fr 1fr';
            hlMenu.style.gridTemplateRows = '1fr';
            hlMenu.style.height = '60px'; 
            hlMenu.style.width = '165px'; // increased width for 3 items
            
            document.body.appendChild(hlMenu);
            
            // Load Saved Highlights
            console.log("Init started...");
            
            // Restore Highlights
            try {
                var highlights = ${jsonEncode(highlights.map((h) => {'id': h.id, 'cfi': h.cfi}).toList())};
                if (highlights && highlights.length > 0) {
                    console.log("Restoring " + highlights.length + " highlights...");
                    // Delay slightly to ensure DOM is ready? already in init..
                    setTimeout(function() {
                         try {
                             highlights.forEach(function(h) {
                                 applyHighlight(h.cfi, h.id);
                             });
                             console.log("Highlights restored.");
                         } catch(e) {
                             console.log("Error inside highlight loop: " + e);
                         }
                    }, 100);
                } else {
                    console.log("No highlights to restore.");
                }
            } catch(e) {
                console.log("Error setting up highlights: " + e);
            }
            
            console.log("Init proceeding...");

             // Bind Events (Main Menu)
            document.getElementById('btn-highlight').addEventListener('mousedown', function(e) { handleAction(e, 'highlight'); });
            document.getElementById('btn-assign').addEventListener('mousedown', function(e) { handleAction(e, 'assign'); });
            document.getElementById('btn-copy').addEventListener('mousedown', function(e) { handleAction(e, 'copy'); });
            
            // Bind Events (Highlight Menu)
            // We use a global currentHighlightId to track what we are acting on
            document.getElementById('btn-hl-assign').addEventListener('mousedown', function(e) { handleHighlightAction(e, 'assign'); });
            document.getElementById('btn-hl-note').addEventListener('mousedown', function(e) { handleHighlightAction(e, 'note'); });
            document.getElementById('btn-delete').addEventListener('mousedown', function(e) { handleHighlightAction(e, 'delete'); });

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
           
           function handleAction(e, action) {
               e.preventDefault();
               e.stopPropagation();
               var cfi = getCFI();
               var text = window.getSelection().toString();
               
               if (window.flutter_inappwebview) {
                   window.flutter_inappwebview.callHandler('onMenuAction', action, cfi, text);
               }
               
               window.getSelection().removeAllRanges();
               hideMenu();
           }

           // Selection Change
           document.addEventListener('selectionchange', function() {
               var selection = window.getSelection();
               console.log('Selection change: ' + selection.toString());
               if (selection.rangeCount > 0 && !selection.isCollapsed && selection.toString().trim().length > 0) {
                   var range = selection.getRangeAt(0);
                   var rect = range.getBoundingClientRect();
                   console.log("DBG: Selection Active. Rect: " + rect.left + "," + rect.top + " W:" + rect.width);
                   showMenu(rect);
               } else {
                   console.log("DBG: Selection Empty or Collapsed");
                   hideMenu();
               }
           });
            try {
                // Initialize Observers
                if (${scrollMode == ReaderScrollMode.vertical}) {
                    if (typeof setupVerticalObservers === 'function') {
                        setupVerticalObservers();
                    } else {
                        console.log("Error: setupVerticalObservers not defined");
                    }
                } else {
                    // Horizontal Observers
                    if (typeof setupHorizontalObservers === 'function') {
                         setupHorizontalObservers();
                    } else {
                         console.log("Error: setupHorizontalObservers not defined");
                    }
                }
                           // Scroll restore
                 var restoreDelay = 500; // Increased to 500ms
                 
                 if (initialProgress === 'END') {
                     console.log("Restoring to END");
                     setTimeout(function() {
                         if (${scrollMode == ReaderScrollMode.horizontal}) {
                              var container = document.getElementById('reader-content');
                              if (container) container.scrollLeft = container.scrollWidth;
                         } else {
                              window.scrollTo(0, document.body.scrollHeight);
                         }
                         document.body.classList.remove('loading');
                         isRestoring = false; // Enable Saving
                     }, restoreDelay);
                     
                 } else if (initialScrollAnchor) {
                     setTimeout(function() {
                         var el = document.getElementById(initialScrollAnchor);
                         if (el) {
                             el.scrollIntoView();
                         }
                         document.body.classList.remove('loading');
                         isRestoring = false; // Enable Saving
                     }, restoreDelay);
                 } else if (initialProgress && initialProgress !== '') {
                     // Restore logic
                     if (initialProgress.includes('/') || initialProgress.startsWith('/')) {
                         console.log("Restoring CFI Path: " + initialProgress);
                         setTimeout(function() { 
                             restorePath(initialProgress); 
                             document.body.classList.remove('loading');
                             isRestoring = false; // Enable Saving
                         }, restoreDelay);
                     } else {
                         // Legacy Percent
                         var pct = parseFloat(initialProgress);
                         if (pct > 0) {
                             setTimeout(function() {
                                  if (${scrollMode == ReaderScrollMode.horizontal}) {
                                     var container = document.getElementById('reader-content');
                                     if (container) container.scrollLeft = container.scrollWidth * pct;
                                  } else {
                                     window.scrollTo(0, (document.body.scrollHeight - window.innerHeight) * pct);
                                  }
                                  document.body.classList.remove('loading');
                                  isRestoring = false; // Enable Saving
                             }, restoreDelay);
                         } else {
                             document.body.classList.remove('loading');
                             isRestoring = false; // Enable Saving
                         }
                     }
                 } else {
                     // No restore needed
                     document.body.classList.remove('loading');
                     isRestoring = false; // Enable Saving
                 }
            } catch(e) {
                console.log("Error in observer/restore setup: " + e);
                // Emergency cleanup
                document.body.classList.remove('loading');
                isRestoring = false;
            }
           

        };
        
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', function() {
                console.log("Reader: DOMContentLoaded");
                init();
            });
        } else {
            console.log("Reader: Immediate init");
            init();
        }
        

        /* ---------------- INTERACTION HELPER ---------------- */
        function isInteractive(target) {
            if (!target) return false;
            // Check specific UI components
            if (target.closest('.menu-item') || 
                target.closest('#custom-menu') || 
                target.closest('.highlight') ||
                target.closest('a') ||
                target.closest('button') ||
                target.closest('input') ||
                target.closest('textarea') ||
                target.closest('select')) {
                return true;
            }
            // Check SVG explicitly if closest fails (rare but safe)
            if (target.tagName === 'svg' || target.tagName === 'path' || target.tagName === 'rect') {
                 // Traverse up to find menu? Already handled by closest ideally.
                 // Assume SVGs in this reader are mostly icons for buttons
                 if (target.closest('.menu-icon') || target.closest('.next-chapter-button')) return true;
            }
            return false;
        }

        // Global restoring flag
        var isRestoring = true;

        /* ---------------- VERTICAL OBSERVERS ---------------- */
        function setupVerticalObservers() {
             var lastScrollTime = 0;
            window.addEventListener('scroll', function() {
                var now = new Date().getTime();
                if (now - lastScrollTime > 200) { // Throttle
                    lastScrollTime = now;
                    reportReadingLocation();
                }
            });
            
            // Add Click Handler for Vertical Mode (Toggle Controls)
            document.addEventListener('click', function(e) {
                if (inputBlocked) {
                    e.preventDefault();
                    e.stopPropagation();
                    console.log("Reader: Click Blocked (Input Disabled)");
                    return;
                }
                
                // 1. Interactive Check
                if (isInteractive(e.target)) return;
                
                // 2. Z-Layer: If Menu is Open, Close it ONLY
                if (isMenuOpen()) {
                     hideMenu();
                     return;
                }
                
                // 3. Safe Zones (Navbar Areas)
                // In Vertical, scrollbar is native, but Navbars are overlaid.
                var y = e.clientY;
                if (y < 80 || y > window.innerHeight - 80) return;
                
                // 4. Toggle controls
                if (window.flutter_inappwebview) {
                    window.flutter_inappwebview.callHandler('onTap');
                }
            });
            
             function reportReadingLocation() {
                if (isRestoring) {
                    console.log("Skipping save: Restoring in progress");
                    return;
                }
                var path = getReadingLocation();
                if (path && window.flutter_inappwebview) {
                    window.flutter_inappwebview.callHandler('onScrollProgress', path);
                }
            }
            
            function getReadingLocation() {
                var x = 60; 
                var y = 60; 
                
                // 1. Precise check: caretPositionFromPoint (Standard)
                if (document.caretPositionFromPoint) {
                    var pos = document.caretPositionFromPoint(x, y);
                    if (pos && pos.offsetNode) {
                        var path = getPathTo(pos.offsetNode);
                        var offset = pos.offset;
                        // console.log("DEBUG: Precision Location via CaretPosition: " + path + " offset: " + offset);
                        return JSON.stringify({ type: 'precise', path: path, offset: offset });
                    }
                }
                // 2. Precise check: caretRangeFromPoint (WebKit)
                else if (document.caretRangeFromPoint) {
                    var range = document.caretRangeFromPoint(x, y);
                    if (range && range.startContainer) {
                         var path = getPathTo(range.startContainer);
                         var offset = range.startOffset;
                         // console.log("DEBUG: Precision Location via CaretRange: " + path + " offset: " + offset);
                         return JSON.stringify({ type: 'precise', path: path, offset: offset });
                    }
                }
                
                // 3. Fallback Probe Loop (Element only)
                for (var i = 0; i < 5; i++) {
                     var testY = y + (i * 40);
                     var el = document.elementFromPoint(x, testY);
                     // console.log("DEBUG Probe: " + x + "," + testY + " Found: " + (el ? el.tagName : "null") + " ID: " + (el ? el.id : ""));
                     
                     if (el && el !== document.body && el !== document.documentElement) {
                         var path = getPathTo(el);
                         // console.log("DEBUG: Found fallback location: " + path);
                         return path; 
                     }
                }
                
                // 4. Fallback Center
                var el = document.elementFromPoint(window.innerWidth / 2, window.innerHeight * 0.3);
                if (el && el !== document.body) return getPathTo(el);
                
                return null;
            }

        function restorePath(pathData) {
            console.log("Attempting to restore: " + pathData);
            if (!pathData || pathData === "") return;
            
            try {
                var path = pathData;
                var offset = 0;
                var isPrecise = false;
                
                if (pathData.trim().startsWith('{')) {
                    try {
                        var json = JSON.parse(pathData);
                        path = json.path;
                        offset = json.offset || 0;
                        isPrecise = true;
                    } catch (e) {
                         console.log("Error parsing path JSON: " + e);
                    }
                }
                
                if (!path.includes('/')) {
                     console.log("Path is legacy (percent): " + path);
                    return; 
                }

                var el = getNodeByPath(path);
                
                if (el) {
                    var nodeName = el.nodeType === 3 ? "TEXT" : el.tagName;
                    var textContent = el.textContent ? el.textContent.substring(0, 20) : "";
                    console.log("Restoring Node found: " + nodeName + " '" + textContent + "' offset: " + offset);
                    
                    var rect;
                    
                    if (isPrecise && el.nodeType === 3) {
                         try {
                            var range = document.createRange();
                            if (offset > el.textContent.length) offset = el.textContent.length;
                            range.setStart(el, offset);
                            range.setEnd(el, offset); 
                            
                            var rects = range.getClientRects();
                            if (rects.length > 0) {
                                rect = rects[0];
                                console.log("Restoring via Range Rect: " + rect.left + "," + rect.top);
                            } else {
                                rect = range.getBoundingClientRect();
                                console.log("Restoring via Range BBOX: " + rect.left + "," + rect.top);
                            }
                         } catch (e) {
                             console.log("Range creation failed: " + e); 
                             var r = document.createRange();
                             r.selectNode(el);
                             rect = r.getBoundingClientRect();
                         }
                    } else {
                         if (el.nodeType === 3) {
                             var range = document.createRange();
                             range.selectNode(el);
                             rect = range.getBoundingClientRect();
                         } else {
                             rect = el.getBoundingClientRect();
                         }
                         console.log("Restoring via Element Rect: " + rect.left + "," + rect.top);
                    }

                    if (${scrollMode == ReaderScrollMode.horizontal}) {
                         var container = document.getElementById('reader-content');
                         var currentScroll = container ? container.scrollLeft : window.scrollX;
                         
                         var visualLeft = rect.left + currentScroll;
                         
                         // Try to be smart about "close calls"
                         // If x=60, visualLeft should be PageIndex * width + 60.
                         // So (visualLeft / width) should be X.0something.
                         // But if visualLeft is slightly less than width (e.g. 799), we are on Page 0.
                         // If rect.left < 0? That would mean previous page.
                         
                         var pageIndex = Math.floor(visualLeft / window.innerWidth);
                         var targetScroll = pageIndex * window.innerWidth;
                         
                         console.log("Restoring Horizontal: RectLeft=" + rect.left + " CurScroll=" + currentScroll + " VisualLeft=" + visualLeft + " WinWidth=" + window.innerWidth + " Page=" + pageIndex);
                         
                         if (container) {
                             container.scrollLeft = targetScroll;
                         } else {
                             window.scrollTo(targetScroll, 0);
                         }
                    } else {
                        if (rect) {
                             var targetY = window.scrollY + rect.top - 60;
                             window.scrollTo(0, targetY);
                        } else {
                            if (el.nodeType === 3 && el.parentNode) { 
                                el.parentNode.scrollIntoView(true); 
                            } else {
                                el.scrollIntoView(true);
                            }
                        }
                    }
                } else {
                    console.log("Node NOT found for path: " + path);
                }
            } catch (e) { console.log("Error restoring path: " + e); }
        }
            
            window.getCurrentLocationPath = getReadingLocation;
        }

        /* ---------------- HORIZONTAL OBSERVERS ---------------- */
         function setupHorizontalObservers() {
              console.log("Reader: Setting up Horizontal Observers...");
              
              var container = document.getElementById('reader-content');
              if (!container) {
                  console.log("Reader: Container not found! Falling back to window.");
                  container = window; // Fallback? But logic differs
                  // Actually, if we use window, we need different logic.
                  // Let's assume container exists because we just injected it.
              }
              
              // Custom Touch Pagination + Tap Zones
              var touchStartX = 0;
              var touchStartY = 0;
              var touchStartTime = 0;
              var startScrollLeft = 0; // Capture initial scroll position
              var isDragging = false;
              var isScrolling = false; // scrolling vertically or selecting
              
              // New MacOS / Desktop Support
              var lastHandledTapTime = 0;
              
              // 1. Key Navigation
              document.addEventListener('keydown', function(e) {
                  if (interactionLocked || inputBlocked) return;
                  
                  if (e.key === 'ArrowRight') {
                       e.preventDefault();
                       var curScroll = container.scrollLeft !== undefined ? container.scrollLeft : window.scrollX;
                       var page = Math.round(curScroll / width);
                       snapToPage(page + 1);
                  } else if (e.key === 'ArrowLeft') {
                       e.preventDefault();
                       var curScroll = container.scrollLeft !== undefined ? container.scrollLeft : window.scrollX;
                       var page = Math.round(curScroll / width);
                       snapToPage(page - 1);
                  }
              });
              
              // 2. Click Handler (for non-touch devices or hybrid)
              document.addEventListener('click', function(e) {
                  if (inputBlocked) return;
                  if (new Date().getTime() - lastHandledTapTime < 500) {
                      console.log("Reader: Click ignored (handled by touch)");
                      return; 
                  }
                  
                  if (isInteractive(e.target)) return;
                  if (isMenuOpen()) { hideMenu(); return; }
                  
                  // Use standardized Tap Logic (Zones)
                  handleTap(e.clientX);
              });
              
              const width = window.innerWidth;
              
              document.addEventListener('touchstart', function(e) {
                  if (inputBlocked) return; // Block interaction
                  
                  // Always capture interaction start
                  if (e.touches.length !== 1) return;
                  touchStartX = e.touches[0].clientX;
                  touchStartY = e.touches[0].clientY;
                  touchStartTime = new Date().getTime();
                  startScrollLeft = container.scrollLeft !== undefined ? container.scrollLeft : window.scrollX;
                  isDragging = true;
                  isScrolling = false;
              }, {passive: false});
              
              document.addEventListener('touchmove', function(e) {
                   // if text is selected, let the native drag happen (don't scroll/swipe)
                   var selection = window.getSelection();
                   if (selection && !selection.isCollapsed) {
                       isDragging = false; // Cancel drag so touchend doesn't trigger swipe
                       return;
                   }

                   if (inputBlocked) {
                       e.preventDefault(); 
                       return;
                   }
                   if (interactionLocked) {
                       e.preventDefault(); // Strict Scroll Lock
                       return;
                   }
                   if (!isDragging) return;
                   
                   var x = e.touches[0].clientX;
                   var y = e.touches[0].clientY;
                   var diffX = touchStartX - x;
                   var diffY = touchStartY - y;
                   
                   // Vertical Scroll Detection
                   if (!isScrolling) {
                       if (Math.abs(diffY) > Math.abs(diffX)) {
                           isScrolling = true;
                           isDragging = false;
                           return; 
                       }
                   }
                   
                   if (isScrolling) return;

                   // Horizontal Swipe Logic
                   e.preventDefault(); // Prevent native
                   
                   // FIX: Calculate new position from START scroll, not current
                   var newScrollLeft = startScrollLeft + diffX;
                   
                   if (container.scrollTo) {
                       container.scrollTo(newScrollLeft, 0);
                   } else {
                       container.scrollLeft = newScrollLeft;
                   }
              }, {passive: false});

              // Wheel Event Listener for Trackpad/Mouse
              var wheelCooldown = false;
              var accumulatedDeltaX = 0;
              var wheelTimer;
              
              document.addEventListener('wheel', function(e) {
                  if (interactionLocked || inputBlocked) {
                      e.preventDefault();
                      return;
                  }
                  
                  // Only hijack vertical scrolling if it's primarily horizontal (or Shift+Scroll)
                  // Actually, trackpads often send DeltaX. 
                  // But standard mouse wheel sends DeltaY. 
                  // We should accept either for paging if strictly horizontal mode.
                  
                  e.preventDefault(); // Stop native scrolling completely in this mode
                  
                  if (wheelCooldown) return;
                  
                  var dx = e.deltaX;
                  var dy = e.deltaY;
                  
                  // Use the dominant axis
                  var delta = Math.abs(dx) > Math.abs(dy) ? dx : dy;
                  
                  accumulatedDeltaX += delta;
                  
                  // Clear accumulator if no events for a short while (user stopped)
                  clearTimeout(wheelTimer);
                  wheelTimer = setTimeout(function() {
                       accumulatedDeltaX = 0;
                  }, 200);
                  
                  // Threshold for page turn
                  var threshold = 30; // Sensitive enough for trackpad flick
                  
                  if (accumulatedDeltaX > threshold) {
                       // Next Page
                       wheelCooldown = true;
                       var curScroll = container.scrollLeft !== undefined ? container.scrollLeft : window.scrollX;
                       var page = Math.round(curScroll / width);
                       snapToPage(page + 1);
                       
                       setTimeout(function() { wheelCooldown = false; accumulatedDeltaX = 0; }, 800); // 800ms lockout
                  } else if (accumulatedDeltaX < -threshold) {
                       // Prev Page
                       wheelCooldown = true;
                       var curScroll = container.scrollLeft !== undefined ? container.scrollLeft : window.scrollX;
                       var page = Math.round(curScroll / width);
                       snapToPage(page - 1);
                       
                       setTimeout(function() { wheelCooldown = false; accumulatedDeltaX = 0; }, 800);
                  }
              }, {passive: false});

              document.addEventListener('touchend', function(e) {
                  if (inputBlocked) {
                      e.preventDefault();
                      return;
                  }

                  var selection = window.getSelection();
                  if (selection && !selection.isCollapsed) return;
                   
                  if (!isDragging) return;
                  isDragging = false;
                  
                  var touchEndX = e.changedTouches[0].clientX;
                  var diffX = touchStartX - touchEndX;
                  var timeDiff = new Date().getTime() - touchStartTime;
                  
                  // Detect Tap
                  if (timeDiff < 300 && Math.abs(diffX) < 10 && Math.abs(touchStartY - e.changedTouches[0].clientY) < 10) {
                      
                      // 1. Check if user tapped an interactive element
                      if (isInteractive(e.target)) {
                           console.log("Reader: Tap on Interactive Element -> Ignoring Toggle");
                           return; // Let native click proceed
                      }
                      
                      // 2. Z-Layer: If Menu is Open, Close it ONLY (Keep controls)
                      if (isMenuOpen()) {
                          console.log("Reader: Tap outside Open Menu -> Closing Menu Only");
                          hideMenu();
                          return;
                      }
                      
                      // 3. If Locked, check Safe Zones (Navbar Areas)
                      if (interactionLocked) {
                          var y = e.changedTouches[0].clientY;
                          var h = window.innerHeight;
                          // Ignore taps in the top/bottom 80px (Navbar areas)
                          if (y < 80 || y > h - 80) {
                              console.log("Reader: Locked Tap in Safe Zone (Navbar) -> Ignoring");
                              return;
                          }
                          
                          console.log("Reader: Locked Tap on Content -> Dismissing Controls");
                          e.preventDefault(); // Prevent ghost click
                          lastHandledTapTime = new Date().getTime(); // Ensure click handler ignores this
                          if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler('onTap');
                          return;
                      }
                      
                      // 4. If Unlocked, handle Tap Zones
                      lastHandledTapTime = new Date().getTime();
                      handleTap(touchStartX);
                      return; 
                  }
                  
                  // Detect Swipe
                  if (interactionLocked) return; // Ignore Swipes if Locked

                  var startPage = Math.round(startScrollLeft / width);
                  var targetPage = startPage;
                      
                  if (Math.abs(diffX) > 50) { 
                      // Significant swipe
                      if (diffX > 0) { 
                          targetPage = startPage + 1; 
                      } else { 
                          targetPage = startPage - 1; 
                      }
                  } else {
                      // Small flick, stay on start page (snap back)
                      targetPage = startPage;
                  }
                  
                  // Clamp to adjacent page only
                  // Ensure we don't jump more than 1 page from START
                  if (targetPage > startPage + 1) targetPage = startPage + 1;
                  if (targetPage < startPage - 1) targetPage = startPage - 1;

                  snapToPage(targetPage);
              });
              
              function handleTap(x) {
                  var width = window.innerWidth;
                  var p = x / width;
                  console.log("Reader: Tap at " + p);
                  
                  if (p < 0.2) {
                      snapToPage(Math.round((container.scrollLeft || window.scrollX) / width) - 1);
                  } else if (p > 0.8) {
                      snapToPage(Math.round((container.scrollLeft || window.scrollX) / width) + 1);
                  } else {
                      // Center Tap -> Toggle
                      if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler('onTap');
                  }
              }
              
              function snapToPage(pageIndex) {
                  // container scrollWidth
                  var scrollW = container.scrollWidth !== undefined ? container.scrollWidth : document.body.scrollWidth;
                  var maxPage = Math.ceil(scrollW / width) - 1;
                  
                  if (pageIndex < 0) {
                      if (container.scrollTo) container.scrollTo({left: 0, behavior: 'smooth'});
                      else container.scrollLeft = 0;
                      
                      if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler('onPrevChapter');
                      return;
                  }
                  
                  if (pageIndex > maxPage) {
                      if (container.scrollTo) container.scrollTo({left: maxPage * width, behavior: 'smooth'});
                      else container.scrollLeft = maxPage * width;
                      
                      if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler('onNextChapter');
                      return;
                  }
                  
                  if (container.scrollTo) {
                      container.scrollTo({
                         left: pageIndex * width,
                         behavior: 'smooth'
                      });
                  } else {
                      // Helper for smooth scroll manually?
                      container.scrollLeft = pageIndex * width;
                  }
   
                  setTimeout(reportHorizontalLocation, 300);
              }
              
              function reportHorizontalLocation() {
                  var path = getHorizontalLocation();
                  if (path && window.flutter_inappwebview) {
                      window.flutter_inappwebview.callHandler('onScrollProgress', path);
                  }
                  
                  // Near End Check
                  var scrollW = container.scrollWidth !== undefined ? container.scrollWidth : document.body.scrollWidth;
                  var curScroll = container.scrollLeft !== undefined ? container.scrollLeft : window.scrollX;
                  
                  var remaining = scrollW - curScroll - window.innerWidth;
                  
                  // console.log("Reader: Progress " + curScroll + " / " + scrollW);
                  
                  if (remaining < window.innerWidth * 1.5) { 
                      if (window.flutter_inappwebview) {
                          window.flutter_inappwebview.callHandler('onNearEnd');
                      }
                  }
              }
              
              function getHorizontalLocation() {
                  var curScroll = container.scrollLeft !== undefined ? container.scrollLeft : window.scrollX;
                  var x = curScroll - curScroll + 40; // Relative to viewport??
                  // elementFromPoint uses Viewport coordinates (window based). 
                  // So x should just be 40 if the sticky header is there?
                  // Wait. If we scroll the CONTAINER, the viewport coordinates of the text change?
                  // No, the text moves left. So text at left edge is what we want.
                  // Text at x=40, y=60 (screen coords) IS the text we are reading.
                  var xScreen = 40;
                  var yScreen = 60;
                  
                  var range, node;
                  if (document.caretRangeFromPoint) {
                      range = document.caretRangeFromPoint(xScreen, yScreen);
                      if (range) node = range.startContainer;
                  }
                  if (!node) node = document.elementFromPoint(xScreen, yScreen);
                  
                  if (node) {
                      if (node.nodeType === 3) {}
                      return getPathTo(node);
                  }
                  return null;
              }
              
              window.getCurrentLocationPath = getHorizontalLocation;
 
              // Initial check
              setTimeout(reportHorizontalLocation, 500);
         }

        
        // Global for Highlight Menu
        var currentHighlightId = null;

        function showMenu(rect) {
            console.log("DBG: showMenu called");
            // Hide highlight menu if open
            hideHighlightMenu();
            
            var menu = document.getElementById('custom-menu');
            if (!menu) {
                console.log("DBG: Menu element not found!");
                return;
            }
            
            var scrollX = window.scrollX || window.pageXOffset;
            var scrollY = window.scrollY || window.pageYOffset;
            
            
            
            menu.style.display = 'grid';
            // Trigger reflow
            menu.offsetHeight;
            menu.classList.add('visible');
            
            // Calculate position
            var menuWidth = menu.offsetWidth;
            var menuHeight = menu.offsetHeight;
            
            var top = rect.top - menuHeight - 15 + scrollY;
            // Pad the interaction area above
            
            // Adjust left to center
            var left = rect.left + (rect.width / 2) + scrollX;
            
            // Check bounds
            if (top < scrollY + 40) {
                // Not enough space above, show below
                top = rect.bottom + 15 + scrollY;
                menu.classList.add('below');
            } else {
                menu.classList.remove('below');
            }
            
            // Ensure horizontal containment
            if (left - (menuWidth / 2) < 10) left = (menuWidth / 2) + 10;
            if (left + (menuWidth / 2) > window.innerWidth - 10) left = window.innerWidth - 10 - (menuWidth / 2);

            menu.style.top = top + 'px';
            menu.style.left = left - (menuWidth / 2) + 'px'; // Center horizontally
        }

        function hideMenu() {
            var menu = document.getElementById('custom-menu');
            if (menu) {
                menu.classList.remove('visible');
                // Wait for transition?
                setTimeout(function() {
                    if (!menu.classList.contains('visible')) {
                        menu.style.display = 'none';
                    }
                }, 200);
            }
        }
        
        function isMenuOpen() {
            var menu = document.getElementById('custom-menu');
            return menu && menu.style.display !== 'none' && menu.style.display !== '';
        }

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

        function showHighlightMenu(rect, id) {
             var menu = document.getElementById('highlight-menu');
             if (!menu) return;
             
             currentHighlightId = id;
             
             var scrollX = window.scrollX || window.pageXOffset;
             var scrollY = window.scrollY || window.pageYOffset;
             
             menu.style.display = 'grid'; 
             menu.offsetHeight;
             menu.classList.add('visible');
             
             var menuWidth = 165; 
             var menuHeight = 60; 
             
             var top = rect.top - menuHeight - 15 + scrollY;
             var left = rect.left + (rect.width / 2) + scrollX;
             
             // Check bounds
             if (top < scrollY + 40) {
                 top = rect.bottom + 15 + scrollY;
                 menu.classList.add('below');
             } else {
                 menu.classList.remove('below');
             }
             
             if (left - (menuWidth / 2) < 10) left = (menuWidth / 2) + 10;
             if (left + (menuWidth / 2) > window.innerWidth - 10) left = window.innerWidth - 10 - (menuWidth / 2);
 
             menu.style.top = top + 'px';
             menu.style.left = left - (menuWidth / 2) + 'px'; 
        }
        
        function hideHighlightMenu() {
            var menu = document.getElementById('highlight-menu');
             if (menu) {
                 menu.classList.remove('visible');
                 setTimeout(function() {
                     if (!menu.classList.contains('visible')) {
                         menu.style.display = 'none';
                     }
                 }, 100);
             }
             currentHighlightId = null;
        }

        function handleHighlightAction(e, action) {
             e.preventDefault();
             e.stopPropagation();
             
             if (window.flutter_inappwebview && currentHighlightId) {
                 window.flutter_inappwebview.callHandler('onHighlightAction', action, currentHighlightId);
             }
             hideHighlightMenu();
        }

        function applyHighlight(cfi, id) {
            console.log("Applying highlight: " + id);
            try {
                // Parse CFI
                var pathObj = cfi;
                if (typeof cfi === 'string') {
                    if (cfi.startsWith('{')) {
                        pathObj = JSON.parse(cfi);
                    } else {
                        return;
                    }
                }
                
                var startNode = getNodeByPath(pathObj.startPath);
                var endNode = getNodeByPath(pathObj.endPath);
                
                if (!startNode || !endNode) {
                    console.log("Nodes not found for highlight " + id);
                    return;
                }

                var range = document.createRange();
                
                // Set Start
                if (startNode.nodeType === 3) {
                     // Clamp offset
                    var maxStart = startNode.length;
                    var sOffset = pathObj.startOffset;
                    if (sOffset > maxStart) sOffset = maxStart;
                    if (sOffset < 0) sOffset = 0;
                    range.setStart(startNode, sOffset);
                } else {
                    range.setStart(startNode, 0); 
                }
                
                // Set End
                if (endNode.nodeType === 3) {
                     // Clamp offset
                    var maxEnd = endNode.length;
                    var eOffset = pathObj.endOffset;
                    if (eOffset > maxEnd) eOffset = maxEnd;
                    if (eOffset < 0) eOffset = 0;
                    range.setEnd(endNode, eOffset);
                } else {
                    range.setEnd(endNode, 0); 
                }

                // Collect all text nodes in the range
                var textNodes = [];
                var treeWalker = document.createTreeWalker(
                    range.commonAncestorContainer,
                    NodeFilter.SHOW_TEXT,
                    {
                        acceptNode: function(node) {
                            if (range.intersectsNode(node)) {
                                return NodeFilter.FILTER_ACCEPT;
                            }
                            return NodeFilter.FILTER_REJECT;
                        }
                    },
                    false
                );
                
                // If start/end are same, TreeWalker might skip if we aren't careful with root
                // But commonAncestor should cover it. 
                // Special check: if commonAncestor is the text node itself
                if (range.commonAncestorContainer.nodeType === 3) {
                   textNodes.push(range.commonAncestorContainer);
                } else {
                    while (treeWalker.nextNode()) {
                        textNodes.push(treeWalker.currentNode);
                    }
                }

                console.log("Found " + textNodes.length + " text nodes to highlight");

                textNodes.forEach(function(node) {
                    var subRange = document.createRange();
                    subRange.selectNodeContents(node);

                    // Clamp start
                    if (node === startNode && startNode.nodeType === 3) {
                        var maxStart = startNode.length;
                        var sOffset = pathObj.startOffset;
                        if (sOffset > maxStart) sOffset = maxStart;
                        if (sOffset < 0) sOffset = 0;
                        subRange.setStart(node, sOffset);
                    }
                    
                    // Clamp end
                    if (node === endNode && endNode.nodeType === 3) {
                        var maxEnd = endNode.length;
                        var eOffset = pathObj.endOffset;
                        if (eOffset > maxEnd) eOffset = maxEnd;
                        if (eOffset < 0) eOffset = 0;
                        subRange.setEnd(node, eOffset);
                    }
                    
                    // Verify validity (not collapsed)
                    if (!subRange.collapsed && subRange.toString().length > 0) {
                        var span = document.createElement('span');
                        span.className = 'highlight';
                        span.dataset.id = id;
                        span.style.backgroundColor = 'rgba(255, 235, 59, 0.5)';
                        span.style.cursor = 'pointer';
                        
                        span.onclick = function(e) {
                             e.stopPropagation();
                             console.log("Clicked highlight " + id);
                             
                             // Show Menu for Highlight
                             // Use bounding client rect of the span
                             var rect = span.getBoundingClientRect();
                             showHighlightMenu(rect, id);
                        };
                        
                        try {
                            subRange.surroundContents(span);
                        } catch (e) {
                            console.log("Error wrapping node: " + e);
                        }
                    }
                });

            } catch (e) {
                console.log("Error applyHighlight: " + e);
            }
        }
        


      </script>

    ''';

    // Wrap initial content in a chapter container for consistency
    // This allows the JS observer to treat all chapters (initial + appended) uniformly
    String finalHtml =
        '''
      <div id="reader-content">
        <div class="chapter-container" data-chapter-index="$currentChapterIndex">
          $processedContent
        </div>
      </div>
    ''';

    // Ensure standard HTML5 doctype and remove XML namespaces
    if (!finalHtml.toLowerCase().startsWith('<!doctype html>')) {
      finalHtml = '<!DOCTYPE html>\n$finalHtml';
    }
    finalHtml = finalHtml.replaceAll(RegExp(r'''xmlns=["'][^"']*["']'''), '');

    // Inject CSS
    if (finalHtml.contains('</head>')) {
      finalHtml = finalHtml.replaceFirst('</head>', '$css</head>');
    } else if (finalHtml.contains('<head>')) {
      finalHtml = finalHtml.replaceFirst('<head>', '<head>$css');
    } else if (finalHtml.contains('<html>')) {
      finalHtml = finalHtml.replaceFirst('<html>', '<html><head>$css</head>');
    } else {
      finalHtml =
          '''
        <!DOCTYPE html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
          $css
        </head>
        <body class="loading">
          $finalHtml
        </body>
        </html>
      ''';
    }

    // Inject Arrow (Vertical Mode Only)
    if (scrollMode == ReaderScrollMode.vertical) {
      if (finalHtml.contains('</body>')) {
        finalHtml = finalHtml.replaceFirst('</body>', '$arrowHtml</body>');
      } else {
        finalHtml += arrowHtml;
      }
    }

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

      // 1. Prune before startAnchor
      if (startAnchor != null) {
        final startElement = document.getElementById(startAnchor);
        if (startElement != null) {
          _removePrecedingSiblings(startElement, body);
        }
      }

      // 2. Prune after endAnchor
      if (endAnchor != null) {
        final endElement = document.getElementById(endAnchor);
        if (endElement != null) {
          _removeFollowingSiblings(endElement, body);
          // Also remove the endElement itself as it belongs to the next chapter
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
      final siblings = parent.nodes.toList(); // Copy list
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
      final siblings = parent.nodes.toList(); // Copy list
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
