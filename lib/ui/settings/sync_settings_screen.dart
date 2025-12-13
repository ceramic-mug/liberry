import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liberry/data/sync/sync_service.dart';
import 'package:liberry/providers.dart';
import 'package:liberry/utils/ios_file_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class SyncSettingsScreen extends ConsumerStatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  ConsumerState<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends ConsumerState<SyncSettingsScreen> {
  static const String _prefSyncPath = 'sync_file_path';

  static const String _prefLastSync = 'last_sync_time';

  String? _syncFilePath;
  bool _autoSyncEnabled = false;

  DateTime? _lastSyncTime;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = ref.read(sharedPreferencesProvider);
    setState(() {
      _syncFilePath = prefs.getString(_prefSyncPath);
      _autoSyncEnabled = prefs.getBool(SyncService.prefAutoSync) ?? false;

      final lastSyncStr = prefs.getString(_prefLastSync);
      _lastSyncTime = lastSyncStr != null
          ? DateTime.tryParse(lastSyncStr)
          : null;
    });
  }

  Future<void> _selectSyncFile() async {
    // Pick a file. We might want to pick a writable location or a file.
    // FilePicker 'any' or custom extension.
    try {
      // Pick a directory is safer for "Create New", but pick file for "Existing".
      // Let's offer "Select Sync File" (picker).
      if (Platform.isIOS) {
        final resultMap = await IosFileUtils.pickSyncFile();
        if (resultMap != null) {
          final path = resultMap['path'];
          final bookmark = resultMap['bookmark'];
          if (path != null && bookmark != null) {
            await _updateSyncPath(path);
            final prefs = ref.read(sharedPreferencesProvider);
            await prefs.setString('sync_file_bookmark_ios', bookmark);
          }
        }
      } else {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          dialogTitle: 'Select Sync File',
          type: FileType.any,
          onFileLoading: (FilePickerStatus status) {
            if (status == FilePickerStatus.picking) {
              setState(() {
                _isLoading = true;
              });
            } else {
              setState(() {
                _isLoading = false;
              });
            }
          },
        );

        if (result != null && result.files.single.path != null) {
          final path = result.files.single.path!;
          await _updateSyncPath(path);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error picking file: $e')));
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _createSyncFile() async {
    // 1. Create a temp file
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/liberry.sync');

    setState(() {
      _isLoading = true;
    });

    try {
      // 2. Export current state to this temp file (initializing it)
      final syncService = ref.read(syncServiceProvider);
      // Ensure we export at least the schema, effectively creating the file.
      // If we have data, it will be exported.
      await syncService.exportToSyncFile(tempFile);

      setState(() {
        _isLoading = false;
      });

      // 3. Share the file so user can save it (Drive, Files, etc.)
      // We explicitly DO NOT provide text/subject to avoid creating extra text files in some targets (like Drive)
      final result = await Share.shareXFiles([XFile(tempFile.path)]);
      if (result.status == ShareResultStatus.dismissed) {
        return;
      }

      // 4. Prompt user to link it
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('File Saved?'),
            content: const Text(
              'If you successfully saved the file, please select it to enable syncing.\n\n'
              '⚠️ For cloud services (Google Drive, iCloud, Dropbox):\n'
              'Wait a few seconds for the file to appear, then select it from the same location where you saved it.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Later'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _selectSyncFile();
                },
                child: const Text('Select File Now'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error creating sync file: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateSyncPath(String path) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_prefSyncPath, path);
    setState(() {
      _syncFilePath = path;
    });
  }

  Future<void> _toggleAutoSync(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(SyncService.prefAutoSync, value);
    setState(() {
      _autoSyncEnabled = value;
    });

    if (value && _syncFilePath != null) {
      // Trigger a sync immediately when enabled
      _performSync();
    }
  }

  Future<void> _performSync() async {
    if (_syncFilePath == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final syncService = ref.read(syncServiceProvider);

      await syncService.performSync(prefs);

      final now = DateTime.now();
      await prefs.setString(_prefLastSync, now.toIso8601String());

      setState(() {
        _lastSyncTime = now;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sync completed successfully.')),
        );
      }
    } catch (e) {
      debugPrint('Sync Exception: $e');
      if (mounted) {
        if (e is PlatformException && e.code == 'BOOKMARK_STALE') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Sync file access lost. Please re-select the file.',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Syncing Guide'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Syncing allows you to keep your reading progress, highlights, and notes consistent across all your devices.',
              ),
              SizedBox(height: 16),
              Text(
                'Step 1: Save a Sync File',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Create or select a file (e.g., "library.booksync") in a folder that is synced to the cloud.',
              ),
              SizedBox(height: 8),
              Text(
                'Note for iOS: We strongly recommend using iCloud Drive. Other providers (Google Drive, Dropbox) may not support direct file syncing due to system restrictions.',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 13,
                  color: Colors.amber,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Step 2: Connect Other Devices',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'On your other devices, select the SAME file from that cloud folder.',
              ),
              SizedBox(height: 12),
              Text(
                'Conflict Resolution',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'The most recent change (based on time) wins. Always ensure your device time is correct.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showHelpDialog,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: const Text('Select Sync File'),
            subtitle: Text(
              _syncFilePath != null
                  ? 'Sync file is set'
                  : 'Select file to sync or restore from',
            ),
            trailing: _syncFilePath != null
                ? const Icon(Icons.check, color: Colors.green)
                : const Icon(Icons.folder_open),
            onTap: _selectSyncFile,
          ),
          ListTile(
            title: const Text('Create New Sync File'),
            subtitle: const Text('Start fresh or export current library'),
            trailing: const Icon(Icons.add),
            onTap: _createSyncFile,
          ),

          const Divider(),
          const SizedBox(height: 24),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            ElevatedButton.icon(
              onPressed: _syncFilePath != null ? _performSync : null,
              icon: const Icon(Icons.sync),
              label: const Text('Sync Now'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          SwitchListTile(
            title: const Text('Automatic Sync'),
            subtitle: const Text('Sync on open, close, and periodically'),
            value: _autoSyncEnabled,
            onChanged: _toggleAutoSync,
          ),
          if (_lastSyncTime != null)
            Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: Center(
                child: Text(
                  'Last synced: ${_lastSyncTime!.toLocal()}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          const SizedBox(height: 24),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: ExpansionTile(
              leading: Icon(
                Icons.info_outline,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text(
                'How Syncing Works',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              children: const [
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '(1) Create new sync file (one time!) that’s accessible across devices (for example, in a cloud storage provider like iCloud Drive, Google Drive, OneDrive, etc.).\n\n'
                        '(2) Select this file as your sync file on each device.\n\n'
                        '(3) Sync and enjoy!',
                        style: TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
