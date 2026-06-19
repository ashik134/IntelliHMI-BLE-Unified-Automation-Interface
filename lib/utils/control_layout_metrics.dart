import 'package:flutter/material.dart';

/// Responsive layout parameters computed from the available body height.
///
/// Prevents overflow on small or landscape-oriented screens by dynamically
/// scaling spacing, widget heights, and conditionally hiding diagnostic rows
/// (sensor / LED) that are non-critical to crane operation.
///
/// Usage — compute once at the top of the Consumer/Consumer2 builder, then
/// thread [bodyPadding], [itemSpacing], [estopHeight], [showSensorRow], and
/// [showLEDs] into the body Column:
///
/// ```dart
/// builder: (ctx, controller, layoutCtrl, _) {
///   final metrics = ControlLayoutMetrics.compute(
///     MediaQuery.of(ctx).size.height
///         - kToolbarHeight
///         - MediaQuery.of(ctx).padding.top
///         - MediaQuery.of(ctx).padding.bottom,
///     baseEstopHeight: sizing.resolvedEstopHeight,
///     preferShowSensor: arrangement.showSensorRow,
///     preferShowLEDs: arrangement.showLiveLEDs,
///   );
///   ...
/// }
/// ```
class ControlLayoutMetrics {
  const ControlLayoutMetrics._({
    required this.showSensorRow,
    required this.showLEDs,
    required this.itemSpacing,
    required this.bodyPadding,
    required this.estopHeight,
    required this.isCompact,
  });

  /// Whether the A1/A2 load-sensor row should be rendered on this screen.
  final bool showSensorRow;

  /// Whether the PLC output LED indicator row should be rendered.
  final bool showLEDs;

  /// Vertical gap between adjacent sections (logical pixels).
  final double itemSpacing;

  /// Outer body padding applied to the top-level Column.
  final EdgeInsets bodyPadding;

  /// Effective height for the E-Stop swipe / active-reset section.
  final double estopHeight;

  /// True when the layout is in compact mode (small or landscape screen).
  /// Pass this to reset-section / other widgets so they can tighten their
  /// own internal padding and icon sizes.
  final bool isCompact;

  // ── Breakpoints (available body height after AppBar + SafeArea) ─────────────

  /// Below this value the layout enters *very compact* mode:
  /// sensor and LED rows are both hidden; spacing is minimised.
  static const double kVerySmall = 480;

  /// Below this value the layout enters *compact* mode:
  /// sensor row is hidden; LED row follows the operator preference;
  /// spacing is slightly reduced.
  static const double kSmall = 600;

  // ── Factory ──────────────────────────────────────────────────────────────────

  /// Compute responsive metrics from [availableHeight].
  ///
  /// Pass `MediaQuery.of(ctx).size.height - kToolbarHeight -
  /// MediaQuery.of(ctx).padding.top - MediaQuery.of(ctx).padding.bottom`
  /// as [availableHeight].
  ///
  /// [baseEstopHeight] is the operator-configured E-Stop button height
  /// (from [ControlWidgetSizeConfig.resolvedEstopHeight]).
  ///
  /// [preferShowSensor] / [preferShowLEDs] reflect the operator's arrangement
  /// preferences; they may be silently overridden on very small screens.
  static ControlLayoutMetrics compute(
    double availableHeight, {
    required double baseEstopHeight,
    required bool preferShowSensor,
    required bool preferShowLEDs,
  }) {
    if (availableHeight < kVerySmall) {
      return ControlLayoutMetrics._(
        showSensorRow: false,
        showLEDs: false,
        itemSpacing: 3.0,
        bodyPadding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
        estopHeight: baseEstopHeight.clamp(44.0, 56.0),
        isCompact: true,
      );
    }
    if (availableHeight < kSmall) {
      return ControlLayoutMetrics._(
        showSensorRow: false,
        showLEDs: preferShowLEDs,
        itemSpacing: 4.0,
        bodyPadding: const EdgeInsets.fromLTRB(12, 5, 12, 8),
        estopHeight: (baseEstopHeight * 0.85).clamp(50.0, 68.0),
        isCompact: true,
      );
    }
    return ControlLayoutMetrics._(
      showSensorRow: preferShowSensor,
      showLEDs: preferShowLEDs,
      itemSpacing: 6.0,
      bodyPadding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      estopHeight: baseEstopHeight,
      isCompact: false,
    );
  }
}
