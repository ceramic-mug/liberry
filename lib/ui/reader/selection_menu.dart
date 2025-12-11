import 'package:flutter/material.dart';

class SelectionMenu extends StatelessWidget {
  final VoidCallback? onHighlight;
  final VoidCallback? onAssign;
  final VoidCallback? onCopy;
  final VoidCallback? onDelete; // For existing highlights
  final VoidCallback? onNote; // For existing highlights
  final bool
  isHighlightMenu; // Toggle between text selection vs highlight context

  const SelectionMenu({
    super.key,
    this.onHighlight,
    this.onAssign,
    this.onCopy,
    this.onDelete,
    this.onNote,
    this.isHighlightMenu = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E), // Dark aesthetic
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: isHighlightMenu
            ? [
                _buildButton(
                  icon: Icons.person_add,
                  label: 'Assign',
                  onTap: onAssign,
                ),
                _buildDivider(),
                _buildButton(
                  icon: Icons.note_add,
                  label: 'Note',
                  onTap: onNote,
                ),
                _buildDivider(),
                _buildButton(
                  icon: Icons.delete,
                  label: 'Delete',
                  color: Colors.redAccent,
                  onTap: onDelete,
                ),
              ]
            : [
                _buildButton(
                  icon: Icons.edit,
                  label: 'Highlight',
                  onTap: onHighlight,
                ),
                _buildDivider(),
                _buildButton(
                  icon: Icons.person_add,
                  label: 'Assign',
                  onTap: onAssign,
                ),
                _buildDivider(),
                _buildButton(icon: Icons.copy, label: 'Copy', onTap: onCopy),
              ],
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Color color = Colors.white,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 2),
              // Optional: Label text if user wants it, keeping it icon-only for now as per design
              // Text(label, style: TextStyle(color: color, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 24,
      color: Colors.white24,
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
