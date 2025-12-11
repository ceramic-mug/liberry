import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'data/database.dart';
import 'data/book_repository.dart';
import 'data/character_repository.dart';
import 'data/remote/opds_service.dart';
import 'data/remote/local_ebooks_service.dart';
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
  final service = OpdsService(ref.read(dioProvider));
  // Credentials removed as we are migrating to offline DB
  return service;
});

final localEbooksServiceProvider = Provider<LocalEbooksService>((ref) {
  return LocalEbooksService();
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
