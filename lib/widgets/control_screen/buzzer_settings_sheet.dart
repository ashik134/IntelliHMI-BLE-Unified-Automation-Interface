import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/horn_config.dart';
import 'package:rev_crane_control_ops/models/plc_condition_config.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/property_field_widgets.dart';

final List<PlcOutputVariant> _configurableVariants = PlcOutputVariant.values
    .where((variant) => variant.isUserConfigurable)
    .toList(growable: false);

Future<void> showBuzzerSettingsSheet(BuildContext context) async {
  final editController = context.read<LayoutEditController>();
  editController.beginHistoryBatch();
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _BuzzerSettingsSheet(),
    );
  } finally {
    editController.endHistoryBatch();
  }
}

class _BuzzerSettingsSheet extends StatelessWidget {
  const _BuzzerSettingsSheet();

  void _update(BuildContext context, HornConfig next) {
    context.read<LayoutEditController>().updateDraftAppBarBuzzerConfig(next);
  }

  @override
  Widget build(BuildContext context) {
    final config = context
        .watch<LayoutEditController>()
        .draft
        .appBarBuzzerConfig;
    final trigger = config.trigger;
    final selectedKeys = trigger.watchedFields
        .map((variant) => variant.storageKey)
        .toSet();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.darkBorder),
            boxShadow: AppMetrics.shadowMd,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.panelStroke,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'AppBar Buzzer',
                  style: TextStyle(
                    color: AppColors.darkText,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                const PropertyInfoBanner(
                  text:
                      'Only status received from the PLC can activate this '
                      'local buzzer. Sending an output does not trigger it.',
                ),
                const PropertySectionHeader('Activation outputs', padTop: 4),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => _update(
                        context,
                        config.copyWith(
                          trigger: trigger.copyWith(
                            watchedFields: _configurableVariants.toSet(),
                          ),
                        ),
                      ),
                      child: const Text('Select all'),
                    ),
                    TextButton(
                      onPressed: () => _update(
                        context,
                        config.copyWith(
                          trigger: trigger.copyWith(watchedFields: const {}),
                        ),
                      ),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                PropertyMultiSelect(
                  options: [
                    for (final variant in _configurableVariants)
                      (variant.storageKey, variant.genericLabel),
                  ],
                  selectedKeys: selectedKeys,
                  onToggle: (key) {
                    final variant = PlcOutputVariant.fromStorageKey(key);
                    if (variant == null) return;
                    _update(
                      context,
                      config.copyWith(trigger: trigger.toggleField(variant)),
                    );
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  'Trigger when',
                  style: TextStyle(
                    color: AppColors.darkText,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                PropertySegmented<PlcConditionCombinator>(
                  options: const [
                    (PlcConditionCombinator.any, 'Any selected is ON'),
                    (PlcConditionCombinator.all, 'All selected are ON'),
                  ],
                  selected: trigger.combinator,
                  onChanged: (value) => _update(
                    context,
                    config.copyWith(
                      trigger: trigger.copyWith(combinator: value),
                    ),
                  ),
                ),
                if (!trigger.hasCondition) ...[
                  const SizedBox(height: 12),
                  const PropertyInfoBanner(
                    text:
                        'No activation output is selected, so the AppBar '
                        'buzzer will remain idle.',
                    isWarning: true,
                  ),
                ],
                const PropertySectionHeader('Local feedback'),
                PropertySwitchTile(
                  title: 'Play local sound',
                  subtitle: 'Sound starts only while the trigger is active.',
                  value: config.soundEnabled,
                  onChanged: (value) =>
                      _update(context, config.copyWith(soundEnabled: value)),
                ),
                PropertySwitchTile(
                  title: 'Haptic feedback',
                  subtitle: 'Vibrate once when the trigger becomes active.',
                  value: config.hapticFeedback,
                  onChanged: (value) =>
                      _update(context, config.copyWith(hapticFeedback: value)),
                ),
                PropertySwitchTile(
                  title: 'Visual pulse',
                  subtitle: 'Pulse the small horn icon while active.',
                  value: config.visualPulseEnabled,
                  onChanged: (value) => _update(
                    context,
                    config.copyWith(visualPulseEnabled: value),
                  ),
                ),
                const PropertySectionHeader('Sound pattern'),
                PropertySegmented<HornSoundPattern>(
                  options: const [
                    (HornSoundPattern.steady, 'Steady'),
                    (HornSoundPattern.pulsing, 'Pulsing'),
                    (HornSoundPattern.doubleBeep, 'Double beep'),
                  ],
                  selected: config.soundPattern,
                  onChanged: (value) =>
                      _update(context, config.copyWith(soundPattern: value)),
                ),
                const PropertySectionHeader('Priority'),
                PropertySegmented<AlarmPriority>(
                  options: const [
                    (AlarmPriority.low, 'Low'),
                    (AlarmPriority.normal, 'Normal'),
                    (AlarmPriority.high, 'High'),
                  ],
                  selected: config.priority,
                  onChanged: (value) =>
                      _update(context, config.copyWith(priority: value)),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.selectionViolet,
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
