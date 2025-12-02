import 'dart:io';
import 'package:epubx/epubx.dart';
import 'package:path/path.dart' as p;

class EpubService {
  EpubBook? _epubBook;

  Future<void> loadBook(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    _epubBook = await EpubReader.readBook(bytes);
  }

  EpubBook? get book => _epubBook;

  List<EpubChapter> getChapters() {
    return _epubBook?.Chapters ?? [];
  }

  // Helper to flatten chapters if needed
  List<EpubChapter> getAllChapters() {
    final List<EpubChapter> allChapters = [];
    void addChapters(List<EpubChapter> chapters) {
      for (var chapter in chapters) {
        allChapters.add(chapter);
        if (chapter.SubChapters != null && chapter.SubChapters!.isNotEmpty) {
          addChapters(chapter.SubChapters!);
        }
      }
    }

    if (_epubBook?.Chapters != null) {
      addChapters(_epubBook!.Chapters!);
    }
    return allChapters;
  }

  String? getChapterContent(EpubChapter chapter) {
    return chapter.HtmlContent;
  }
}
