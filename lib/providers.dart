import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'data/database.dart';
import 'data/book_repository.dart';
import 'data/character_repository.dart';
import 'data/remote/opds_service.dart';
import 'data/remote/gutendex_service.dart';
import 'data/download_manager.dart';
import 'services/epub_service.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

final bookRepositoryProvider = Provider<BookRepository>((ref) {
  return BookRepository(ref.read(databaseProvider));
});

final characterRepositoryProvider = Provider<CharacterRepository>((ref) {
  return CharacterRepository(ref.read(databaseProvider));
});

final dioProvider = Provider<Dio>((ref) {
  return Dio();
});

final opdsServiceProvider = Provider<OpdsService>((ref) {
  return OpdsService(ref.read(dioProvider));
});

final gutendexServiceProvider = Provider<GutendexService>((ref) {
  return GutendexService(ref.read(dioProvider));
});

final downloadManagerProvider = Provider<DownloadManager>((ref) {
  return DownloadManager(
    ref.read(dioProvider),
    ref.read(bookRepositoryProvider),
  );
});

final epubServiceProvider = Provider<EpubService>((ref) {
  return EpubService();
});
