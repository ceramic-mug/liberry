import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'data/database.dart';
import 'data/reader_settings_repository.dart';
import 'providers.dart';
import 'ui/character_library.dart';
import 'ui/discover_screen.dart';
import 'ui/book_details_screen.dart';
import 'ui/highlights_screen.dart';
import 'ui/splash_screen.dart';
import 'package:flutter_svg/flutter_svg.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Liberry',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFD9534F)),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  late final List<Widget> _widgetOptions;

  @override
  void initState() {
    super.initState();
    _widgetOptions = <Widget>[
      LibraryScreen(onNavigateToDiscover: () => _onItemTapped(3)),
      const CharacterLibraryScreen(),
      const HighlightsScreen(),
      const DiscoverScreen(),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _widgetOptions.elementAt(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed, // Needed for 4+ items
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.library_books),
            label: 'Library',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Characters',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.highlight),
            label: 'Highlights',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Discover'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        onTap: _onItemTapped,
      ),
    );
  }
}

class LibraryScreen extends ConsumerWidget {
  final VoidCallback onNavigateToDiscover;

  const LibraryScreen({super.key, required this.onNavigateToDiscover});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookRepo = ref.watch(bookRepositoryProvider);
    final booksStream = bookRepo.watchAllBooks();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            SvgPicture.asset('assets/icon.svg', height: 24),
            const SizedBox(width: 8),
            const Text('Library'),
          ],
        ),
        centerTitle: false,
        titleSpacing: 16,
      ),
      body: StreamBuilder<List<Book>>(
        stream: booksStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final books = snapshot.data!;
          if (books.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No books yet.'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: onNavigateToDiscover,
                    child: const Text('Discover Books'),
                  ),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.55, // Taller to accommodate 2:3 covers + text
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: books.length,
            itemBuilder: (context, index) {
              final book = books[index];
              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => BookDetailsScreen(book: book),
                    ),
                  );
                },
                onLongPress: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete Book'),
                      content: Text(
                        'Are you sure you want to delete "${book.title}"?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            await bookRepo.deleteBook(book.id);
                          },
                          child: const Text(
                            'Delete',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: FutureBuilder<File?>(
                          future: _resolveCoverPath(book.coverPath),
                          builder: (context, snapshot) {
                            if (snapshot.hasData && snapshot.data != null) {
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  snapshot.data!,
                                  fit: BoxFit
                                      .fill, // Fill the container (no cropping)
                                  width: double.infinity,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Center(
                                        child: Icon(Icons.book, size: 40),
                                      ),
                                ),
                              );
                            }
                            return const Center(
                              child: Icon(Icons.book, size: 40),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (book.author != null)
                      Text(
                        book.author!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: onNavigateToDiscover,
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<File?> _resolveCoverPath(String? path) async {
    if (path == null) {
      print('Cover path is null');
      return null;
    }

    // Check if it's an absolute path (legacy)
    final file = File(path);
    if (await file.exists()) {
      print('Found absolute cover: $path');
      return file;
    }

    try {
      final docsDir = await getApplicationDocumentsDirectory();

      // If path is relative (e.g. "covers/uuid.png"), join it
      if (!p.isAbsolute(path)) {
        final fullPath = p.join(docsDir.path, path);
        final fullFile = File(fullPath);
        if (await fullFile.exists()) {
          print('Found relative cover: $fullPath');
          return fullFile;
        } else {
          print('Relative cover not found: $fullPath');
        }
      }

      // Fallback: try to find by basename in covers dir
      final filename = p.basename(path);
      final newPath = p.join(docsDir.path, 'covers', filename);
      final newFile = File(newPath);
      if (await newFile.exists()) {
        print('Found fallback cover: $newPath');
        return newFile;
      }
    } catch (e) {
      print('Error resolving cover: $e');
    }
    return null;
  }
}
