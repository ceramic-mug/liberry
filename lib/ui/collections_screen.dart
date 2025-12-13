import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/book_collections.dart';
import 'collection_details_screen.dart';

class CollectionsScreen extends ConsumerWidget {
  final void Function(CollectionBook) onSearch;

  const CollectionsScreen({super.key, required this.onSearch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Book Collections')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: BookCollectionsData.collections.map((collection) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: _buildCollectionCard(
              context,
              collection: collection,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CollectionDetailsScreen(
                      collection: collection,
                      onSearch: onSearch,
                    ),
                  ),
                );
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCollectionCard(
    BuildContext context, {
    required BookCollection collection,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.transparent
                      : collection.color.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Theme.of(context).brightness == Brightness.dark
                      ? Border.all(color: collection.color, width: 2)
                      : null,
                ),
                child: Icon(collection.icon, size: 32, color: collection.color),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      collection.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      collection.subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
