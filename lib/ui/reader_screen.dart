import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liberry/data/database.dart';
import 'package:liberry/data/book_repository.dart';
import 'package:liberry/data/reader_settings_repository.dart';
import 'package:liberry/providers.dart';
import 'package:liberry/services/epub_service.dart';
import 'package:liberry/ui/reader/reader_html_generator.dart';
import 'package:liberry/ui/reader/reader_models.dart';
import 'package:liberry/ui/reader/reader_settings_modal.dart';
import 'package:epubx/epubx.dart' as epub;
import 'package:share_plus/share_plus.dart';

import 'package:liberry/ui/reader/reader_drawer.dart';
import 'package:liberry/ui/reader/reader_navigation_bar.dart';
import 'package:liberry/ui/reader/reader_top_bar.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  final Book book;

  const ReaderScreen({super.key, required this.book});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  InAppWebViewController? _webViewController;

  // State
  bool _isLoading = true;
  bool _showControls = false;
  List<epub.EpubChapterRef> _chapters = [];
  List<List<epub.EpubChapterRef>> _spineGroups = [];
  int _currentChapterIndex = 0;
  String _currentProgressCfi = '';

  // Settings
  ReaderTheme _theme = ReaderTheme.light;
  ReaderScrollMode _scrollMode = ReaderScrollMode.vertical;
  double _fontSize = 100.0;
  String _fontFamily = 'Georgia';

  // Services
  late EpubService _epubService;

  bool _isGutenberg = false;

  @override
  void initState() {
    super.initState();
    _epubService = ref.read(epubServiceProvider);
    _loadBook();
  }

  Future<void> _loadBook() async {
    try {
      final settingsRepo = ref.read(readerSettingsRepositoryProvider);
      final bookRepo = ref.read(bookRepositoryProvider);

      // Load Settings
      _theme = settingsRepo.getTheme();
      _scrollMode = settingsRepo.getScrollMode();
      _fontSize = settingsRepo.getFontSize();
      _fontFamily = settingsRepo.getFontFamily();

      // Parse Epub
      final file = File(widget.book.filePath);
      if (!await file.exists()) {
        throw Exception("Book file not found at ${widget.book.filePath}");
      }

      await _epubService.loadBook(widget.book.filePath);
      final epubBook = _epubService.book;

      if (epubBook == null) {
        throw Exception("Failed to parse EPUB");
      }

      // Detect Project Gutenberg
      _isGutenberg =
          (epubBook.Title?.contains('Project Gutenberg') ?? false) ||
          (epubBook.Author?.contains('Project Gutenberg') ?? false);

      // Flatten chapters
      _chapters = await _epubService.getAllChapters();

      // Group chapters
      _spineGroups = _groupChaptersBySpine(epubBook, _chapters);

      // Resolve initial location
      int initialIndex = 0;
      String initialCfi = '';

      // Fetch progress from repository properly
      final savedProgress = await bookRepo.getReadingProgress(widget.book.id);

      if (savedProgress != null && savedProgress.isNotEmpty) {
        final parts = savedProgress.split('|');
        if (parts.isNotEmpty) {
          initialIndex = int.tryParse(parts[0]) ?? 0;
          if (parts.length > 1) {
            initialCfi = parts[1];
          }
        }
      }

      if (initialIndex >= _chapters.length) initialIndex = 0;

      setState(() {
        _currentChapterIndex = initialIndex;
        _currentProgressCfi = initialCfi;
        _isLoading = false;
      });

      // Note: Actual content loading happens in onWebViewCreated -> _loadChapter
    } catch (e) {
      print("Error loading book: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading book: $e')));
        Navigator.pop(context);
      }
    }
  }

  List<List<epub.EpubChapterRef>> _groupChaptersBySpine(
    epub.EpubBookRef book,
    List<epub.EpubChapterRef> chapters,
  ) {
    List<List<epub.EpubChapterRef>> groups = [];
    if (chapters.isEmpty) return groups;

    List<epub.EpubChapterRef> currentGroup = [];
    String? currentFileName;

    for (var chapter in chapters) {
      if (currentFileName == null) {
        currentFileName = chapter.ContentFileName;
        currentGroup.add(chapter);
      } else if (chapter.ContentFileName != currentFileName) {
        if (currentGroup.isNotEmpty) {
          groups.add(currentGroup);
        }
        currentGroup = [chapter];
        currentFileName = chapter.ContentFileName;
      } else {
        currentGroup.add(chapter);
      }
    }
    if (currentGroup.isNotEmpty) {
      groups.add(currentGroup);
    }
    return groups;
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    // Lock JS interactions if controls are visible
    _webViewController?.evaluateJavascript(
      source:
          "if (window.setInteractionLocked) setInteractionLocked($_showControls);",
    );
  }

  void _updateWebViewSettings() {
    _webViewController?.setSettings(
      settings: InAppWebViewSettings(
        transparentBackground: true,
        supportZoom: false,
        horizontalScrollBarEnabled: false,
        verticalScrollBarEnabled: false,
        // Disable native paging, we handle it with JS
        isPagingEnabled: false,
        disableContextMenu: true,
        // Ensure content mode fits formatting
        pageZoom: 1.0,
      ),
    );
  }

  Future<void> _loadChapter(int index, {String? initialCfiOverride}) async {
    if (index < 0 || index >= _chapters.length) return;

    // Logic: Use override if provided.
    // Else if index == _currentChapterIndex, use _currentProgressCfi.
    // Else start at top.
    final targetCfi =
        initialCfiOverride ??
        (index == _currentChapterIndex ? _currentProgressCfi : '');

    print(
      "DEBUG: _loadChapter index=$index override=$initialCfiOverride targetCfi=$targetCfi",
    );

    setState(() {
      _currentChapterIndex = index;
      _showControls = false; // Auto-hide controls on chapter change
    });

    try {
      final chapter = _chapters[index];

      // Find spine group
      int spineIndex = -1;
      for (int i = 0; i < _spineGroups.length; i++) {
        if (_spineGroups[i].contains(chapter)) {
          spineIndex = i;
          break;
        }
      }

      if (spineIndex == -1) return;

      // Get content
      final content = await _epubService.getChapterContent(
        _spineGroups[spineIndex].first,
      );

      if (content != null) {
        String? startAnchor = chapter.Anchor;
        String? endAnchor;

        final group = _spineGroups[spineIndex];
        final indexInGroup = group.indexOf(chapter);

        if (indexInGroup != -1 && indexInGroup < group.length - 1) {
          endAnchor = group[indexInGroup + 1].Anchor;
        }

        // Fetch highlights for this chapter
        final allHighlights = await ref
            .read(bookRepositoryProvider)
            .getHighlights(widget.book.id);
        final chapterHighlights = allHighlights.where((h) {
          if (h.cfi == null) return false;
          try {
            final Map<String, dynamic> data = jsonDecode(h.cfi!);
            return data['chapterIndex'] == index;
          } catch (e) {
            return false;
          }
        }).toList();

        // Generate HTML
        final html = await ReaderHtmlGenerator.generateHtml(
          content,
          theme: _theme,
          fontSize: _fontSize,
          fontFamily: _fontFamily,
          scrollMode: _scrollMode,
          currentChapterIndex: index,
          initialProgress: targetCfi,
          highlights: chapterHighlights,
          spineIndex: spineIndex,
          anchors: [],
          scrollToAnchor: startAnchor,
          startAnchor: startAnchor,
          endAnchor: endAnchor,
          isGutenberg: _isGutenberg,
          isInteractionLocked: _showControls, // Maintain lock state
        );

        _updateWebViewSettings();
        await _webViewController?.loadData(data: html);

        // We do typically save simplified progress here, but real progress comes from scroll
        _saveProgress(index, targetCfi);
      }
    } catch (e) {
      print("Error loading chapter: $e");
    }
  }

  void _saveProgress(int chapterIndex, [String cfi = '']) {
    print("DEBUG: _saveProgress chapter=$chapterIndex cfi=$cfi");
    // Save both chapter index and detailed CFI
    ref
        .read(bookRepositoryProvider)
        .saveReadingProgress(widget.book.id, "$chapterIndex|$cfi");
  }

  void _onNextChapter() {
    if (_currentChapterIndex < _chapters.length - 1) {
      _currentProgressCfi = ''; // Reset for new chapter
      _loadChapter(_currentChapterIndex + 1);
    }
  }

  void _onPrevChapter() {
    if (_currentChapterIndex > 0) {
      _currentProgressCfi = ''; // Reset for new chapter
      _loadChapter(_currentChapterIndex - 1, initialCfiOverride: 'END');
    }
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
        return const Color(0xFFE0E0E0);
      case ReaderTheme.sepia:
        return const Color(0xFF5B4636);
    }
  }

  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2)}';
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
      drawer: ReaderDrawer(
        bookTitle: widget.book.title,
        chapters: _chapters,
        activeChapterIndex: _currentChapterIndex,
        backgroundColor: scaffoldColor,
        textColor: textColor,
        activeColor: Theme.of(context).primaryColor,
        onChapterSelected: (index) {
          Navigator.pop(context); // Close drawer
          _loadChapter(index);
        },
      ),
      body: Stack(
        children: [
          // WebView
          Positioned.fill(
            child: SafeArea(
              child: InAppWebView(
                key: ValueKey(
                  _scrollMode,
                ), // Force rebuild when mode changes to apply paging settings
                initialSettings: InAppWebViewSettings(
                  transparentBackground: true,
                  supportZoom: false,
                  horizontalScrollBarEnabled: false,
                  verticalScrollBarEnabled: false,
                  isPagingEnabled:
                      false, // Disable native paging, we handle it with JS
                  disableContextMenu: true,
                  pageZoom: 1.0,
                ),
                onWebViewCreated: (controller) {
                  _webViewController = controller;
                  controller.addJavaScriptHandler(
                    handlerName: 'onTap',
                    callback: (_) => _toggleControls(),
                  );

                  // Progress Handler (Granular)
                  controller.addJavaScriptHandler(
                    handlerName: 'onScrollProgress',
                    callback: (args) {
                      if (args.isNotEmpty) {
                        final cfi = args[0].toString();
                        // Only update if changed to avoid spam
                        if (cfi != _currentProgressCfi) {
                          _currentProgressCfi = cfi; // Update local state
                          _saveProgress(_currentChapterIndex, cfi);
                        }
                      }
                    },
                  );

                  controller.addJavaScriptHandler(
                    handlerName: 'onNearEnd',
                    callback: (args) {
                      // Potential pre-loading trigger or end-of-chapter hint
                    },
                  );

                  // Handle Chapter Navigation from JS (e.g. click next button or swipe past end)
                  controller.addJavaScriptHandler(
                    handlerName: 'onNextChapter',
                    callback: (args) => _onNextChapter(),
                  );

                  controller.addJavaScriptHandler(
                    handlerName: 'onPrevChapter',
                    callback: (args) => _onPrevChapter(),
                  );

                  controller.addJavaScriptHandler(
                    handlerName: 'consoleLog',
                    callback: (args) {
                      print("JS_LOG: ${args.join(' ')}");
                    },
                  );

                  controller.addJavaScriptHandler(
                    handlerName: 'onMenuAction',
                    callback: (args) {
                      if (args.length >= 3) {
                        _handleMenuAction(
                          args[0].toString(),
                          args[1].toString(),
                          args[2].toString(),
                        );
                      }
                    },
                  );

                  controller.addJavaScriptHandler(
                    handlerName: 'onHighlightAction',
                    callback: (args) {
                      if (args.length >= 2) {
                        _handleHighlightAction(
                          args[0].toString(), // action
                          args[1].toString(), // id
                        );
                      }
                    },
                  );
                  _loadChapter(_currentChapterIndex);
                },
              ),
            ),
          ),

          // Controls
          if (_showControls) ...[
            // Top Bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ReaderTopBar(
                showControls: _showControls,
                onExit: () => Navigator.of(context).pop(),
                onTOC: () => _scaffoldKey.currentState?.openDrawer(),
                onSettings: () {
                  _showSettingsModal(context);
                },
                backgroundColor: scaffoldColor,
                textColor: textColor,
              ),
            ),

            // Bottom Nav
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: ReaderNavigationBar(
                showControls: _showControls,
                backgroundColor: scaffoldColor,
                textColor: textColor,
                onPrevious: _onPrevChapter,
                onNext: _onNextChapter,
                canGoPrevious: _currentChapterIndex > 0,
                canGoNext: _currentChapterIndex < _chapters.length - 1,
                previousChapterTitle: _currentChapterIndex > 0
                    ? (_chapters[_currentChapterIndex - 1].Title ?? 'Previous')
                    : '',
                nextChapterTitle: _currentChapterIndex < _chapters.length - 1
                    ? (_chapters[_currentChapterIndex + 1].Title ?? 'Next')
                    : '',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleHighlightAction(String action, String id) async {
    switch (action) {
      case 'delete':
        await ref.read(bookRepositoryProvider).deleteHighlight(id);
        // Remove from UI (reload or JS remove?)
        // Easiest is to just reload the chapter or inject JS to remove the span
        // For now, reload is safest to ensure consistency, but flash might be annoying.
        // Let's try JS removal first? No, we need to locate all spans with that ID.
        await _webViewController?.evaluateJavascript(
          source:
              """
          var spans = document.querySelectorAll('span.highlight[data-id="$id"]');
          spans.forEach(function(span) {
              var parent = span.parentNode;
              while (span.firstChild) parent.insertBefore(span.firstChild, span);
              parent.removeChild(span);
          });
        """,
        );
        break;
      case 'note':
        if (mounted) {
          _showAddNoteToHighlightDialog(context, id);
        }
        break;
      case 'assign':
        if (mounted) {
          _showAssignCharacterDialog(context, id);
        }
        break;
    }
  }

  Future<void> _showAddNoteToHighlightDialog(
    BuildContext context,
    String highlightId,
  ) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Note to Highlight'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter your thoughts...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                // Save note linked to highlight
                // We use BookNotes table but with quoteId
                await ref
                    .read(bookRepositoryProvider)
                    .addBookNote(
                      widget.book.id,
                      controller.text,
                      quoteId: highlightId,
                    );

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Note attached to highlight')),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
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
                  // Show list + Create New option
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.add, color: Colors.blue),
                        title: const Text(
                          'Create New Character',
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _showCreateCharacterDialog(context, highlightId);
                        },
                      ),
                      const Divider(),
                      if (characters.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text('No characters yet.'),
                        )
                      else
                        Flexible(
                          child: ListView.builder(
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
                                      ? Text(char.name[0].toUpperCase())
                                      : null,
                                ),
                                title: Text(char.name),
                                onTap: () async {
                                  // Assign highlight to character
                                  await ref
                                      .read(bookRepositoryProvider)
                                      .updateHighlightCharacter(
                                        highlightId,
                                        char.id,
                                      );
                                  if (mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Assigned to ${char.name}',
                                        ),
                                      ),
                                    );
                                  }
                                },
                              );
                            },
                          ),
                        ),
                    ],
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

  Future<void> _showCreateCharacterDialog(
    BuildContext context,
    String? assignHighlightId,
  ) async {
    final nameController = TextEditingController();
    // If we have a highlight, maybe pre-fill name if it's short?
    if (assignHighlightId != null) {
      // Get highlight text (async lookup needed? or passing it?)
      // Ideally we passed text, but we only have ID here.
      // Let's keep it empty for now or user can type.
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Character'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Character Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (nameController.text.trim().isNotEmpty) {
                final charId = await ref
                    .read(characterRepositoryProvider)
                    .createCharacter(
                      name: nameController.text.trim(),
                      originBookId: widget.book.id,
                    );

                if (assignHighlightId != null && mounted) {
                  await ref
                      .read(bookRepositoryProvider)
                      .updateHighlightCharacter(assignHighlightId, charId);
                }

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Character created and assigned!'),
                    ),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleMenuAction(String action, String cfi, String text) async {
    switch (action) {
      case 'highlight':
        await _createHighlight(text, cfi);
        break;
      case 'assign':
        // For assign, we first create the highlight, then show the dialog
        final highlightId = await _createHighlight(text, cfi);
        if (highlightId != null && mounted) {
          _showAssignCharacterDialog(context, highlightId);
        }
        break;
      case 'copy':
        await Clipboard.setData(ClipboardData(text: text));
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
        }
        break;
      case 'share':
        await Share.share(text);
        break;
      case 'define':
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Dictionary lookup not implemented')),
          );
        }
        break;
    }
  }

  // Helper method now available
  Future<String?> _createHighlight(String text, String cfi) async {
    try {
      // Create highlight JSON
      final Map<String, dynamic> cfiJson = jsonDecode(cfi);
      cfiJson['chapterIndex'] = _currentChapterIndex; // Fixed variable name

      if (!cfiJson.containsKey('text')) {
        cfiJson['text'] = text;
      }
      final String finalCfiString = jsonEncode(cfiJson);

      final id = await ref
          .read(bookRepositoryProvider)
          .addHighlight(widget.book.id, text, finalCfiString);

      // Apply visual highlight in JS
      // FIX: Properly encode the CFI string for JS injection
      final encodedCfi = jsonEncode(
        cfi,
      ); // Encodes to a valid JS string literal content
      await _webViewController?.evaluateJavascript(
        source: "applyHighlight($encodedCfi, '$id'); null;",
      );

      // Add to local list so it persists in this session without reload
      // setState(() {
      //   _currentHighlights.add(...)
      // });

      return id;
    } catch (e) {
      print("Error saving highlight: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving highlight: $e')));
      }
      return null;
    }
  }

  void _updateFontSize(double size) {
    setState(() {
      _fontSize = size;
    });
    ref.read(readerSettingsRepositoryProvider).setFontSize(size);
    _webViewController?.evaluateJavascript(
      source:
          "document.body.style.setProperty('font-size', '${size}%', 'important'); null;",
    );
  }

  void _toggleInputBlocking(bool blocked) {
    _webViewController?.evaluateJavascript(
      source: "setInputBlocked($blocked); null;",
    );
  }

  void _showSettingsModal(BuildContext context) async {
    // JS Blocking (The "Real" Fix)
    _toggleInputBlocking(true);

    await showModalBottomSheet(
      context: context,
      builder: (context) => ReaderSettingsModal(
        theme: _theme,
        scrollMode: _scrollMode,
        fontSize: _fontSize,
        fontFamily: _fontFamily,
        activeChapterIndex: _currentChapterIndex,
        totalChapters: _chapters.length,
        onThemeChanged: (theme) {
          setState(() {
            _theme = theme;
          });
          ref.read(readerSettingsRepositoryProvider).setTheme(theme);

          final textColor = _colorToHex(_getTextColor());
          final bgColor = _colorToHex(_getScaffoldColor());
          _webViewController?.evaluateJavascript(
            source: "setTheme('$textColor', '$bgColor'); null;",
          );
        },
        onScrollModeChanged: (mode) async {
          // Attempt to capture current progress before switch
          try {
            final result = await _webViewController?.evaluateJavascript(
              source:
                  "window.getCurrentLocationPath ? window.getCurrentLocationPath() : null;",
            );
            print("DEBUG: Mode Switch Capture Result: $result");
            if (result != null &&
                result.toString().isNotEmpty &&
                result.toString() != 'null') {
              _currentProgressCfi = result.toString();
              _saveProgress(_currentChapterIndex, _currentProgressCfi);
              print("DEBUG: Saved CFI for switch: $_currentProgressCfi");
            } else {
              print("DEBUG: Capture failed or empty. Result: $result");
            }
          } catch (e) {
            print("Error capturing progress: $e");
          }

          setState(() {
            _scrollMode = mode;
          });
          ref.read(readerSettingsRepositoryProvider).setScrollMode(mode);
          _updateWebViewSettings(); // Ensure WebView settings (paging) are updated
          print(
            "DEBUG: calling _loadChapter with override: $_currentProgressCfi",
          );
          _loadChapter(
            _currentChapterIndex,
            initialCfiOverride: _currentProgressCfi,
          ); // Reload to apply CSS changes
        },
        onFontSizeChanged: (size) {
          _updateFontSize(size);
        },
        onFontFamilyChanged: (family) {
          setState(() {
            _fontFamily = family;
          });
          ref.read(readerSettingsRepositoryProvider).setFontFamily(family);
          // Use helper function which sets !important
          _webViewController?.evaluateJavascript(
            source: "setFontFamily('$family'); null;",
          );
        },
      ),
    );

    // Unblock JS
    _toggleInputBlocking(false);
  }
}
