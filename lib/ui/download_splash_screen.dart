import 'dart:convert';
import 'dart:io';
import 'dart:ui'; // For ImageFilter
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../data/remote/remote_book.dart';
import '../providers.dart';

import 'common/kindle_helper.dart';
import 'reader_screen.dart';

// Now functions as a "Book Preview" screen before downloading
class DownloadSplashScreen extends ConsumerStatefulWidget {
  final RemoteBook book;
  final bool autoStartDownload;

  const DownloadSplashScreen({
    super.key,
    required this.book,
    this.autoStartDownload = false,
  });

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
  bool _isDownloading = false;
  String _loadingMessage = "Downloading..."; // Dynamic loading text
  String? _error;

  // Animation for downloading state
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

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

    if (widget.autoStartDownload) {
      _startDownload();
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
        _isDownloading = false; // Show error state
      });
      return;
    }

    setState(() {
      _isDownloading = true;
      _loadingMessage = "Downloading...";
      _error = null;
    });

    try {
      final bookId = await ref
          .read(downloadManagerProvider)
          .downloadBook(
            widget.book.downloadUrl!,
            widget.book.title,
            coverUrl: widget.book.coverUrl,
            sourceMetadata: jsonEncode(widget.book.toJson()),
          );

      // Auto-categorize as "Desk" and "Not Started"
      await ref.read(bookRepositoryProvider).updateBookLocation(bookId, 'desk');
      await ref
          .read(bookRepositoryProvider)
          .updateBookStatus(bookId, 'not_started');

      if (mounted) {
        setState(() {
          _bookId = bookId;
          _isDownloading = false;
          _addedToDesk = true; // Mark as added since we did it auto
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

  Future<void> _markAsRead() async {
    setState(() {
      _isDownloading = true; // Show loading
      _loadingMessage = "Saving title to bookshelf...";
    });

    try {
      final bookId = await ref
          .read(bookRepositoryProvider)
          .addOffloadedBook(
            title: widget.book.title,
            author: widget.book.author,
            remoteCoverUrl: widget.book.coverUrl,
            sourceMetadata: jsonEncode(widget.book.toJson()),
          );

      if (mounted) {
        setState(() {
          _bookId = bookId;
          _isDownloading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Marked as read and added to bookshelf'),
          ),
        );

        Navigator.pop(context); // Return to collection
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
      // Just open, don't change status to reading yet unless Reader does it (it usually does).
      // actually user preferred "Not Started" on download, so let's respect that until they actively read.
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
        _addedToBookshelf = false;
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
    // Reset to library tab
    ref.read(navigationIndexProvider.notifier).setIndex(0);
    // Pop to root to ensure we are back at the main screen
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _showShareSheet() async {
    if (_bookId == null) return;
    final book = await ref.read(bookRepositoryProvider).getBook(_bookId!);
    if (book == null || !mounted) return;

    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Text(
                'Share Book',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.send),
                title: const Text('Send to Kindle'),
                trailing: IconButton(
                  icon: const Icon(Icons.settings_remote, color: Colors.grey),
                  tooltip: 'Manage Kindle Devices',
                  onPressed: () async {
                    await KindleHelper(
                      context: context,
                      ref: ref,
                    ).showManageDevicesDialog();
                  },
                ),
                onTap: () async {
                  Navigator.pop(sheetContext); // Close sheet

                  // Resolve cover path logic identical to BookDetails
                  // Since we just downloaded it, it might still only have a URL or a local path.
                  // Book entity has coverPath.
                  String? resolvedCoverPath;
                  if (book.coverPath != null) {
                    final appDir = await getApplicationDocumentsDirectory();
                    final path = book.coverPath!;
                    final fullPath = p.isAbsolute(path)
                        ? path
                        : p.join(appDir.path, path);
                    if (await File(fullPath).exists()) {
                      resolvedCoverPath = fullPath;
                    }
                  }

                  await KindleHelper(
                    context: context,
                    ref: ref,
                  ).handleSendToKindle(
                    filePath: book.filePath,
                    bookTitle: book.title,
                    coverPath: resolvedCoverPath,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Share File'),
                onTap: () async {
                  Navigator.pop(sheetContext); // Close sheet
                  final file = File(book.filePath);
                  if (await file.exists()) {
                    await Share.shareXFiles([
                      XFile(book.filePath),
                    ], text: 'Check out this book: ${book.title}');
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Book file not found')),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCover({bool large = false}) {
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

    return Container(
      width: large ? 180 : 120,
      height: large ? 270 : 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    // Background setup
    Widget bgCover;
    if (widget.book.coverUrl != null &&
        widget.book.coverUrl!.startsWith('data:')) {
      try {
        bgCover = Image.memory(
          base64Decode(widget.book.coverUrl!.split(',').last),
          fit: BoxFit.cover,
        );
      } catch (_) {
        bgCover = Container(color: Colors.black);
      }
    } else if (widget.book.coverUrl != null) {
      bgCover = Image.network(
        widget.book.coverUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(color: Colors.black),
      );
    } else {
      bgCover = Container(color: Colors.black);
    }

    final isSuccess = !_isDownloading && _bookId != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background - Static, blurred, and opaque to prevent ghosting
          SizedBox.expand(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Transform.scale(
                scale: 1.2, // Slight scale to avoid blur edges
                child: bgCover,
              ),
            ),
          ),

          // Dimming Overlay
          Container(color: Colors.black.withOpacity(0.6)),

          // Navigation Back Button
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
            ),
          ),

          // Share Button (Only on success)
          if (isSuccess)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: IconButton(
                onPressed: _showShareSheet,
                icon: const Icon(
                  Icons.ios_share,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),

                  // Cover
                  // Use Hero for smooth transition if not actively downloading/pulsing
                  if (_isDownloading)
                    ScaleTransition(
                      scale: _pulseAnimation,
                      child: _buildCover(large: true),
                    )
                  else
                    _buildCover(large: true),

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

                  // ==========================
                  // STATE 1: PREVIEW (Download Button)
                  // ==========================
                  if (!_isDownloading && _bookId == null) ...[
                    if (_error != null) ...[
                      Icon(
                        Icons.error_outline,
                        color: Colors.red[300],
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red[100]),
                      ),
                      const SizedBox(height: 24),
                      OutlinedButton(
                        onPressed: _startDownload,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white30),
                        ),
                        child: const Text("Retry"),
                      ),
                    ] else ...[
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _startDownload,
                          icon: const Icon(Icons.download),
                          label: const Text("Download to Library"),
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
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _markAsRead,
                          icon: const Icon(Icons.check),
                          label: const Text("Mark as Already Read"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white30),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ]
                  // ==========================
                  // STATE 2: DOWNLOADING
                  // ==========================
                  else if (_isDownloading) ...[
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 20),
                    Text(
                      _loadingMessage,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 14,
                      ),
                    ),
                  ]
                  // ==========================
                  // STATE 3: SUCCESS (Post-Download Options)
                  // ==========================
                  else ...[
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
                    TextButton(
                      onPressed: _handleGoToLibrary,
                      child: const Text(
                        "Go to Library",
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                    ),
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
