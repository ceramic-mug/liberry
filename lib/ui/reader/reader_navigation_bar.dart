import 'package:flutter/material.dart';

class ReaderNavigationBar extends StatelessWidget {
  final bool showControls;
  final Color backgroundColor;
  final Color textColor;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final String previousChapterTitle;
  final String nextChapterTitle;
  final bool canGoPrevious;
  final bool canGoNext;

  const ReaderNavigationBar({
    super.key,
    required this.showControls,
    required this.backgroundColor,
    required this.textColor,
    required this.onPrevious,
    required this.onNext,
    required this.previousChapterTitle,
    required this.nextChapterTitle,
    required this.canGoPrevious,
    required this.canGoNext,
  });

  @override
  Widget build(BuildContext context) {
    if (!showControls) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {}, // Consume taps
      behavior: HitTestBehavior.opaque,
      child: BottomAppBar(
        color: backgroundColor,
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Previous Chapter
            Expanded(
              flex: 1,
              child: canGoPrevious
                  ? GestureDetector(
                      onTap: onPrevious,
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_back, color: textColor, size: 20),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              previousChapterTitle,
                              style: TextStyle(color: textColor, fontSize: 10),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            // Spacer to push items to edges (since we removed center title)
            const SizedBox(width: 16),

            // Next Chapter
            Expanded(
              flex: 1,
              child: canGoNext
                  ? GestureDetector(
                      onTap: onNext,
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Expanded(
                            child: Text(
                              nextChapterTitle,
                              textAlign: TextAlign.right,
                              style: TextStyle(color: textColor, fontSize: 10),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.arrow_forward, color: textColor, size: 20),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
