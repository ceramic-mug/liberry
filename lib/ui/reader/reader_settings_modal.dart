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
  final double sideMargin;
  final Function(double) onSideMarginChanged;
  final bool twoColumnEnabled;
  final Function(bool) onTwoColumnChanged;

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
    required this.sideMargin,
    required this.onSideMarginChanged,
    required this.twoColumnEnabled,
    required this.onTwoColumnChanged,
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
    _currentScrollMode = widget.scrollMode;
    _currentFontFamily = widget.fontFamily;
    _currentSideMargin = widget.sideMargin;
    _currentTwoColumnEnabled = widget.twoColumnEnabled;
  }

  // Local state for smoother sliding
  late double _currentSideMargin;
  late bool _currentTwoColumnEnabled;

  @override
  Widget build(BuildContext context) {
    final textColor = _getTextColor(_currentTheme);
    final bgColor = _getBackgroundColor(_currentTheme);

    return Container(
      color: bgColor,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Update active chapter
              if (widget.activeChapterIndex >= 0 &&
                  widget.activeChapterIndex < widget.totalChapters)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Chapter ${widget.activeChapterIndex + 1} of ${widget.totalChapters}',
                    style: TextStyle(
                      color: textColor.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                ),

              // Scroll Mode
              Text(
                'Scroll Mode',
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildScrollModeButton(
                      context,
                      ReaderScrollMode.vertical,
                      'Vertical',
                      Icons.swap_vert,
                      textColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildScrollModeButton(
                      context,
                      ReaderScrollMode.horizontal,
                      'Horizontal',
                      Icons.swap_horiz,
                      textColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Text(
                'Theme',
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildThemeButton(
                      context,
                      ReaderTheme.light,
                      'Light',
                      Icons.light_mode,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildThemeButton(
                      context,
                      ReaderTheme.sepia,
                      'Sepia',
                      Icons.chrome_reader_mode,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildThemeButton(
                      context,
                      ReaderTheme.dark,
                      'Dark',
                      Icons.dark_mode,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Font Size & Family Combined loosely or just tighter
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Font Size',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      InkWell(
                        onTap: () {
                          if (_currentFontSize > 50) {
                            setState(() => _currentFontSize -= 10);
                            widget.onFontSizeChanged(_currentFontSize);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.remove, color: textColor, size: 16),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          '${_currentFontSize.toInt()}%',
                          style: TextStyle(color: textColor),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          if (_currentFontSize < 300) {
                            setState(() => _currentFontSize += 10);
                            widget.onFontSizeChanged(_currentFontSize);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.add, color: textColor, size: 16),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Text(
                'Font Family',
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildFontButton(
                      context,
                      'Serif',
                      'Georgia, serif',
                      textColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildFontButton(
                      context,
                      'Sans',
                      'Helvetica, Arial, sans-serif',
                      textColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Side Margin Slider
              Text(
                'Side Margins',
                style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
              ),
              Slider(
                value: _currentSideMargin,
                min: 0,
                max: 100,
                divisions: 20,
                label: _currentSideMargin.round().toString(),
                activeColor: Colors.blue,
                inactiveColor: Colors.grey.withOpacity(0.3),
                onChanged: (value) {
                  setState(() {
                    _currentSideMargin = value;
                  });
                  widget.onSideMarginChanged(value);
                },
              ),

              if (_currentScrollMode == ReaderScrollMode.horizontal) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    'Two-Column (Landscape)',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  value: _currentTwoColumnEnabled,
                  activeColor: Colors.blue,
                  onChanged: (value) {
                    setState(() {
                      _currentTwoColumnEnabled = value;
                    });
                    widget.onTwoColumnChanged(value);
                  },
                ),
              ],
            ],
          ),
        ),
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
