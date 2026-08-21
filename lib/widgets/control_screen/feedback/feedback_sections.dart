import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/feedback_manager.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/feedback/feedback_palette.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/live_led_row.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/sensor_row.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/status_bar_chip.dart';

class FeedbackSensorSection extends StatelessWidget {
  const FeedbackSensorSection({super.key});

  @override
  Widget build(BuildContext context) {
    final readings = context
        .select<FeedbackManager, List<AnalogFeedbackReading>>(
          (manager) => manager.snapshot.analog,
        );

    return RepaintBoundary(
      child: SensorRow(
        gauges: [
          for (var i = 0; i < readings.length; i++)
            _specFor(readings[i], index: i),
        ],
      ),
    );
  }

  SensorGaugeSpec _specFor(
    AnalogFeedbackReading reading, {
    required int index,
  }) {
    final config = reading.config;
    final (color, colorLight) = FeedbackPalette.analogChannel(
      index,
      override: config.color,
    );
    return SensorGaugeSpec(
      tag: config.channelKey,
      label: reading.displayLabel,
      value: reading.value,
      color: color,
      colorLight: colorLight,
      unit: config.unit,
      minValue: config.displayMin,
      maxValue: config.displayMax,
      warningFraction: config.warningFraction,
      criticalFraction: config.criticalFraction,
    );
  }
}

/// Input/output feedback — the live LED indicator row.
class FeedbackLedSection extends StatelessWidget {
  const FeedbackLedSection({
    super.key,
    required this.variants,
    required this.mappedVariants,
  });

  /// Channels this PLC model exposes on the wire, in wire order.
  final List<PlcOutputVariant> variants;

  /// Channels some control in the active layout can actually drive; everything
  /// else renders as a spare (dashed grey ring) or is hidden, per config.
  final Set<PlcOutputVariant> mappedVariants;

  @override
  Widget build(BuildContext context) {
    // Watches the manager rather than selecting a value: the row depends on
    // every channel's commanded AND confirmed bit plus the config, so any
    // change that matters here is already a manager notification.
    final manager = context.watch<FeedbackManager>();
    final readings = manager.resolveLeds(
      variants: variants,
      mappedVariants: mappedVariants,
    );
    if (readings.isEmpty) return const SizedBox.shrink();

    return RepaintBoundary(
      child: LiveLedRow(
        leds: [
          for (final reading in readings)
            LedSpec(
              label: reading.displayLabel,
              pin: reading.variant.storageKey,
              active: reading.confirmed,
              color: FeedbackPalette.ledActive(reading.variant, reading.config),
              inactiveColor: FeedbackPalette.ledInactive(
                reading.variant,
                reading.config,
              ),
              pulseWhenInactive: FeedbackPalette.ledPulsesWhenInactive(
                reading.variant,
                reading.config,
              ),
            ),
        ],
      ),
    );
  }
}

/// PLC status indicator — the live status chip. Hidden entirely when the
/// layout's system feedback config turns it off.
class FeedbackStatusChipSection extends StatelessWidget {
  const FeedbackStatusChipSection({super.key});

  @override
  Widget build(BuildContext context) {
    final visible = context.select<FeedbackManager, bool>(
      (manager) => manager.config.system.showStatusChip,
    );
    if (!visible) return const SizedBox.shrink();

    final controller = context.watch<CraneController>();
    return RepaintBoundary(
      child: StatusBarChip(
        color: controller.estopLatched
            ? AppColors.eStopColor
            : controller.activeCommand.isIdle
            ? AppColors.idleColor
            : AppColors.accent,
        label: controller.statusLabel,
      ),
    );
  }
}
