import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ui/reader/reader_models.dart';
import '../providers.dart';

class ReaderSettingsRepository {
  final SharedPreferences _prefs;

  ReaderSettingsRepository(this._prefs);

  static const _keyTheme = 'reader_theme';
  static const _keyScrollMode = 'reader_scroll_mode';
  static const _keyFontSize = 'reader_font_size';
  static const _keyFontFamily = 'reader_font_family';
  static const _keySideMargin = 'reader_side_margin';
  static const _keyTwoColumnEnabled = 'reader_two_column_enabled';

  ReaderTheme getTheme() {
    final index = _prefs.getInt(_keyTheme) ?? ReaderTheme.light.index;
    return ReaderTheme.values[index];
  }

  Future<void> setTheme(ReaderTheme theme) async {
    await _prefs.setInt(_keyTheme, theme.index);
  }

  ReaderScrollMode getScrollMode() {
    final index =
        _prefs.getInt(_keyScrollMode) ?? ReaderScrollMode.vertical.index;
    return ReaderScrollMode.values[index];
  }

  Future<void> setScrollMode(ReaderScrollMode mode) async {
    await _prefs.setInt(_keyScrollMode, mode.index);
  }

  double getFontSize() {
    return _prefs.getDouble(_keyFontSize) ?? 100.0;
  }

  Future<void> setFontSize(double size) async {
    await _prefs.setDouble(_keyFontSize, size);
  }

  String getFontFamily() {
    return _prefs.getString(_keyFontFamily) ?? 'Georgia, serif';
  }

  Future<void> setFontFamily(String family) async {
    await _prefs.setString(_keyFontFamily, family);
  }

  double getSideMargin() {
    // Default 20px
    return _prefs.getDouble(_keySideMargin) ?? 20.0;
  }

  Future<void> setSideMargin(double margin) async {
    await _prefs.setDouble(_keySideMargin, margin);
  }

  bool getTwoColumnEnabled() {
    return _prefs.getBool(_keyTwoColumnEnabled) ?? false;
  }

  Future<void> setTwoColumnEnabled(bool enabled) async {
    await _prefs.setBool(_keyTwoColumnEnabled, enabled);
  }
}

final readerSettingsRepositoryProvider = Provider<ReaderSettingsRepository>((
  ref,
) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ReaderSettingsRepository(prefs);
});
