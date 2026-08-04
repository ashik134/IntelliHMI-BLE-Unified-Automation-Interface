import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/services/layout_validation_service.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/general_tab.dart'
    show ButtonUpdater;
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/property_field_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SafetyTab
//
// Mutual exclusion (backed by the existing MutualExclusionConfig, whole-
// button granularity — see the plan's "per side"/"opposite direction" scope
// note: there's no per-zone exclusion primitive in the model today) plus a
// live validation panel reusing LayoutValidationService.validateButtonConfig,
// the same check the Done button runs on exit — surfacing it here lets the
// operator fix a problem immediately instead of discovering it later.
// ─────────────────────────────────────────────────────────────────────────────

const LayoutValidationService _validator = LayoutValidationService();

class SafetyTab extends StatelessWidget {
  const SafetyTab({
    super.key,
    required this.config,
    required this.allButtons,
    required this.onUpdate,
    required this.updateButtonById,
    this.gridColumns = ButtonConfig.controlGridColumns,
    this.gridRows = ButtonConfig.controlGridRows,
  });

  final ButtonConfig config;
  final Map<String, ButtonConfig> allButtons;
  final ButtonUpdater onUpdate;
  final void Function(String id, ButtonConfig Function(ButtonConfig)) updateButtonById;

  /// The active layout's grid shape — see ControlLayoutConfig.gridLayout —
  /// so the live validation panel below checks placement bounds against the
  /// real grid rather than the old fixed 2x3 default.
  final int gridColumns;
  final int gridRows;

  List<(String, String)> get _otherButtonOptions => [
    for (final b in allButtons.values)
      if (b.id != config.id && b.role == null) (b.id, b.label.isEmpty ? b.id : b.label),
  ];

  void _toggleExclusion(String otherId) {
    final willExclude = !config.mutualExclusion.excludedButtonIds.contains(
      otherId,
    );

    void applyTo(String id, String partnerId) {
      updateButtonById(id, (b) {
        final current = Set<String>.from(b.mutualExclusion.excludedButtonIds);
        if (willExclude) {
          current.add(partnerId);
        } else {
          current.remove(partnerId);
        }
        return b.copyWith(
          mutualExclusion: b.mutualExclusion.copyWith(
            excludedButtonIds: current,
          ),
        );
      });
    }

    applyTo(config.id, otherId);
    applyTo(otherId, config.id);
  }

  void _toggleInclusive(String otherId) {
    final current = Set<String>.from(config.mutualExclusion.inclusiveButtonIds);
    if (current.contains(otherId)) {
      current.remove(otherId);
    } else {
      current.add(otherId);
    }
    onUpdate(
      (b) => b.copyWith(
        mutualExclusion: b.mutualExclusion.copyWith(
          inclusiveButtonIds: current,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final options = _otherButtonOptions;
    final validation = _validator.validateButtonConfig(
      config,
      allButtons,
      columns: gridColumns,
      rows: gridRows,
    );

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      children: [
        if (!validation.isValid) ...[
          const PropertySectionHeader('Warnings', padTop: 4),
          for (final error in validation.errors)
            PropertyInfoBanner(text: error, isWarning: true),
        ],
        PropertySectionHeader(
          'Mutual Exclusion',
          padTop: validation.isValid ? 4 : 18,
        ),
        const Text(
          'Selected widgets are forced idle whenever this one is active, '
          'and vice versa — an interlock for outputs that must never both '
          'be asserted (e.g. opposite directions).',
          style: TextStyle(color: Color(0xFF94A6B7), fontSize: 12, height: 1.3),
        ),
        const SizedBox(height: 10),
        PropertyMultiSelect(
          options: options,
          selectedKeys: config.mutualExclusion.excludedButtonIds,
          onToggle: _toggleExclusion,
        ),
        const PropertySectionHeader('Explicitly Allowed Together'),
        const Text(
          'Informational only — documents combinations that are safe to '
          'run at the same time.',
          style: TextStyle(color: Color(0xFF94A6B7), fontSize: 12, height: 1.3),
        ),
        const SizedBox(height: 10),
        PropertyMultiSelect(
          options: options,
          selectedKeys: config.mutualExclusion.inclusiveButtonIds,
          onToggle: _toggleInclusive,
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
