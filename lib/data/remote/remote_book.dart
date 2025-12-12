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

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'author': author,
      'coverUrl': coverUrl,
      'downloadUrl': downloadUrl,
      'source': source,
    };
  }

  factory RemoteBook.fromJson(Map<String, dynamic> json) {
    return RemoteBook(
      title: json['title'] as String,
      author: json['author'] as String,
      coverUrl: json['coverUrl'] as String?,
      downloadUrl: json['downloadUrl'] as String?,
      source: json['source'] as String,
    );
  }
}
