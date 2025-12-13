import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ui/discover_screen.dart';
import 'ui/notes_screen.dart';
import 'ui/splash_screen.dart';
import 'ui/library_screen.dart';
import 'dart:async';
import 'package:liberry/data/sync/sync_service.dart';
import 'providers.dart';

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

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Liberry',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFD9534F)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD9534F),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: themeMode,
      home: const SplashScreen(),
      builder: (context, child) => GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child,
      ),
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
  Timer? _periodicSyncTimer;

  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _widgetOptions = <Widget>[
      LibraryScreen(onNavigateToDiscover: () => _updateIndex(2)),
      const NotesScreen(),
      const DiscoverScreen(),
    ];

    _listener = AppLifecycleListener(onStateChange: _onStateChanged);

    // Initialize Auto Sync
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupAutoSync();
    });
  }

  Future<void> _setupAutoSync() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final enabled = prefs.getBool(SyncService.prefAutoSync) ?? false;

    // Always start periodic timer, check enabled status inside.
    // This handles if user enables it later (though we might want to restart timer then).
    // Better: if enabled, start timer. If not, ensure stopped.
    // For simplicity, we just check inside the timer.
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      final currentEnabled = prefs.getBool(SyncService.prefAutoSync) ?? false;
      if (currentEnabled) {
        _performSilentSync(prefs);
      }
    });

    if (enabled) {
      await _performInitialSync(prefs);
    }
  }

  Future<void> _performInitialSync(SharedPreferences prefs) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Syncing...'),
        duration: Duration(seconds: 1),
      ),
    );

    try {
      await ref.read(syncServiceProvider).performSyncWithRetry(prefs);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sync complete'),
            duration: Duration(seconds: 2),
            showCloseIcon: true,
          ),
        );
      }
    } catch (e) {
      debugPrint('Initial sync failed after retries: $e');
      // Optional: Show error
    }
  }

  Future<void> _performSilentSync(SharedPreferences prefs) async {
    try {
      await ref.read(syncServiceProvider).performSync(prefs);
    } catch (e) {
      debugPrint('Silent sync failed: $e');
    }
  }

  @override
  void dispose() {
    _periodicSyncTimer?.cancel();
    _listener.dispose();
    super.dispose();
  }

  void _onStateChanged(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      final prefs = ref.read(sharedPreferencesProvider);
      final enabled = prefs.getBool(SyncService.prefAutoSync) ?? false;
      if (enabled) {
        _performSilentSync(prefs);
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
