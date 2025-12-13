import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:drift/drift.dart' show Value;
import '../data/database.dart';
import '../data/character_repository.dart';
import '../providers.dart';
import 'book_details_screen.dart';

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
                dense: true,
                title: Text(character.name),
                subtitle: Text(
                  '${item.book.title}\n${character.bio ?? 'No bio'}',
                ),
                leading: CircleAvatar(child: Text(character.name[0])),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CharacterDetailScreen(
                        character: character,
                        book: item.book,
                      ),
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

class CharacterDetailScreen extends ConsumerStatefulWidget {
  final Character character;
  final Book? book;

  const CharacterDetailScreen({super.key, required this.character, this.book});

  @override
  ConsumerState<CharacterDetailScreen> createState() =>
      _CharacterDetailScreenState();
}

class _CharacterDetailScreenState extends ConsumerState<CharacterDetailScreen> {
  bool _isEditing = false;
  late TextEditingController _nameController;
  late TextEditingController _bioController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.character.name);
    _bioController = TextEditingController(text: widget.character.bio);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) return;

    final updatedChar = widget.character.copyWith(
      name: newName,
      bio: Value(_bioController.text.trim()),
    );

    await ref.read(characterRepositoryProvider).updateCharacter(updatedChar);

    if (mounted) {
      setState(() {
        _isEditing = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Character updated')));
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Character'),
        content: const Text('Are you sure you want to delete this character?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref
          .read(characterRepositoryProvider)
          .deleteCharacter(widget.character.id);
      if (mounted) {
        Navigator.pop(context); // Go back to list
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final charRepo = ref.watch(characterRepositoryProvider);
    // Use widget.character.id to listen to updates.
    // However, if we update the character, 'widget.character' is stale.
    // We should ideally watch the single character stream or rely on parent updates if we pop.
    // But since we are editing in place, let's just use the stream for quotes,
    // and for the character details, we can watch a single character stream OR just assume
    // the parent list updates on pop. But to reflect changes immediately in non-edit mode:

    // Better yet, let's watch the character to show updated data.
    // But characterRepository.getCharacter returns a Future.
    // Let's rely on the fact we are updating the local state via controllers
    // and when we save, we might need to refresh or just assume the repository update triggers a rebuild if we were watching it.
    // Since we are not watching a stream of the single character here (only quotes),
    // let's wrap the body in a simpler FutureBuilder or just use the passed character
    // BUT since we stay on the screen after save, we should show the new values.
    // Actually, 'CharactersTab' passes a 'Character' object.
    // If we want reactive updates, we should probably watch the list in the parent.
    // For simplicity: We will rely on the fact that when we toggle _isEditing to false,
    // we show the text from the Controller (or we should update the widget.character?).
    // No, we can't update widget.character.
    // Let's just create a local view variable or fetch fresh data.
    // Using FutureBuilder for the character is generic.
    // Let's implement a 'watchCharacter' in repository if needed, or just use what we have.
    // We have watchQuotesForCharacter.
    // Let's add a simplified StreamBuilder for the character itself if we want 100% correctness,
    // or arguably just use the values from controllers when not editing if we just saved?
    // No, that's messy.
    // Let's assume the parent list rebuilds, but we are pushed on the stack.
    // The cleanest way:
    // We only need to show the updated name/bio after save.
    // let's use a FutureBuilder that we refresh on save?
    // Or simpler: update local state variables for display?
    // The controllers have the latest text. We can just use them for display!

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Character' : _nameController.text),
        actions: [
          if (_isEditing)
            IconButton(icon: const Icon(Icons.check), onPressed: _save)
          else
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') {
                  setState(() {
                    _isEditing = true;
                  });
                } else if (value == 'delete') {
                  _delete();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  child: Text(
                    _nameController.text.isNotEmpty
                        ? _nameController.text[0]
                        : '?',
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
                const SizedBox(height: 16),
                if (_isEditing) ...[
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _bioController,
                    decoration: const InputDecoration(
                      labelText: 'Bio',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                ] else ...[
                  if (widget.book != null) ...[
                    InkWell(
                      onTap: () {
                        // Navigate to book details
                        // We need the book object.
                        // Assuming 'BookDetailsScreen' constructor takes a Book.
                        // We need to import 'book_details_screen.dart'.
                        // But wait, we don't have that import in this file yet.
                        // I will add it via a separate edit or assume it's available?
                        // It is NOT available. I need to add import.
                        // For now I'll generate the code assuming I'll add the import.
                        // Actually I can try to use named route or just add the import in a previous step?
                        // No, I'll add the import in a multi-step.
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                BookDetailsScreen(book: widget.book!),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8.0,
                          horizontal: 12.0,
                        ),
                        child: Text(
                          widget.book!.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    _bioController.text.isNotEmpty
                        ? _bioController.text
                        : 'No bio',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: StreamBuilder<List<Quote>>(
              stream: charRepo.watchQuotesForCharacter(widget.character.id),
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
          _showAddQuoteDialog(context, ref, widget.character.id);
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
