import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../data/character_repository.dart';
import 'widgets/highlight_details_sheet.dart';
import '../providers.dart';

class HighlightsTab extends ConsumerWidget {
  final String searchQuery;
  final String? bookId;
  final String? author;

  const HighlightsTab({
    super.key,
    required this.searchQuery,
    this.bookId,
    this.author,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final charRepo = ref.watch(characterRepositoryProvider);

    return StreamBuilder<List<QuoteWithBook>>(
      stream: charRepo.watchAllQuotesWithBooks(
        searchQuery,
        bookId: bookId,
        author: author,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final quotes = snapshot.data!;
        if (quotes.isEmpty) {
          return Center(
            child: Text(
              searchQuery.isEmpty ? 'No highlights yet.' : 'No matches found.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: quotes.length,
          itemBuilder: (context, index) {
            final item = quotes[index];
            return InkWell(
              onTap: () => _showHighlightDetails(context, ref, item),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 4,
                          height: 40,
                          color: Theme.of(
                            context,
                          ).primaryColor, // Highlight color
                          margin: const EdgeInsets.only(right: 12),
                        ),
                        Expanded(
                          child: Text(
                            '"${item.quote.textContent}"',
                            style: const TextStyle(
                              fontSize: 14, // Smaller font
                              // No italics
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.book, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.book.title,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          DateFormat.yMMMd().format(item.quote.createdAt),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showHighlightDetails(
    BuildContext context,
    WidgetRef ref,
    QuoteWithBook item,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) =>
          HighlightDetailsSheet(highlight: item.quote, book: item.book),
    );
  }
}
