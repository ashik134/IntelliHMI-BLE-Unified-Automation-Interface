import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:rev_crane_control_ops/models/button_rotation.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/utils/button_state_log.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';

abstract final class PushControlStateId {
  static const String idle = 'idle';
  static const String pressed = 'pressed';
  static const String off = 'off';
  static const String on = 'on';

  static const Set<String> springReturnValues = {idle, pressed};
  static const Set<String> latchingValues = {off, on};

  static bool isActive(String stateId, {required bool isSpringReturn}) =>
      isSpringReturn ? stateId == pressed : stateId == on;
}

class PushControlButton extends StatelessWidget {
  const PushControlButton({
    super.key,
    required this.label,
    required this.icon,
    this.isDisabled = false,
    this.isSpringReturn = true,
    this.externalStateId = PushControlStateId.idle,
    this.activeColor,
    this.activeColorLight,
    this.hapticFeedback = true,
    this.rotation = ButtonRotation.none,
    this.pressScale = 0.965,
    this.debounceMs = 0,
    this.longPressRequiredMs = 0,
    required this.onStateChanged,
  });

  final String label;
  final IconData icon;
  final bool isDisabled;
  final bool isSpringReturn;
  final String externalStateId;
  final Color? activeColor;
  final Color? activeColorLight;
  final bool hapticFeedback;
  final ButtonRotation rotation;

  /// See ButtonBehaviorConfig.pressAnimationStrength/pressScale.
  final double pressScale;

  /// See ButtonBehaviorConfig.debounceMs.
  final int debounceMs;

  /// See ButtonBehaviorConfig.longPressRequiredMs.
  final int longPressRequiredMs;
  final ValueChanged<String> onStateChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = !isDisabled;
    final isActive = PushControlStateId.isActive(
      externalStateId,
      isSpringReturn: isSpringReturn,
    );
    final latched = !isSpringReturn && isActive;

    return IndustrialSpringButton(
      label: label,
      icon: icon,
      activeColor: activeColor!,
      activeColorLight: activeColorLight!,
      isActive: isActive && enabled,
      isSpringReturn: isSpringReturn,
      isLatched: latched,
      enabled: enabled,
      hapticFeedback: hapticFeedback,
      rotation: rotation,
      pressScale: pressScale,
      debounceMs: debounceMs,
      longPressRequiredMs: longPressRequiredMs,
      onPressed: isSpringReturn
          ? () => onStateChanged(PushControlStateId.pressed)
          : null,
      onReleased: isSpringReturn
          ? () => onStateChanged(PushControlStateId.idle)
          : null,
      // Latching mode toggles and reports its new value exclusively through
      // onChanged (see IndustrialSpringButton._handlePointerUp) — onPressed/
      // onReleased are wired to null above since they're the spring-return
      // path. Without this, a latching push button flips its own visual
      // state locally but never calls onStateChanged.
      onChanged: isSpringReturn
          ? null
          : (value) => onStateChanged(
              value ? PushControlStateId.on : PushControlStateId.off,
            ),
    );
  }
}

/// Reusable industrial push-button surface/interaction primitive.
///
/// It owns presentation, pointer press/release behavior, haptics, local visual
/// state, and latch mechanics only. Domain state IDs, PLC outputs, and packet
/// composition stay outside it.
class IndustrialSpringButton extends StatefulWidget {
  const IndustrialSpringButton({
    super.key,
    required this.label,
    required this.icon,
    this.enabled = true,
    this.activeColor = AppColors.upColor,
    this.activeColorLight = AppColors.upColorLight,
    this.isActive = false,
    this.isSpringReturn = true,
    this.isLatched = false,
    this.hapticFeedback = true,
    this.pressScale = 0.965,
    this.animationDuration = const Duration(milliseconds: 90),
    this.releaseDuration = const Duration(milliseconds: 150),
    this.rotation = ButtonRotation.none,
    this.debounceMs = 0,
    this.longPressRequiredMs = 0,
    this.onChanged,
    this.onPressed,
    this.onReleased,
  });

  final String label;
  final IconData icon;
  final Color activeColor;
  final Color activeColorLight;
  final ButtonRotation rotation;
  final bool isActive;
  final bool isSpringReturn;
  final bool isLatched;
  final bool enabled;
  final bool hapticFeedback;
  final double pressScale;
  final Duration animationDuration;
  final Duration releaseDuration;

  /// 0 disables debouncing — a new press right after a release is always
  /// honored (today's exact behavior). See ButtonBehaviorConfig.debounceMs.
  final int debounceMs;

  /// Spring-return only: holds the press for this long before it actually
  /// activates (see _handlePointerDown). 0 disables the requirement — a
  /// press activates immediately on pointer-down (today's exact behavior).
  /// See ButtonBehaviorConfig.longPressRequiredMs.
  final int longPressRequiredMs;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onPressed;
  final VoidCallback? onReleased;

  @override
  State<IndustrialSpringButton> createState() => _IndustrialSpringButtonState();
}

class _IndustrialSpringButtonState extends State<IndustrialSpringButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _pressAnim;

  bool _pointerIsDown = false;
  int? _activePointerId;
  bool _hovered = false;
  bool _focused = false;
  bool _internalActive = false;

  bool _suppressExternalReactivation = false;

  /// True for [widget.debounceMs] after each release — a new press is
  /// ignored while this is true. A Timer-driven flag rather than comparing
  /// DateTime.now() timestamps so it advances correctly under
  /// WidgetTester.pump(duration)'s fake clock, not just real wall-clock time.
  bool _debounceBlocked = false;
  Timer? _debounceTimer;

  /// Pending long-press-required activation — see [widget.longPressRequiredMs].
  Timer? _longPressTimer;

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

    if (widget.isActive != oldWidget.isActive) {
      final isStaleReactivation =
          widget.isSpringReturn &&
          widget.isActive &&
          _suppressExternalReactivation;
      if (isStaleReactivation) {
        ButtonStateLog.log(
          'PLC_STATUS_ACTIVE ignored (stale, post-release) [${widget.label}]',
        );
      } else {
        _internalActive = widget.isActive;
      }
    }

    if (!widget.enabled && oldWidget.enabled && _pointerIsDown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _finishPress();
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _longPressTimer?.cancel();
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
    ButtonStateLog.log(
      '${value ? 'VISUAL_ACTIVE' : 'VISUAL_IDLE'} [${widget.label}]',
    );
    widget.onChanged?.call(value);
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.enabled || _pointerIsDown) return;
    // Debounced: too soon after the previous release — ignore this press
    // entirely (no visual/haptic/dispatch of any kind).
    if (_debounceBlocked) return;
    _pointerIsDown = true;
    _activePointerId = event.pointer;
    _suppressExternalReactivation = false;
    ButtonStateLog.log('USER_DOWN [${widget.label}] pointer=${event.pointer}');
    _triggerHaptic();
    _pressCtrl.forward();

    if (widget.isSpringReturn) {
      if (widget.longPressRequiredMs > 0) {
        // Press animation already started above for immediate feedback;
        // activation itself is deferred until the hold duration elapses —
        // a release before then (see _finishPress) cancels this timer and
        // the press never activates at all.
        _longPressTimer?.cancel();
        _longPressTimer = Timer(
          Duration(milliseconds: widget.longPressRequiredMs),
          () {
            if (!mounted || !_pointerIsDown) return;
            _setActive(true);
            widget.onPressed?.call();
          },
        );
      } else {
        _setActive(true);
        widget.onPressed?.call();
      }
    } else {
      widget.onPressed?.call();
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointerId) return;
    final wasDown = _pointerIsDown;
    ButtonStateLog.log('USER_UP [${widget.label}] pointer=${event.pointer}');
    _finishPress();

    if (wasDown && !widget.isSpringReturn) {
      _setActive(!_internalActive);
      if (!_internalActive) {
        widget.onReleased?.call();
      }
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointerId) return;
    ButtonStateLog.log(
      'USER_CANCEL [${widget.label}] pointer=${event.pointer}',
    );
    _finishPress();
  }

  void _finishPress() {
    if (!_pointerIsDown) return;
    _longPressTimer?.cancel();
    _longPressTimer = null;
    if (widget.debounceMs > 0) {
      _debounceBlocked = true;
      _debounceTimer?.cancel();
      _debounceTimer = Timer(Duration(milliseconds: widget.debounceMs), () {
        _debounceBlocked = false;
      });
    }
    _pointerIsDown = false;
    _activePointerId = null;
    _pressCtrl.animateBack(
      0.0,
      duration: widget.releaseDuration,
      curve: Curves.easeOutBack,
    );

    if (widget.isSpringReturn) {
      _suppressExternalReactivation = true;
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
              return SizedBox.square(
                dimension: 96,
                child: RepaintBoundary(
                  child: _CircularIndustrialButtonContent(
                    icon: widget.icon,
                    activeColor: widget.activeColor,
                    activeColorLight: widget.activeColorLight,
                    press: press,
                    pressScale: widget.pressScale,
                    isActive: isActive,
                    isEnabled: widget.enabled,
                    onPointerDown: _handlePointerDown,
                    onPointerUp: _handlePointerUp,
                    onPointerCancel: _handlePointerCancel,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The complete visible widget and hit target: one 96 x 96 circle.
class _CircularIndustrialButtonContent extends StatelessWidget {
  const _CircularIndustrialButtonContent({
    required this.icon,
    required this.activeColor,
    required this.activeColorLight,
    required this.press,
    required this.pressScale,
    required this.isActive,
    required this.isEnabled,
    required this.onPointerDown,
    required this.onPointerUp,
    required this.onPointerCancel,
  });

  final IconData icon;
  final Color activeColor;
  final Color activeColorLight;
  final double press;
  final double pressScale;
  final bool isActive;
  final bool isEnabled;
  final void Function(PointerDownEvent) onPointerDown;
  final void Function(PointerUpEvent) onPointerUp;
  final void Function(PointerCancelEvent) onPointerCancel;

  int _alpha(double opacity) => (opacity.clamp(0.0, 1.0) * 255).round();

  @override
  Widget build(BuildContext context) {
    final visualScale = 1.0 - ((1.0 - pressScale) * press);

    return ClipOval(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: onPointerDown,
        onPointerUp: onPointerUp,
        onPointerCancel: onPointerCancel,
        child: Stack(
          fit: StackFit.expand,
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
            ),
            Center(
              child: Transform.scale(
                scale: visualScale,
                child: Icon(
                  icon,
                  size: 32,
                  color: !isEnabled
                      ? AppColors.darkTextSub.withAlpha(_alpha(0.45))
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
            ),
            if (!isEnabled)
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withAlpha(_alpha(0.25)),
                  border: Border.all(
                    color: Colors.white.withAlpha(_alpha(0.08)),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.lock_outline_rounded,
                    size: 20,
                    color: Colors.white.withAlpha(_alpha(0.3)),
                  ),
                ),
              ),
          ],
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

class PushButtonPreview extends StatelessWidget {
  const PushButtonPreview({
    super.key,
    required this.wiringConfig,
    this.upLabel = 'UP',
    this.downLabel = 'DOWN',
    this.scale = 1.0,
  });

  final PushButtonWiringConfig wiringConfig;
  final String upLabel;
  final String downLabel;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      alignment: Alignment.topCenter,
      child: Row(
        children: [
          Expanded(
            child: _PreviewButton(
              label: upLabel,
              icon: Icons.arrow_upward_rounded,
              activeColor: AppColors.upColor,
              activeColorLight: AppColors.upColorLight,
              isSpringReturn: wiringConfig.upIsSpringReturn,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _PreviewButton(
              label: downLabel,
              icon: Icons.arrow_downward_rounded,
              activeColor: AppColors.downColor,
              activeColorLight: AppColors.downColorLight,
              isSpringReturn: wiringConfig.downIsSpringReturn,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewButton extends StatelessWidget {
  const _PreviewButton({
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.activeColorLight,
    required this.isSpringReturn,
  });

  final String label;
  final IconData icon;
  final Color activeColor;
  final Color activeColorLight;
  final bool isSpringReturn;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: IgnorePointer(
        child: IndustrialSpringButton(
          label: label,
          icon: icon,
          activeColor: activeColor,
          activeColorLight: activeColorLight,
          isSpringReturn: isSpringReturn,
          hapticFeedback: false,
        ),
      ),
    );
  }
}
