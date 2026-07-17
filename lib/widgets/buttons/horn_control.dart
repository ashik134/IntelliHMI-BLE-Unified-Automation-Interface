import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/horn_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/control_button_visuals.dart';

// ─────────────────────────────────────────────────────────────────────────────
// IndustrialHornControl
//
// Professional horn/buzzer control: speaker-style glyph, pulsing active
// glow, and an optional expanding "sound ring" beep animation while active.
// Mirrors IndustrialSpringButton's press/haptic conventions (pointer-based,
// not GestureDetector, so a fast release is never dropped) but is visually
// its own thing — a speaker cone rather than a round pushbutton cap.
//
// Momentary by default (sounds while held, silent on release), matching a
// real horn button; a maintained/latching mode is left to
// ButtonBehaviorConfig.wiring exactly like PushButtonStrategy, so this
// widget only renders `isActive` and reports raw press/release — it never
// decides latching semantics itself.
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
    this.onPressed,
    this.onReleased,
    this.onChanged,
    this.isSpringReturn = true,
  });

  final String label;
  final IconData icon;
  final Color activeColor;
  final Color activeColorLight;
  final bool isActive;
  final bool enabled;
  final HornConfig config;

  /// Spring-return (momentary) semantics: fires while held. Matches
  /// PushButtonStrategy's onPressed/onReleased pairing.
  final VoidCallback? onPressed;
  final VoidCallback? onReleased;

  /// Latching semantics: fires the new toggled value on tap-release. Only
  /// used when [isSpringReturn] is false.
  final ValueChanged<bool>? onChanged;
  final bool isSpringReturn;

  @override
  State<IndustrialHornControl> createState() => _IndustrialHornControlState();
}

class _IndustrialHornControlState extends State<IndustrialHornControl>
    with TickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _pressAnim;
  late final AnimationController _ringCtrl;

  bool _pointerIsDown = false;
  int? _activePointerId;
  bool _internalActive = false;

  @override
  void initState() {
    super.initState();
    _internalActive = widget.isActive;
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 150),
    );
    _pressAnim = CurvedAnimation(
      parent: _pressCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutBack,
    );
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    if (_internalActive) _startRing();
  }

  @override
  void didUpdateWidget(covariant IndustrialHornControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      _internalActive = widget.isActive;
      if (_internalActive) {
        _startRing();
      } else {
        _ringCtrl.stop();
      }
    }
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    _ringCtrl.dispose();
    super.dispose();
  }

  void _startRing() {
    if (!widget.config.visualBeepAnimation) return;
    _ringCtrl
      ..reset()
      ..repeat();
  }

  Future<void> _triggerHaptic() async {
    if (!widget.config.hapticFeedback) return;
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {
      try {
        await HapticFeedback.selectionClick();
      } catch (_) {}
    }
  }

  void _setActive(bool value) {
    if (_internalActive == value) return;
    setState(() => _internalActive = value);
    if (value) {
      _startRing();
    } else {
      _ringCtrl.stop();
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.enabled || _pointerIsDown) return;
    _pointerIsDown = true;
    _activePointerId = event.pointer;
    _triggerHaptic();
    _pressCtrl.forward();

    if (widget.isSpringReturn) {
      _setActive(true);
      widget.onPressed?.call();
    } else {
      widget.onPressed?.call();
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointerId) return;
    final wasDown = _pointerIsDown;
    _finishPress();
    if (wasDown && !widget.isSpringReturn) {
      _setActive(!_internalActive);
      widget.onChanged?.call(_internalActive);
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointerId) return;
    _finishPress();
  }

  void _finishPress() {
    if (!_pointerIsDown) return;
    _pointerIsDown = false;
    _activePointerId = null;
    _pressCtrl.animateBack(
      0.0,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutBack,
    );

    if (widget.isSpringReturn) {
      _setActive(false);
      widget.onReleased?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.enabled && _internalActive;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      toggled: _internalActive,
      label: widget.label,
      child: FocusableActionDetector(
        enabled: widget.enabled,
        mouseCursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: AnimatedBuilder(
          animation: Listenable.merge([_pressAnim, _ringCtrl]),
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
                  child: RepaintBoundary(
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _handlePointerDown,
                      onPointerUp: _handlePointerUp,
                      onPointerCancel: _handlePointerCancel,
                      child: _HornContent(
                        label: widget.label,
                        icon: widget.icon,
                        activeColor: widget.activeColor,
                        activeColorLight: widget.activeColorLight,
                        press: _pressAnim.value.clamp(0.0, 1.0),
                        ringT: _ringCtrl.value,
                        isActive: isActive,
                        isEnabled: widget.enabled,
                        showRing: widget.config.visualBeepAnimation,
                        pattern: widget.config.soundPattern,
                      ),
                    ),
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
    required this.press,
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
  final double press;
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
                      final visualScale = 1.0 - (0.04 * press);
                      return SizedBox.square(
                        dimension: diameter,
                        child: Transform.scale(
                          scale: visualScale,
                          child: CustomPaint(
                            painter: _HornPainter(
                              activeColor: activeColor,
                              activeColorLight: activeColorLight,
                              isActive: isActive,
                              isEnabled: isEnabled,
                              press: press,
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

/// Speaker/horn cone: a bezeled disc with a trapezoid cone glyph baked into
/// the backdrop, plus an expanding ring "sound wave" animation while active.
/// The disc itself carries the glow — Icon(icon) painted on top by the
/// parent is the actual campaign/volume glyph so custom icons still work.
class _HornPainter extends CustomPainter {
  const _HornPainter({
    required this.activeColor,
    required this.activeColorLight,
    required this.isActive,
    required this.isEnabled,
    required this.press,
    required this.ringT,
    required this.showRing,
    required this.pattern,
  });

  final Color activeColor;
  final Color activeColorLight;
  final bool isActive;
  final bool isEnabled;
  final double press;
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

    // Speaker mesh ticks — subtle industrial detail ring.
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
        oldDelegate.press != press ||
        oldDelegate.ringT != ringT ||
        oldDelegate.showRing != showRing ||
        oldDelegate.pattern != pattern;
  }
}
