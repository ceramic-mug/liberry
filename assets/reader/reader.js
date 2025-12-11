/* ---------------- GLOBAL STATE ---------------- */
// These are expected to be injected in a script tag before this file loads:
// window.currentSpineIndex
// window.chapterAnchors
// window.initialScrollAnchor
// window.initialProgress
// window.highlightData

window.onerror = function (message, source, lineno, colno, error) {
    console.log("JS ERROR: " + message + " at " + lineno + ":" + colno);
};

console.log("JS STARTING - Spine Index: " + window.currentSpineIndex);
var interactionLocked = false;
var inputBlocked = false;

window.setInteractionLocked = function (locked) {
    interactionLocked = locked;
    console.log("Interaction Locked: " + locked);
}

window.setInputBlocked = function (blocked) {
    inputBlocked = blocked;
    console.log("Input Blocked: " + blocked);
}

window.setTheme = function (textColor, bgColor) {
    console.log("Setting Theme: Text=" + textColor + " Bg=" + bgColor);
    document.body.style.setProperty('--text-color', textColor); // Update CSS var
    if (bgColor) {
        document.body.style.setProperty('--bg-color', bgColor);
        document.documentElement.style.setProperty('background-color', bgColor, 'important');
    }
};

window.setFontFamily = function (family) {
    console.log("Setting Font Family: " + family);
    document.body.style.setProperty('--font-family', family);
};

function isHorizontal() {
    return document.body.classList.contains('mode-horizontal');
}

/* ---------------- POLYFILLS & UTILS ---------------- */
var oldLog = console.log;
console.log = function (message) {
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
    var idMatch = path.match(/^\/\/\*\[@id="([^"]+)"\]/);
    if (idMatch && idMatch[1]) {
        var id = idMatch[1];
        var foundEl = document.getElementById(id);
        if (foundEl) {
            el = foundEl;
            var suffix = path.substring(idMatch[0].length);
            parts = suffix.split('/').filter(function (p) { return p !== ""; });
        } else {
            console.log("Element with ID " + id + " not found, falling back to body traversal.");
            return null;
        }
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

/* ---------------- ICONS ---------------- */
const icons = {
    highlight: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04c.39-.39.39-1.02 0-1.41l-2.34-2.34c-.39-.39-1.02-.39-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z"/></svg>',
    assign: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/></svg>',
    copy: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z"/></svg>',
    delete: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z"/></svg>',
    note: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M14 2H6c-1.1 0-1.99.9-1.99 2L4 20c0 1.1.89 2 1.99 2H18c1.1 0 2-.9 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z"/></svg>'
};

/* ---------------- INITIALIZATION ---------------- */
function init() {
    console.log("Initializing Reader...");
    // injectMenus(); // Removed
    setupHighlights();
    setupEvents();

    // Initialize Observers based on Mode
    try {
        if (isHorizontal()) {
            setupHorizontalObservers();
        } else {
            setupVerticalObservers();
        }
        handleRestore();
    } catch (e) {
        console.log("Error in observer/restore setup: " + e);
        document.body.classList.remove('loading');
        window.isRestoring = false;
    }
}

function injectMenus() {
    // Main Menu
    var menu = document.createElement('div');
    menu.id = 'custom-menu';
    menu.innerHTML = `
      <div class="menu-item" id="btn-highlight" style="grid-column: span 2;">
        ${icons.highlight}
      </div>
      <div class="menu-item" id="btn-assign">
        ${icons.assign}
      </div>
      <div class="menu-item" id="btn-copy">
        ${icons.copy}
      </div>
     `;
    document.body.appendChild(menu);

    // Highlight Context Menu
    var hlMenu = document.createElement('div');
    hlMenu.id = 'highlight-menu';
    hlMenu.innerHTML = `
      <div class="menu-item" id="btn-hl-assign">
        ${icons.assign}
      </div>
      <div class="menu-item" id="btn-hl-note">
        ${icons.note}
      </div>
      <div class="menu-item" id="btn-delete">
        ${icons.delete}
      </div>
    `;
    // Styles handled in CSS
    // Specific Grid config for HL Menu in CSS
    // Specific Grid config for Main Menu in CSS
    document.body.appendChild(hlMenu);
}

function setupHighlights() {
    console.log("Restoring highlights...");
    try {
        var highlights = window.highlightData || [];
        if (highlights.length > 0) {
            setTimeout(function () {
                try {
                    highlights.forEach(function (h) {
                        applyHighlight(h.cfi, h.id);
                    });
                    console.log("Highlights restored.");
                } catch (e) {
                    console.log("Error inside highlight loop: " + e);
                }
            }, 100);
        }
    } catch (e) {
        console.log("Error setting up highlights: " + e);
    }
}

function setupEvents() {
    // Selection Change
    document.addEventListener('selectionchange', function () {
        // Debounce slightly
        if (window.selectionTimer) clearTimeout(window.selectionTimer);
        window.selectionTimer = setTimeout(reportSelection, 150);
    });

    // Interaction Check for Taps
    // (Vertical Click logic and Horizontal Tap logic reuse checking logic)
}

/* ---------------- ACTION HANDLERS ---------------- */
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



/* ---------------- RESTORE LOGIC ---------------- */
var isRestoring = true;

function handleRestore() {
    var restoreDelay = 500;

    if (window.initialProgress === 'END') {
        console.log("Restoring to END");
        setTimeout(function () {
            if (isHorizontal()) {
                var container = document.getElementById('reader-content');
                if (container) container.scrollLeft = container.scrollWidth;
            } else {
                window.scrollTo(0, document.body.scrollHeight);
            }
            document.body.classList.remove('loading');
            isRestoring = false;
        }, restoreDelay);

    } else if (window.initialProgress && window.initialProgress !== '') {
        // Restore logic
        if (window.initialProgress.includes('/') || window.initialProgress.startsWith('/')) {
            console.log("Restoring CFI Path: " + window.initialProgress);
            setTimeout(function () {
                restorePath(window.initialProgress);
                document.body.classList.remove('loading');
                isRestoring = false;
            }, restoreDelay);
        } else {
            // Legacy Percent
            var pct = parseFloat(window.initialProgress);
            if (pct > 0) {
                setTimeout(function () {
                    if (isHorizontal()) {
                        var container = document.getElementById('reader-content');
                        if (container) container.scrollLeft = container.scrollWidth * pct;
                    } else {
                        window.scrollTo(0, (document.body.scrollHeight - window.innerHeight) * pct);
                    }
                    document.body.classList.remove('loading');
                    isRestoring = false;
                }, restoreDelay);
            } else {
                document.body.classList.remove('loading');
                isRestoring = false;
            }
        }
    } else if (window.initialScrollAnchor) {
        setTimeout(function () {
            var el = document.getElementById(window.initialScrollAnchor);
            if (el) {
                el.scrollIntoView();
            }
            document.body.classList.remove('loading');
            isRestoring = false;
        }, restoreDelay);
    } else {
        // No restore needed
        document.body.classList.remove('loading');
        isRestoring = false;
    }
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
            // Logic to calculate Rect...
            var rect;

            if (isPrecise && el.nodeType === 3) {
                try {
                    var range = document.createRange();
                    if (offset > el.textContent.length) offset = el.textContent.length;
                    range.setStart(el, offset);
                    range.setEnd(el, offset);

                    var rects = range.getClientRects();
                    if (rects.length > 0) rect = rects[0];
                    else rect = range.getBoundingClientRect();
                } catch (e) {
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
            }

            if (isHorizontal()) {
                var container = document.getElementById('reader-content');
                var currentScroll = container ? container.scrollLeft : window.scrollX;
                var visualLeft = rect.left + currentScroll;
                var pageIndex = Math.floor(visualLeft / window.innerWidth);
                var targetScroll = pageIndex * window.innerWidth;

                if (container) container.scrollLeft = targetScroll;
                else window.scrollTo(targetScroll, 0);
            } else {
                if (rect) {
                    var targetY = window.scrollY + rect.top - 60;
                    window.scrollTo(0, targetY);
                } else {
                    el.scrollIntoView(true);
                }
            }
        }
    } catch (e) { console.log("Error restoring path: " + e); }
}

/* ---------------- OBSERVERS ---------------- */
function setupVerticalObservers() {
    var lastScrollTime = 0;
    window.addEventListener('scroll', function () {
        var now = new Date().getTime();
        if (now - lastScrollTime > 200) {
            lastScrollTime = now;
            var path = getReadingLocation();
            if (path && window.flutter_inappwebview && !isRestoring) {
                window.flutter_inappwebview.callHandler('onScrollProgress', path);
            }
        }
    });

    document.addEventListener('click', function (e) {
        if (inputBlocked) { e.preventDefault(); e.stopPropagation(); return; }
        if (isInteractive(e.target)) return;

        var y = e.clientY;
        if (y < 80 || y > window.innerHeight - 80) return;

        if (window.flutter_inappwebview) {
            window.flutter_inappwebview.callHandler('onTap');
        }
    });

    window.getCurrentLocationPath = getReadingLocation;
}

function getReadingLocation() {
    // Precise vertical location
    var x = 60;
    var y = 60;

    if (document.caretPositionFromPoint) {
        var pos = document.caretPositionFromPoint(x, y);
        if (pos && pos.offsetNode) {
            return JSON.stringify({ type: 'precise', path: getPathTo(pos.offsetNode), offset: pos.offset });
        }
    }
    else if (document.caretRangeFromPoint) {
        var range = document.caretRangeFromPoint(x, y);
        if (range && range.startContainer) {
            return JSON.stringify({ type: 'precise', path: getPathTo(range.startContainer), offset: range.startOffset });
        }
    }

    // Fallback
    var el = document.elementFromPoint(window.innerWidth / 2, window.innerHeight * 0.3);
    if (el && el !== document.body) return getPathTo(el);

    return null;
}

function setupHorizontalObservers() {
    // Horizontal Observer setup
    console.log("Setting up Horizontal Observers...");

    // Force reset vertical scroll to prevent displacement
    window.scrollTo(0, 0);

    var container = document.getElementById('reader-content');
    if (!container) return;

    // [Re-implementation of Horizontal Logic from original file]
    // Consolidating variables
    var touchStartX = 0, touchStartY = 0, touchStartTime = 0, startScrollLeft = 0;
    var isDragging = false, isScrolling = false;
    var lastHandledTapTime = 0;
    const width = window.innerWidth;

    // Key Nav
    document.addEventListener('keydown', function (e) {
        if (interactionLocked || inputBlocked) return;
        if (e.key === 'ArrowRight') {
            e.preventDefault();
            snapToPage(Math.round(container.scrollLeft / width) + 1);
        } else if (e.key === 'ArrowLeft') {
            e.preventDefault();
            snapToPage(Math.round(container.scrollLeft / width) - 1);
        }
    });

    // Click
    document.addEventListener('click', function (e) {
        if (inputBlocked) return;
        if (new Date().getTime() - lastHandledTapTime < 500) return;
        if (isInteractive(e.target)) return;
        handleTap(e.clientX);
    });

    // Touch Logic
    document.addEventListener('touchstart', function (e) {
        if (inputBlocked) return;
        if (e.touches.length !== 1) return;
        touchStartX = e.touches[0].clientX;
        touchStartY = e.touches[0].clientY;
        touchStartTime = new Date().getTime();
        startScrollLeft = container.scrollLeft;
        isDragging = true;
        isScrolling = false;
    }, { passive: false });

    document.addEventListener('touchmove', function (e) {
        var selection = window.getSelection();
        if (selection && !selection.isCollapsed) { isDragging = false; return; }
        if (inputBlocked) { e.preventDefault(); return; }
        if (interactionLocked) { e.preventDefault(); return; }
        if (!isDragging) return;

        var x = e.touches[0].clientX;
        var y = e.touches[0].clientY;
        var diffX = touchStartX - x;
        var diffY = touchStartY - y;

        if (!isScrolling) {
            if (Math.abs(diffY) > Math.abs(diffX)) {
                isScrolling = true;
                isDragging = false;
                return;
            }
        }
        if (isScrolling) return;

        e.preventDefault();
        container.scrollLeft = startScrollLeft + diffX;
    }, { passive: false });

    document.addEventListener('touchend', function (e) {
        if (inputBlocked) { e.preventDefault(); return; }
        if (!isDragging) return;
        isDragging = false;

        var touchEndX = e.changedTouches[0].clientX;
        var diffX = touchStartX - touchEndX;
        var timeDiff = new Date().getTime() - touchStartTime;

        if (timeDiff < 300 && Math.abs(diffX) < 10 && Math.abs(touchStartY - e.changedTouches[0].clientY) < 10) {
            if (isInteractive(e.target)) return;
            if (interactionLocked) {
                // Navbar zone check
                var y = e.changedTouches[0].clientY;
                if (y < 80 || y > window.innerHeight - 80) return;
                e.preventDefault();
                lastHandledTapTime = new Date().getTime();
                if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler('onTap');
                return;
            }
            lastHandledTapTime = new Date().getTime();
            handleTap(touchStartX);
            return;
        }

        if (interactionLocked) return;
        var startPage = Math.round(startScrollLeft / width);
        var targetPage = startPage;
        if (Math.abs(diffX) > 50) {
            targetPage = (diffX > 0) ? startPage + 1 : startPage - 1;
        }
        snapToPage(targetPage);
    });

    function snapToPage(pageIndex) {
        var scrollW = container.scrollWidth;
        var maxPage = Math.ceil(scrollW / width) - 1;

        if (pageIndex < 0) {
            container.scrollLeft = 0;
            if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler('onPrevChapter');
            return;
        }
        if (pageIndex > maxPage) {
            container.scrollLeft = maxPage * width;
            if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler('onNextChapter');
            return;
        }

        // CSS Smooth scroll doesn't always work perfectly with programmatic scrollLeft in loop
        // Standard assignment is usually better here unless utilizing scrollIntoView
        container.scrollTo({ left: pageIndex * width, behavior: 'smooth' });
        setTimeout(reportHorizontalLocation, 300);
    }

    function handleTap(x) {
        var p = x / window.innerWidth;
        if (p < 0.2) snapToPage(Math.round(container.scrollLeft / width) - 1);
        else if (p > 0.8) snapToPage(Math.round(container.scrollLeft / width) + 1);
        else if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler('onTap');
    }

    function reportHorizontalLocation() {
        var path = getHorizontalLocation();
        if (path && window.flutter_inappwebview) {
            window.flutter_inappwebview.callHandler('onScrollProgress', path);
        }
    }

    function getHorizontalLocation() {
        // Precise Horizontal Location
        // We probe a bit inside the page to avoid margin issues
        var xScreen = 60; // Just past the left margin usually
        var yScreen = 80; // Down from top

        if (document.caretPositionFromPoint) {
            var pos = document.caretPositionFromPoint(xScreen, yScreen);
            if (pos && pos.offsetNode) {
                return JSON.stringify({ type: 'precise', path: getPathTo(pos.offsetNode), offset: pos.offset });
            }
        } else if (document.caretRangeFromPoint) {
            var range = document.caretRangeFromPoint(xScreen, yScreen);
            if (range && range.startContainer) {
                return JSON.stringify({ type: 'precise', path: getPathTo(range.startContainer), offset: range.startOffset });
            }
        }

        // Fallback to element lookup
        var el = document.elementFromPoint(xScreen, yScreen);
        if (el && el !== document.body) return getPathTo(el);

        return null;
    }

    window.getCurrentLocationPath = getHorizontalLocation;
}

/* ---------------- MENU & INTERACTION UTILS ---------------- */
var currentHighlightId = null;

function reportSelection() {
    var selection = window.getSelection();
    if (selection.rangeCount > 0 && !selection.isCollapsed && selection.toString().trim().length > 0) {
        var range = selection.getRangeAt(0);
        var rect = range.getBoundingClientRect();
        var cfi = getCFI();
        var text = selection.toString();

        if (window.flutter_inappwebview) {
            window.flutter_inappwebview.callHandler('onSelectionChanged',
                rect.left, rect.top, rect.width, rect.height, text, cfi
            );
        }
    } else {
        if (window.flutter_inappwebview) {
            if (!window.ignoreSelectionClear) {
                window.flutter_inappwebview.callHandler('onSelectionCleared');
            }
        }
    }
}

function isInteractive(target) {
    if (!target) return false;
    if (target.closest('.highlight') ||
        target.closest('a') ||
        target.closest('button')) return true;
    return false;
}

function applyHighlight(cfi, id) {
    try {
        var pathObj = cfi;
        if (typeof cfi === 'string' && cfi.startsWith('{')) pathObj = JSON.parse(cfi);

        var startNode = getNodeByPath(pathObj.startPath);
        var endNode = getNodeByPath(pathObj.endPath);
        if (!startNode || !endNode) return;

        var range = document.createRange();

        // Start
        if (startNode.nodeType === 3) {
            var sOffset = Math.min(Math.max(0, pathObj.startOffset), startNode.length);
            range.setStart(startNode, sOffset);
        } else {
            range.setStart(startNode, 0);
        }

        // End
        if (endNode.nodeType === 3) {
            var eOffset = Math.min(Math.max(0, pathObj.endOffset), endNode.length);
            range.setEnd(endNode, eOffset);
        } else {
            range.setEnd(endNode, 0);
        }

        // Walk
        var textNodes = [];
        var treeWalker = document.createTreeWalker(range.commonAncestorContainer, NodeFilter.SHOW_TEXT, {
            acceptNode: function (node) {
                return range.intersectsNode(node) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
            }
        }, false);

        if (range.commonAncestorContainer.nodeType === 3) textNodes.push(range.commonAncestorContainer);
        else {
            while (treeWalker.nextNode()) textNodes.push(treeWalker.currentNode);
        }

        textNodes.forEach(function (node) {
            var subRange = document.createRange();
            subRange.selectNodeContents(node);

            if (node === startNode && startNode.nodeType === 3) subRange.setStart(node, Math.min(Math.max(0, pathObj.startOffset), node.length));
            if (node === endNode && endNode.nodeType === 3) subRange.setEnd(node, Math.min(Math.max(0, pathObj.endOffset), node.length));

            if (!subRange.collapsed && subRange.toString().length > 0) {
                var span = document.createElement('span');
                span.className = 'highlight';
                span.dataset.id = id;
                span.onclick = function (e) {
                    e.stopPropagation();

                    // Prevent immediate clearing by selectionchange
                    window.ignoreSelectionClear = true;
                    setTimeout(function () { window.ignoreSelectionClear = false; }, 500);

                    // Report highlight click to Flutter
                    if (window.flutter_inappwebview) {
                        var rect = span.getBoundingClientRect();
                        console.log("JS Highlight Click: " + id + " Rect: " + rect.left + "," + rect.top + " " + rect.width + "x" + rect.height);
                        window.flutter_inappwebview.callHandler('onHighlightClicked',
                            id, rect.left, rect.top, rect.width, rect.height
                        );
                    }
                };
                try { subRange.surroundContents(span); } catch (e) { }
            }
        });
    } catch (e) { console.log("Error applyHighlight: " + e); }
}

// Bootstrap
if (document.readyState === 'loading') {
    document.addEventListener("DOMContentLoaded", init);
} else {
    init();
}
