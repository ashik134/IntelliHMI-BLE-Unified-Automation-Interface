import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CustomizationBadge
//
// Small circular icon badge used for customization-mode affordances (edit
// pencil, hide/visibility-off, lock). Promoted out of EditableControlTile so
// CustomizationCanvas's per-button tiles can reuse the same visual instead
// of duplicating the Material/InkWell boilerplate a third time.
// ─────────────────────────────────────────────────────────────────────────────

class CustomizationBadge extends StatelessWidget {
  const CustomizationBadge({
    super.key,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 12, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
