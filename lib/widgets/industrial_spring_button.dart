import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';

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
    this.onPressed,
    this.onReleased,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final Color activeColor;
  final Color activeColorLight;
  final bool isActive;
  final bool isSpringReturn;
  final bool isLatched;
  final bool enabled;
  final bool hapticFeedback;
  final double pressScale;
  final Duration animationDuration;
  final Duration releaseDuration;
  final VoidCallback? onPressed;
  final VoidCallback? onReleased;
  final VoidCallback? onTap;

  @override
  State<IndustrialSpringButton> createState() => _IndustrialSpringButtonState();
}

class _IndustrialSpringButtonState extends State<IndustrialSpringButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _pressAnim;

  bool _hovered = false;
  bool _focused = false;
  bool _pointerIsDown = false;

  @override
  void initState() {
    super.initState();
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

    if (!widget.enabled && oldWidget.enabled && _pointerIsDown) {
      _finishPress(callRelease: true);
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

  void _handlePointerDown(PointerDownEvent _) {
    if (!widget.enabled || _pointerIsDown) return;
    _pointerIsDown = true;
    _triggerHaptic();
    _pressCtrl.forward();
    widget.onPressed?.call();
  }

  void _handlePointerUp(PointerUpEvent _) => _finishPress(callRelease: true);
  void _handlePointerCancel(PointerCancelEvent _) =>
      _finishPress(callRelease: true);

  void _finishPress({required bool callRelease}) {
    if (!_pointerIsDown) return;
    _pointerIsDown = false;
    _pressCtrl.animateBack(
      0.0,
      duration: widget.releaseDuration,
      curve: Curves.easeOutBack,
    );
    if (callRelease) {
      widget.onReleased?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: widget.enabled,
      toggled: widget.isActive,
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
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _handlePointerDown,
            onPointerUp: _handlePointerUp,
            onPointerCancel: _handlePointerCancel,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.enabled && !widget.isSpringReturn
                  ? widget.onTap
                  : null,
              child: AnimatedBuilder(
                animation: _pressAnim,
                builder: (context, _) {
                  final press = _pressAnim.value.clamp(0.0, 1.0);
                  final isActive = widget.enabled && widget.isActive;
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final hasBoundedWidth = constraints.hasBoundedWidth;
                      final hasBoundedHeight = constraints.hasBoundedHeight;
                      final width = hasBoundedWidth
                          ? constraints.maxWidth
                          : 152.0;
                      final height = hasBoundedHeight
                          ? constraints.maxHeight
                          : 184.0;

                      return SizedBox(
                        width: hasBoundedWidth ? double.infinity : width,
                        height: hasBoundedHeight ? double.infinity : height,
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _IndustrialButtonPlatePainter(
                              press: press,
                              isActive: isActive,
                              isHovered: _hovered,
                              isFocused: _focused,
                              isEnabled: widget.enabled,
                              activeColor: widget.activeColor,
                            ),
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
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
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

  @override
  Widget build(BuildContext context) {
    final statusLabel = !isEnabled
        ? 'LOCKED'
        : isActive
        ? 'ACTIVE'
        : press > 0.08
        ? 'PRESSED'
        : 'READY';
    final modeLabel = isSpringReturn
        ? 'HOLD'
        : isLatched
        ? 'LATCHED'
        : 'TAP';
    final labelColor = !isEnabled
        ? AppColors.darkTextSub.withAlpha(_alpha(0.55))
        : isActive
        ? activeColorLight
        : AppColors.darkText;
    final mutedColor = !isEnabled
        ? AppColors.darkTextSub.withAlpha(_alpha(0.45))
        : isActive
        ? activeColorLight
        : AppColors.darkTextMuted;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxHeight < 170 || constraints.maxWidth < 135;
        final padding = compact
            ? const EdgeInsets.fromLTRB(10, 9, 10, 10)
            : const EdgeInsets.fromLTRB(14, 12, 14, 14);

        return Padding(
          padding: padding,
          child: Column(
            children: [
              SizedBox(
                height: compact ? 20 : 24,
                child: Row(
                  children: [
                    _IndicatorLed(
                      color: activeColor,
                      isActive: isActive,
                      isEnabled: isEnabled,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        statusLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: mutedColor,
                          fontSize: compact ? 9 : 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    Text(
                      modeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.darkTextSub.withAlpha(
                          isEnabled ? _alpha(0.85) : _alpha(0.45),
                        ),
                        fontSize: compact ? 9 : 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
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
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
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
                                    color: Colors.black.withAlpha(_alpha(0.58)),
                                    blurRadius: 5,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: compact ? 15 : 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                    shadows: [
                      Shadow(
                        color: Colors.black.withAlpha(_alpha(0.55)),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 7),
              _StatusRail(
                color: activeColor,
                isActive: isActive,
                isPressed: press > 0.08,
                isEnabled: isEnabled,
              ),
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
  });

  final Color color;
  final bool isActive;
  final bool isPressed;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    final fill = !isEnabled
        ? AppColors.disabled
        : isActive
        ? color
        : isPressed
        ? color.withAlpha(_alpha(0.56))
        : AppColors.darkBorder;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      height: 5,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        color: fill,
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: color.withAlpha(_alpha(0.5)),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}

class _IndustrialButtonPlatePainter extends CustomPainter {
  const _IndustrialButtonPlatePainter({
    required this.press,
    required this.isActive,
    required this.isHovered,
    required this.isFocused,
    required this.isEnabled,
    required this.activeColor,
  });

  final double press;
  final bool isActive;
  final bool isHovered;
  final bool isFocused;
  final bool isEnabled;
  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outer = RRect.fromRectAndRadius(
      rect.deflate(1),
      const Radius.circular(8),
    );

    final shadowAlpha = isEnabled ? 0.46 : 0.25;
    canvas.drawRRect(
      outer.shift(const Offset(0, 5)),
      Paint()
        ..color = Colors.black.withAlpha(_alpha(shadowAlpha))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    final bodyGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isEnabled
          ? const [Color(0xFF24394A), Color(0xFF142433), Color(0xFF0A141E)]
          : const [Color(0xFF1B2631), Color(0xFF121C26), Color(0xFF090F15)],
      stops: const [0, 0.52, 1],
    );

    canvas.drawRRect(outer, Paint()..shader = bodyGradient.createShader(rect));

    final inner = outer.deflate(2);
    canvas.drawRRect(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withAlpha(_alpha(isEnabled ? 0.09 : 0.04)),
    );

    final bevelLight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withAlpha(_alpha(isEnabled ? 0.16 : 0.06));
    final bevelDark = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.black.withAlpha(_alpha(0.44));

    canvas.drawLine(
      Offset(outer.left + 8, outer.top + 2),
      Offset(outer.right - 8, outer.top + 2),
      bevelLight,
    );
    canvas.drawLine(
      Offset(outer.left + 2, outer.top + 8),
      Offset(outer.left + 2, outer.bottom - 8),
      bevelLight,
    );
    canvas.drawLine(
      Offset(outer.left + 8, outer.bottom - 2),
      Offset(outer.right - 8, outer.bottom - 2),
      bevelDark,
    );
    canvas.drawLine(
      Offset(outer.right - 2, outer.top + 8),
      Offset(outer.right - 2, outer.bottom - 8),
      bevelDark,
    );

    if (isHovered && isEnabled) {
      canvas.drawRRect(
        inner.deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withAlpha(_alpha(0.12)),
      );
    }

    if (isActive) {
      canvas.drawRRect(
        inner.deflate(2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = activeColor.withAlpha(_alpha(0.58)),
      );
    }

    if (isFocused) {
      canvas.drawRRect(
        outer.deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AppColors.darkInfo.withAlpha(_alpha(0.75)),
      );
    }

    if (!isEnabled) {
      canvas.drawRRect(
        outer,
        Paint()..color = Colors.black.withAlpha(_alpha(0.22)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _IndustrialButtonPlatePainter oldDelegate) {
    return oldDelegate.press != press ||
        oldDelegate.isActive != isActive ||
        oldDelegate.isHovered != isHovered ||
        oldDelegate.isFocused != isFocused ||
        oldDelegate.isEnabled != isEnabled ||
        oldDelegate.activeColor != activeColor;
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

    if (isActive && isEnabled) {
      canvas.drawCircle(
        center,
        bezelR * 1.02,
        Paint()
          ..color = activeColor.withAlpha(_alpha(0.32))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13),
      );
    }

    canvas.drawCircle(
      center + Offset(0, 3 + press * 2),
      bezelR * 0.98,
      Paint()
        ..color = Colors.black.withAlpha(_alpha(0.52 + press * 0.18))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

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

    canvas.drawCircle(
      center,
      capR + side * 0.035,
      Paint()
        ..color = Colors.black.withAlpha(_alpha(0.35 + press * 0.34))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + press * 3),
    );

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
