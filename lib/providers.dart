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
import 'services/offline_gutenberg_service.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

final bookRepositoryProvider = Provider<BookRepository>((ref) {
  return BookRepository(ref.read(databaseProvider));
});

final allBooksProvider = StreamProvider<List<Book>>((ref) {
  return ref.watch(bookRepositoryProvider).watchAllBooks();
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

final offlineGutenbergServiceProvider = Provider<OfflineGutenbergService>((
  ref,
) {
  return OfflineGutenbergService();
});

class NavigationIndexNotifier extends Notifier<int> {
  @override
  int build() {
    return 0;
  }

  void setIndex(int index) {
    state = index;
  }
}

final navigationIndexProvider = NotifierProvider<NavigationIndexNotifier, int>(
  NavigationIndexNotifier.new,
);

// Provides a map of local books keyed by "title|author" for fast lookup
// Used to link remote discover listings to local library copies.
final localBookMapProvider = Provider<Map<String, Book>>((ref) {
  final booksAsync = ref.watch(allBooksProvider);

  return booksAsync.maybeWhen(
    data: (books) {
      final map = <String, Book>{};
      for (final book in books) {
        // Normalize consistent with RemoteBookTile
        final String title = book.title
            .toLowerCase()
            .replaceAll(RegExp(r'[^\w\s]'), '')
            .trim();
        final String author = (book.author ?? '')
            .toLowerCase()
            .replaceAll(RegExp(r'[^\w\s]'), '')
            .trim();
        final key = '$title|$author';
        map[key] = book;
      }
      return map;
    },
    orElse: () => {},
  );
});
