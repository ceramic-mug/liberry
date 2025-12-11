import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../data/database.dart';
import '../providers.dart';
import 'highlights_screen.dart';

class BookJournalScreen extends ConsumerStatefulWidget {
  final String bookId;
  final String bookTitle;
  final int initialTab;

  const BookJournalScreen({
    super.key,
    required this.bookId,
    required this.bookTitle,
    this.initialTab = 0,
  });

  @override
  ConsumerState<BookJournalScreen> createState() => _BookJournalScreenState();
}

class _BookJournalScreenState extends ConsumerState<BookJournalScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _noteController = TextEditingController();
  bool _isAdding = false;
  String? _editingNoteId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _submitNote() {
    final content = _noteController.text.trim();
    if (content.isEmpty) return;

    if (_editingNoteId != null) {
      ref.read(bookRepositoryProvider).updateNote(_editingNoteId!, content);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Note updated')));
    } else {
      ref.read(bookRepositoryProvider).addNote(widget.bookId, content);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Note added')));
    }

    setState(() {
      _isAdding = false;
      _editingNoteId = null;
      _noteController.clear();
    });
  }

  void _startEdit(BookNote note) {
    setState(() {
      _isAdding = true;
      _editingNoteId = note.id;
      _noteController.text = note.content;
    });
  }

  void _deleteNote(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Note'),
        content: const Text('Are you sure you want to delete this note?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(bookRepositoryProvider).deleteNote(id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookTitle),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Journal'),
            Tab(text: 'Highlights'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildJournalTab(),
          HighlightsTab(searchQuery: '', bookId: widget.bookId),
        ],
      ),
      floatingActionButton: _tabController.index == 0 && !_isAdding
          ? FloatingActionButton(
              onPressed: () {
                if (_tabController.index == 0) {
                  setState(() => _isAdding = true);
                }
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _buildJournalTab() {
    final notesStream = ref
        .watch(bookRepositoryProvider)
        .watchNotesForBook(widget.bookId);

    return Column(
      children: [
        if (_isAdding)
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).cardColor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _editingNoteId != null ? 'Edit Entry' : 'New Entry',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _noteController,
                  maxLines: 5,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Write your thoughts...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isAdding = false;
                          _editingNoteId = null;
                          _noteController.clear();
                        });
                      },
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _submitNote,
                      child: Text(_editingNoteId != null ? 'Save' : 'Add'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        Expanded(
          child: StreamBuilder<List<BookNote>>(
            stream: notesStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final notes = snapshot.data!;

              if (notes.isEmpty && !_isAdding) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.history_edu,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No journal entries yet.',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => setState(() => _isAdding = true),
                        icon: const Icon(Icons.add),
                        label: const Text('Start Journaling'),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: notes.length,
                itemBuilder: (context, index) {
                  final note = notes[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                DateFormat.yMMMd().add_jm().format(
                                  note.createdAt,
                                ),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: Colors.grey),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 20),
                                    onPressed: () => _startEdit(note),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      size: 20,
                                      color: Colors.red,
                                    ),
                                    onPressed: () => _deleteNote(note.id),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Divider(),
                          Text(
                            note.content,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
