import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/harvard_classics.dart';
import '../providers.dart';

class HarvardClassicsScreen extends StatelessWidget {
  final void Function(HarvardClassic) onSearch;

  const HarvardClassicsScreen({super.key, required this.onSearch});

  Map<String, List<HarvardClassic>> get _harvardClassicsByClassification {
    final Map<String, List<HarvardClassic>> grouped = {};
    for (var classic in HarvardClassicsData.classics) {
      if (!grouped.containsKey(classic.classification)) {
        grouped[classic.classification] = [];
      }
      grouped[classic.classification]!.add(classic);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Harvard Classics')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _buildSectionHeader(
            context,
            'Harvard Classics',
            'Dr. Eliot\'s Five-Foot Shelf of Books',
          ),
          ..._harvardClassicsByClassification.entries.map((classEntry) {
            final classification = classEntry.key;
            final classBooks = classEntry.value;

            // Group by category within this classification
            final Map<String, List<HarvardClassic>> booksByCategory = {};
            for (var c in classBooks) {
              if (!booksByCategory.containsKey(c.category)) {
                booksByCategory[c.category] = [];
              }
              booksByCategory[c.category]!.add(c);
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    classification,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ),
                ...booksByCategory.entries.map((catEntry) {
                  final category = catEntry.key;
                  final catBooks = catEntry.value;

                  // Group by topic (subcategory) within this category
                  final Map<String, List<HarvardClassic>> booksByTopic = {};
                  for (var c in catBooks) {
                    if (!booksByTopic.containsKey(c.topic)) {
                      booksByTopic[c.topic] = [];
                    }
                    booksByTopic[c.topic]!.add(c);
                  }

                  return ExpansionTile(
                    title: Text(category),
                    children: booksByTopic.entries.map((topicEntry) {
                      final topicTitle = topicEntry.key;
                      final topicBooks = topicEntry.value;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (topicTitle.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                              child: Text(
                                topicTitle,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ...topicBooks.map(
                            (classic) => _HarvardClassicTile(
                              classic: classic,
                              onSearch: onSearch,
                            ),
                          ),
                          const Divider(height: 1),
                        ],
                      );
                    }).toList(),
                  );
                }),
                const SizedBox(height: 16),
              ],
            );
          }),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    String subtitle,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0, top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
          const Divider(),
        ],
      ),
    );
  }
}

class _HarvardClassicTile extends ConsumerWidget {
  final HarvardClassic classic;
  final void Function(HarvardClassic) onSearch;

  const _HarvardClassicTile({required this.classic, required this.onSearch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<bool>(
      future: ref.read(bookRepositoryProvider).isBookDownloaded(classic.title),
      builder: (context, snapshot) {
        final isInLibrary = snapshot.data ?? false;

        return ListTile(
          title: Text(classic.title),
          subtitle: Text(classic.author),
          trailing: isInLibrary
              ? const Icon(Icons.check_circle, color: Colors.green)
              : const Icon(Icons.search),
          onTap: () {
            if (!isInLibrary) {
              onSearch(classic);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('You already have this book!')),
              );
            }
          },
        );
      },
    );
  }
}
