import 'dart:io';
import 'package:flutter/services.dart';

/// Utility class for iOS-specific file operations using Security Scoped Resources
/// and NSFileCoordinator for cloud file access.
class IosFileUtils {
  static const MethodChannel _channel = MethodChannel('com.liberry.app/sync');

  /// Opens the iOS file picker in "Open" mode (UIDocumentPickerModeOpen).
  /// Returns a map with 'path' (display path) and 'bookmark' (base64) if successful.
  /// The bookmark should be stored and used for future access.
  static Future<Map<String, String>?> pickSyncFile() async {
    if (!Platform.isIOS) return null;
    try {
      final result = await _channel.invokeMethod('pickSyncFile');
      if (result != null && result is Map) {
        return Map<String, String>.from(result);
      }
    } catch (e) {
      print('Error picking sync file: $e');
    }
    return null;
  }

  /// Resolves the bookmark and copies the cloud file to a local temp location
  /// using NSFileCoordinator for proper cloud provider integration.
  /// Returns the temp file path on success.
  /// Throws PlatformException with code 'BOOKMARK_STALE' if bookmark needs refresh.
  static Future<String?> prepareSyncRead(String bookmarkBase64) async {
    if (!Platform.isIOS) return null;
    try {
      final path = await _channel.invokeMethod(
        'prepareSyncRead',
        bookmarkBase64,
      );
      return path as String?;
    } on PlatformException catch (e) {
      print('prepareSyncRead error: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      print('prepareSyncRead unexpected error: $e');
      return null;
    }
  }

  /// Copies the temp file back to the cloud location using NSFileCoordinator.
  /// This ensures the cloud provider (Google Drive, iCloud, etc.) is properly
  /// notified of the change and will sync it.
  static Future<bool> commitSyncWrite({
    required String bookmarkBase64,
    required String tempPath,
  }) async {
    if (!Platform.isIOS) return false;
    try {
      final result = await _channel.invokeMethod('commitSyncWrite', {
        'bookmark': bookmarkBase64,
        'tempPath': tempPath,
      });
      return result == true;
    } on PlatformException catch (e) {
      print('commitSyncWrite error: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      print('commitSyncWrite unexpected error: $e');
      return false;
    }
  }

  /// Cleans up the temp file used during sync.
  static Future<void> cleanupSync(String tempPath) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('cleanupSync', tempPath);
    } catch (e) {
      print('cleanupSync error: $e');
    }
  }

  /// Stops accessing the security scoped resource.
  /// Should be called after sync operations are complete.
  static Future<void> stopAccess() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('stopAccess');
    } catch (e) {
      print('stopAccess error: $e');
    }
  }
}
