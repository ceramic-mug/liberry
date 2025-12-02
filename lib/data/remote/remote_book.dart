class RemoteBook {
  final String title;
  final String author;
  final String? coverUrl;
  final String? downloadUrl;
  final String source; // 'Standard Ebooks' or 'Gutenberg'

  RemoteBook({
    required this.title,
    required this.author,
    this.coverUrl,
    this.downloadUrl,
    required this.source,
  });
}
