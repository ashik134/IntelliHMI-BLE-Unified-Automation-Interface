import 'package:flutter/material.dart' show IconData, Icons;

import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ButtonCatalogEntry
//
// Static display metadata for the Widget Catalog page. ButtonTypeStrategy
// (see button_type_strategy.dart) intentionally carries no display name,
// category, or grid-size metadata of its own — this table is the one place
// that maps every ButtonType to how it's presented for selection, kept
// separate from the strategy layer so adding UI-only catalog copy never
// touches rendering/behavior code.
// ─────────────────────────────────────────────────────────────────────────────

enum ButtonCatalogCategory {
  digitalControls,
  analogControls,
  feedbackAndStatus,
  systemWidgets,
}

extension ButtonCatalogCategoryInfo on ButtonCatalogCategory {
  String get displayName => switch (this) {
    ButtonCatalogCategory.digitalControls => 'Digital Controls',
    ButtonCatalogCategory.analogControls => 'Analog Controls',
    ButtonCatalogCategory.feedbackAndStatus => 'Feedback and Status',
    ButtonCatalogCategory.systemWidgets => 'System Widgets',
  };
}

/// System Widgets entries are backed by the existing
/// [ControlArrangementConfig] toggles rather than a grid-placed [ButtonConfig]
/// — there is no ButtonType for "sensor row" or "LED row", these are already
/// modeled as whole-screen show/hide flags.
enum ArrangementToggle {
  sensorRow,
  liveLeds,
  connectionSubtitle;

  ControlArrangementConfig apply(ControlArrangementConfig config) =>
      switch (this) {
        ArrangementToggle.sensorRow => config.copyWith(
          showSensorRow: !config.showSensorRow,
        ),
        ArrangementToggle.liveLeds => config.copyWith(
          showLiveLEDs: !config.showLiveLEDs,
        ),
        ArrangementToggle.connectionSubtitle => config.copyWith(
          showConnectionSubtitle: !config.showConnectionSubtitle,
        ),
      };

  bool isEnabledIn(ControlArrangementConfig config) => switch (this) {
    ArrangementToggle.sensorRow => config.showSensorRow,
    ArrangementToggle.liveLeds => config.showLiveLEDs,
    ArrangementToggle.connectionSubtitle => config.showConnectionSubtitle,
  };
}

class ButtonCatalogEntry {
  const ButtonCatalogEntry({
    required this.category,
    required this.displayName,
    required this.description,
    required this.icon,
    this.buttonType,
    this.arrangementToggle,
  }) : assert(
         (buttonType == null) != (arrangementToggle == null),
         'Exactly one of buttonType/arrangementToggle must be set.',
       );

  final ButtonCatalogCategory category;
  final String displayName;
  final String description;
  final IconData icon;

  /// Null only for System Widgets entries (see [arrangementToggle]).
  final ButtonType? buttonType;

  /// Non-null only for System Widgets entries.
  final ArrangementToggle? arrangementToggle;
}

/// Default footprint shown on the catalog card — purely informational, the
/// same static table [ButtonConfig.defaultGridSizeFor] already owns. Resize
/// gestures are out of scope for this pass; this does not claim a widget can
/// be resized after placement, only what size it starts at.
(int, int) catalogGridSizeFor(ButtonType type) =>
    ButtonConfig.defaultGridSizeFor(type);

/// Whether [type]'s default footprint spans more than one grid cell — the
/// only "resize capability" signal that exists anywhere in the model layer
/// today (there is no separate resizable/canResize flag).
bool catalogIsResizableFor(ButtonType type) {
  final (cols, rows) = catalogGridSizeFor(type);
  return cols > 1 || rows > 1;
}

const List<ButtonCatalogEntry> kButtonCatalog = [
  // ── Digital Controls ────────────────────────────────────────────────────
  ButtonCatalogEntry(
    category: ButtonCatalogCategory.digitalControls,
    buttonType: ButtonType.pushButton,
    displayName: 'Push Button',
    description: 'Momentary or latched digital control.',
    icon: Icons.radio_button_checked_rounded,
  ),
  ButtonCatalogEntry(
    category: ButtonCatalogCategory.digitalControls,
    buttonType: ButtonType.toggle,
    displayName: 'Toggle Switch',
    description: 'Two- or three-position toggle switch.',
    icon: Icons.toggle_on_rounded,
  ),
  ButtonCatalogEntry(
    category: ButtonCatalogCategory.digitalControls,
    buttonType: ButtonType.sliderButton,
    displayName: 'Slider Button',
    description: 'Multi-step spring-return slider.',
    icon: Icons.tune_rounded,
  ),
  ButtonCatalogEntry(
    category: ButtonCatalogCategory.digitalControls,
    buttonType: ButtonType.bidirectionalSlider5Step,
    displayName: '5-Zone Slider',
    description: 'Bidirectional slider with five speed zones.',
    icon: Icons.linear_scale_rounded,
  ),
  ButtonCatalogEntry(
    category: ButtonCatalogCategory.digitalControls,
    buttonType: ButtonType.bidirectionalSlider3Step,
    displayName: '3-Zone Slider',
    description: 'Bidirectional slider with three speed zones.',
    icon: Icons.linear_scale_rounded,
  ),
  ButtonCatalogEntry(
    category: ButtonCatalogCategory.digitalControls,
    buttonType: ButtonType.joystick,
    displayName: 'Joystick',
    description: 'Single- or dual-axis digital joystick.',
    icon: Icons.control_camera_rounded,
  ),
  // ── Analog Controls ─────────────────────────────────────────────────────
  ButtonCatalogEntry(
    category: ButtonCatalogCategory.analogControls,
    buttonType: ButtonType.potentiometer,
    displayName: 'Potentiometer',
    description: 'Continuous analog rotary control.',
    icon: Icons.speed_rounded,
  ),
  ButtonCatalogEntry(
    category: ButtonCatalogCategory.analogControls,
    buttonType: ButtonType.analogJoystick1D,
    displayName: 'Analog Joystick (1-Axis)',
    description: 'Continuous single-axis analog joystick.',
    icon: Icons.swap_horiz_rounded,
  ),
  ButtonCatalogEntry(
    category: ButtonCatalogCategory.analogControls,
    buttonType: ButtonType.analogJoystick2D,
    displayName: 'Analog Joystick (2-Axis)',
    description: 'Continuous dual-axis analog joystick.',
    icon: Icons.control_camera_rounded,
  ),
  ButtonCatalogEntry(
    category: ButtonCatalogCategory.analogControls,
    buttonType: ButtonType.analogSliderOT,
    displayName: 'Analog Slider (O-T)',
    description: 'Continuous analog slider, off-to-throttle.',
    icon: Icons.multiline_chart_rounded,
  ),
  ButtonCatalogEntry(
    category: ButtonCatalogCategory.analogControls,
    buttonType: ButtonType.analogSliderTOT,
    displayName: 'Analog Slider (T-O-T)',
    description: 'Continuous analog slider, throttle-off-throttle.',
    icon: Icons.multiline_chart_rounded,
  ),
  // ── Feedback and Status ─────────────────────────────────────────────────
  ButtonCatalogEntry(
    category: ButtonCatalogCategory.feedbackAndStatus,
    buttonType: ButtonType.horn,
    displayName: 'Horn',
    description: 'PLC status-driven horn indicator.',
    icon: Icons.campaign_rounded,
  ),
  ButtonCatalogEntry(
    category: ButtonCatalogCategory.feedbackAndStatus,
    buttonType: ButtonType.alarmIndicator,
    displayName: 'Alarm Indicator',
    description: 'PLC status-driven alarm indicator.',
    icon: Icons.warning_amber_rounded,
  ),
  // ── System Widgets (ControlArrangementConfig toggles) ───────────────────
  ButtonCatalogEntry(
    category: ButtonCatalogCategory.systemWidgets,
    arrangementToggle: ArrangementToggle.sensorRow,
    displayName: 'Sensor Row',
    description: 'Shows the live analog sensor readout row.',
    icon: Icons.sensors_rounded,
  ),
  ButtonCatalogEntry(
    category: ButtonCatalogCategory.systemWidgets,
    arrangementToggle: ArrangementToggle.liveLeds,
    displayName: 'Live LED Row',
    description: 'Shows the live PLC output LED indicators.',
    icon: Icons.light_mode_rounded,
  ),
  ButtonCatalogEntry(
    category: ButtonCatalogCategory.systemWidgets,
    arrangementToggle: ArrangementToggle.connectionSubtitle,
    displayName: 'Connection Subtitle',
    description: 'Shows the connection status subtitle in the AppBar.',
    icon: Icons.wifi_tethering_rounded,
  ),
];
