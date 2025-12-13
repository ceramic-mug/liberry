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

function fixColumnLayout() {
    // 1. Remove existing spacer to get clean measurement
    var existingSpacer = document.getElementById('column-spacer');
    if (existingSpacer) {
        existingSpacer.parentNode.removeChild(existingSpacer);
    }

    // 2. Check Prerequisites
    // Must be Horizontal + Two-Column + Landscape
    if (!isHorizontal()) return;
    if (!document.body.classList.contains('two-column-enabled')) return;

    // Check orientation (Landscape)
    var w = window.innerWidth;
    var h = window.innerHeight;
    if (h >= w) return;

    var container = document.getElementById('reader-content');
    if (!container) return;

    // 3. Measure
    var scrollW = container.scrollWidth;
    var clientW = container.clientWidth;

    if (clientW === 0) return;

    var remainder = scrollW % clientW;

    // We expect remainder to be close to 0 (full pages)
    // If remainder is significant (e.g. > 50px), it means we have a partial page (odd column)
    if (remainder > 50 && remainder < (clientW - 10)) {
        console.log("Fixing Column Layout: Odd columns detected (Remainder: " + remainder + ")");
        var spacer = document.createElement('div');
        spacer.id = 'column-spacer';
        spacer.style.breakBefore = 'column';
        spacer.style.width = '1px';
        spacer.style.height = '1px';
        spacer.style.visibility = 'hidden';
        container.appendChild(spacer);
    }
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
            fixColumnLayout();
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
    // const width = window.innerWidth; // Removed static width

    // Key Nav
    document.addEventListener('keydown', function (e) {
        if (interactionLocked || inputBlocked) return;
        var w = window.innerWidth;
        if (e.key === 'ArrowRight') {
            e.preventDefault();
            snapToPage(Math.round(container.scrollLeft / w) + 1);
        } else if (e.key === 'ArrowLeft') {
            e.preventDefault();
            snapToPage(Math.round(container.scrollLeft / w) - 1);
        }
    });

    // Resize Listener
    var resizeTimer;
    window.addEventListener('resize', function () {
        // Debounce
        if (resizeTimer) clearTimeout(resizeTimer);

        // Capture location if not already restoring
        if (!window.isRestoring) {
            // We want to capture where we were *before* the chaotic resize happened, 
            // but 'resize' fires often. 
            // Ideally we find the element currently on screen and scroll to it after.
            // Let's just rely on getting the location *now* or finding the element that WAS at the top-left.
        }

        resizeTimer = setTimeout(function () {
            console.log("Resize finished. Restoring location...");
            fixColumnLayout();

            // Re-snap or restore.
            // Since column width changed, scrollLeft is likely invalid. 
            // We need to re-find our place.
            // Best bet: use the location we (hopefully) tracked or just re-read current position?
            // Actually, if we just resize, the content flows. 
            // We should grab a precise location *before* we do anything else, or better:
            // Continually track 'current top-left element' in a var?

            // Simple approach: grab location now (might be off if flow changed) and restore it.
            // OR: relying on the fact that we can get a location from the center of screen.

            var loc = getHorizontalLocation();
            if (loc) {
                try {
                    var jsonObj = JSON.parse(loc);
                    // restorePath handles the logic of finding that element and scrolling to it
                    restorePath(loc);
                } catch (e) {
                    console.log("Error restoring after resize: " + e);
                }
            } else {
                // Fallback: update scroll
                snapToPage(Math.round(container.scrollLeft / window.innerWidth));
            }
        }, 200);
    });


    // Prevent Native Context Menu (Keep selection, but hide the bar so we can show ours)
    document.addEventListener('contextmenu', function (e) {
        e.preventDefault();
    });

    // Click
    document.addEventListener('click', function (e) {
        if (inputBlocked) return;
        if (new Date().getTime() - lastHandledTapTime < 500) return;
        if (window.justClearedSelection) {
            console.log("Ignored click because selection was just cleared");
            window.justClearedSelection = false;
            return;
        }
        if (isInteractive(e.target)) return;
        handleTap(e.clientX);
    });


    // Touch Logic
    var TAP_TOLERANCE = 15;
    var LONG_PRESS_DELAY = 250;
    var longPressTimer;
    var isLongPress = false;

    document.addEventListener('touchstart', function (e) {
        if (inputBlocked) return;
        if (e.touches.length !== 1) return;

        touchStartX = e.touches[0].clientX;
        touchStartY = e.touches[0].clientY;
        touchStartTime = new Date().getTime();
        startScrollLeft = container.scrollLeft;
        isDragging = true;
        isScrolling = false;
        isLongPress = false;

        // Long Press Detection for Text Selection
        if (longPressTimer) clearTimeout(longPressTimer);
        longPressTimer = setTimeout(function () {
            // If we haven't moved significantly, assume User wants to Select Text
            if (isDragging && !isScrolling) {
                console.log("Long Press detected - Releasing control to Native");
                isLongPress = true;
                isDragging = false; // Stop our drag logic
            }
        }, LONG_PRESS_DELAY);

    }, { passive: false });

    document.addEventListener('touchmove', function (e) {
        // If Long Press is active, let native behavior happen (selection drag)
        if (isLongPress) return;

        // If a selection exists, also let native behavior happen (refining selection)
        var selection = window.getSelection();
        if (selection && !selection.isCollapsed) {
            isDragging = false;
            if (longPressTimer) clearTimeout(longPressTimer);
            return;
        }

        if (inputBlocked || interactionLocked) { e.preventDefault(); return; }
        if (!isDragging) return;
        if (isScrolling) return;

        var x = e.touches[0].clientX;
        var y = e.touches[0].clientY;
        var diffX = touchStartX - x;
        var diffY = touchStartY - y;

        // Check for threshold before taking action
        if (Math.abs(diffX) < TAP_TOLERANCE && Math.abs(diffY) < TAP_TOLERANCE) {
            return; // Too small
        }

        // Movement detected -> Cancel Long Press Timer
        if (longPressTimer) clearTimeout(longPressTimer);

        // Significant movement detected. Determine axis.
        if (Math.abs(diffY) > Math.abs(diffX)) {
            isScrolling = true; // treat as vertical/other
            isDragging = false;
            return;
        }

        // Horizontal Drag Confirmed
        e.preventDefault();
        container.scrollLeft = startScrollLeft + diffX;
    }, { passive: false });

    document.addEventListener('touchend', function (e) {
        if (longPressTimer) clearTimeout(longPressTimer);
        if (isLongPress) {
            isLongPress = false;
            return; // Native handled it
        }

        if (inputBlocked) { e.preventDefault(); return; }
        if (!isDragging) return;
        isDragging = false;

        var touchEndX = e.changedTouches[0].clientX;
        var diffX = touchStartX - touchEndX;
        var timeDiff = new Date().getTime() - touchStartTime;

        // Check for Tap
        if (timeDiff < 300 && Math.abs(diffX) < TAP_TOLERANCE && Math.abs(touchStartY - e.changedTouches[0].clientY) < TAP_TOLERANCE) {
            var target = e.target;

            // 0. Check for Active Selection (Unselect tap)
            var selection = window.getSelection();
            if (selection && !selection.isCollapsed) {
                // Tap while selection makes it clear.
                // We MUST allow default for the browser to clear it.
                // We ALSO must prevent 'snapToPage' from firing on the subsequent click.
                console.log("Tap with selection active - allowing default to clear");
                window.justClearedSelection = true;
                setTimeout(function () { window.justClearedSelection = false; }, 200);
                // Do not prevent default.
                return;
            }

            // 1. Check for Highlight Tap (Centralized)
            // Use parentNode loop or closest (with text node safety)
            var hl = getClosestHighlight(target);
            if (hl) {
                e.preventDefault();
                e.stopPropagation(); // Stop ghost clicks
                handleHighlightClick(hl);
                return;
            }

            // 2. Check for other Interactive Elements
            if (isInteractive(target)) return; // Let bubble to click

            // 3. Navbar / Zones
            if (interactionLocked) {
                var y = e.changedTouches[0].clientY;
                if (y < 80 || y > window.innerHeight - 80) return; // Navbar click
                e.preventDefault();
                lastHandledTapTime = new Date().getTime();
                if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler('onTap');
                return;
            }

            // 4. Page Turn
            e.preventDefault();
            lastHandledTapTime = new Date().getTime();
            handleTap(touchStartX);
            return;
        }

        // Drag End (Snap)
        if (interactionLocked || isScrolling) return;

        var currentW = window.innerWidth;
        var startPage = Math.round(startScrollLeft / currentW);
        var targetPage = startPage;
        if (Math.abs(diffX) > 50) {
            targetPage = (diffX > 0) ? startPage + 1 : startPage - 1;
        }
        snapToPage(targetPage);
    });

    setTimeout(reportHorizontalLocation, 300);
}

function getClosestHighlight(node) {
    if (!node) return null;
    if (node.nodeType === 3) node = node.parentNode; // Handle Text Node
    if (!node || !node.closest) return null;
    return node.closest('.highlight');
}

function handleHighlightClick(span) {
    var id = span.dataset.id;
    if (!id) return;

    // Prevent immediate clearing by selectionchange
    window.ignoreSelectionClear = true;
    setTimeout(function () { window.ignoreSelectionClear = false; }, 500);

    // Report highlight click to Flutter
    if (window.flutter_inappwebview) {
        var rect = span.getBoundingClientRect();
        console.log("JS Highlight Tap: " + id);
        window.flutter_inappwebview.callHandler('onHighlightClicked',
            id, rect.left, rect.top, rect.width, rect.height
        );
    }
}

function handleTap(x) {
    var container = document.getElementById('reader-content');
    if (!container) return;

    var w = container.clientWidth;
    var p = x / w;
    if (p < 0.2) snapToPage(Math.round(container.scrollLeft / w) - 1);
    else if (p > 0.8) snapToPage(Math.round(container.scrollLeft / w) + 1);
    else if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler('onTap');
}


function snapToPage(pageIndex) {
    var container = document.getElementById('reader-content');
    if (!container) return;

    var w = container.clientWidth;
    var scrollW = container.scrollWidth;

    var remainder = scrollW % w;
    var pages = Math.floor(scrollW / w);
    if (remainder > 10) {
        pages += 1;
    }
    var maxPage = pages - 1;

    console.log("DEBUG: snapToPage request: " + pageIndex + ". Max: " + maxPage);

    if (pageIndex < 0) {
        if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler('onPrevChapter');
        return;
    }

    if (pageIndex > maxPage) {
        console.log("DEBUG: Triggering Next Chapter");
        if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler('onNextChapter');
        return;
    }

    container.scrollTo({
        left: pageIndex * w,
        behavior: 'smooth'
    });
    setTimeout(reportHorizontalLocation, 300);
}

// Expose for Flutter to call after changing settings
window.snapToPage = snapToPage;

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
    // Fix for Text Nodes which don't have .closest()
    if (target.nodeType === 3) target = target.parentNode;

    if (target && target.closest && (
        target.closest('.highlight') ||
        target.closest('a') ||
        target.closest('button'))) return true;
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
                // No onclick here anymore. Handled centrally in touchend.
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
