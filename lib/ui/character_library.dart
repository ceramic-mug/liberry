import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../data/database.dart';
import '../data/character_repository.dart';
import '../providers.dart';

class CharactersTab extends ConsumerWidget {
  final String searchQuery;
  final String? bookId;
  final String? author;

  const CharactersTab({
    super.key,
    required this.searchQuery,
    this.bookId,
    this.author,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final charRepo = ref.watch(characterRepositoryProvider);
    final charactersStream = charRepo.watchCharactersWithFilteredBooks(
      searchQuery,
      bookId: bookId,
      author: author,
    );

    return StreamBuilder<List<CharacterWithBook>>(
      stream: charactersStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!;
        if (data.isEmpty) {
          return const Center(child: Text('No characters found.'));
        }

        return Scaffold(
          body: ListView.builder(
            itemCount: data.length,
            itemBuilder: (context, index) {
              final item = data[index];
              final character = item.character;
              return ListTile(
                title: Text(character.name),
                subtitle: Text(character.bio ?? 'No bio'),
                leading: CircleAvatar(child: Text(character.name[0])),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          CharacterDetailScreen(character: character),
                    ),
                  );
                },
              );
            },
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              _showAddCharacterDialog(context, ref);
            },
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  void _showAddCharacterDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final bioController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Character'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: bioController,
                decoration: const InputDecoration(labelText: 'Bio'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final name = nameController.text;
                if (name.isNotEmpty) {
                  // Hack: Just use a placeholder book ID for now if no books.
                  final bookRepo = ref.read(bookRepositoryProvider);
                  final books = await bookRepo.watchAllBooks().first;

                  String bookId;
                  if (books.isNotEmpty) {
                    bookId = books.first.id;
                  } else {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Add a book first!')),
                    );
                    return;
                  }

                  if (!context.mounted) return;

                  await ref
                      .read(characterRepositoryProvider)
                      .createCharacter(
                        name: name,
                        originBookId: bookId,
                        bio: bioController.text,
                      );
                  if (context.mounted) Navigator.pop(context);
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }
}

class CharacterDetailScreen extends ConsumerWidget {
  final Character character;

  const CharacterDetailScreen({super.key, required this.character});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final charRepo = ref.watch(characterRepositoryProvider);
    final quotesStream = charRepo.watchQuotesForCharacter(character.id);

    return Scaffold(
      appBar: AppBar(title: Text(character.name)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  child: Text(
                    character.name[0],
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  character.bio ?? 'No bio',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: StreamBuilder<List<Quote>>(
              stream: quotesStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final quotes = snapshot.data!;
                if (quotes.isEmpty) {
                  return const Center(child: Text('No quotes yet.'));
                }

                return ListView.builder(
                  itemCount: quotes.length,
                  itemBuilder: (context, index) {
                    final quote = quotes[index];
                    return Card(
                      margin: const EdgeInsets.all(8.0),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          quote.textContent,
                          style: const TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showAddQuoteDialog(context, ref, character.id);
        },
        child: const Icon(Icons.format_quote),
      ),
    );
  }

  void _showAddQuoteDialog(
    BuildContext context,
    WidgetRef ref,
    String characterId,
  ) {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Quote'),
          content: TextField(
            controller: textController,
            decoration: const InputDecoration(labelText: 'Quote'),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                if (textController.text.isNotEmpty) {
                  final char = await ref
                      .read(characterRepositoryProvider)
                      .getCharacter(characterId);
                  final bookId =
                      char?.originBookId ??
                      'unknown'; // Should not be null if FK holds

                  await ref
                      .read(characterRepositoryProvider)
                      .addQuote(
                        text: textController.text,
                        bookId: bookId,
                        characterId: characterId,
                      );
                  if (context.mounted) Navigator.pop(context);
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }
}
