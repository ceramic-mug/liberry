import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/remote/remote_book.dart';
import '../providers.dart';

import '../data/kindle_settings_repository.dart'; // Still needed for refresh event if we want to listen, but helper does work
import 'common/kindle_helper.dart';
import 'reader_screen.dart';

class DownloadSplashScreen extends ConsumerStatefulWidget {
  final RemoteBook book;

  const DownloadSplashScreen({super.key, required this.book});

  @override
  ConsumerState<DownloadSplashScreen> createState() =>
      _DownloadSplashScreenState();
}

class _DownloadSplashScreenState extends ConsumerState<DownloadSplashScreen>
    with SingleTickerProviderStateMixin {
  // State for post-download actions
  bool _addedToDesk = false;
  bool _addedToBookshelf = false;

  // Download state
  String? _bookId;
  bool _isDownloading = true;
  String? _error;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Kindle Email state
  // Kindle Devices state
  List<KindleDevice> _kindleDevices = [];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Load Kindle devices
    _refreshKindleDevices();

    _startDownload();
  }

  void _refreshKindleDevices() {
    // With KindleHelper, we might not need to strictly maintain this list locally if we delegate everything,
    // but showing the 'edit' icon conditional on having devices requires it.
    // For now, let's keep it sync.
    try {
      setState(() {
        _kindleDevices = ref
            .read(kindleSettingsRepositoryProvider)
            .getDevices();
      });
    } catch (_) {
      // Provider might not be ready
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startDownload() async {
    if (widget.book.downloadUrl == null) {
      setState(() {
        _error = 'No download URL available.';
        _isDownloading = false;
      });
      return;
    }

    try {
      final bookId = await ref
          .read(downloadManagerProvider)
          .downloadBook(
            widget.book.downloadUrl!,
            widget.book.title,
            coverUrl: widget.book.coverUrl,
          );

      if (mounted) {
        setState(() {
          _bookId = bookId;
          _isDownloading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isDownloading = false;
        });
      }
    }
  }

  void _handleOpen() async {
    if (_bookId == null) return;
    final book = await ref.read(bookRepositoryProvider).getBook(_bookId!);
    if (book != null && mounted) {
      await ref
          .read(bookRepositoryProvider)
          .updateBookStatus(_bookId!, 'reading');

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => ReaderScreen(book: book)),
      );
    }
  }

  void _handleAddToDesk() async {
    if (_bookId == null) return;
    await ref.read(bookRepositoryProvider).updateBookLocation(_bookId!, 'desk');
    if (mounted) {
      setState(() {
        _addedToDesk = true;
        _addedToBookshelf =
            false; // Mutually exclusive usually, or can be both? Book model has single 'group'. Assuming exclusive.
      });
    }
  }

  void _handleAddToBookshelf() async {
    if (_bookId == null) return;
    await ref
        .read(bookRepositoryProvider)
        .updateBookLocation(_bookId!, 'bookshelf');
    if (mounted) {
      setState(() {
        _addedToBookshelf = true;
        _addedToDesk = false;
      });
    }
  }

  void _handleGoToLibrary() {
    // Pop until we are at root, then maybe switch tab?
    // Assuming Library is a main tab. Navigation structure is complex.
    // For now, let's pop everything (to Discover) and let user navigate,
    // OR if we can, find the MainScreen and switch index.
    // Simplifying: Pop splash, let user navigate.
    // Wait, user explicitly asked to "go to library".
    // If we pop, we are back in Discover.
    // We can pop, then try to navigate.
    Navigator.of(context).popUntil((route) => route.isFirst);
    // TODO: Implement cleaner navigation to specific tab if possible.
    // For now this returns to home.
  }

  Future<void> _handleSendToKindle() async {
    if (_bookId == null) return;

    // We can use the helper now
    final book = await ref.read(bookRepositoryProvider).getBook(_bookId!);
    if (book != null && mounted) {
      await KindleHelper(
        context: context,
        ref: ref,
      ).handleSendToKindle(filePath: book.filePath, bookTitle: book.title);
      // Refresh local state to update UI (show/hide settings icon)
      _refreshKindleDevices();
    }
  }

  Future<void> _showManageDevicesDialog() async {
    await KindleHelper(context: context, ref: ref).showManageDevicesDialog();
    _refreshKindleDevices();
  }

  @override
  Widget build(BuildContext context) {
    // Try to parse cover if data URI
    Widget coverWidget;
    if (widget.book.coverUrl != null) {
      if (widget.book.coverUrl!.startsWith('data:')) {
        try {
          final base64String = widget.book.coverUrl!.split(',').last;
          final bytes = base64Decode(base64String);
          coverWidget = Image.memory(bytes, fit: BoxFit.cover);
        } catch (e) {
          coverWidget = Container(
            color: Colors.grey[800],
            child: const Icon(Icons.book, size: 50, color: Colors.white54),
          );
        }
      } else {
        coverWidget = Image.network(
          widget.book.coverUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: Colors.grey[800],
            child: const Icon(Icons.book, size: 50, color: Colors.white54),
          ),
        );
      }
    } else {
      coverWidget = Container(
        color: Colors.grey[800],
        child: const Icon(Icons.book, size: 50, color: Colors.white54),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black, // Dark immersive background
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred Background
          Opacity(
            opacity: 0.3,
            child: ImageFiltered(
              imageFilter: const ColorFilter.mode(Colors.black, BlendMode.dst),
              // Re-doing background: just a dark container with the cover large and blurred
              child: Transform.scale(scale: 2.0, child: coverWidget),
            ),
          ),

          // Dark Overlay
          Container(color: Colors.black.withOpacity(0.85)),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),

                  // Cover
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      width: 180,
                      height: 270,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: coverWidget,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Title & Author
                  Text(
                    widget.book.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.book.author,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(height: 50),

                  // Status / Actions
                  if (_isDownloading) ...[
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 20),
                    Text(
                      "Downloading...",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 14,
                      ),
                    ),
                  ] else if (_error != null) ...[
                    Icon(Icons.error_outline, color: Colors.red[300], size: 48),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.red[100]),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _error = null;
                          _isDownloading = true;
                        });
                        _startDownload();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white30),
                      ),
                      child: const Text("Retry"),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        "Cancel",
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  ] else ...[
                    // Success Actions
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _handleOpen,
                        icon: const Icon(Icons.menu_book),
                        label: const Text("Open Book"),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _addedToDesk ? null : _handleAddToDesk,
                            icon: Icon(
                              _addedToDesk
                                  ? Icons.check
                                  : Icons.table_restaurant,
                              color: _addedToDesk ? Colors.greenAccent : null,
                            ),
                            label: Text(
                              _addedToDesk ? "Added" : "Desk",
                              style: TextStyle(
                                color: _addedToDesk ? Colors.greenAccent : null,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: _addedToDesk
                                    ? Colors.greenAccent
                                    : Colors.white30,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _addedToBookshelf
                                ? null
                                : _handleAddToBookshelf,
                            icon: Icon(
                              _addedToBookshelf ? Icons.check : Icons.shelves,
                              color: _addedToBookshelf
                                  ? Colors.greenAccent
                                  : null,
                            ),
                            label: Text(
                              _addedToBookshelf ? "Added" : "Bookshelf",
                              style: TextStyle(
                                color: _addedToBookshelf
                                    ? Colors.greenAccent
                                    : null,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: _addedToBookshelf
                                    ? Colors.greenAccent
                                    : Colors.white30,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _handleSendToKindle,
                              icon: const Icon(Icons.send),
                              label: const Text("Send to Kindle"),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white30),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          if (_kindleDevices.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: _showManageDevicesDialog,
                              icon: const Icon(
                                Icons.settings_remote,
                                color: Colors.white54,
                              ),
                              tooltip: 'Manage Kindle Devices',
                            ),
                          ],
                        ],
                      ),
                    ),

                    if (_addedToDesk || _addedToBookshelf) ...[
                      const SizedBox(height: 24),
                      Divider(color: Colors.white.withOpacity(0.1)),
                      const SizedBox(height: 16),
                      // Additional Navigation options once action is taken
                      TextButton(
                        onPressed: _handleGoToLibrary,
                        child: const Text(
                          "Go to Library",
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          "Discover More Books",
                          style: TextStyle(color: Colors.white54, fontSize: 14),
                        ),
                      ),
                    ],
                  ],

                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
