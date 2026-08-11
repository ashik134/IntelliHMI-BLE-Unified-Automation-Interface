import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/horn_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button/horn_control.dart';

/// Small, feedback-only AppBar presentation of [IndustrialHornControl].
///
/// Its trigger reads only status received from the PLC. It has no gesture
/// callbacks and never sends an output command.
class CompactPlcStatusBuzzer extends StatelessWidget {
  const CompactPlcStatusBuzzer({super.key, required this.config});

  final HornConfig config;

  @override
  Widget build(BuildContext context) {
    final isActive = context.select<CraneController, bool>(
      (controller) => config.trigger.isActive(controller.isReportedFieldActive),
    );
    final message = isActive
        ? config.soundEnabled
              ? 'PLC status active — local buzzer sounding'
              : 'PLC status active — local sound disabled'
        : 'PLC status idle — local buzzer ready';

    return Tooltip(
      message: message,
      child: SizedBox.square(
        dimension: 34,
        child: IndustrialHornControl(
          label: 'PLC status buzzer',
          activeColor: AppColors.fastColor,
          activeColorLight: AppColors.fastColorLight,
          isActive: isActive,
          enabled: true,
          config: config,
          presentation: HornControlPresentation.compact,
        ),
      ),
    );
  }
}
