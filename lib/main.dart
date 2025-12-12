import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ui/discover_screen.dart';
import 'ui/notes_screen.dart';
import 'ui/splash_screen.dart';
import 'ui/library_screen.dart';
import 'dart:io';
import 'data/sync/sync_service.dart';
import 'providers.dart';
import 'utils/ios_file_utils.dart';

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

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final List<Widget> _widgetOptions;

  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _widgetOptions = <Widget>[
      LibraryScreen(onNavigateToDiscover: () => _updateIndex(2)),
      const NotesScreen(),
      const DiscoverScreen(),
    ];

    _listener = AppLifecycleListener(
      onStateChange: _onStateChanged,
      onDetach: _runSync,
      onPause: _runSync,
    );

    // Initial Sync
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runSync(isStartup: true);
    });
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  void _onStateChanged(AppLifecycleState state) {
    // Handle specific state changes if needed
  }

  Future<void> _runSync({bool isStartup = false}) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final autoSync = prefs.getBool('auto_sync_enabled') ?? false;
    final syncPath = prefs.getString('sync_file_path');

    if (!autoSync || syncPath == null || syncPath.isEmpty) return;

    String? tempFilePath;
    String? bookmark;

    try {
      File syncFile;
      final syncService = ref.read(syncServiceProvider);

      // iOS: Use coordinated file access
      if (Platform.isIOS) {
        bookmark = prefs.getString('sync_file_bookmark_ios');
        if (bookmark == null) {
          debugPrint('Auto-sync: No iOS bookmark found, skipping.');
          return;
        }

        debugPrint('Auto-sync: iOS preparing coordinated read...');
        try {
          tempFilePath = await IosFileUtils.prepareSyncRead(bookmark);
        } catch (e) {
          debugPrint('Auto-sync: Failed to prepare iOS sync file: $e');
          return;
        }

        if (tempFilePath == null) {
          debugPrint('Auto-sync: iOS temp file path is null, skipping.');
          return;
        }
        syncFile = File(tempFilePath);
      } else {
        // Non-iOS: Direct file access
        if (!File(syncPath).existsSync()) {
          debugPrint('Auto-sync: File does not exist, skipping.');
          return;
        }
        syncFile = File(syncPath);
      }

      if (isStartup) {
        // Startup: Import only
        await syncService.importFromSyncFile(syncFile);
      } else {
        // On Close/Pause: Import then Export
        await syncService.importFromSyncFile(syncFile);
        await syncService.exportToSyncFile(syncFile);

        // iOS: Commit changes back to cloud
        if (Platform.isIOS && bookmark != null && tempFilePath != null) {
          debugPrint('Auto-sync: iOS committing coordinated write...');
          await IosFileUtils.commitSyncWrite(
            bookmarkBase64: bookmark,
            tempPath: tempFilePath,
          );
        }
      }

      final now = DateTime.now();
      await prefs.setString('last_sync_time', now.toIso8601String());
      debugPrint('Auto-sync completed at $now');
    } catch (e) {
      debugPrint('Auto-sync failed: $e');
    } finally {
      // iOS: Cleanup
      if (Platform.isIOS) {
        if (tempFilePath != null) {
          await IosFileUtils.cleanupSync(tempFilePath);
        }
        await IosFileUtils.stopAccess();
      }
    }
  }

  void _updateIndex(int index) {
    ref.read(navigationIndexProvider.notifier).setIndex(index);
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(navigationIndexProvider);

    return Scaffold(
      body: _widgetOptions.elementAt(selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed, // Needed for 4+ items
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.library_books),
            label: 'Library',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.sticky_note_2),
            label: 'Notes',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Discover'),
        ],
        currentIndex: selectedIndex,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        onTap: _updateIndex,
      ),
    );
  }
}
