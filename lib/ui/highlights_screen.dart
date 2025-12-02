import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../data/database.dart';
import '../data/character_repository.dart';
import '../providers.dart';

class HighlightsScreen extends ConsumerStatefulWidget {
  const HighlightsScreen({super.key});

  @override
  ConsumerState<HighlightsScreen> createState() => _HighlightsScreenState();
}

class _HighlightsScreenState extends ConsumerState<HighlightsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    // We need a way to get all quotes.
    // Currently CharacterRepository has watchQuotesForCharacter.
    // We might need to add a method to watch ALL quotes or search them.
    // For now, let's assume we can get all quotes or we'll add the method.
    // Let's check CharacterRepository again.
    // It has searchCharacters but not searchQuotes.
    // We should probably add searchQuotes to CharacterRepository or a new QuoteRepository.
    // For this prototype, let's just list all quotes if possible, or mock it if we can't easily change repo yet.
    // Actually, I can modify the repo.

    // Let's assume we will add `watchAllQuotes` to CharacterRepository.
    final charRepo = ref.watch(characterRepositoryProvider);

    // Since we can't easily modify the repo in this single file write,
    // let's use a FutureBuilder with a direct DB query if possible,
    // or better, let's modify the repo in the next step.
    // For now, I'll write the UI code assuming the stream exists.

    return Scaffold(
      appBar: AppBar(title: const Text('Highlights')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search highlights & notes...',
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<List<QuoteWithBook>>(
              // We need a stream that joins Quotes with Books to get the title/author
              stream: charRepo.watchAllQuotesWithBooks(_searchQuery),
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
                      _searchQuery.isEmpty
                          ? 'No highlights yet.'
                          : 'No matches found.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: quotes.length,
                  itemBuilder: (context, index) {
                    final item = quotes[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
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
                                    fontSize: 16,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(
                                Icons.book,
                                size: 16,
                                color: Colors.grey,
                              ),
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
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
