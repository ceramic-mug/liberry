import 'dart:convert';
import 'package:liberry/data/database.dart';
import 'reader_models.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

class ReaderHtmlGenerator {
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
  }) {
    // Prune content if anchors are provided
    String processedContent = content;
    if (startAnchor != null || endAnchor != null) {
      processedContent = _pruneHtml(content, startAnchor, endAnchor);
    }

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

    // Horizontal Mode CSS (Strict Pagination)
    String scrollCss = '';
    if (scrollMode == ReaderScrollMode.horizontal) {
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
          padding: 50px 30px 40px 30px;
          margin: 0 auto;
          max-width: 800px;
          box-sizing: border-box;
          overflow-x: hidden;
        }
        img, video, svg {
          max-width: 100%;
          height: auto;
        }
      ''';
    }

    // Prepare highlights JSON with ID, filtering by current chapter
    final highlightsJson = jsonEncode(
      highlights
          .where((h) {
            if (h.cfi == null) return false;
            try {
              final Map<String, dynamic> cfiMap = jsonDecode(h.cfi!);
              // Check if the highlight belongs to this chapter
              // We use loose equality or int parsing to be safe
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

    // Serialize anchors for JS
    final anchorsJson = jsonEncode(anchors);

    // Arrow HTML
    const arrowHtml = '''
      <div id="next-chapter-btn" onclick="window.flutter_inappwebview.callHandler('onNextChapter')" class="next-chapter-button" style="margin-top: auto; padding: 40px 0; text-align: center; cursor: pointer; opacity: 0.5; transition: opacity 0.3s;">
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
          console.log("JS STARTING - Spine Index: " + currentSpineIndex);
        console.log("JS Font Size: ${fontSize}%");
        console.log("JS Highlights Count: ${highlights.length}");
        console.log("JS Initial Progress: '" + initialProgress + "'");
          color: $textColor !important;
          font-size: ${fontSize}% ;
          font-family: $fontFamily !important;
          line-height: 1.8 !important;
          position: relative;
          -webkit-touch-callout: none !important; /* Attempt to suppress system menu */
          -webkit-user-select: text !important; /* Allow selection */
          user-select: text !important;
          -webkit-text-size-adjust: 100%;
          width: 100%;
          
          /* Flexbox for sticky footer behavior */
          min-height: 100%;
          display: flex;
          flex-direction: column;
        }
        $scrollCss
        /* Suppress on all elements */
        * {
          -webkit-touch-callout: none !important;
        }
        
        /* Force font size inheritance to respect body setting */
        p, div, span, li, blockquote, a {
            font-size: inherit !important;
            line-height: inherit !important;
        }
        
        h1 { font-size: 2em !important; }
        h2 { font-size: 1.5em !important; }
        h3 { font-size: 1.17em !important; }
        h4 { font-size: 1em !important; }
        h5 { font-size: 0.83em !important; }
        h6 { font-size: 0.67em !important; }
          /* Custom Menu */
        #custom-menu {
            position: absolute;
            background-color: #333;
            border-radius: 8px;
            padding: 4px;
            display: none;
            grid-template-columns: 1fr 1fr;
            gap: 1px;
            z-index: 1000;
            box-shadow: 0 4px 12px rgba(0,0,0,0.3);
            width: 240px; /* Wider for "Character" */
            overflow: hidden; /* Ensure rounded corners clip children */
        }
        .menu-item {
            color: white;
            padding: 12px 10px; /* More vertical padding */
            cursor: pointer;
            font-size: 14px;
            display: flex;
            align-items: center;
            justify-content: center; /* Center content */
            background-color: #333;
            transition: background-color 0.2s;
        }
        .menu-item:hover {
            background-color: #444;
        }
        .menu-icon {
            margin-right: 8px;
            display: flex;
            align-items: center;
            width: 20px; /* Fixed width for icon alignment */
            justify-content: center;
        }
        .highlight {
            background-color: ${theme == ReaderTheme.dark ? '#fdd835' : '#ffeb3b'};
            cursor: pointer;
            mix-blend-mode: ${theme == ReaderTheme.dark ? 'difference' : 'multiply'};
            color: ${theme == ReaderTheme.dark ? 'black' : 'inherit'}; /* Ensure text is readable in difference mode */
        }
      </style>
      <script type="text/javascript">
      /* <![CDATA[ */
        // Injected Data
        const currentSpineIndex = $spineIndex;
        const chapterAnchors = $anchorsJson; // [{id: 'p1', chapterIndex: 5}, ...]
        const initialScrollAnchor = ${jsonEncode(scrollToAnchor)};
        const initialProgress = ${jsonEncode(initialProgress)};
        
        window.onerror = function(message, source, lineno, colno, error) {
            console.log("JS ERROR: " + message + " at " + lineno + ":" + colno);
        };

        console.log("JS STARTING - Spine Index: " + currentSpineIndex);

        function getPathTo(element) {
            if (element === document.body) return "";
            if (!element.parentNode) return "";
            var siblings = element.parentNode.childNodes;
            for (var i = 0; i < siblings.length; i++) {
                var sibling = siblings[i];
                if (sibling === element) {
                    var parentPath = getPathTo(element.parentNode);
                    return parentPath === "" ? "" + i : parentPath + "/" + i;
                }
            }
            return null;
        }

        function getNodeByPath(path) {
            if (!path || path === "") return document.body;
            var parts = path.split('/');
            var el = document.body;
            for (var i = 0; i < parts.length; i++) {
                if (parts[i] === "") continue; // Skip empty parts (handles // or leading /)
                var ix = parseInt(parts[i]);
                if (isNaN(ix)) {
                    console.log("Invalid path part: " + parts[i] + " in " + path);
                    continue;
                }
                
                if (ix < el.childNodes.length) {
                    el = el.childNodes[ix];
                } else {
                    console.log("Node not found: " + path + " at step " + i + " (index " + ix + "). Parent has " + el.childNodes.length + " children.");
                    return null;
                }
            }
            return el;
        }

        function restorePath(path) {
            if (!path || path === "") return;
            try {
                var parts = path.split('/').filter(p => p.length > 0);
                var el = document.body;
                for (var i = 0; i < parts.length; i++) {
                    var ix = parseInt(parts[i]);
                    if (ix < el.childNodes.length) {
                        el = el.childNodes[ix];
                    } else {
                        console.log("Path restoration failed at step " + i + ": index " + ix + " out of bounds (" + el.childNodes.length + ")");
                        return;
                    }
                }
                if (el) {
                    // Scroll into view
                    // If it's a text node, we need to scroll its parent or a range
                    if (el.nodeType === 3) { // Text node
                        var range = document.createRange();
                        range.selectNode(el);
                        var rect = range.getBoundingClientRect();
                        // Scroll to the rect
                        // Since we can't call scrollIntoView on a text node or range directly in all browsers easily,
                        // scrolling the parent is a safe bet, or using window.scrollTo
                        if (el.parentNode) {
                             el.parentNode.scrollIntoView({behavior: "auto", block: "center", inline: "center"});
                        }
                    } else if (el.scrollIntoView) {
                        el.scrollIntoView({behavior: "auto", block: "center", inline: "center"});
                    }
                }
            } catch (e) { console.log("Error restoring path: " + e); }
        }

        const icons = {
          highlight: '<svg viewBox="0 0 24 24" width="20" height="20" fill="white"><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/><path d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM5.92 19H5v-.92l9.06-9.06.92.92L5.92 19z"/></svg>',
          assign: '<svg viewBox="0 0 24 24" width="20" height="20" fill="white"><path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/></svg>',
          copy: '<svg viewBox="0 0 24 24" width="20" height="20" fill="white"><path d="M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z"/></svg>',
          share: '<svg viewBox="0 0 24 24" width="20" height="20" fill="white"><path d="M18 16.08c-.76 0-1.44.3-1.96.77L8.91 12.7c.05-.23.09-.46.09-.7s-.04-.47-.09-.7l7.05-4.11c.54.5 1.25.81 2.04.81 1.66 0 3-1.34 3-3s-1.34-3-3-3-3 1.34-3 3c0 .24.04.47.09.7L8.04 9.81C7.5 9.31 6.79 9 6 9c-1.66 0-3 1.34-3 3s1.34 3 3 3c.79 0 1.5-.31 2.04-.81l7.12 4.16c-.05.21-.08.43-.08.65 0 1.61 1.31 2.92 2.92 2.92 1.61 0 2.92-1.31 2.92-2.92s-1.31-2.92-2.92-2.92z"/></svg>'
        };

        // Global state
        let observer;
        
        function init() {
           console.log("Initializing Reader...");
           // Inject Menu
           var menu = document.createElement('div');
           menu.id = 'custom-menu';
           menu.innerHTML = `
             <div class="menu-item" id="btn-highlight">
               <span class="menu-icon">\${icons.highlight}</span>
               Highlight
             </div>
             <div class="menu-item" id="btn-assign">
               <span class="menu-icon">\${icons.assign}</span>
               Character
             </div>
             <div class="menu-item" id="btn-copy">
               <span class="menu-icon">\${icons.copy}</span>
               Copy
              </div>
              <div class="menu-item" id="btn-share">
                <span class="menu-icon">\${icons.share}</span>
                Share
              </div>
            `;
           document.body.appendChild(menu);

           // Bind Events
           document.getElementById('btn-highlight').addEventListener('mousedown', function(e) { handleAction(e, 'highlight'); });
           document.getElementById('btn-assign').addEventListener('mousedown', function(e) { handleAction(e, 'assign'); });
           document.getElementById('btn-copy').addEventListener('mousedown', function(e) { handleAction(e, 'copy'); });
           document.getElementById('btn-share').addEventListener('mousedown', function(e) { handleAction(e, 'share'); });

           function handleAction(e, action) {
               e.preventDefault();
               e.stopPropagation();
               var cfi = getCFI();
               var text = window.getSelection().toString();
               
               if (window.flutter_inappwebview) {
                   window.flutter_inappwebview.callHandler('onMenuAction', action, cfi, text);
               }
               
               // We do NOT apply highlight here immediately. 
               // We wait for Flutter to save it and then call applyHighlight via JS.
               // This prevents race conditions and ensures we have the DB ID.
               
               window.getSelection().removeAllRanges();
               hideMenu();
           }

           // Selection Change
           document.addEventListener('selectionchange', function() {
               var selection = window.getSelection();
               // console.log('Selection change: ' + selection.toString());
               if (selection.rangeCount > 0 && !selection.isCollapsed && selection.toString().trim().length > 0) {
                   var range = selection.getRangeAt(0);
                   var rect = range.getBoundingClientRect();
                   showMenu(rect);
               } else {
                   hideMenu();
               }
           });

           // Initialize Observers
           if (${scrollMode == ReaderScrollMode.vertical}) {
               setupVerticalObservers();
           }
           
           // Scroll to anchor if requested
           if (initialScrollAnchor) {
               setTimeout(function() {
                   var el = document.getElementById(initialScrollAnchor);
                   if (el) {
                       el.scrollIntoView();
                   }
               }, 100);
           } else if (initialProgress && initialProgress !== '0.0' && initialProgress !== '') {
               // Restore logic
               // FIX: Check for slash to identify path even if it doesn't start with one
               if (initialProgress.includes('/') || initialProgress.startsWith('/')) {
                   setTimeout(function() { restorePath(initialProgress); }, 100);
               } else {
                   var pct = parseFloat(initialProgress);
                   if (pct > 0) {
                       if (${scrollMode == ReaderScrollMode.horizontal}) {
                          window.scrollTo(document.body.scrollWidth * pct, 0);
                       } else {
                          window.scrollTo(0, (document.body.scrollHeight - window.innerHeight) * pct);
                       }
                   }
               }
           }
           
           // Highlights
           var highlights = $highlightsJson;
           if (highlights && highlights.length > 0) {
               highlights.forEach(function(h) { applyHighlight(h.cfi, h.id); });
           }
        };
        
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', init);
        } else {
            init();
        }


        function setupVerticalObservers() {
            // 1. Active Chapter Observer (Anchors)
            // We use a scroll listener for more reliable "top of screen" detection
            
            function checkActiveChapter() {
                var triggerLine = window.innerHeight * 0.2;
                var activeAnchor = null;
                
                for (var i = 0; i < chapterAnchors.length; i++) {
                    var a = chapterAnchors[i];
                    if (!a.id) continue;
                    var el = document.getElementById(a.id);
                    if (!el) continue;
                    
                    var rect = el.getBoundingClientRect();
                    
                    if (rect.top < triggerLine) {
                        activeAnchor = a;
                    } else {
                        break;
                    }
                }
                
                if (activeAnchor) {
                    if (window.flutter_inappwebview) {
                        if (window._lastSentChapterIndex !== activeAnchor.chapterIndex) {
                             window._lastSentChapterIndex = activeAnchor.chapterIndex;
                             window.flutter_inappwebview.callHandler('onActiveChapterChanged', activeAnchor.chapterIndex);
                        }
                    }
                }
            }

            function reportReadingLocation() {
                // Find the element at the top of the viewport (with some offset)
                var x = window.innerWidth / 2;
                var y = window.innerHeight * 0.2; // 20% down
                
                var el = document.elementFromPoint(x, y);
                if (!el) return;

                // If we hit a text node's parent (most likely), that's good.
                // If we hit the body, try to find a child.
                if (el === document.body) {
                     // Try a bit lower if we hit body (maybe margin/padding)
                     el = document.elementFromPoint(x, y + 50);
                }
                
                if (el && el !== document.body) {
                    var path = getPathTo(el);
                    if (path) {
                        if (window.flutter_inappwebview) {
                            window.flutter_inappwebview.callHandler('onScrollProgress', path);
                        }
                    }
                }
            }
            
            // Throttle scroll event
            var lastScrollTime = 0;
            window.addEventListener('scroll', function() {
                var now = new Date().getTime();
                if (now - lastScrollTime > 500) { // Check every 500ms (less frequent than before to save resources)
                    lastScrollTime = now;
                    checkActiveChapter();
                    reportReadingLocation();
                }
            });
            
            // Initial check
            setTimeout(function() {
                checkActiveChapter();
                reportReadingLocation();
            }, 500);
        }
        
        function showMenu(rect) {
            var menu = document.getElementById('custom-menu');
            if (!menu) return;
            
            var scrollX = window.scrollX || window.pageXOffset;
            var scrollY = window.scrollY || window.pageYOffset;
            
            menu.style.display = 'grid';
            
            // Calculate position
            var menuWidth = menu.offsetWidth;
            var menuHeight = menu.offsetHeight;
            
            var top = rect.top - menuHeight - 15 + scrollY;
            var left = rect.left + (rect.width / 2) + scrollX;
            
            // Check bounds
            if (top < scrollY + 10) {
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
            if (menu) menu.style.display = 'none';
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
                            window.flutter_inappwebview.callHandler('onHighlightClick', id);
                        };
                    }
                    range.surroundContents(span);
                } else {
                    console.log("Could not find nodes for highlight: " + id + " Start: " + cfi.startPath + " End: " + cfi.endPath);
                }
            } catch(e) { console.log("Error applying highlight: " + e); }
        }

        function removeHighlight(id) {
            var span = document.getElementById('highlight-' + id);
            if (span) {
                var parent = span.parentNode;
                while (span.firstChild) parent.insertBefore(span.firstChild, span);
                parent.removeChild(span);
            }
        }
        

        function setTheme(textColor) {
            // Background is handled by Flutter Scaffold transparency
            document.body.style.setProperty('color', textColor, 'important');
        }
        
        function setFontFamily(family) {
            document.body.style.setProperty('font-family', family, 'important');
        }

        // Custom Tap Detection
        let touchStartTime = 0;
        let touchStartX = 0;
        let touchStartY = 0;
        let isTouch = false;
        
        document.addEventListener('touchstart', function(e) {
            isTouch = true;
            touchStartTime = new Date().getTime();
            touchStartX = e.changedTouches[0].clientX;
            touchStartY = e.changedTouches[0].clientY;
        }, {passive: true});
        
        document.addEventListener('touchend', function(e) {
            let touchEndTime = new Date().getTime();
            let touchEndX = e.changedTouches[0].clientX;
            let touchEndY = e.changedTouches[0].clientY;
            
            let diffX = Math.abs(touchEndX - touchStartX);
            let diffY = Math.abs(touchEndY - touchStartY);
            let timeDiff = touchEndTime - touchStartTime;
            
            // Tap criteria: short duration, little movement
            if (timeDiff < 300 && diffX < 10 && diffY < 10) {
                // Check if we tapped a link or the menu
                if (e.target.tagName === 'A' || e.target.closest('#custom-menu') || e.target.closest('.next-chapter-button')) {
                    return;
                }
                
                // Check if text is selected
                if (window.getSelection().toString().length > 0) {
                    return;
                }
                
                // Trigger toggle
                if (window.flutter_inappwebview) {
                   window.flutter_inappwebview.callHandler('onTap');
                }
            }
        }, {passive: true});

        // Fallback click for desktop or if touch fails
        document.addEventListener('click', function(e) {
            if (!isTouch) {
                if (e.target.tagName === 'A' || e.target.closest('#custom-menu') || e.target.closest('.next-chapter-button')) return;
                if (window.getSelection().toString().length > 0) return;
                
                if (window.flutter_inappwebview) {
                   window.flutter_inappwebview.callHandler('onTap');
                }
            }
            // Reset isTouch after a delay to allow mixed usage? 
            // Usually not needed for mobile-only, but good for hybrid.
            setTimeout(() => isTouch = false, 500);
        });
        
        // Debug selection
        document.addEventListener('selectionchange', function() {
            var selection = window.getSelection();
            if (selection.rangeCount > 0 && !selection.isCollapsed && selection.toString().trim().length > 0) {
                var range = selection.getRangeAt(0);
                var rect = range.getBoundingClientRect();
                showMenu(rect);
            } else {
                hideMenu();
            }
        });

      </script>

    ''';

    String finalHtml = processedContent;

    // Inject CSS
    if (finalHtml.contains('<head>')) {
      finalHtml = finalHtml.replaceFirst('<head>', '<head>$css');
    } else if (finalHtml.contains('<html>')) {
      finalHtml = finalHtml.replaceFirst('<html>', '<html><head>$css</head>');
    } else {
      // Should not happen with _pruneHtml returning outerHtml, but fallback:
      finalHtml =
          '''
        <!DOCTYPE html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
          $css
        </head>
        <body>
          $processedContent
        </body>
        </html>
      ''';
    }

    // Inject Arrow
    if (finalHtml.contains('</body>')) {
      finalHtml = finalHtml.replaceFirst('</body>', '$arrowHtml</body>');
    } else {
      finalHtml += arrowHtml;
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
