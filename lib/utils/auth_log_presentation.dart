import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/auth_log_entry.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/widgets/shared/brand_widgets.dart';

/// Shared presentation helpers for [AuthLogEntry] — used by both the Event
/// Log table (event_log_screen.dart) and the Event Details push target
/// (event_detail_screen.dart) so tone/icon/label logic never drifts between
/// the two views.

BrandTone toneForLogEntry(AuthLogEntry entry) {
  switch (entry.category) {
    case AuthLogCategory.authentication:
      switch (entry.result) {
        case AuthEventResult.success:
          return BrandTone.success;
        case AuthEventResult.failed:
        case AuthEventResult.error:
          return BrandTone.danger;
        case AuthEventResult.cancelled:
          return BrandTone.warning;
        case null:
          return BrandTone.neutral;
      }
    case AuthLogCategory.operatorManagement:
      return BrandTone.info;
    case AuthLogCategory.system:
      return BrandTone.neutral;
  }
}

Color toneColorFor(BrandTone tone) {
  switch (tone) {
    case BrandTone.success:
      return AppColors.brandSuccess;
    case BrandTone.danger:
      return AppColors.brandDanger;
    case BrandTone.warning:
      return AppColors.brandWarning;
    case BrandTone.info:
      return AppColors.brandInfo;
    case BrandTone.violet:
      return AppColors.brandViolet;
    case BrandTone.neutral:
      return AppColors.brandTextSub;
  }
}

IconData iconForLogEntry(AuthLogEntry entry) {
  switch (entry.category) {
    case AuthLogCategory.authentication:
      switch (entry.method) {
        case AuthEventMethod.biometric:
          return Icons.fingerprint_rounded;
        case AuthEventMethod.face:
          return Icons.face_retouching_natural_rounded;
        case AuthEventMethod.pin:
          return Icons.pin_rounded;
        case AuthEventMethod.password:
        case null:
          return Icons.lock_outline_rounded;
      }
    case AuthLogCategory.operatorManagement:
      return Icons.badge_outlined;
    case AuthLogCategory.system:
      return Icons.info_outline_rounded;
  }
}

String titleForLogEntry(AuthLogEntry entry) {
  switch (entry.category) {
    case AuthLogCategory.authentication:
      final method = entry.method?.displayName ?? 'Unknown';
      return '$method Authentication';
    case AuthLogCategory.operatorManagement:
      return entry.lifecycleEvent?.displayName ?? 'Operator Management';
    case AuthLogCategory.system:
      return 'System Notice';
  }
}

String subtitleForLogEntry(AuthLogEntry entry) {
  final name = entry.operatorNameSnapshot ?? entry.userIdentifier;
  if (name == null) return entry.category.displayName;
  if (entry.role == null) return name;
  return '$name · ${entry.role}';
}

String badgeLabelForLogEntry(AuthLogEntry entry) {
  if (entry.result != null) return entry.result!.displayName.toUpperCase();
  if (entry.lifecycleEvent != null) {
    return entry.lifecycleEvent!.displayName.toUpperCase();
  }
  return entry.category.displayName.toUpperCase();
}

/// Display name for the operator/user attached to [entry], or `null` when
/// the event carries no identity (e.g. a bare system notice).
String? operatorLabelForLogEntry(AuthLogEntry entry) =>
    entry.operatorNameSnapshot ?? entry.userIdentifier;

/// The PLC/MAC ID this event belongs to, or `null` when the event isn't
/// tied to a specific connected PLC (e.g. operator-management or
/// app-startup system events).
String? macIdForLogEntry(AuthLogEntry entry) => entry.plcDeviceId;

String _two(int v) => v.toString().padLeft(2, '0');

const _kMonthAbbr = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Full timestamp, e.g. "2026-09-08 09:14:32" — used on the Event Details
/// screen where there's room to be unambiguous.
String formatLogTimestampFull(DateTime timestamp) {
  final t = timestamp.toLocal();
  return '${t.year}-${_two(t.month)}-${_two(t.day)} '
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
}

/// Short date only, e.g. "Sep 8" — used for date-range filter labels.
String formatDateShort(DateTime date) {
  final d = date.toLocal();
  return '${_kMonthAbbr[d.month - 1]} ${d.day}';
}

/// Compact timestamp for the table's TIME column — just "HH:mm" for events
/// from today, otherwise "MMM d, HH:mm" so older rows still sort/scan
/// sensibly without eating column width.
String formatLogTimestampCompact(DateTime timestamp) {
  final t = timestamp.toLocal();
  final now = DateTime.now();
  final isToday =
      t.year == now.year && t.month == now.month && t.day == now.day;
  final time = '${_two(t.hour)}:${_two(t.minute)}';
  if (isToday) return time;
  return '${_kMonthAbbr[t.month - 1]} ${t.day}, $time';
}
