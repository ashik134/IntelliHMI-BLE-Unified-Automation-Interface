import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/button_icon_registry.dart';
import 'package:rev_crane_control_ops/models/button_rotation.dart';
import 'package:rev_crane_control_ops/models/control_orientation.dart';
import 'package:rev_crane_control_ops/widgets/buttons/control_button_visuals.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/icon_picker_sheet.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/property_field_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GeneralTab
//
// Common-to-all-19 identity/placement fields: label, show/hide label, icon,
// enable/disable, lock position, rotation, reset to default, delete. Every
// field here already exists on ButtonConfig — this is pure UI over it.
// ─────────────────────────────────────────────────────────────────────────────

typedef ButtonUpdater = void Function(ButtonConfig Function(ButtonConfig));

class GeneralTab extends StatefulWidget {
  const GeneralTab({
    super.key,
    required this.config,
    required this.onUpdate,
    required this.onReset,
    required this.onDelete,
  });

  final ButtonConfig config;
  final ButtonUpdater onUpdate;
  final VoidCallback onReset;
  final VoidCallback onDelete;

  @override
  State<GeneralTab> createState() => _GeneralTabState();
}

class _GeneralTabState extends State<GeneralTab> {
  late final TextEditingController _labelController;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.config.label);
  }

  @override
  void didUpdateWidget(covariant GeneralTab old) {
    super.didUpdateWidget(old);
    // Only resync when the label changed for a reason OTHER than this
    // field's own onChanged (e.g. Reset to default) — otherwise every
    // keystroke would fight the controller's own cursor position.
    if (widget.config.label != _labelController.text &&
        widget.config.label != old.config.label) {
      _labelController.text = widget.config.label;
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _pickIcon() async {
    final result = await showIconPickerSheet(
      context,
      currentKey: widget.config.iconKey,
    );
    if (result == null) return;
    widget.onUpdate(
      (b) => result.iconKey == null
          ? b.copyWith(clearIcon: true, clearIconKey: true)
          : b.copyWith(
              icon: iconForKey(result.iconKey),
              iconKey: result.iconKey,
            ),
    );
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.darkBorder),
        ),
        title: const Text(
          'Reset to default?',
          style: TextStyle(color: AppColors.darkText),
        ),
        content: const Text(
          'Restores this widget\'s appearance and function to their '
          'catalogue defaults. PLC output mapping, mutual exclusion, and '
          'position are not affected.',
          style: TextStyle(color: AppColors.darkTextSub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Reset',
              style: TextStyle(color: AppColors.selectionViolet),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.onReset();
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final icon = config.icon;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      children: [
        PropertyTextField(
          controller: _labelController,
          label: 'Label',
          maxLength: ControlButtonVisualMetrics.maxLabelLength,
          onChanged: (v) => widget.onUpdate((b) => b.copyWith(label: v)),
        ),
        PropertySwitchTile(
          title: 'Show label',
          subtitle: 'Hide the text label and show only the icon.',
          value: config.style.showLabel,
          onChanged: (v) => widget.onUpdate(
            (b) => b.copyWith(style: b.style.copyWith(showLabel: v)),
          ),
        ),
        const PropertySectionHeader('Icon'),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _pickIcon,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.darkBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: Row(
              children: [
                Icon(
                  icon ?? Icons.image_not_supported_outlined,
                  color: icon == null
                      ? AppColors.darkTextMuted
                      : AppColors.darkText,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    icon == null ? 'Default icon' : 'Custom icon',
                    style: const TextStyle(
                      color: AppColors.darkText,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.darkTextMuted,
                ),
              ],
            ),
          ),
        ),
        const PropertySectionHeader('State'),
        PropertySwitchTile(
          title: 'Enabled',
          subtitle: 'Disabled widgets stay on the grid but never send PLC output.',
          value: config.enabled,
          onChanged: (v) => widget.onUpdate((b) => b.copyWith(enabled: v)),
        ),
        PropertySwitchTile(
          title: 'Lock position',
          subtitle: 'Prevents this widget from being moved or resized on the canvas.',
          value: config.locked,
          onChanged: (v) => widget.onUpdate((b) => b.copyWith(locked: v)),
        ),
        if (ButtonConfig.supportsStructuralRotation(config.type)) ...[
          const PropertySectionHeader('Rotation'),
          PropertySegmented<ButtonRotation>(
            options: const [
              (ButtonRotation.none, '0°'),
              (ButtonRotation.deg90, '90°'),
              (ButtonRotation.deg270, '270°'),
              // 360° is the same underlying state as 0° (ButtonRotation.none)
              // — both pills light up together whenever rotation == none.
              // See ButtonConfig.supportsStructuralRotation's doc comment
              // for why 180° is never offered for these two types.
              (ButtonRotation.none, '360°'),
            ],
            selected: config.rotation,
            onChanged: (r) => widget.onUpdate((b) => b.copyWith(rotation: r)),
          ),
        ] else if (ButtonConfig.supportsOrientation(
          config.type,
          customProperties: config.customProperties,
        )) ...[
          const PropertySectionHeader('Orientation'),
          PropertySegmented<ControlOrientation>(
            options: const [
              (ControlOrientation.horizontal, 'Horizontal'),
              (ControlOrientation.vertical, 'Vertical'),
            ],
            selected: ButtonConfig.orientationOf(
              config.type,
              config.customProperties,
            ),
            onChanged: (o) => widget.onUpdate(
              (b) => b.copyWith(
                customProperties: ButtonConfig.applyOrientation(
                  b.type,
                  b.customProperties,
                  o,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _confirmReset,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.darkText,
                  side: const BorderSide(color: AppColors.darkBorder),
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('Reset to Default'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onDelete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.eStopColor,
                  side: const BorderSide(color: AppColors.eStopColor),
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.delete_rounded, size: 18),
                label: const Text('Delete Widget'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
