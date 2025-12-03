import 'dart:io';
import 'package:epubx/epubx.dart';

class EpubService {
  EpubBookRef? _epubBook;

  Future<void> loadBook(String filePath) async {
    print('EpubService: Loading book from $filePath');
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    print('EpubService: Read ${bytes.length} bytes');
    _epubBook = await EpubReader.openBook(bytes);
    print('EpubService: Book opened successfully. Title: ${_epubBook?.Title}');
  }

  EpubBookRef? get book => _epubBook;

  Future<List<EpubChapterRef>> getChapters() async {
    print('EpubService: Fetching chapters...');
    final chapters = await _epubBook?.getChapters() ?? [];
    print('EpubService: Fetched ${chapters.length} top-level chapters');
    return chapters;
  }

  // Helper to flatten chapters if needed
  Future<List<EpubChapterRef>> getAllChapters() async {
    print('EpubService: Getting all chapters (flattened)...');
    final List<EpubChapterRef> allChapters = [];

    // Recursive helper
    void addChapters(List<EpubChapterRef> chapters) {
      for (var chapter in chapters) {
        allChapters.add(chapter);
        if (chapter.SubChapters != null && chapter.SubChapters!.isNotEmpty) {
          addChapters(chapter.SubChapters!);
        }
      }
    }

    final chapters = await _epubBook?.getChapters();
    if (chapters != null) {
      addChapters(chapters);
    }
    print('EpubService: Total flattened chapters: ${allChapters.length}');
    return allChapters;
  }

  Future<String?> getChapterContent(EpubChapterRef chapter) async {
    print('EpubService: Reading content for chapter: ${chapter.Title}');
    return await chapter.readHtmlContent();
  }
}
