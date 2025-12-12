import 'dart:convert';
import 'package:flutter/material.dart';
import '../../data/remote/remote_book.dart';
import '../../data/database.dart';
import '../download_splash_screen.dart';
import '../book_details_screen.dart';

class RemoteBookTile extends StatelessWidget {
  final RemoteBook book;
  final bool isStandardEbook;
  final Map<String, Book>? localBookMap;

  const RemoteBookTile({
    super.key,
    required this.book,
    required this.isStandardEbook,
    this.localBookMap,
  });

  String _normalize(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
  }

  @override
  Widget build(BuildContext context) {
    // Check if book matches any local book
    final key = '${_normalize(book.title)}|${_normalize(book.author)}';
    final existingLocalBook = localBookMap?[key];
    final isDownloaded = existingLocalBook != null;

    Widget imageWidget;
    if (book.coverUrl != null) {
      if (book.coverUrl!.startsWith('data:')) {
        try {
          final base64String = book.coverUrl!.split(',').last;
          final bytes = base64Decode(base64String);
          imageWidget = Image.memory(
            bytes,
            width: 50,
            height: 75,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildPlaceholder(),
          );
        } catch (e) {
          imageWidget = _buildPlaceholder();
        }
      } else {
        imageWidget = Image.network(
          book.coverUrl!,
          width: 50,
          height: 75,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildPlaceholder(),
        );
      }
    } else {
      imageWidget = _buildPlaceholder();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      child: InkWell(
        onTap: () {
          if (isDownloaded) {
            // Open Local Book Details
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) =>
                    BookDetailsScreen(book: existingLocalBook),
              ),
            );
          } else {
            // Preview mode (autoStartDownload: false)
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) =>
                    DownloadSplashScreen(book: book, autoStartDownload: false),
                fullscreenDialog: true,
              ),
            );
          }
        },
        child: ListTile(
          contentPadding: const EdgeInsets.all(8),
          title: Text(
            book.title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(book.author),
              if (isStandardEbook)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Standard Ebooks',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
            ],
          ),
          leading: Hero(
            tag: 'cover_${book.title}_${book.author}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: imageWidget,
            ),
          ),
          trailing: isDownloaded
              ? Icon(
                  Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary,
                )
              : (book.downloadUrl != null
                    ? IconButton(
                        icon: const Icon(Icons.download),
                        onPressed: () {
                          // Download mode (autoStartDownload: true)
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => DownloadSplashScreen(
                                book: book,
                                autoStartDownload: true,
                              ),
                              fullscreenDialog: true,
                            ),
                          );
                        },
                      )
                    : null),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 50,
      height: 75,
      color: Colors.grey,
      child: const Icon(Icons.book),
    );
  }
}
