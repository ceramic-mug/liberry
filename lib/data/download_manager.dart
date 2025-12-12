import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'book_repository.dart';

class DownloadManager {
  final Dio _dio;
  final BookRepository _bookRepo;

  DownloadManager(this._dio, this._bookRepo);

  Future<String> downloadBook(
    String url,
    String title, {
    String? coverUrl,
  }) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final filename = '${const Uuid().v4()}.epub';
      final savePath = p.join(appDir.path, filename);

      await _dio.download(url, savePath);

      // Add to repository
      // FIX: Store only the filename (relative path) in DB to survive container UUID changes on iOS
      return await _bookRepo.addBook(
        filename,
        remoteCoverUrl: coverUrl,
        downloadUrl: url,
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> redownloadBook(String bookId) async {
    final book = await _bookRepo.getBook(bookId);
    if (book == null) throw Exception("Book not found");
    if (book.downloadUrl == null)
      throw Exception("No download URL for this book");

    final appDir = await getApplicationDocumentsDirectory();
    final filename = '${const Uuid().v4()}.epub';
    final savePath = p.join(appDir.path, filename);

    try {
      await _dio.download(book.downloadUrl!, savePath);

      // Update Book record
      await _bookRepo.updateBookFile(bookId, filename, true);
    } catch (e) {
      if (await File(savePath).exists()) {
        await File(savePath).delete();
      }
      rethrow;
    }
  }
}
