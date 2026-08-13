import 'package:flutter/painting.dart' show Color;

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/alarm_indicator_config.dart'
    show AlarmSeverity;
import 'package:rev_crane_control_ops/models/feedback/alarm_feedback_config.dart';
import 'package:rev_crane_control_ops/models/feedback/analog_feedback_config.dart';
import 'package:rev_crane_control_ops/models/feedback/led_feedback_config.dart';
import 'package:rev_crane_control_ops/models/feedback/system_feedback_config.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FeedbackPalette
//
// The one place a feedback config's nullable "use the default" colour becomes
// a concrete one. Kept out of FeedbackManager on purpose: the manager resolves
// STATE (severity, zones, health) and must stay renderer-agnostic, while every
// theme decision lives here where the settings sheets and the live surfaces
// can share it — a swatch in Feedback Settings and the LED it configures are
// then guaranteed to be the same colour.
// ─────────────────────────────────────────────────────────────────────────────

abstract final class FeedbackPalette {
  /// Standard escalation palette. Amber -> orange -> red is the convention the
  /// gauges (GaugeZone) and the alarm indicator widget already use, so the
  /// layout-level alarm reads consistently with them.
  static const Color warning = AppColors.accent;
  static const Color alarm = Color(0xFFF97316);
  static const Color critical = AppColors.eStopColor;
  static const Color normal = AppColors.darkSuccess;
  static const Color muted = AppColors.disabled;

  static Color severity(AlarmSeverity severity, {AlarmFeedbackConfig? config}) {
    return config?.colorFor(severity) ??
        switch (severity) {
          AlarmSeverity.critical => critical,
          AlarmSeverity.alarm => alarm,
          AlarmSeverity.warning => warning,
          AlarmSeverity.muted => muted,
          AlarmSeverity.normal => normal,
        };
  }

  static Color comms(CommsHealth health) => switch (health) {
    CommsHealth.live => AppColors.darkSuccess,
    CommsHealth.stale => AppColors.accent,
    CommsHealth.offline => AppColors.eStopColor,
  };

  static String commsLabel(CommsHealth health) => switch (health) {
    CommsHealth.live => 'Link live',
    CommsHealth.stale => 'Link stale',
    CommsHealth.offline => 'Link down',
  };

  static Color analogZone(AnalogFeedbackZone zone, Color channelColor) =>
      switch (zone) {
        AnalogFeedbackZone.normal => channelColor,
        AnalogFeedbackZone.warning => AppColors.accent,
        AnalogFeedbackZone.critical => AppColors.eStopColorLight,
      };

  /// Channel identity colours for the analog readers, by display position.
  /// Two channels exist today; the list wraps so adding a third reader never
  /// renders it colourless.
  static const List<(Color, Color)> analogChannelColors = [
    (AppColors.upColor, AppColors.upColorLight),
    (AppColors.downColor, AppColors.downColorLight),
    (AppColors.traverseColor, AppColors.traverseColorLight),
    (AppColors.travelColor, AppColors.travelColorLight),
  ];

  /// Base/light pair for the analog reader at [index], honouring a configured
  /// override. The light partner of a custom colour is the colour itself —
  /// the gauge only uses it for the arc's leading edge, which stays legible.
  static (Color, Color) analogChannel(int index, {Color? override}) {
    if (override != null) return (override, override);
    return analogChannelColors[index % analogChannelColors.length];
  }

  // ── LED indicator row ────────────────────────────────────────────────────

  /// Confirmed-ON colour for [variant]. E-STOP keeps the safety red; every
  /// other channel uses the app's generic output amber.
  static Color ledActive(
    PlcOutputVariant variant,
    LedChannelFeedbackConfig config,
  ) {
    return config.activeColor ??
        (variant.isEmergencyStop ? AppColors.eStopColor : AppColors.accent);
  }

  /// Confirmed-OFF "ready" colour, or null to leave the LED dark when off.
  /// Only E-STOP defaults to a lit ready state — an operator must be able to
  /// see at a glance that the safety channel is healthy, not merely unlit.
  static Color? ledInactive(
    PlcOutputVariant variant,
    LedChannelFeedbackConfig config,
  ) {
    if (config.inactiveColor != null) return config.inactiveColor;
    return variant.isEmergencyStop ? AppColors.darkSuccess : null;
  }

  static bool ledPulsesWhenInactive(
    PlcOutputVariant variant,
    LedChannelFeedbackConfig config,
  ) {
    return config.pulseWhenInactive ?? variant.isEmergencyStop;
  }
}
