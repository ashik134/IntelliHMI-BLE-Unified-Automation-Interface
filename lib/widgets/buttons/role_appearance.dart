import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Role appearance lookup — kept in the widget layer so control_role.dart
// stays free of Flutter/Material imports. Shared by the button-type
// strategies (ConfigurableButton's rendering path) and ButtonEditSheet, so
// the default icon/color per role is defined exactly once.
// ─────────────────────────────────────────────────────────────────────────────

IconData iconForRole(ControlRole role) => switch (role) {
  ControlRole.hoistUp => Icons.arrow_upward_rounded,
  ControlRole.hoistDown => Icons.arrow_downward_rounded,
  ControlRole.traverseLeft => Icons.arrow_back_rounded,
  ControlRole.traverseRight => Icons.arrow_forward_rounded,
  ControlRole.travelForward => Icons.north_rounded,
  ControlRole.travelReverse => Icons.south_rounded,
  ControlRole.estop => Icons.power_settings_new_rounded,
  ControlRole.resetEstop => Icons.restart_alt_rounded,
};

(Color, Color) colorsForRole(ControlRole role) => switch (role) {
  ControlRole.hoistUp => (AppColors.upColor, AppColors.upColorLight),
  ControlRole.hoistDown => (AppColors.downColor, AppColors.downColorLight),
  ControlRole.traverseLeft || ControlRole.traverseRight => (
    AppColors.traverseColor,
    AppColors.traverseColorLight,
  ),
  ControlRole.travelForward || ControlRole.travelReverse => (
    AppColors.travelColor,
    AppColors.travelColorLight,
  ),
  ControlRole.estop => (AppColors.eStopColor, AppColors.eStopColorLight),
  ControlRole.resetEstop => (AppColors.eStopColor, AppColors.eStopColorLight),
};
