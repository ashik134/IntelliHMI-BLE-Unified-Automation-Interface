import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/alarm_indicator_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AlarmIndicatorControl
//
// Read-mostly monitor widget: renders an AlarmSeverity with the appropriate
// red/amber/green styling and blink/pulse animation. Never asserts a PLC
// output on its own — see AlarmIndicatorConfig.acknowledgeEnabled doc. The
// severity is entirely caller-supplied (today: derived from ControlState by
// AlarmIndicatorStrategy; later: real PLC status feedback) — this widget has
// no PLC/controller awareness of its own.
// ─────────────────────────────────────────────────────────────────────────────

class AlarmIndicatorControl extends StatefulWidget {
  const AlarmIndicatorControl({
    super.key,
    required this.label,
    required this.severity,
    required this.enabled,
    this.config = const AlarmIndicatorConfig(),
    this.statusText,
    this.timestampText,
    this.onAcknowledge,
  });

  final String label;
  final AlarmSeverity severity;
  final bool enabled;
  final AlarmIndicatorConfig config;

  /// Optional freeform status line (e.g. "Hoist over-temp"). Falls back to a
  /// generic per-severity label when null/empty.
  final String? statusText;

  /// Optional small timestamp/message area, e.g. "14:32:07".
  final String? timestampText;

  /// Only ever invoked when [config.acknowledgeEnabled] is true AND
  /// [severity] is acknowledgeable (alarm/critical/warning) — see
  /// _isAcknowledgeable. Null (the default via strategy wiring) makes this
  /// widget purely passive/view-only.
  final VoidCallback? onAcknowledge;

  static bool isAcknowledgeable(AlarmSeverity severity) =>
      severity == AlarmSeverity.warning ||
      severity == AlarmSeverity.alarm ||
      severity == AlarmSeverity.critical;

  @override
  State<AlarmIndicatorControl> createState() => _AlarmIndicatorControlState();
}

class _AlarmIndicatorControlState extends State<AlarmIndicatorControl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant AlarmIndicatorControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.severity != widget.severity) _syncAnimation();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _syncAnimation() {
    if (_isAnimated(widget.severity)) {
      if (!_pulseCtrl.isAnimating) _pulseCtrl.repeat(reverse: true);
    } else {
      _pulseCtrl.stop();
      _pulseCtrl.value = 0.0;
    }
  }

  bool _isAnimated(AlarmSeverity severity) =>
      severity == AlarmSeverity.alarm || severity == AlarmSeverity.critical;

  void _handleTap() {
    if (!widget.enabled) return;
    if (!widget.config.acknowledgeEnabled) return;
    if (!AlarmIndicatorControl.isAcknowledgeable(widget.severity)) return;
    HapticFeedback.selectionClick();
    widget.onAcknowledge?.call();
  }

  @override
  Widget build(BuildContext context) {
    final canAcknowledge =
        widget.enabled &&
        widget.config.acknowledgeEnabled &&
        AlarmIndicatorControl.isAcknowledgeable(widget.severity);

    return Semantics(
      label: widget.label,
      value: _severityLabel(widget.severity),
      button: canAcknowledge,
      enabled: widget.enabled,
      child: GestureDetector(
        onTap: canAcknowledge ? _handleTap : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (context, _) {
            return _AlarmContent(
              label: widget.label,
              severity: widget.severity,
              enabled: widget.enabled,
              pulseT: _pulseCtrl.value,
              statusText: widget.statusText,
              timestampText: widget.timestampText,
              showStatusText: widget.config.showStatusText,
              showTimestamp:
                  widget.config.showTimestamp &&
                  (widget.timestampText?.isNotEmpty ?? false),
              canAcknowledge: canAcknowledge,
            );
          },
        ),
      ),
    );
  }
}

String _severityLabel(AlarmSeverity severity) => switch (severity) {
  AlarmSeverity.normal => 'Normal',
  AlarmSeverity.warning => 'Warning',
  AlarmSeverity.alarm => 'Alarm',
  AlarmSeverity.critical => 'Critical',
  AlarmSeverity.muted => 'Muted / Acknowledged',
};

(Color, Color) _colorsForSeverity(AlarmSeverity severity) => switch (severity) {
  AlarmSeverity.normal => (AppColors.darkSuccess, AppColors.darkSuccess),
  AlarmSeverity.warning => (AppColors.fastColor, AppColors.fastColorLight),
  AlarmSeverity.alarm => (AppColors.darkDanger, AppColors.eStopColorLight),
  AlarmSeverity.critical => (AppColors.eStopColor, AppColors.eStopColorLight),
  AlarmSeverity.muted => (AppColors.darkTextSub, AppColors.darkTextSub),
};

IconData _iconForSeverity(AlarmSeverity severity) => switch (severity) {
  AlarmSeverity.normal => Icons.check_circle_rounded,
  AlarmSeverity.warning => Icons.warning_rounded,
  AlarmSeverity.alarm => Icons.notification_important_rounded,
  AlarmSeverity.critical => Icons.dangerous_rounded,
  AlarmSeverity.muted => Icons.notifications_off_rounded,
};

class _AlarmContent extends StatelessWidget {
  const _AlarmContent({
    required this.label,
    required this.severity,
    required this.enabled,
    required this.pulseT,
    required this.statusText,
    required this.timestampText,
    required this.showStatusText,
    required this.showTimestamp,
    required this.canAcknowledge,
  });

  final String label;
  final AlarmSeverity severity;
  final bool enabled;
  final double pulseT;
  final String? statusText;
  final String? timestampText;
  final bool showStatusText;
  final bool showTimestamp;
  final bool canAcknowledge;

  @override
  Widget build(BuildContext context) {
    final (color, colorLight) = _colorsForSeverity(severity);
    final isBlinking = severity == AlarmSeverity.alarm;
    final isPulsing = severity == AlarmSeverity.critical;
    final blinkOn = !isBlinking || pulseT < 0.5;
    final pulseScale = isPulsing ? 1.0 + math.sin(pulseT * math.pi) * 0.06 : 1.0;
    final effectiveColor = enabled
        ? color
        : AppColors.disabled;
    final effectiveColorLight = enabled ? colorLight : AppColors.disabled;
    final glyphVisible = enabled && (isBlinking ? blinkOn : true);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxHeight < 100 || constraints.maxWidth < 130;

        return Container(
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(compact ? 10 : 14),
            border: Border.all(
              color: enabled
                  ? effectiveColor.withAlpha(isBlinking && !blinkOn ? 70 : 190)
                  : AppColors.darkBorder,
              width: 1.4,
            ),
            boxShadow: enabled && (isBlinking ? blinkOn : isPulsing)
                ? [
                    BoxShadow(
                      color: effectiveColor.withAlpha(
                        isPulsing ? (70 + pulseT * 60).round() : 110,
                      ),
                      blurRadius: isPulsing ? 10 + pulseT * 10 : 12,
                      spreadRadius: isPulsing ? pulseT * 2 : 1,
                    ),
                  ]
                : null,
          ),
          padding: compact
              ? const EdgeInsets.fromLTRB(8, 6, 8, 6)
              : const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: pulseScale,
                    child: Icon(
                      _iconForSeverity(severity),
                      size: compact ? 18 : 22,
                      color: glyphVisible
                          ? effectiveColorLight
                          : effectiveColor.withAlpha(60),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.darkText,
                        fontSize: compact ? 10 : 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 4 : 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: effectiveColor.withAlpha(enabled ? 40 : 20),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _severityLabel(severity).toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: effectiveColorLight,
                    fontSize: compact ? 8 : 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              if (showStatusText && (statusText?.isNotEmpty ?? false)) ...[
                SizedBox(height: compact ? 3 : 5),
                Text(
                  statusText!,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.darkTextSub,
                    fontSize: compact ? 8 : 9.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (showTimestamp) ...[
                const SizedBox(height: 2),
                Text(
                  timestampText!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.darkTextMuted,
                    fontSize: 8,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (canAcknowledge) ...[
                SizedBox(height: compact ? 3 : 5),
                Text(
                  'TAP TO ACK',
                  style: TextStyle(
                    color: AppColors.darkTextMuted.withAlpha(200),
                    fontSize: 7,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
