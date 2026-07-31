import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Role appearance lookup — kept in the widget layer so control_role.dart
// stays free of Flutter/Material imports. Only the two safety controls
// (E-STOP, Reset E-STOP) have a fixed role/appearance; every other control
// is a generic ButtonConfig (role: null) and gets its default icon/color
// straight from its own button-type strategy's fallback instead.
// ─────────────────────────────────────────────────────────────────────────────

IconData iconForRole(ControlRole role) => switch (role) {
  ControlRole.estop => Icons.power_settings_new_rounded,
  ControlRole.resetEstop => Icons.restart_alt_rounded,
};

(Color, Color) colorsForRole(ControlRole role) => switch (role) {
  ControlRole.estop => (AppColors.eStopColor, AppColors.eStopColorLight),
  ControlRole.resetEstop => (AppColors.eStopColor, AppColors.eStopColorLight),
};
