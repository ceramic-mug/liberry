import 'package:flutter/material.dart';
import 'package:epubx/epubx.dart';

class ReaderDrawer extends StatelessWidget {
  final String bookTitle;
  final List<EpubChapterRef> chapters;
  final int activeChapterIndex;
  final Color backgroundColor;
  final Color textColor;
  final Color activeColor;
  final Function(int) onChapterSelected;

  const ReaderDrawer({
    super.key,
    required this.bookTitle,
    required this.chapters,
    required this.activeChapterIndex,
    required this.backgroundColor,
    required this.textColor,
    required this.activeColor,
    required this.onChapterSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: backgroundColor,
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: textColor.withOpacity(0.1)),
              ),
            ),
            child: Center(
              child: Text(
                bookTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: chapters.length,
              itemBuilder: (context, index) {
                final chapter = chapters[index];
                final isSelected = index == activeChapterIndex;
                return ListTile(
                  title: Text(
                    chapter.Title ?? 'Chapter ${index + 1}',
                    style: TextStyle(
                      color: isSelected ? activeColor : textColor,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  onTap: () {
                    onChapterSelected(index);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
