import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EditableControlTile
//
// Generic external wrapper used by both control screens while Customization
// Mode is active. Composes around any existing control widget without
// touching its internals:
//   - AbsorbPointer blocks every gesture from reaching the real control
//     (and therefore the PLC command callbacks) while editing.
//   - An optional pencil badge (top-right) opens the edit sheet for a
//     motion-control role.
//   - An optional visibility-off badge (top-left) hides a chrome element,
//     behind a confirmation dialog.
//
// E-Stop is NEVER wrapped in this widget — see plc14/plc38 control screens.
// ─────────────────────────────────────────────────────────────────────────────

class EditableControlTile extends StatelessWidget {
  const EditableControlTile({
    super.key,
    required this.child,
    required this.isEditing,
    this.onCustomize,
    this.onDelete,
    this.deleteConfirmTitle = 'Hide this element?',
    this.deleteConfirmBody =
        'You can restore it later from the customization overflow menu. '
        'This only takes effect once you Apply.',
    this.absorbInput = true,
  });

  final Widget child;
  final bool isEditing;

  /// Non-null → shows a pencil badge that opens the per-control edit sheet.
  final VoidCallback? onCustomize;

  /// Non-null → shows a visibility-off badge (chrome elements only —
  /// motion controls and E-Stop never pass a callback here).
  final VoidCallback? onDelete;

  final String deleteConfirmTitle;
  final String deleteConfirmBody;

  /// Whether the wrapped control's gestures are absorbed while editing.
  /// Always true for motion controls; kept configurable for chrome tiles
  /// that have no PLC-command gesture to begin with.
  final bool absorbInput;

  Future<void> _confirmThenDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: Text(
          deleteConfirmTitle,
          style: const TextStyle(color: AppColors.darkText, fontSize: 16),
        ),
        content: Text(
          deleteConfirmBody,
          style: const TextStyle(color: AppColors.darkTextSub, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.eStopColor),
            child: const Text('Hide'),
          ),
        ],
      ),
    );
    if (confirmed == true) onDelete?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!isEditing) return child;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AbsorbPointer(absorbing: absorbInput, child: child),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.accent.withAlpha(140),
                  width: 1.5,
                  strokeAlign: BorderSide.strokeAlignOutside,
                ),
              ),
            ),
          ),
        ),
        if (onCustomize != null)
          Positioned(
            top: -6,
            right: -6,
            child: _Badge(
              icon: Icons.edit_rounded,
              color: AppColors.accent,
              onTap: onCustomize!,
              tooltip: 'Customize',
            ),
          ),
        if (onDelete != null)
          Positioned(
            top: -6,
            left: -6,
            child: _Badge(
              icon: Icons.visibility_off_rounded,
              color: AppColors.eStopColor,
              onTap: () => _confirmThenDelete(context),
              tooltip: 'Hide',
            ),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
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
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 14, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
