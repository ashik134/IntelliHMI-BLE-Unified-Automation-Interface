import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/horn_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button/horn_control.dart';

/// Small, feedback-only AppBar presentation of [IndustrialHornControl].
///
/// Whether it is sounding is decided upstream by FeedbackManager — which reads
/// PLC status only — and handed in as [isActive]. This widget has no trigger
/// logic and no gesture that reaches a controller: [onSilence] acknowledges
/// the local episode and nothing else, so tapping it can never write to the
/// PLC.
class CompactPlcStatusBuzzer extends StatelessWidget {
  const CompactPlcStatusBuzzer({
    super.key,
    required this.config,
    required this.isActive,
    this.onSilence,
  });

  final HornConfig config;
  final bool isActive;

  /// Null when silencing is disabled or nothing is sounding.
  final VoidCallback? onSilence;

  @override
  Widget build(BuildContext context) {
    final message = isActive
        ? config.soundEnabled
              ? 'PLC status active — local buzzer sounding'
                    '${onSilence != null ? '. Tap to silence.' : ''}'
              : 'PLC status active — local sound disabled'
        : 'PLC status idle — local buzzer ready';

    return Tooltip(
      message: message,
      child: GestureDetector(
        onTap: onSilence,
        behavior: HitTestBehavior.opaque,
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
      ),
    );
  }
}
