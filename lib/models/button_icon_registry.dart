import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Button icon registry
//
// ButtonConfig.icon historically round-tripped through toJson/fromJson as a
// bare codePoint, which fromJson deliberately never restores (see
// ButtonConfig.icon's doc comment) — a codePoint alone can't reconstruct a
// real IconData once the font family/package are lost. This registry sidesteps
// that: every icon selectable from the customization sheet's icon picker
// comes from this fixed, curated map, addressed by a stable string key that
// IS safe to persist. ButtonConfig.iconKey stores the key; ButtonConfig.icon
// is resolved from kButtonIconChoices[iconKey] on load, giving a real,
// fully-specified IconData with zero ambiguity. Icons outside this set (e.g.
// a future hardcoded per-role default) are unaffected — they simply never
// have an iconKey and keep working exactly as before.
// ─────────────────────────────────────────────────────────────────────────────

const Map<String, IconData> kButtonIconChoices = {
  // Directional
  'arrow_up': Icons.arrow_upward_rounded,
  'arrow_down': Icons.arrow_downward_rounded,
  'arrow_left': Icons.arrow_back_rounded,
  'arrow_right': Icons.arrow_forward_rounded,
  'north': Icons.north_rounded,
  'south': Icons.south_rounded,
  'east': Icons.east_rounded,
  'west': Icons.west_rounded,
  'north_east': Icons.north_east_rounded,
  'north_west': Icons.north_west_rounded,
  'south_east': Icons.south_east_rounded,
  'south_west': Icons.south_west_rounded,
  'chevron_left': Icons.chevron_left_rounded,
  'chevron_right': Icons.chevron_right_rounded,
  'expand_less': Icons.expand_less_rounded,
  'expand_more': Icons.expand_more_rounded,
  'unfold_more': Icons.unfold_more_rounded,
  'unfold_less': Icons.unfold_less_rounded,
  'swap_vert': Icons.swap_vert_rounded,
  'swap_horiz': Icons.swap_horiz_rounded,
  'sync': Icons.sync_rounded,
  'rotate_right': Icons.rotate_right_rounded,

  // Controls / interaction
  'radio_checked': Icons.radio_button_checked,
  'radio_unchecked': Icons.radio_button_unchecked,
  'toggle_on': Icons.toggle_on_rounded,
  'toggle_off': Icons.toggle_off_rounded,
  'tune': Icons.tune_rounded,
  'gamepad': Icons.gamepad_rounded,
  'control_camera': Icons.control_camera_rounded,
  'touch_app': Icons.touch_app_rounded,
  'pan_tool': Icons.pan_tool_rounded,
  'restart_alt': Icons.restart_alt_rounded,
  'play_circle': Icons.play_circle_rounded,
  'pause_circle': Icons.pause_circle_rounded,
  'stop_circle': Icons.stop_circle_rounded,

  // Power / safety
  'power': Icons.power_settings_new_rounded,
  'bolt': Icons.bolt_rounded,
  'flash_on': Icons.flash_on_rounded,
  'electric_bolt': Icons.electric_bolt_rounded,
  'cable': Icons.cable_rounded,
  'warning': Icons.warning_amber_rounded,
  'dangerous': Icons.dangerous_rounded,
  'emergency': Icons.emergency_rounded,
  'lock': Icons.lock_rounded,
  'lock_open': Icons.lock_open_rounded,

  // Feedback / status
  'campaign': Icons.campaign_rounded,
  'volume_up': Icons.volume_up_rounded,
  'notifications_active': Icons.notifications_active_rounded,
  'vibration': Icons.vibration_rounded,
  'timer': Icons.timer_rounded,
  'speed': Icons.speed_rounded,
  'trending_up': Icons.trending_up_rounded,
  'trending_down': Icons.trending_down_rounded,

  // Industrial
  'build': Icons.build_rounded,
  'engineering': Icons.engineering_rounded,
  'precision_manufacturing': Icons.precision_manufacturing_rounded,
  'factory': Icons.factory_rounded,
  'local_shipping': Icons.local_shipping_rounded,
  'warehouse': Icons.warehouse_rounded,
  'height': Icons.height_rounded,
  'compress': Icons.compress_rounded,
  'open_in_full': Icons.open_in_full_rounded,
  'settings': Icons.settings_rounded,

  // Environmental
  'air': Icons.air_rounded,
  'water_drop': Icons.water_drop_rounded,
  'whatshot': Icons.whatshot_rounded,
  'ac_unit': Icons.ac_unit_rounded,

  // Shapes (generic markers)
  'crop_square': Icons.crop_square_rounded,
  'circle': Icons.circle,
  'hexagon': Icons.hexagon_rounded,
};

/// Reverse lookup — used by the icon picker to preselect the entry matching
/// the config's current icon, if any. Compares by codePoint/fontFamily/
/// fontPackage since [IconData] doesn't implement value equality by default
/// for const instances from different declarations.
String? iconKeyFor(IconData? icon) {
  if (icon == null) return null;
  for (final entry in kButtonIconChoices.entries) {
    final candidate = entry.value;
    if (candidate.codePoint == icon.codePoint &&
        candidate.fontFamily == icon.fontFamily &&
        candidate.fontPackage == icon.fontPackage) {
      return entry.key;
    }
  }
  return null;
}

/// Resolves a persisted [iconKey] back to a real, fully-specified [IconData].
/// Returns null for an unknown/missing key (including legacy JSON with no
/// iconKey at all) — callers fall back to their own type/role default exactly
/// as they did before this registry existed.
IconData? iconForKey(String? iconKey) {
  if (iconKey == null) return null;
  return kButtonIconChoices[iconKey];
}
