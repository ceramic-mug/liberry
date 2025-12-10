import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'book_repository.dart';

class DownloadManager {
  final Dio _dio;
  final BookRepository _bookRepo;

  DownloadManager(this._dio, this._bookRepo);

  Future<void> downloadBook(
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
      await _bookRepo.addBook(filename, remoteCoverUrl: coverUrl);
    } catch (e) {
      rethrow;
    }
  }
}
