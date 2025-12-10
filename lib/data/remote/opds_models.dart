import 'remote_book.dart';

enum OpdsEntryKind { navigation, acquisition }

abstract class OpdsEntry {
  final String title;
  final String id;

  const OpdsEntry({required this.title, required this.id});
}

class OpdsNavigationEntry extends OpdsEntry {
  final String content;
  final String link; // URL to the next feed
  final String? subtitle;
  final String? thumbnail;

  const OpdsNavigationEntry({
    required super.title,
    required super.id,
    required this.content,
    required this.link,
    this.subtitle,
    this.thumbnail,
  });
}

class OpdsAcquisitionEntry extends OpdsEntry {
  final String author;
  final String? summary;
  final String? coverUrl;
  final String? thumbnail;
  final String? epubUrl;
  final String? epubBestUrl; // 'advanced' or regular compatible epub

  const OpdsAcquisitionEntry({
    required super.title,
    required super.id,
    required this.author,
    this.summary,
    this.coverUrl,
    this.thumbnail,
    this.epubUrl,
    this.epubBestUrl,
  });

  RemoteBook toRemoteBook() {
    return RemoteBook(
      title: title,
      author: author,
      coverUrl: coverUrl ?? thumbnail,
      downloadUrl: epubBestUrl ?? epubUrl,
      source: 'Standard Ebooks',
    );
  }
}

class OpdsFeed {
  final String title;
  final List<OpdsEntry> entries;
  final String? nextLink;

  const OpdsFeed({required this.title, required this.entries, this.nextLink});
}
