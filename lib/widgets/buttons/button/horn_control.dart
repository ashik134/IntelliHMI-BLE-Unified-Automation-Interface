import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/button_rotation.dart';
import 'package:rev_crane_control_ops/models/horn_config.dart';
import 'package:rev_crane_control_ops/services/buzzer_tone_service.dart';
import 'package:rev_crane_control_ops/widgets/buttons/control_button_visuals.dart';

// ─────────────────────────────────────────────────────────────────────────────
// IndustrialHornControl
//
// Pure PLC-status FEEDBACK widget — a horn/buzzer that reflects whether its
// configured trigger condition is currently true. It has no gestures: it is
// never tapped, pressed, or dragged, and it never calls back into the app
// (no onPressed/onChanged/onCommand). [isActive] is caller-supplied (see
// HornButtonStrategy, which derives it from live PLC output/status fields),
// and this widget only ever renders that boolean — plus starts/stops the
// optional local buzzer tone, sound-ring animation, and haptic pulse.
// ─────────────────────────────────────────────────────────────────────────────

class IndustrialHornControl extends StatefulWidget {
  const IndustrialHornControl({
    super.key,
    required this.label,
    required this.activeColor,
    required this.activeColorLight,
    required this.isActive,
    required this.enabled,
    this.icon = Icons.campaign_rounded,
    this.config = const HornConfig(),
    this.rotation = ButtonRotation.none,
  });

  final String label;
  final IconData icon;
  final Color activeColor;
  final Color activeColorLight;
  final ButtonRotation rotation;

  /// Whether the configured PLC condition is currently true. Purely
  /// caller-supplied — this widget never evaluates or sends anything itself.
  final bool isActive;
  final bool enabled;
  final HornConfig config;

  @override
  State<IndustrialHornControl> createState() => _IndustrialHornControlState();
}

class _IndustrialHornControlState extends State<IndustrialHornControl>
    with TickerProviderStateMixin {
  late final AnimationController _ringCtrl;
  late final String _buzzerId;

  @override
  void initState() {
    super.initState();
    _buzzerId = 'horn-${identityHashCode(this)}';
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    if (_isActiveForEffects(widget)) {
      unawaited(_triggerHaptic());
      unawaited(_startSound());
      _startRing();
    }
  }

  @override
  void didUpdateWidget(covariant IndustrialHornControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasActive = _isActiveForEffects(oldWidget);
    final isActive = _isActiveForEffects(widget);
    if (isActive && !wasActive) {
      unawaited(_triggerHaptic());
    }
    _syncSound(oldWidget);
    if (isActive && widget.config.visualPulseEnabled) {
      if (!wasActive ||
          !oldWidget.config.visualPulseEnabled ||
          oldWidget.enabled != widget.enabled) {
        _startRing();
      }
    } else {
      _ringCtrl.stop();
    }
  }

  @override
  void dispose() {
    _stopSound();
    _ringCtrl.dispose();
    super.dispose();
  }

  bool _isActiveForEffects(IndustrialHornControl control) {
    return control.enabled && control.isActive;
  }

  bool _isSounding(IndustrialHornControl control) {
    return _isActiveForEffects(control) && control.config.soundEnabled;
  }

  void _syncSound(IndustrialHornControl oldWidget) {
    final wasSounding = _isSounding(oldWidget);
    final shouldSound = _isSounding(widget);
    final toneChanged =
        oldWidget.config.soundPattern != widget.config.soundPattern ||
        oldWidget.config.priority != widget.config.priority;

    if (shouldSound && (!wasSounding || toneChanged)) {
      unawaited(_startSound());
    } else if (wasSounding && !shouldSound) {
      _stopSound();
    }
  }

  void _startRing() {
    if (!widget.enabled || !widget.config.visualPulseEnabled) return;
    _ringCtrl
      ..reset()
      ..repeat();
  }

  Future<void> _triggerHaptic() async {
    if (!widget.enabled || !widget.config.hapticFeedback) return;
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {
      try {
        await HapticFeedback.selectionClick();
      } catch (_) {}
    }
  }

  Future<void> _startSound() async {
    if (!widget.enabled || !widget.config.soundEnabled) return;
    await BuzzerToneService.start(
      id: _buzzerId,
      pattern: widget.config.soundPattern,
      priority: widget.config.priority,
    );
  }

  void _stopSound() {
    unawaited(BuzzerToneService.stop(id: _buzzerId));
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.enabled && widget.isActive;
    return Semantics(
      label: widget.label,
      value: isActive ? 'Sounding' : 'Idle',
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _ringCtrl,
          builder: (context, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.hasBoundedWidth
                    ? constraints.maxWidth
                    : 152.0;
                final height = constraints.hasBoundedHeight
                    ? constraints.maxHeight
                    : 120.0;
                return SizedBox(
                  width: constraints.hasBoundedWidth ? double.infinity : width,
                  height: constraints.hasBoundedHeight
                      ? double.infinity
                      : height,
                  child: _HornContent(
                    label: widget.label,
                    icon: widget.icon,
                    activeColor: widget.activeColor,
                    activeColorLight: widget.activeColorLight,
                    rotation: widget.rotation,
                    ringT: _ringCtrl.value,
                    isActive: isActive,
                    isEnabled: widget.enabled,
                    showRing: widget.config.visualPulseEnabled,
                    pattern: widget.config.soundPattern,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _HornContent extends StatelessWidget {
  const _HornContent({
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.activeColorLight,
    this.rotation = ButtonRotation.none,
    required this.ringT,
    required this.isActive,
    required this.isEnabled,
    required this.showRing,
    required this.pattern,
  });

  final String label;
  final IconData icon;
  final Color activeColor;
  final Color activeColorLight;
  final ButtonRotation rotation;
  final double ringT;
  final bool isActive;
  final bool isEnabled;
  final bool showRing;
  final HornSoundPattern pattern;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxHeight < 96 || constraints.maxWidth < 120;
        final statusLabel = !isEnabled
            ? 'LOCKED'
            : isActive
            ? 'SOUNDING'
            : 'READY';

        return Padding(
          padding: compact
              ? const EdgeInsets.fromLTRB(8, 6, 8, 6)
              : const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: compact ? 16 : 20,
                child: Row(
                  children: [
                    _StatusDot(
                      color: activeColor,
                      isActive: isActive,
                      isEnabled: isEnabled,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        statusLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isActive
                              ? activeColorLight
                              : AppColors.darkTextSub,
                          fontSize: compact ? 8 : 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: compact ? 4 : 6),
              Expanded(
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final diameter = math
                          .min(box.maxWidth, box.maxHeight)
                          .clamp(48.0, 120.0);
                      return SizedBox.square(
                        dimension: diameter,
                        child: CustomPaint(
                          painter: _HornPainter(
                            activeColor: activeColor,
                            activeColorLight: activeColorLight,
                            isActive: isActive,
                            isEnabled: isEnabled,
                            ringT: ringT,
                            showRing: showRing,
                            pattern: pattern,
                          ),
                          child: Center(
                            child: Icon(
                              icon,
                              size: diameter * 0.34,
                              color: !isEnabled
                                  ? AppColors.darkTextSub.withAlpha(120)
                                  : isActive
                                  ? Colors.white
                                  : activeColorLight,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withAlpha(
                                    isActive ? 150 : 90,
                                  ),
                                  blurRadius: isActive ? 8 : 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              SizedBox(height: compact ? 3 : 5),
              SizedBox(
                height: ControlButtonVisualMetrics.rowHeight,
                child: ControlButtonLabelIcon(
                  label: label,
                  color: !isEnabled
                      ? AppColors.darkTextMuted
                      : AppColors.darkText,
                  showIcon: false,
                  rotation: rotation,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({
    required this.color,
    required this.isActive,
    required this.isEnabled,
  });

  final Color color;
  final bool isActive;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    final active = isEnabled && isActive;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? color : AppColors.idleColor,
        boxShadow: active
            ? [
                BoxShadow(
                  color: color.withAlpha(180),
                  blurRadius: 7,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}

/// Speaker/horn cone: a bezeled disc with mesh ticks, plus an expanding ring
/// "sound wave" animation while active. The disc carries the glow — the
/// Icon painted on top by the parent is the actual campaign/volume glyph so
/// custom icons still work.
class _HornPainter extends CustomPainter {
  const _HornPainter({
    required this.activeColor,
    required this.activeColorLight,
    required this.isActive,
    required this.isEnabled,
    required this.ringT,
    required this.showRing,
    required this.pattern,
  });

  final Color activeColor;
  final Color activeColorLight;
  final bool isActive;
  final bool isEnabled;
  final double ringT;
  final bool showRing;
  final HornSoundPattern pattern;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final discR = side * 0.46;

    if (isActive && isEnabled && showRing) {
      _paintSoundRings(canvas, center, discR);
    }

    if (isActive && isEnabled) {
      canvas.drawCircle(
        center,
        discR * 1.05,
        Paint()
          ..color = activeColor.withAlpha(90)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
    }

    canvas.drawCircle(
      center + Offset(0, side * 0.03),
      discR,
      Paint()
        ..color = Colors.black.withAlpha(130)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    final discRect = Rect.fromCircle(center: center, radius: discR);
    final baseGradient = RadialGradient(
      center: const Alignment(-0.35, -0.45),
      radius: 1.15,
      colors: isActive && isEnabled
          ? [
              Color.lerp(activeColorLight, Colors.white, 0.25)!,
              activeColor,
              Color.lerp(activeColor, Colors.black, 0.4)!,
            ]
          : isEnabled
          ? const [Color(0xFF3A4756), Color(0xFF212D3A), Color(0xFF0C1620)]
          : const [Color(0xFF3A4046), Color(0xFF262B30), Color(0xFF15181C)],
      stops: const [0.0, 0.55, 1.0],
    );
    canvas.drawCircle(
      center,
      discR,
      Paint()..shader = baseGradient.createShader(discRect),
    );

    canvas.drawCircle(
      center,
      discR - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, side * 0.02)
        ..color = Colors.white.withAlpha(isEnabled ? 46 : 20),
    );

    final meshPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, side * 0.012)
      ..color = Colors.black.withAlpha(isActive && isEnabled ? 70 : 50);
    for (var i = 0; i < 16; i++) {
      final angle = (math.pi * 2 / 16) * i;
      final r1 = discR * 0.62;
      final r2 = discR * 0.86;
      canvas.drawLine(
        center + Offset(math.cos(angle) * r1, math.sin(angle) * r1),
        center + Offset(math.cos(angle) * r2, math.sin(angle) * r2),
        meshPaint,
      );
    }

    if (!isEnabled) {
      canvas.drawCircle(
        center,
        discR,
        Paint()..color = Colors.black.withAlpha(56),
      );
    }
  }

  void _paintSoundRings(Canvas canvas, Offset center, double discR) {
    final ringCount = switch (pattern) {
      HornSoundPattern.steady => 1,
      HornSoundPattern.pulsing => 2,
      HornSoundPattern.doubleBeep => 2,
    };
    for (var i = 0; i < ringCount; i++) {
      final phase = ((ringT + i / ringCount) % 1.0);
      final radius = discR * (1.0 + phase * 0.9);
      final opacity = (1.0 - phase) * 0.55;
      if (opacity <= 0.01) continue;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, discR * 0.05 * (1.0 - phase))
          ..color = activeColorLight.withAlpha((opacity * 255).round()),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HornPainter oldDelegate) {
    return oldDelegate.activeColor != activeColor ||
        oldDelegate.activeColorLight != activeColorLight ||
        oldDelegate.isActive != isActive ||
        oldDelegate.isEnabled != isEnabled ||
        oldDelegate.ringT != ringT ||
        oldDelegate.showRing != showRing ||
        oldDelegate.pattern != pattern;
  }
}
