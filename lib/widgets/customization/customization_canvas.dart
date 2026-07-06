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

  @override
  Widget build(BuildContext context) {
    return ControlSlotGrid(
      layoutCfg: layoutCfg,
      roles: roles,
      slotCount: slotCount ?? ButtonConfig.controlSlotCount,
      isEditing: true,
      activeStateFor: (_) => ControlState.idle,
      isDisabled: (_) => true,
      onCommand: (_, _) {},
      onEditButton: (config) {
        final role = config.role;
        if (role != null) onEditRole(role);
      },
      onSlotDrop: (dragged, sourceSlot, target, targetSlot) {
        final customCtrl = context.read<CustomizationModeController>();
        final result = buildGridSlotDrop(
          buttons: customCtrl.draft.resolvedButtons,
          dragged: dragged,
          sourceSlot: sourceSlot,
          target: target,
          targetSlot: targetSlot,
          slotCount: slotCount ?? ButtonConfig.controlSlotCount,
        );
        if (!result.isValid) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.message ?? kCrossTravelSpanMessage)),
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
