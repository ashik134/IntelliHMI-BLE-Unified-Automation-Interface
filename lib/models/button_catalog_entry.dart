import 'package:rev_crane_control_ops/models/control_layout_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ArrangementToggle
//
// System Widgets entries are backed by the existing [ControlArrangementConfig]
// toggles rather than a grid-placed [ButtonConfig] — there is no ButtonType
// for "sensor row" or "LED row", these are already modeled as whole-screen
// show/hide flags. Surfaced today via the Layout Settings sheet's SYSTEM
// WIDGETS section (see layout_settings_sheet.dart) — the Widget Catalogue
// (see widget_catalog.dart) is scoped to control widgets only and does not
// list these.
// ─────────────────────────────────────────────────────────────────────────────

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
