import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/ble_scan_device.dart';
import 'package:rev_crane_control_ops/widgets/circular_progress_indicator.dart';

// ═══════════════════════════════════════════════════════════
// Shared card geometry
//
// Both rows in the devices list — an advertising device and the one being
// connected to — render through [_DeviceCardShell], so they occupy exactly
// the same footprint. Only colour, the avatar's activity ring and the
// trailing action differ between them.
// ═══════════════════════════════════════════════════════════

abstract final class _CardSpec {
  /// Every device row is at least this tall, whichever card renders it.
  /// A minimum (rather than a fixed height) so the row still grows instead
  /// of overflowing under a large system text scale — and because both
  /// cards share this shell, they grow by the same amount.
  static const double minHeight = 68;

  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 11,
    vertical: 12,
  );
  static const double radius = AppMetrics.radiusMd;

  static const double avatar = 40;
  static const double avatarIcon = 20;
  static const double avatarRadius = 12;

  static const double gapAvatar = 10;
  static const double gapAction = 8;

  static const double actionWidth = 74;
  static const double actionWidthNarrow = 38;
  static const double actionHeight = 36;
  static const double actionRadius = 10;

  /// Below this card width the trailing action collapses to an icon, so a
  /// ~320 dp phone still lays out cleanly.
  static const double narrowBreakpoint = 272;

  /// The signal bars always show; the dBm read-out next to them only earns
  /// its width once the device name is no longer competing for it.
  static const double rssiValueBreakpoint = 320;

  /// Above this there is room to spell the PLC model out in full instead of
  /// using its short code.
  static const double roomyBreakpoint = 380;
}

// ═══════════════════════════════════════════════════════════
// Available Device Card
// ═══════════════════════════════════════════════════════════

class AvailableDeviceCard extends StatelessWidget {
  const AvailableDeviceCard({
    super.key,
    required this.device,
    required this.connecting,
    required this.onConnect,
  });

  final BleScanDevice device;
  final bool connecting;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final staleStatus = device.staleStatus;
    final isStale = staleStatus != DeviceStaleStatus.active;
    final isExpired = staleStatus == DeviceStaleStatus.expired;

    // Dimmer when another device is connecting
    final double opacity = connecting ? 0.45 : (isExpired ? 0.70 : 1.0);

    return AnimatedOpacity(
      opacity: opacity,
      duration: const Duration(milliseconds: 300),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final narrow = width < _CardSpec.narrowBreakpoint;

          return _DeviceCardShell(
            background: isStale
                ? AppColors.brandWarningSoft
                : AppColors.brandSurfaceAlt,
            borderColor: isStale
                ? AppColors.brandWarning.withAlpha(80)
                : AppColors.brandBorder,
            avatar: _DeviceAvatar(
              background: isStale
                  ? AppColors.brandWarning.withAlpha(28)
                  : AppColors.brandVioletSoft,
              borderColor: isStale
                  ? AppColors.brandWarning.withAlpha(70)
                  : AppColors.brandViolet.withAlpha(45),
              tint: isStale
                  ? AppColors.brandWarning
                  : AppColors.brandVioletDeep,
            ),
            name: device.name,
            nameColor: isStale ? AppColors.brandTextSub : AppColors.brandText,
            deviceId: device.id,
            plcType: device.plcType,
            fullPlcName: width >= _CardSpec.roomyBreakpoint,
            titleTrailing: _SignalBars(
              rssi: device.rssi,
              showValue: width >= _CardSpec.rssiValueBreakpoint,
              muted: isStale,
            ),
            // A stale advertisement can't be connected to, but the slot keeps
            // its footprint so every row in the list stays aligned.
            action: isStale
                ? _ActionStatusChip(
                    narrow: narrow,
                    label: isExpired ? 'LOST' : 'STALE',
                    icon: Icons.warning_amber_rounded,
                    foreground: AppColors.brandWarning,
                    background: AppColors.brandWarning.withAlpha(28),
                    borderColor: AppColors.brandWarning.withAlpha(80),
                  )
                : _ActionSlot(
                    narrow: narrow,
                    child: FilledButton(
                      // Disabled rather than hidden while another device is
                      // being connected: the row keeps its shape and still
                      // reads as unavailable.
                      onPressed: connecting ? null : onConnect,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brandViolet,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.brandBorderStrong,
                        disabledForegroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            _CardSpec.actionRadius,
                          ),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      child: narrow
                          ? const Icon(Icons.link_rounded, size: 18)
                          : const _ActionLabel('CONNECT'),
                    ),
                  ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Connected Device Card
// ═══════════════════════════════════════════════════════════

class ConnectedDeviceCard extends StatelessWidget {
  const ConnectedDeviceCard({
    super.key,
    required this.device,
    required this.onCancel,
    this.isCancelling = false,
  });

  final BleScanDevice device;
  final VoidCallback onCancel;
  final bool isCancelling;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final narrow = width < _CardSpec.narrowBreakpoint;

        return _DeviceCardShell(
          background: AppColors.brandVioletSoft,
          borderColor: AppColors.brandViolet.withAlpha(90),
          avatar: _DeviceAvatar(
            background: Colors.white,
            borderColor: AppColors.brandViolet.withAlpha(60),
            tint: AppColors.brandVioletDeep,
            // The activity ring lives inside the avatar so this card keeps
            // the same single-row footprint as an available one.
            showActivityRing: true,
            // Ring stops turning once the abort is under way.
            ringAnimating: !isCancelling,
          ),
          name: device.name,
          nameColor: AppColors.brandText,
          deviceId: device.id,
          plcType: device.plcType,
          fullPlcName: width >= _CardSpec.roomyBreakpoint,
          titleTrailing: _SignalBars(
            rssi: device.rssi,
            showValue: width >= _CardSpec.rssiValueBreakpoint,
          ),
          action: _ActionSlot(
            narrow: narrow,
            child: OutlinedButton(
              onPressed: isCancelling ? null : onCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brandTextSub,
                backgroundColor: Colors.white,
                side: BorderSide(
                  color: isCancelling
                      ? AppColors.brandBorder
                      : AppColors.brandBorderStrong,
                ),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_CardSpec.actionRadius),
                ),
                textStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              child: isCancelling
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.brandTextMuted,
                      ),
                    )
                  : (narrow
                        ? const Icon(Icons.close_rounded, size: 18)
                        : const _ActionLabel('CANCEL')),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Card Shell — the single source of truth for row geometry
// ═══════════════════════════════════════════════════════════

class _DeviceCardShell extends StatelessWidget {
  const _DeviceCardShell({
    required this.background,
    required this.borderColor,
    required this.avatar,
    required this.name,
    required this.nameColor,
    required this.deviceId,
    required this.plcType,
    required this.fullPlcName,
    required this.titleTrailing,
    required this.action,
  });

  final Color background;
  final Color borderColor;
  final Widget avatar;
  final String name;
  final Color nameColor;
  final String deviceId;
  final PlcType plcType;
  final bool fullPlcName;
  final Widget titleTrailing;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      constraints: const BoxConstraints(minHeight: _CardSpec.minHeight),
      padding: _CardSpec.padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(_CardSpec.radius),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: _CardSpec.gapAvatar),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: nameColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    titleTrailing,
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    _PlcTypeBadge(plcType: plcType, full: fullPlcName),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        deviceId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.brandTextMuted,
                          fontSize: 9.5,
                          fontFamily: 'monospace',
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: _CardSpec.gapAction),
          action,
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Device Avatar
// ═══════════════════════════════════════════════════════════

class _DeviceAvatar extends StatelessWidget {
  const _DeviceAvatar({
    required this.background,
    required this.borderColor,
    required this.tint,
    this.showActivityRing = false,
    this.ringAnimating = false,
  });

  final Color background;
  final Color borderColor;
  final Color tint;
  final bool showActivityRing;
  final bool ringAnimating;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _CardSpec.avatar,
      height: _CardSpec.avatar,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(_CardSpec.avatarRadius),
                border: Border.all(color: borderColor),
              ),
            ),
          ),
          if (showActivityRing)
            CustomCircularStepProgressIndicator(
              totalSteps: 20,
              currentStep: 12,
              stepSize: 2.5,
              width: _CardSpec.avatar,
              height: _CardSpec.avatar,
              selectedColor: AppColors.brandViolet,
              unselectedColor: Colors.transparent,
              padding: math.pi / 80,
              startingAngle: -math.pi * 2 / 3,
              arcSize: math.pi * 2 / 3 * 2,
              gradientColor: const LinearGradient(
                colors: [AppColors.brandViolet, AppColors.brandVioletDeep],
              ),
              showStepDots: false,
              showGlow: false,
              isAnimating: ringAnimating,
            ),
          // Sized explicitly: the surrounding Stack hands down tight
          // constraints, which an unwrapped Image would stretch to fill.
          SizedBox(
            width: _CardSpec.avatarIcon,
            height: _CardSpec.avatarIcon,
            child: Image.asset(
              'assets/icons/Connector.png',
              color: tint,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Trailing action slot — fixed footprint shared by every card state
// ═══════════════════════════════════════════════════════════

class _ActionSlot extends StatelessWidget {
  const _ActionSlot({required this.narrow, required this.child});

  final bool narrow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: narrow ? _CardSpec.actionWidthNarrow : _CardSpec.actionWidth,
      height: _CardSpec.actionHeight,
      child: child,
    );
  }
}

/// Button caption for the action slot. The slot has a fixed width so rows
/// stay aligned, so the caption scales down rather than spilling out of it
/// once the system text scale grows.
class _ActionLabel extends StatelessWidget {
  const _ActionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(label, maxLines: 1),
      ),
    );
  }
}

/// Non-interactive stand-in for a button, e.g. the STALE marker on a device
/// that stopped advertising. Same footprint as [_ActionSlot]'s buttons.
class _ActionStatusChip extends StatelessWidget {
  const _ActionStatusChip({
    required this.narrow,
    required this.label,
    required this.icon,
    required this.foreground,
    required this.background,
    required this.borderColor,
  });

  final bool narrow;
  final String label;
  final IconData icon;
  final Color foreground;
  final Color background;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return _ActionSlot(
      narrow: narrow,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(_CardSpec.actionRadius),
          border: Border.all(color: borderColor),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 13, color: foreground),
                if (!narrow) ...[
                  const SizedBox(width: 4),
                  Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: foreground,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Signal Strength
// ═══════════════════════════════════════════════════════════

class _SignalBars extends StatelessWidget {
  const _SignalBars({
    required this.rssi,
    this.showValue = true,
    this.muted = false,
  });

  final int rssi;
  final bool showValue;
  final bool muted;

  /// Bar count follows the same tiers as [BleScanDevice.signalLabel].
  int get _level => rssi >= -55
      ? 4
      : rssi >= -68
      ? 3
      : rssi >= -80
      ? 2
      : 1;

  Color get _tone {
    if (muted) return AppColors.brandTextMuted;
    return rssi >= -68
        ? AppColors.brandSuccess
        : rssi >= -80
        ? AppColors.brandWarning
        : AppColors.brandDanger;
  }

  @override
  Widget build(BuildContext context) {
    final tone = _tone;
    final level = _level;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (int bar = 1; bar <= 4; bar++) ...[
          if (bar > 1) const SizedBox(width: 1.5),
          Container(
            width: 2.5,
            height: 3 + bar * 2.2,
            decoration: BoxDecoration(
              color: bar <= level ? tone : AppColors.brandBorderStrong,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
        if (showValue) ...[
          const SizedBox(width: 5),
          Text(
            '$rssi',
            style: TextStyle(
              color: tone,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// PLC Type Badge
// ═══════════════════════════════════════════════════════════

class _PlcTypeBadge extends StatelessWidget {
  const _PlcTypeBadge({required this.plcType, this.full = false});

  final PlcType plcType;

  /// Spell the model out ("IntelliKran MAX") instead of its short code.
  /// Only affordable on wide cards — on a phone the meta row has to leave
  /// room for the device address next to it.
  final bool full;

  bool get _isKnown => plcType != PlcType.unknown;

  String get _label {
    if (full) return plcType.displayName;
    switch (plcType) {
      case PlcType.plc14:
        return 'MIN';
      case PlcType.plc21:
        return 'MID';
      case PlcType.plc38:
        return 'MAX';
      case PlcType.unknown:
        return 'N/A';
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color bg = _isKnown
        ? AppColors.brandViolet.withAlpha(24)
        : AppColors.brandSurfaceAlt;
    final Color border = _isKnown
        ? AppColors.brandViolet.withAlpha(70)
        : AppColors.brandBorder;
    final Color textColor = _isKnown
        ? AppColors.brandVioletDeep
        : AppColors.brandTextMuted;

    return Tooltip(
      message: plcType.displayName,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: border),
        ),
        child: Text(
          _label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: textColor,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}
