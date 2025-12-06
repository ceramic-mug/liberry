import 'package:flutter/material.dart';

class ReaderTopBar extends StatelessWidget implements PreferredSizeWidget {
  final bool showControls;
  final Color backgroundColor;
  final Color textColor;
  final VoidCallback onExit;
  final VoidCallback onTOC;
  final VoidCallback onSettings;

  const ReaderTopBar({
    super.key,
    required this.showControls,
    required this.backgroundColor,
    required this.textColor,
    required this.onExit,
    required this.onTOC,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    // If controls are hidden, we don't want to show the AppBar at all.
    // However, Scaffold.appBar expects a widget.
    // If we return SizedBox.shrink(), it effectively hides it.
    if (!showControls) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {}, // Consume taps
      behavior: HitTestBehavior.opaque,
      child: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        toolbarHeight: 40,
        // Remove the default back button since we have our own Exit button
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            IconButton(
              icon: Icon(Icons.close, color: textColor),
              onPressed: onExit,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const Spacer(),
            IconButton(
              icon: Icon(Icons.list, color: textColor),
              onPressed: onTOC,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 16),
            IconButton(
              // "Text icon (like big T little T)"
              icon: Icon(Icons.format_size, color: textColor),
              onPressed: onSettings,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        // We use title with a Row to have full control over layout
        centerTitle: true,
      ),
    );
  }

  @override
  Size get preferredSize =>
      showControls ? const Size.fromHeight(40) : Size.zero;
}
