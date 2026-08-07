import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/appearance_tab.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/function_tab.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/general_tab.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/output_tab.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/safety_tab.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WidgetPropertiesSheet
//
// The type-aware customization sheet: General / Appearance / Function /
// Output / Safety tabs, each built by widget_properties/*_tab.dart. Every
// field mutates the LayoutEditController draft directly — same "nothing
// persists until Save Layout / Done" contract as Layout Settings and every
// other customization mutation. Reachable both from the canvas's per-widget
// pencil badge (control_canvas.dart) and the customization toolbar's
// "Properties" action (customization_toolbar.dart) — both simply call
// [showWidgetPropertiesSheet] with the target button's id.
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showWidgetPropertiesSheet(
  BuildContext context,
  String buttonId,
) async {
  // The whole sheet visit — label edits, appearance sliders, rotation,
  // reset-to-default, delete — collapses into a single undo entry rather
  // than one per keystroke/slider frame. See LayoutEditController's
  // beginHistoryBatch doc comment.
  final editCtrl = context.read<LayoutEditController>();
  editCtrl.beginHistoryBatch();
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WidgetPropertiesSheet(buttonId: buttonId),
    );
  } finally {
    editCtrl.endHistoryBatch();
  }
}

class WidgetPropertiesSheet extends StatelessWidget {
  const WidgetPropertiesSheet({super.key, required this.buttonId});

  final String buttonId;

  void _delete(BuildContext context, String id) {
    final result = context.read<LayoutEditController>().deleteButton(id);
    if (!context.mounted) return;
    if (!result.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Could not delete this widget.'),
        ),
      );
      return;
    }

    // A successful draft mutation removes [id] from resolvedButtons. The
    // watched controller then rebuilds this sheet through the config == null
    // branch below, which owns the one and only route pop. Popping here as
    // well races the bottom-sheet exit animation and can pop the control
    // sub-shell underneath it, briefly exposing Scan Devices.
  }

  @override
  Widget build(BuildContext context) {
    final editCtrl = context.watch<LayoutEditController>();
    final config = editCtrl.draft.resolvedButtons[buttonId];

    if (config == null) {
      // Selection was cleared (e.g. deleted elsewhere) while this sheet was
      // open — close it rather than render a stale/broken editor.
      final sheetRoute = ModalRoute.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // showModalBottomSheet's future completes when its pop starts, before
        // the reverse animation disposes this subtree. endHistoryBatch() can
        // therefore rebuild the missing-config branch once more. Only dismiss
        // when this exact sheet is still the navigator's current route; a
        // later callback must never pop the control route underneath it.
        if (context.mounted && sheetRoute?.isCurrent == true) {
          Navigator.of(context).pop();
        }
      });
      return const SizedBox.shrink();
    }

    if (config.role != null) {
      return _LockedSheet(typeName: _typeDisplayName(config.type));
    }

    void onUpdate(ButtonConfig Function(ButtonConfig) update) {
      context.read<LayoutEditController>().updateButton(buttonId, update);
    }

    const tabs = [
      Tab(text: 'General'),
      Tab(text: 'Appearance'),
      Tab(text: 'Function'),
      Tab(text: 'Output'),
      Tab(text: 'Safety'),
    ];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          margin: const EdgeInsets.all(12),
          height: MediaQuery.of(context).size.height * 0.82,
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.darkBorder),
            boxShadow: AppMetrics.shadowMd,
          ),
          child: Material(
            color: Colors.transparent,
            child: DefaultTabController(
              length: tabs.length,
              child: Column(
                children: [
                  const SizedBox(height: 10),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Widget Properties',
                                style: TextStyle(
                                  color: AppColors.darkText,
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _typeDisplayName(config.type),
                                style: const TextStyle(
                                  color: AppColors.darkTextMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: AppColors.darkTextMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const TabBar(
                    tabs: tabs,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelColor: AppColors.selectionViolet,
                    unselectedLabelColor: AppColors.darkTextMuted,
                    indicatorColor: AppColors.selectionViolet,
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.darkBorder),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: TabBarView(
                        children: [
                          GeneralTab(
                            config: config,
                            onUpdate: onUpdate,
                            onReset: () => context
                                .read<LayoutEditController>()
                                .resetButtonToDefault(buttonId),
                            onDelete: () => _delete(context, buttonId),
                          ),
                          AppearanceTab(config: config, onUpdate: onUpdate),
                          FunctionTab(config: config, onUpdate: onUpdate),
                          OutputTab(config: config, onUpdate: onUpdate),
                          SafetyTab(
                            config: config,
                            allButtons: editCtrl.draft.resolvedButtons,
                            onUpdate: onUpdate,
                            updateButtonById: context
                                .read<LayoutEditController>()
                                .updateButton,
                            gridColumns: editCtrl.draft.gridLayout.columns,
                            gridRows: editCtrl.draft.gridLayout.rows,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LockedSheet extends StatelessWidget {
  const _LockedSheet({required this.typeName});

  final String typeName;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.darkBorder),
          boxShadow: AppMetrics.shadowMd,
        ),
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
              'Widget Properties',
              style: TextStyle(
                color: AppColors.darkText,
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              typeName,
              style: const TextStyle(
                color: AppColors.darkTextMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Safety controls cannot be edited or removed.',
              style: TextStyle(
                color: AppColors.darkTextMuted,
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.selectionViolet,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

String _typeDisplayName(ButtonType type) => switch (type) {
  ButtonType.pushButton => 'Push Button',
  ButtonType.toggle => 'Toggle Switch',
  ButtonType.sliderButton => 'Slider Button',
  ButtonType.bidirectionalSlider5Step => '5-Zone Slider',
  ButtonType.bidirectionalSlider3Step => '3-Zone Slider',
  ButtonType.joystick => 'Joystick',
  ButtonType.potentiometer => 'Potentiometer',
  ButtonType.horn => 'Horn',
  ButtonType.alarmIndicator => 'Alarm Indicator',
  ButtonType.analogJoystick1D => 'Analog Joystick (1-Axis)',
  ButtonType.analogJoystick2D => 'Analog Joystick (2-Axis)',
  ButtonType.analogSliderOT => 'Analog Slider (O-T)',
  ButtonType.analogSliderTOT => 'Analog Slider (T-O-T)',
};
