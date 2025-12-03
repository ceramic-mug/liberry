import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:epubx/epubx.dart';
import 'dart:convert';
import 'dart:io';
import '../data/database.dart';
import '../services/epub_service.dart';
import '../data/reader_settings_repository.dart';

import '../providers.dart';
import 'reader/reader_models.dart';
import 'reader/reader_html_generator.dart';
import 'reader/reader_settings_modal.dart';
import 'reader/reader_navigation_bar.dart';
import 'reader/reader_drawer.dart';
import 'reader/reader_top_bar.dart';

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
  List<EpubChapterRef> _chapters = [];
  List<List<EpubChapterRef>> _spineGroups = []; // Grouped by file
  int _currentChapterIndex = 0; // Current logical chapter (TOC)
  int _activeChapterIndex = 0; // The chapter currently visible in UI
  List<Quote> _currentHighlights = []; // Store full Quote objects

  // Settings
  double _fontSize = 100.0;
  String _fontFamily = 'Georgia, serif';
  ReaderTheme _theme = ReaderTheme.light;
  ReaderScrollMode _scrollMode = ReaderScrollMode.vertical;
  bool _showControls = false; // Start immersive

  String _initialCfiPath = '';
  int? _initialChapterIndex;
  bool _isSettingsOpen = false;

  @override
  void initState() {
    super.initState();

    // Load settings
    final settingsRepo = ref.read(readerSettingsRepositoryProvider);
    _theme = settingsRepo.getTheme();
    _scrollMode = settingsRepo.getScrollMode();
    _fontSize = settingsRepo.getFontSize();
    _fontFamily = settingsRepo.getFontFamily();

    // Restore progress if available
    if (widget.initialCfi.isNotEmpty) {
      try {
        // Try parsing as JSON first
        if (widget.initialCfi.startsWith('{')) {
          try {
            final json = jsonDecode(widget.initialCfi);
            if (json['chapterIndex'] != null) {
              _initialChapterIndex = json['chapterIndex'] is int
                  ? json['chapterIndex']
                  : int.tryParse(json['chapterIndex'].toString());
            }

            if (json['cfi'] != null) {
              _initialCfiPath = json['cfi'];
            } else if (json['startPath'] != null) {
              _initialCfiPath = json['startPath'];
            }
          } catch (e) {
            print('Error parsing initial CFI JSON: $e');
          }
        } else {
          // Legacy int parsing
          _initialChapterIndex = int.tryParse(widget.initialCfi);
        }
      } catch (e) {
        print('Error parsing initial CFI: $e');
      }
    }

    _loadBook();
  }

  Future<void> _loadBook() async {
    print('ReaderScreen: _loadBook started');
    try {
      await _epubService.loadBook(widget.book.filePath);
      print('ReaderScreen: Book loaded in service');
      final allChapters = await _epubService.getAllChapters();
      print('ReaderScreen: Got ${allChapters.length} chapters');

      setState(() {
        _chapters = allChapters;
        _spineGroups = _groupChaptersBySpine(_chapters);
      });
      print('ReaderScreen: Created ${_spineGroups.length} spine groups');

      // Load settings
      final settingsRepo = ref.read(readerSettingsRepositoryProvider);
      _theme = settingsRepo.getTheme();
      _scrollMode = settingsRepo.getScrollMode();
      _fontSize = settingsRepo.getFontSize();
      _fontFamily = settingsRepo.getFontFamily();

      // Restore progress ONLY if we didn't pass an initial CFI (e.g. from a highlight)
      if (widget.initialCfi.isEmpty) {
        final progress = await ref
            .read(bookRepositoryProvider)
            .getReadingProgress(widget.book.id);
        print('ReaderScreen: Progress restored: $progress');

        if (progress != null) {
          try {
            final json = jsonDecode(progress);
            _initialChapterIndex = json['chapterIndex'];
            _initialCfiPath = json['cfi'];
          } catch (e) {
            print('Error parsing progress: $e');
          }
        }
      } else {
        print('ReaderScreen: Skipping progress restore, using initialCfi');
      }

      // Determine initial spine index
      // Determine initial chapter index
      if (_initialChapterIndex != null &&
          _initialChapterIndex! < _chapters.length) {
        _currentChapterIndex = _initialChapterIndex!;
        _activeChapterIndex = _initialChapterIndex!;
      }
      print('ReaderScreen: Initial chapter index: $_currentChapterIndex');

      setState(() {
        _isLoading = false;
      });

      // Load the initial chapter
      if (mounted) {
        if (_webViewController != null) {
          print(
            'ReaderScreen: WebView ready, triggering _loadChapter($_currentChapterIndex)',
          );
          _loadChapter(_currentChapterIndex, initialCfi: _initialCfiPath);
        } else {
          print(
            'ReaderScreen: WebView not ready, waiting for onWebViewCreated',
          );
        }
      }
    } catch (e, stack) {
      print('Error loading book: $e');
      print(stack);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading book: $e')));
      }
    }
  }

  Future<void> _loadChapter(int index, {String initialCfi = ''}) async {
    if (index < 0 || index >= _chapters.length) return;

    if (_webViewController == null) {
      return;
    }

    print(
      "ReaderScreen: _loadChapter($index) called with initialCfi: '$initialCfi'",
    );

    // Find which spine group this chapter belongs to
    int spineIndex = -1;
    for (int i = 0; i < _spineGroups.length; i++) {
      if (_spineGroups[i].contains(_chapters[index])) {
        spineIndex = i;
        break;
      }
    }

    if (spineIndex == -1) {
      print("Error: Could not find spine group for chapter $index");
      return;
    }

    setState(() {
      _currentChapterIndex = index;
      _activeChapterIndex = index;
    });

    // Save progress (initial load)
    _saveProgress(_activeChapterIndex, initialCfi);

    // Load content of the spine item
    // We use the first chapter in the group to get the file content, as they share the file
    final content = await _epubService.getChapterContent(
      _spineGroups[spineIndex].first,
    );

    if (content != null) {
      // Determine anchors for slicing
      final currentChapter = _chapters[index];
      String? startAnchor = currentChapter.Anchor;
      String? endAnchor;

      // Check if there is a next chapter in the SAME spine group
      final group = _spineGroups[spineIndex];
      final indexInGroup = group.indexOf(currentChapter);
      if (indexInGroup != -1 && indexInGroup < group.length - 1) {
        endAnchor = group[indexInGroup + 1].Anchor;
      }

      // Prepare anchors for this spine item (for JS scroll/active detection if needed, though less relevant now)
      final anchors = group.map((c) {
        return {
          'id': c.Anchor, // The ID in the HTML (e.g. "p1")
          'chapterIndex': _chapters.indexOf(c),
        };
      }).toList();

      // Refresh highlights
      final highlights = await ref
          .read(bookRepositoryProvider)
          .getHighlights(widget.book.id);

      setState(() {
        _currentHighlights = highlights;
      });

      print(
        "ReaderScreen: Loading chapter $index (Spine $spineIndex). Start: $startAnchor, End: $endAnchor",
      );
      await _webViewController?.loadData(
        data: ReaderHtmlGenerator.generateHtml(
          content,
          theme: _theme,
          fontSize: _fontSize,
          fontFamily: _fontFamily,
          scrollMode: _scrollMode,
          currentChapterIndex: _currentChapterIndex,
          initialProgress: initialCfi,
          highlights: _currentHighlights,
          spineIndex: spineIndex,
          anchors: anchors,
          scrollToAnchor:
              null, // We slice, so we start at top usually (unless CFI)
          startAnchor: startAnchor,
          endAnchor: endAnchor,
        ),
      );
    }
  }

  Future<void> _saveProgress(int chapterIndex, String cfi) async {
    final progressJson = jsonEncode({
      'chapterIndex': chapterIndex,
      'cfi': cfi,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    await ref
        .read(bookRepositoryProvider)
        .saveReadingProgress(widget.book.id, progressJson);
  }

  // Helper to group chapters by their source file (spine item)
  // This is crucial because EPUBs often split one file into multiple "chapters" (anchors)
  List<List<EpubChapterRef>> _groupChaptersBySpine(
    List<EpubChapterRef> chapters,
  ) {
    List<List<EpubChapterRef>> groups = [];
    if (chapters.isEmpty) return groups;

    String? currentFileName;
    List<EpubChapterRef> currentGroup = [];

    for (var chapter in chapters) {
      if (chapter.ContentFileName != currentFileName) {
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

    print(
      "ReaderScreen: Grouped ${chapters.length} chapters into ${groups.length} spine items",
    );
    for (var i = 0; i < groups.length; i++) {
      print(
        "Spine Group $i: ${groups[i].length} chapters. File: ${groups[i].first.ContentFileName}",
      );
    }

    return groups;
  }

  void _toggleControls() {
    if (_isSettingsOpen) return;
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
        // Attempt to suppress default context menu
        disableContextMenu: true,
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

  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
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
      // appBar and bottomNavigationBar removed to allow overlay
      drawer: ReaderDrawer(
        bookTitle: widget.book.title,
        chapters: _chapters,
        activeChapterIndex: _activeChapterIndex,
        backgroundColor: scaffoldColor,
        textColor: textColor,
        activeColor: Theme.of(context).primaryColor,
        onChapterSelected: (index) {
          if (index >= 0 && index < _chapters.length) {
            _loadChapter(index);
          }
        },
      ),
      bottomNavigationBar: null, // Removed
      body: Stack(
        children: [
          // WebView
          SafeArea(
            child: InAppWebView(
              initialSettings: InAppWebViewSettings(
                transparentBackground: true,
                supportZoom: false,
                horizontalScrollBarEnabled: false,
                verticalScrollBarEnabled: false,
                isPagingEnabled: false,
                disableContextMenu: true,
              ),
              initialData: InAppWebViewInitialData(
                data: '''
                  <!DOCTYPE html>
                  <html>
                  <head>
                    <style>
                      body { 
                        display: flex; 
                        justify-content: center; 
                        align-items: center; 
                        height: 100vh; 
                        margin: 0; 
                        font-family: sans-serif; 
                        color: #888;
                      }
                    </style>
                  </head>
                  <body>
                    Loading...
                  </body>
                  </html>
                ''',
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
                print("ReaderScreen: onWebViewCreated");

                // If book is already loaded, trigger spine load
                if (_chapters.isNotEmpty) {
                  print(
                    "ReaderScreen: Book already loaded, triggering _loadChapter($_currentChapterIndex)",
                  );
                  _loadChapter(
                    _currentChapterIndex,
                    initialCfi: _initialCfiPath,
                  );
                } else {
                  print("ReaderScreen: Book not yet loaded, waiting...");
                }

                // Scroll Handlers
                controller.addJavaScriptHandler(
                  handlerName: 'onNextChapter',
                  callback: (args) {
                    print("ReaderScreen: onNextChapter triggered from JS");
                    if (_currentChapterIndex < _chapters.length - 1) {
                      _loadChapter(_currentChapterIndex + 1);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'You have reached the end of the book.',
                          ),
                        ),
                      );
                    }
                  },
                );

                controller.addJavaScriptHandler(
                  handlerName: 'onActiveChapterChanged',
                  callback: (args) {
                    if (args.isNotEmpty && args[0] != null) {
                      setState(() {
                        _activeChapterIndex = args[0] as int;
                        _currentChapterIndex = _activeChapterIndex;
                      });
                      _saveProgress(_activeChapterIndex, '');
                    }
                  },
                );

                controller.addJavaScriptHandler(
                  handlerName: 'onScrollProgress',
                  callback: (args) {
                    if (args.isNotEmpty) {
                      final String path = args[0].toString();
                      _saveProgress(_activeChapterIndex, path);
                    }
                  },
                );

                controller.addJavaScriptHandler(
                  handlerName: 'onTap',
                  callback: (args) {
                    _toggleControls();
                  },
                );

                controller.addJavaScriptHandler(
                  handlerName: 'onMenuAction',
                  callback: (args) {
                    if (args.length >= 3) {
                      final action = args[0] as String;
                      final cfi = args[1] as String;
                      final text = args[2] as String;
                      _handleMenuAction(action, cfi, text);
                    }
                  },
                );

                controller.addJavaScriptHandler(
                  handlerName: 'onHighlightClick',
                  callback: (args) {
                    if (args.isNotEmpty) {
                      final id = args[0] as String;
                      _showHighlightOptions(context, id);
                    }
                  },
                );
              },
              onConsoleMessage: (controller, consoleMessage) {
                print("JS Console: ${consoleMessage.message}");
              },
              onLoadStop: (controller, url) async {
                print("ReaderScreen: onLoadStop");
              },
            ),
          ),

          if (_isLoading)
            Container(
              color: scaffoldColor,
              child: const Center(child: CircularProgressIndicator()),
            ),

          // Top Bar (Overlay)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ReaderTopBar(
              showControls: _showControls,
              backgroundColor: scaffoldColor,
              textColor: textColor,
              onExit: () {
                Navigator.pop(context);
              },
              onTOC: () {
                _scaffoldKey.currentState?.openDrawer();
              },
              onSettings: () => _showSettingsModal(context),
            ),
          ),

          // Bottom Bar (Overlay)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: ReaderNavigationBar(
                showControls: _showControls,
                backgroundColor: scaffoldColor,
                textColor: textColor,
                previousChapterTitle:
                    _chapters.isNotEmpty && _currentChapterIndex > 0
                    ? _chapters[_currentChapterIndex - 1].Title ?? ''
                    : '',
                nextChapterTitle:
                    _chapters.isNotEmpty &&
                        _currentChapterIndex < _chapters.length - 1
                    ? _chapters[_currentChapterIndex + 1].Title ?? ''
                    : '',
                canGoPrevious: _currentChapterIndex > 0,
                canGoNext: _currentChapterIndex < _chapters.length - 1,
                onPrevious: () => _loadChapter(_currentChapterIndex - 1),
                onNext: () => _loadChapter(_currentChapterIndex + 1),
              ),
            ),
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
    }
  }

  Future<String?> _createHighlight(String text, String cfi) async {
    try {
      // Create highlight JSON
      final Map<String, dynamic> cfiJson = jsonDecode(cfi);
      cfiJson['chapterIndex'] = _activeChapterIndex;
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
        source: "applyHighlight($encodedCfi, '$id')",
      );

      // Add to local list so it persists in this session without reload
      setState(() {
        _currentHighlights.add(
          Quote(
            id: id,
            textContent: text,
            bookId: widget.book.id,
            cfi: finalCfiString,
            createdAt: DateTime.now(),
          ),
        );
      });

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
      source: "document.body.style.fontSize = '${size}%';",
    );
  }

  void _showSettingsModal(BuildContext context) async {
    setState(() {
      _isSettingsOpen = true;
    });
    await showModalBottomSheet(
      context: context,
      builder: (context) => ReaderSettingsModal(
        theme: _theme,
        scrollMode: _scrollMode,
        fontSize: _fontSize,
        fontFamily: _fontFamily,
        activeChapterIndex: _activeChapterIndex,
        totalChapters: _chapters.length,
        onThemeChanged: (theme) {
          setState(() {
            _theme = theme;
          });
          ref.read(readerSettingsRepositoryProvider).setTheme(theme);

          final textColor = _colorToHex(_getTextColor());
          _webViewController?.evaluateJavascript(
            source: "setTheme('$textColor')",
          );
        },
        onScrollModeChanged: (mode) {
          setState(() {
            _scrollMode = mode;
          });
          ref.read(readerSettingsRepositoryProvider).setScrollMode(mode);
          _updateWebViewSettings();
          _loadChapter(_currentChapterIndex);
        },
        onFontSizeChanged: (size) {
          _updateFontSize(size);
        },
        onFontFamilyChanged: (family) {
          setState(() {
            _fontFamily = family;
          });
          ref.read(readerSettingsRepositoryProvider).setFontFamily(family);
          _webViewController?.evaluateJavascript(
            source: "setFontFamily('$family')",
          );
        },
      ),
    );
    setState(() {
      _isSettingsOpen = false;
    });
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
}
