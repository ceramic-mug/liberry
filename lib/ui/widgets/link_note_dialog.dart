import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../data/book_repository.dart';
import '../../data/database.dart';
import '../../providers.dart';

class LinkNoteDialog extends ConsumerStatefulWidget {
  final String bookId;
  final Quote? highlight; // If linking to a note, this is the source highlight
  final BookNote? note; // If linking to a highlight, this is the source note

  const LinkNoteDialog({
    super.key,
    required this.bookId,
    this.highlight,
    this.note,
  }) : assert(highlight != null || note != null);

  @override
  ConsumerState<LinkNoteDialog> createState() => _LinkNoteDialogState();
}

class _LinkNoteDialogState extends ConsumerState<LinkNoteDialog> {
  String? _selectedId;

  // For creating a new note
  final TextEditingController _noteContentController = TextEditingController();
  bool _isCreatingNew = false;

  @override
  void dispose() {
    _noteContentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLinkingToJournal = widget.highlight != null;
    final title = isLinkingToJournal
        ? 'Link to Journal Entry'
        : 'Link to Highlight';

    return Dialog(
      child: Container(
        width: 400,
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (isLinkingToJournal) ...[
              // If linking to journal, offer "Create New" or "Select Existing"
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('Existing'),
                          icon: Icon(Icons.list),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('New Entry'),
                          icon: Icon(Icons.add),
                        ),
                      ],
                      selected: {_isCreatingNew},
                      onSelectionChanged: (Set<bool> newSelection) {
                        setState(() {
                          _isCreatingNew = newSelection.first;
                          _selectedId = null;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            Expanded(
              child: _isCreatingNew
                  ? TextField(
                      controller: _noteContentController,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        hintText: 'Write your journal entry here...',
                        border: OutlineInputBorder(),
                      ),
                    )
                  : _buildList(isLinkingToJournal),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed:
                      (_selectedId == null && !_isCreatingNew) &&
                          !(_isCreatingNew &&
                              _noteContentController.text.isNotEmpty)
                      ? null
                      : () async {
                          final repo = ref.read(bookRepositoryProvider);
                          if (isLinkingToJournal) {
                            if (_isCreatingNew) {
                              // Create new note linked to highlight
                              await repo.addBookNote(
                                widget.bookId,
                                _noteContentController.text,
                                quoteId: widget.highlight!.id,
                              );
                            } else if (_selectedId != null) {
                              // Link existing note to highlight
                              await repo.updateNoteQuote(
                                _selectedId!,
                                widget.highlight!.id,
                              );
                            }
                          } else {
                            // Link existing highlight to note
                            // We are coming from a note, and _selectedId is a quoteId
                            if (_selectedId != null) {
                              await repo.updateNoteQuote(
                                widget.note!.id,
                                _selectedId!,
                              );
                            }
                          }
                          if (mounted) Navigator.pop(context);
                        },
                  child: const Text('Link'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(bool isLinkingToJournal) {
    if (isLinkingToJournal) {
      // List existing notes
      return StreamBuilder<List<BookNote>>(
        stream: ref
            .watch(bookRepositoryProvider)
            .watchNotesForBook(widget.bookId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final notes = snapshot.data!;
          if (notes.isEmpty) {
            return const Center(child: Text('No existing journal entries.'));
          }
          return ListView.builder(
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              final isSelected = _selectedId == note.id;
              final isAlreadyLinked = note.quoteId != null;

              // Optionally we can show if it's already linked

              return ListTile(
                title: Text(
                  note.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(DateFormat.yMMMd().format(note.createdAt)),
                selected: isSelected,
                trailing: isAlreadyLinked
                    ? const Icon(Icons.link, size: 16)
                    : null,
                onTap: () {
                  setState(() {
                    _selectedId = note.id;
                  });
                },
              );
            },
          );
        },
      );
    } else {
      // List existing highlights
      return StreamBuilder<List<Quote>>(
        stream: ref
            .watch(bookRepositoryProvider)
            .watchHighlightsForBook(widget.bookId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final quotes = snapshot.data!;
          if (quotes.isEmpty) {
            return const Center(child: Text('No highlights found.'));
          }
          return ListView.builder(
            itemCount: quotes.length,
            itemBuilder: (context, index) {
              final quote = quotes[index];
              final isSelected = _selectedId == quote.id;

              return ListTile(
                title: Text(
                  quote.textContent,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(DateFormat.yMMMd().format(quote.createdAt)),
                selected: isSelected,
                onTap: () {
                  setState(() {
                    _selectedId = quote.id;
                  });
                },
              );
            },
          );
        },
      );
    }
  }
}
