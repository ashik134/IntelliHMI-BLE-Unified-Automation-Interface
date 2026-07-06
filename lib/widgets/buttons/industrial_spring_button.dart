import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';

/// A reusable, production-grade industrial pushbutton with realistic
/// mechanical feedback through visual compression and haptic response.
///
/// Supports two interaction modes:
/// * `isSpringReturn: true` — active only while pressed/held, spring-returns
///   to inactive on release. Mirrors a momentary spring-return button.
/// * `isSpringReturn: false` with `isLatched: true` — tap once to activate,
///   tap again to deactivate. Mirrors a maintained industrial latch button.
class IndustrialSpringButton extends StatefulWidget {
  const IndustrialSpringButton({
    super.key,
    required this.label,
    required this.icon,
    this.activeColor = AppColors.upColor,
    this.activeColorLight = AppColors.upColorLight,
    this.isActive = false,
    this.isSpringReturn = true,
    this.isLatched = false,
    this.enabled = true,
    this.hapticFeedback = true,
    this.pressScale = 0.965,
    this.animationDuration = const Duration(milliseconds: 90),
    this.releaseDuration = const Duration(milliseconds: 150),
    this.onChanged,
    this.onPressed,
    this.onReleased,
  });

  final String label;
  final IconData icon;
  final Color activeColor;
  final Color activeColorLight;

  /// External active state (controlled by parent)
  final bool isActive;

  /// If true: spring-return (active only while held)
  /// If false: latching (tap to toggle)
  final bool isSpringReturn;

  /// Only used when isSpringReturn is false
  final bool isLatched;

  final bool enabled;
  final bool hapticFeedback;
  final double pressScale;
  final Duration animationDuration;
  final Duration releaseDuration;

  /// Called when state changes (for latching mode)
  final ValueChanged<bool>? onChanged;

  /// Called when button is pressed down
  final VoidCallback? onPressed;

  /// Called when button is released
  final VoidCallback? onReleased;

  @override
  State<IndustrialSpringButton> createState() => _IndustrialSpringButtonState();
}

class _IndustrialSpringButtonState extends State<IndustrialSpringButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _pressAnim;

  bool _pointerIsDown = false;
  bool _hovered = false;
  bool _focused = false;
  bool _internalActive = false;

  @override
  void initState() {
    super.initState();
    _internalActive = widget.isActive;
    _pressCtrl = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
      reverseDuration: widget.releaseDuration,
    );
    _pressAnim = CurvedAnimation(
      parent: _pressCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutBack,
    );
  }

  @override
  void didUpdateWidget(covariant IndustrialSpringButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _pressCtrl.duration = widget.animationDuration;
    _pressCtrl.reverseDuration = widget.releaseDuration;

    // Update internal state if external isActive changes
    if (widget.isActive != oldWidget.isActive) {
      _internalActive = widget.isActive;
    }

    if (!widget.enabled && oldWidget.enabled && _pointerIsDown) {
      _finishPress();
    }
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  Future<void> _triggerHaptic() async {
    if (!widget.hapticFeedback) return;
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {
      try {
        await HapticFeedback.selectionClick();
      } catch (_) {}
    }
  }

  void _setActive(bool value) {
    if (_internalActive == value) return;
    setState(() => _internalActive = value);
    widget.onChanged?.call(value);
  }

  void _handlePointerDown(PointerDownEvent _) {
    if (!widget.enabled || _pointerIsDown) return;
    _pointerIsDown = true;
    _triggerHaptic();
    _pressCtrl.forward();

    // Spring return: activate immediately
    if (widget.isSpringReturn) {
      _setActive(true);
      widget.onPressed?.call();
    } else {
      // Latching: will toggle on release
      widget.onPressed?.call();
    }
  }

  void _handlePointerUp(PointerUpEvent _) {
    final wasDown = _pointerIsDown;
    _finishPress();

    // Latching: toggle on release
    if (wasDown && !widget.isSpringReturn) {
      _setActive(!_internalActive);
      if (!_internalActive) {
        widget.onReleased?.call();
      }
    }
  }

  void _handlePointerCancel(PointerCancelEvent _) => _finishPress();

  void _finishPress() {
    if (!_pointerIsDown) return;
    _pointerIsDown = false;
    _pressCtrl.animateBack(
      0.0,
      duration: widget.releaseDuration,
      curve: Curves.easeOutBack,
    );

    // Spring return: deactivate on release
    if (widget.isSpringReturn) {
      _setActive(false);
      widget.onReleased?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
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
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        child: MouseRegion(
          onEnter: (_) {
            if (widget.enabled) setState(() => _hovered = true);
          },
          onExit: (_) => setState(() => _hovered = false),
          child: AnimatedBuilder(
            animation: _pressAnim,
            builder: (context, _) {
              final press = _pressAnim.value.clamp(0.0, 1.0);
              final isActive = widget.enabled && _internalActive;
              return LayoutBuilder(
                builder: (context, constraints) {
                  final hasBoundedWidth = constraints.hasBoundedWidth;
                  final hasBoundedHeight = constraints.hasBoundedHeight;
                  final width = hasBoundedWidth ? constraints.maxWidth : 152.0;
                  final height = hasBoundedHeight ? constraints.maxHeight : 184.0;

                  return SizedBox(
                    width: hasBoundedWidth ? double.infinity : width,
                    height: hasBoundedHeight ? double.infinity : height,
                    child: RepaintBoundary(
                      child: _IndustrialButtonContent(
                        label: widget.label,
                        icon: widget.icon,
                        activeColor: widget.activeColor,
                        activeColorLight: widget.activeColorLight,
                        press: press,
                        pressScale: widget.pressScale,
                        isActive: isActive,
                        isSpringReturn: widget.isSpringReturn,
                        isLatched: widget.isLatched,
                        isEnabled: widget.enabled,
                        isHovered: _hovered,
                        isFocused: _focused,
                        onPointerDown: _handlePointerDown,
                        onPointerUp: _handlePointerUp,
                        onPointerCancel: _handlePointerCancel,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _IndustrialButtonContent extends StatelessWidget {
  const _IndustrialButtonContent({
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.activeColorLight,
    required this.press,
    required this.pressScale,
    required this.isActive,
    required this.isSpringReturn,
    required this.isLatched,
    required this.isEnabled,
    required this.isHovered,
    required this.isFocused,
    required this.onPointerDown,
    required this.onPointerUp,
    required this.onPointerCancel,
  });

  final String label;
  final IconData icon;
  final Color activeColor;
  final Color activeColorLight;
  final double press;
  final double pressScale;
  final bool isActive;
  final bool isSpringReturn;
  final bool isLatched;
  final bool isEnabled;
  final bool isHovered;
  final bool isFocused;
  final void Function(PointerDownEvent) onPointerDown;
  final void Function(PointerUpEvent) onPointerUp;
  final void Function(PointerCancelEvent) onPointerCancel;

  int _alpha(double opacity) {
    return (opacity.clamp(0.0, 1.0) * 255).round();
  }

  @override
  Widget build(BuildContext context) {
    final bool isPressed = press > 0.08;
    final bool isLocked = !isEnabled;

    final statusLabel = isLocked
        ? 'LOCKED'
        : isActive
            ? 'ACTIVE'
            : isPressed
                ? 'PRESSED'
                : 'READY';
    final modeLabel = isSpringReturn
        ? 'HOLD'
        : isLatched
            ? 'LATCHED'
            : 'TAP';
    final labelColor = isLocked
        ? AppColors.darkTextMuted.withAlpha(_alpha(0.9))
        : isActive
            ? activeColorLight
            : AppColors.darkText;
    final mutedColor = isLocked
        ? AppColors.darkTextMuted.withAlpha(_alpha(0.85))
        : isActive
            ? activeColorLight
            : isPressed
                ? activeColor.withAlpha(_alpha(0.8))
                : AppColors.darkTextMuted;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 180 || constraints.maxWidth < 150;
        final padding = compact
            ? const EdgeInsets.fromLTRB(10, 8, 10, 8)
            : const EdgeInsets.fromLTRB(16, 12, 16, 12);
        final double statusFontSize = compact ? 8 : 10;
        final double modeFontSize = compact ? 8 : 10;
        final double labelFontSize = compact ? 14 : 17;

        final double headerSpacing = compact ? 6 : 8;
        final double bottomSpacing = compact ? 5 : 7;

        return Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Status Header ──────────────────────────────────────────
              SizedBox(
                height: compact ? 20 : 24,
                child: Row(
                  children: [
                    _IndicatorLed(
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
                          color: mutedColor,
                          fontSize: statusFontSize,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          shadows: [
                            Shadow(
                              color: Colors.black.withAlpha(_alpha(0.3)),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      modeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.darkTextSub.withAlpha(
                          isEnabled ? _alpha(0.95) : _alpha(0.7),
                        ),
                        fontSize: modeFontSize,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        shadows: [
                          Shadow(
                            color: Colors.black.withAlpha(_alpha(0.2)),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: headerSpacing),

              // ── Main Button ────────────────────────────────────────────
              Expanded(
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, buttonBox) {
                      final maxDiameter = math.min(
                        buttonBox.maxWidth,
                        buttonBox.maxHeight,
                      );
                      final diameter = maxDiameter.clamp(
                        compact ? 74.0 : 88.0,
                        compact ? 104.0 : 136.0,
                      );
                      final visualScale = 1.0 - ((1.0 - pressScale) * press);

                      return SizedBox.square(
                        dimension: diameter,
                        child: ClipOval(
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: onPointerDown,
                            onPointerUp: onPointerUp,
                            onPointerCancel: onPointerCancel,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // ── Custom Painted Button ──────────────
                                CustomPaint(
                                  painter: _IndustrialRoundButtonPainter(
                                    press: press,
                                    activeColor: activeColor,
                                    activeColorLight: activeColorLight,
                                    isActive: isActive,
                                    isEnabled: isEnabled,
                                  ),
                                  size: Size.square(diameter),
                                ),

                                // ── Icon with Scale Animation ──────────
                                Transform.scale(
                                  scale: visualScale,
                                  child: Icon(
                                    icon,
                                    size: diameter * 0.32,
                                    color: !isEnabled
                                        ? AppColors.darkTextSub.withAlpha(
                                            _alpha(0.45),
                                          )
                                        : isActive
                                            ? Colors.white
                                            : AppColors.darkText,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black.withAlpha(
                                          isActive ? _alpha(0.6) : _alpha(0.4),
                                        ),
                                        blurRadius: isActive ? 8 : 4,
                                        offset: Offset(0, isActive ? 2 : 1),
                                      ),
                                    ],
                                  ),
                                ),

                                // ── Lock Overlay ────────────────────────
                                if (isLocked)
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.black.withAlpha(_alpha(0.25)),
                                      border: Border.all(
                                        color: Colors.white.withAlpha(_alpha(0.08)),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.lock_outline_rounded,
                                      size: diameter * 0.2,
                                      color: Colors.white.withAlpha(_alpha(0.3)),
                                    ),
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
              SizedBox(height: bottomSpacing),

              // ── Label ──────────────────────────────────────────────────
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: labelFontSize,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    shadows: [
                      Shadow(
                        color: Colors.black.withAlpha(_alpha(0.55)),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                      if (isActive)
                        Shadow(
                          color: activeColor.withAlpha(_alpha(0.3)),
                          blurRadius: 12,
                          offset: Offset.zero,
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: bottomSpacing * 0.8),

              // ── Status Rail ────────────────────────────────────────────
              // _StatusRail(
              //   color: activeColor,
              //   isActive: isActive,
              //   isPressed: isPressed,
              //   isEnabled: isEnabled,
              //   isCompact: compact,
              // ),
            ],
          ),
        );
      },
    );
  }
}

class _IndicatorLed extends StatelessWidget {
  const _IndicatorLed({
    required this.color,
    required this.isActive,
    required this.isEnabled,
  });

  final Color color;
  final bool isActive;
  final bool isEnabled;

  int _alpha(double opacity) {
    return (opacity.clamp(0.0, 1.0) * 255).round();
  }

  @override
  Widget build(BuildContext context) {
    final active = isEnabled && isActive;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? color : AppColors.idleColor,
        border: Border.all(
          color: active
              ? color.withAlpha(_alpha(0.95))
              : AppColors.darkBorder.withAlpha(_alpha(0.9)),
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: color.withAlpha(_alpha(0.75)),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withAlpha(_alpha(0.45)),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
    );
  }
}

class _StatusRail extends StatelessWidget {
  const _StatusRail({
    required this.color,
    required this.isActive,
    required this.isPressed,
    required this.isEnabled,
    this.isCompact = false,
  });

  final Color color;
  final bool isActive;
  final bool isPressed;
  final bool isEnabled;
  final bool isCompact;

  int _alpha(double opacity) {
    return (opacity.clamp(0.0, 1.0) * 255).round();
  }

  @override
  Widget build(BuildContext context) {
    final bool isLocked = !isEnabled;
    final double railHeight = isCompact ? 2.5 : 3;

    return SizedBox(
      height: railHeight + 4,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: double.infinity,
        height: railHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(railHeight / 2),
          color: isLocked
              ? Colors.grey.withAlpha(_alpha(0.15))
              : isActive
                  ? color
                  : isPressed
                      ? color.withAlpha(_alpha(0.5))
                      : Colors.grey.withAlpha(_alpha(0.1)),
          boxShadow: (isActive || isPressed) && !isLocked
              ? [
                  BoxShadow(
                    color: color.withAlpha(_alpha(0.3)),
                    blurRadius: 4,
                    spreadRadius: 0,
                  ),
                ]
              : [],
        ),
      ),
    );
  }
}

class _IndustrialRoundButtonPainter extends CustomPainter {
  const _IndustrialRoundButtonPainter({
    required this.press,
    required this.activeColor,
    required this.activeColorLight,
    required this.isActive,
    required this.isEnabled,
  });

  final double press;
  final Color activeColor;
  final Color activeColorLight;
  final bool isActive;
  final bool isEnabled;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = side * 0.49;
    final bezelR = side * 0.455;
    final wellR = side * 0.36;
    final capR = side * (0.292 - press * 0.012);

    // ── Active Glow ──────────────────────────────────────────────────────
    if (isActive && isEnabled) {
      canvas.drawCircle(
        center,
        bezelR * 1.02,
        Paint()
          ..color = activeColor.withAlpha(_alpha(0.32))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13),
      );
    }

    // ── Shadow ──────────────────────────────────────────────────────────
    canvas.drawCircle(
      center + Offset(0, 3 + press * 2),
      bezelR * 0.98,
      Paint()
        ..color = Colors.black.withAlpha(_alpha(0.52 + press * 0.18))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // ── Bezel ───────────────────────────────────────────────────────────
    final bezelRect = Rect.fromCircle(center: center, radius: bezelR);
    final bezelGradient = RadialGradient(
      center: const Alignment(-0.42, -0.50),
      radius: 1.18,
      colors: isEnabled
          ? const [
              Color(0xFFE9EEF4),
              Color(0xFFAAB5C0),
              Color(0xFF65717D),
              Color(0xFF1A2430),
            ]
          : const [
              Color(0xFF98A2AD),
              Color(0xFF69737E),
              Color(0xFF38434E),
              Color(0xFF161F28),
            ],
      stops: const [0.0, 0.32, 0.68, 1.0],
    );
    canvas.drawCircle(
      center,
      bezelR,
      Paint()..shader = bezelGradient.createShader(bezelRect),
    );

    // ── Bezel Borders ──────────────────────────────────────────────────
    canvas.drawCircle(
      center,
      bezelR - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withAlpha(_alpha(isEnabled ? 0.38 : 0.12)),
    );
    canvas.drawCircle(
      center,
      bezelR - 3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.black.withAlpha(_alpha(0.32)),
    );

    // ── Inner Well ──────────────────────────────────────────────────────
    final wellRect = Rect.fromCircle(center: center, radius: wellR);
    const wellGradient = RadialGradient(
      center: Alignment(0.28, 0.35),
      radius: 1.08,
      colors: [Color(0xFF05090E), Color(0xFF0F1D29), Color(0xFF263745)],
      stops: [0.0, 0.62, 1.0],
    );
    canvas.drawCircle(
      center,
      wellR,
      Paint()..shader = wellGradient.createShader(wellRect),
    );

    // ── Inner Ring ──────────────────────────────────────────────────────
    final ringColor = isEnabled
        ? activeColor.withAlpha(_alpha(isActive ? 0.95 : 0.24 + press * 0.18))
        : AppColors.disabled.withAlpha(_alpha(0.45));
    if (isActive && isEnabled) {
      canvas.drawCircle(
        center,
        wellR * 0.89,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = side * 0.036
          ..color = activeColor.withAlpha(_alpha(0.42))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
    canvas.drawCircle(
      center,
      wellR * 0.89,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = side * 0.025
        ..color = ringColor,
    );

    // ── Cap Shadow ─────────────────────────────────────────────────────
    canvas.drawCircle(
      center,
      capR + side * 0.035,
      Paint()
        ..color = Colors.black.withAlpha(_alpha(0.35 + press * 0.34))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + press * 3),
    );

    // ── Cap Gradient ────────────────────────────────────────────────────
    const idleBase = Color(0xFF566371);
    const idleLight = Color(0xFFA5AFBA);
    const idleDark = Color(0xFF1A242E);
    final base = isActive && isEnabled
        ? activeColor
        : Color.lerp(idleBase, activeColor, isEnabled ? 0.12 : 0.02)!;
    final light = isActive && isEnabled
        ? Color.lerp(activeColorLight, Colors.white, 0.18)!
        : idleLight;
    final dark = isActive && isEnabled
        ? Color.lerp(activeColor, Colors.black, 0.48)!
        : idleDark;
    final pressedBase = Color.lerp(base, Colors.black, press * 0.22)!;
    final capRect = Rect.fromCircle(center: center, radius: capR);
    final capGradient = RadialGradient(
      center: Alignment(-0.36 + press * 0.16, -0.46 + press * 0.16),
      radius: 1.18,
      colors: isEnabled
          ? [
              Color.lerp(light, Colors.black, press * 0.10)!,
              pressedBase,
              Color.lerp(dark, Colors.black, press * 0.18)!,
            ]
          : [
              idleLight.withAlpha(_alpha(0.36)),
              idleBase.withAlpha(_alpha(0.42)),
              idleDark.withAlpha(_alpha(0.65)),
            ],
      stops: const [0.0, 0.48, 1.0],
    );
    canvas.drawCircle(
      center,
      capR,
      Paint()..shader = capGradient.createShader(capRect),
    );

    // ── Gloss Highlight ─────────────────────────────────────────────────
    final capPath = Path()..addOval(capRect);
    canvas.save();
    canvas.clipPath(capPath);
    final glossRect = Rect.fromLTWH(
      center.dx - capR * 0.72,
      center.dy - capR * 0.88,
      capR * 1.44,
      capR * 0.88,
    );
    canvas.drawOval(
      glossRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withAlpha(
              _alpha(isEnabled ? 0.42 - press * 0.23 : 0.1),
            ),
            Colors.white.withAlpha(_alpha(isEnabled ? 0.08 : 0.03)),
            Colors.transparent,
          ],
        ).createShader(glossRect),
    );
    canvas.restore();

    // ── Cap Borders ─────────────────────────────────────────────────────
    canvas.drawCircle(
      center,
      capR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withAlpha(_alpha(isEnabled ? 0.18 : 0.06)),
    );
    canvas.drawCircle(
      center,
      capR - 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withAlpha(_alpha(0.24 + press * 0.28)),
    );

    // ── Press Depression Ring ──────────────────────────────────────────
    if (press > 0.03) {
      canvas.drawCircle(
        center,
        capR * 0.82,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = side * 0.018
          ..color = Colors.black.withAlpha(_alpha(press * 0.42))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
    }

    // ── Disabled Overlay ──────────────────────────────────────────────
    if (!isEnabled) {
      canvas.drawCircle(
        center,
        outerR,
        Paint()..color = Colors.black.withAlpha(_alpha(0.22)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _IndustrialRoundButtonPainter oldDelegate) {
    return oldDelegate.press != press ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.activeColorLight != activeColorLight ||
        oldDelegate.isActive != isActive ||
        oldDelegate.isEnabled != isEnabled;
  }
}

int _alpha(double opacity) {
  return (opacity.clamp(0.0, 1.0) * 255).round();
}