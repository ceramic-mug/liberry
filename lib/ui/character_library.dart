import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../data/database.dart';
import '../providers.dart';

class CharacterLibraryScreen extends ConsumerWidget {
  const CharacterLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final charRepo = ref.watch(characterRepositoryProvider);
    final charactersStream = charRepo.watchAllCharacters();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            SvgPicture.asset('assets/icon.svg', height: 24),
            const SizedBox(width: 8),
            const Text('Characters'),
          ],
        ),
      ),
      body: StreamBuilder<List<Character>>(
        stream: charactersStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final characters = snapshot.data!;
          if (characters.isEmpty) {
            return const Center(child: Text('No characters yet.'));
          }

          return ListView.builder(
            itemCount: characters.length,
            itemBuilder: (context, index) {
              final character = characters[index];
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
  }

  void _showAddCharacterDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    final bioController = TextEditingController();

    // For now, we need a book ID. Let's just pick the first book or ask user.
    // To keep it simple for MVP, we'll fetch books and let user pick or auto-pick.
    // Actually, let's just use a dummy ID or fetch books.

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
                  // Ideally we select a book.
                  // Let's fetch books first in the dialog or parent.
                  // For speed, let's just pass "unknown" or handle it.
                  // But FK constraint might fail if "unknown" doesn't exist.
                  // We need a valid book ID.

                  // Let's get the first book from repo.
                  final bookRepo = ref.read(bookRepositoryProvider);
                  final books = await bookRepo.watchAllBooks().first;

                  String bookId;
                  if (books.isNotEmpty) {
                    bookId = books.first.id;
                  } else {
                    // Create a dummy book or error?
                    // Let's just return for now.
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
                  // We need a book ID. Ideally we know which book the user was just reading.
                  // For now, let's pick the first book or "unknown".
                  // A better way: Store "last read book" in a provider.
                  // For MVP, let's just fetch the first book again or use the character's origin book.
                  // Let's use character's origin book for now as a default.

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
