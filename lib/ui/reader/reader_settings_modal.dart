import 'package:flutter/material.dart';

import 'reader_models.dart';

class ReaderSettingsModal extends StatefulWidget {
  final ReaderTheme theme;
  final ReaderScrollMode scrollMode;
  final double fontSize;
  final String fontFamily;
  final int activeChapterIndex;
  final int totalChapters;
  final Function(ReaderTheme) onThemeChanged;
  final Function(ReaderScrollMode) onScrollModeChanged;
  final Function(double) onFontSizeChanged;
  final Function(String) onFontFamilyChanged;

  const ReaderSettingsModal({
    super.key,
    required this.theme,
    required this.scrollMode,
    required this.fontSize,
    required this.fontFamily,
    required this.activeChapterIndex,
    required this.totalChapters,
    required this.onThemeChanged,
    required this.onScrollModeChanged,
    required this.onFontSizeChanged,
    required this.onFontFamilyChanged,
  });

  @override
  State<ReaderSettingsModal> createState() => _ReaderSettingsModalState();
}

class _ReaderSettingsModalState extends State<ReaderSettingsModal> {
  late double _currentFontSize;
  late ReaderTheme _currentTheme;
  late ReaderScrollMode _currentScrollMode;
  late String _currentFontFamily;

  @override
  void initState() {
    super.initState();
    _currentFontSize = widget.fontSize;
    _currentTheme = widget.theme;
    _currentScrollMode = widget.scrollMode;
    _currentFontFamily = widget.fontFamily;
  }

  @override
  Widget build(BuildContext context) {
    final textColor = _getTextColor(_currentTheme);
    final bgColor = _getBackgroundColor(_currentTheme);

    return Container(
      color: bgColor,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Update active chapter
          if (widget.activeChapterIndex >= 0 &&
              widget.activeChapterIndex < widget.totalChapters)
            Text(
              'Chapter ${widget.activeChapterIndex + 1} of ${widget.totalChapters}',
              style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 12),
            ),
          const SizedBox(height: 4),
          // Scroll Mode Toggle
          Text(
            'Scroll Mode',
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildScrollModeButton(
                context,
                ReaderScrollMode.vertical,
                'Vertical',
                Icons.swap_vert,
                textColor,
              ),
              _buildScrollModeButton(
                context,
                ReaderScrollMode.horizontal,
                'Horizontal',
                Icons.swap_horiz,
                textColor,
              ),
            ],
          ),
          const SizedBox(height: 24),

          Text(
            'Theme',
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildThemeButton(
                context,
                ReaderTheme.light,
                'Light',
                Icons.light_mode,
              ),
              _buildThemeButton(
                context,
                ReaderTheme.sepia,
                'Sepia',
                Icons.chrome_reader_mode,
              ),
              _buildThemeButton(
                context,
                ReaderTheme.dark,
                'Dark',
                Icons.dark_mode,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Font Size',
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Decrease Font Size
              InkWell(
                onTap: () {
                  if (_currentFontSize > 50) {
                    setState(() {
                      _currentFontSize -= 10;
                    });
                    widget.onFontSizeChanged(_currentFontSize);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'A-',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 32),
              // Increase Font Size
              InkWell(
                onTap: () {
                  if (_currentFontSize < 300) {
                    setState(() {
                      _currentFontSize += 10;
                    });
                    widget.onFontSizeChanged(_currentFontSize);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'A+',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Font Family',
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildFontButton(context, 'Serif', 'Georgia, serif', textColor),
              _buildFontButton(
                context,
                'Sans',
                'Helvetica, Arial, sans-serif',
                textColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThemeButton(
    BuildContext context,
    ReaderTheme themeOption,
    String label,
    IconData icon,
  ) {
    final isSelected = _currentTheme == themeOption;
    return InkWell(
      onTap: () {
        setState(() {
          _currentTheme = themeOption;
        });
        widget.onThemeChanged(themeOption);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: isSelected ? Colors.blue : Colors.grey),
          borderRadius: BorderRadius.circular(20),
          color: isSelected ? Colors.blue.withOpacity(0.1) : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? Colors.blue : Colors.grey),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.blue : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollModeButton(
    BuildContext context,
    ReaderScrollMode modeOption,
    String label,
    IconData icon,
    Color textColor,
  ) {
    final isSelected = _currentScrollMode == modeOption;
    return InkWell(
      onTap: () {
        setState(() {
          _currentScrollMode = modeOption;
        });
        widget.onScrollModeChanged(modeOption);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: isSelected ? Colors.blue : Colors.grey),
          borderRadius: BorderRadius.circular(20),
          color: isSelected ? Colors.blue.withOpacity(0.1) : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? Colors.blue : Colors.grey),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.blue : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFontButton(
    BuildContext context,
    String label,
    String family,
    Color textColor,
  ) {
    final isSelected = _currentFontFamily == family;
    return InkWell(
      onTap: () {
        setState(() {
          _currentFontFamily = family;
        });
        widget.onFontFamilyChanged(family);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: isSelected ? Colors.blue : Colors.grey),
          borderRadius: BorderRadius.circular(20),
          color: isSelected ? Colors.blue.withOpacity(0.1) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.blue : Colors.grey,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Color _getTextColor(ReaderTheme theme) {
    switch (theme) {
      case ReaderTheme.light:
        return Colors.black;
      case ReaderTheme.dark:
        return const Color(0xFFE0E0E0); // Off-white for better contrast
      case ReaderTheme.sepia:
        return const Color(0xFF5B4636);
    }
  }

  Color _getBackgroundColor(ReaderTheme theme) {
    switch (theme) {
      case ReaderTheme.light:
        return Colors.white;
      case ReaderTheme.dark:
        return const Color(0xFF121212);
      case ReaderTheme.sepia:
        return const Color(0xFFF4ECD8);
    }
  }
}
