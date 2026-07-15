import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/customization_mode_controller.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/control_slot_grid.dart';

class CustomizationCanvas extends StatelessWidget {
  const CustomizationCanvas({
    super.key,
    required this.layoutCfg,
    required this.roles,
    required this.onEditRole,
    this.slotCount,
  });

  final ControlLayoutConfig layoutCfg;
  final List<ControlRole> roles;
  final void Function(ControlRole role) onEditRole;
  final int? slotCount;

  // Mirrors ControlSlotGrid's own `rows` derivation so grid-mutation
  // validation here uses the same row count the grid actually renders,
  // rather than always assuming the full 3-row default.
  int get _effectiveSlotCount => slotCount ?? ButtonConfig.controlSlotCount;
  int get _effectiveRows =>
      (_effectiveSlotCount / ButtonConfig.controlGridColumns).ceil();

  @override
  Widget build(BuildContext context) {
    return ControlSlotGrid(
      layoutCfg: layoutCfg,
      roles: roles,
      slotCount: _effectiveSlotCount,
      isEditing: true,
      activeStateFor: (_) => ControlState.idle,
      isDisabled: (_) => true,
      onCommand: (_, _) {},
      onEditButton: (config) {
        final role = config.role;
        if (role != null) onEditRole(role);
      },
      onSlotDrop:
          (
            dragged,
            sourceSlot,
            target,
            targetSlot, {
            required targetPageIndex,
          }) {
            final customCtrl = context.read<CustomizationModeController>();
            final result = buildGridSlotDrop(
              buttons: customCtrl.draft.resolvedButtons,
              dragged: dragged,
              sourceSlot: sourceSlot,
              target: target,
              targetSlot: targetSlot,
              targetPageIndex: targetPageIndex,
              slotCount: _effectiveSlotCount,
              rows: _effectiveRows,
            );
            if (!result.isValid) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(result.message ?? kCrossTravelSpanMessage),
                ),
              );
              return;
            }
            customCtrl.applyDraftChange(
              customCtrl.draft.copyWith(buttons: result.buttons),
            );
          },
      onResizeButton: (config, gridColumns, gridRows, {anchorX, anchorY}) {
        final customCtrl = context.read<CustomizationModeController>();
        final result = buildButtonResize(
          buttons: customCtrl.draft.resolvedButtons,
          selected: config,
          gridColumns: gridColumns,
          gridRows: gridRows,
          anchorX: anchorX,
          anchorY: anchorY,
          slotCount: _effectiveSlotCount,
          rows: _effectiveRows,
        );
        if (!result.isValid) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.message ?? kWidgetPlacementMessage)),
          );
          return;
        }
        customCtrl.applyDraftChange(
          customCtrl.draft.copyWith(buttons: result.buttons),
        );
      },
    );
  }
}
