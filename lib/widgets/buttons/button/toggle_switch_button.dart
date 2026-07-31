import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'package:rev_crane_control_ops/models/button_rotation.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/button_state_log.dart';
import 'package:rev_crane_control_ops/widgets/buttons/control_button_visuals.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ToggleSwitchMode
// ─────────────────────────────────────────────────────────────────────────────

enum ToggleSwitchMode {
  springReturnOneSide, // O-T
  latchingOneSide, // O-R
  springReturnBoth, // R-O-R
  latchingBoth, // T-O-T
  mixed, // T-O-R
}

// ─────────────────────────────────────────────────────────────────────────────
// ToggleSwitchPosition
// ─────────────────────────────────────────────────────────────────────────────

/// Logical lever position.
///   left   → top of the vertical lever  (first active direction)
///   center → neutral / OFF
///   right  → bottom of the vertical lever (second active direction)
enum ToggleSwitchPosition { left, center, right }

// ─────────────────────────────────────────────────────────────────────────────
// Private constants
// ─────────────────────────────────────────────────────────────────────────────

/// Physics spring: mass=1, stiffness=460, damping=26 → ζ≈0.60 (underdamped).
/// Produces a crisp snap with a subtle one-cycle bounce — premium toggle feel.
const _kSpring = SpringDescription(mass: 1.0, stiffness: 460.0, damping: 26.0);

const Duration _kColorDur = Duration(milliseconds: 150);

/// Knob y-alignment targets.  ±0.36 keeps the sphere well inside the pill's
/// rounded end caps.
const double _kKnobTopY = -0.58;
const double _kKnobBotY = 0.58;
const double _kKnobVisualLimit = 0.62;

// Interaction zones (fraction of the full Listener area height).
const double _kTopZone = 0.33; // 0 – 33 %
const double _kBottomZone = 0.67; // 67 – 100 %
const double _kDragMin = 14.0; // px before a drag is treated as directional

// Lever housing colours
const _kBodyGradStart = Color(0xFF1A2634);
const _kBodyGradEnd = Color(0xFF0D1520);
const _kBodyBorder = Color(0xFF24394C);
const _kGrooveTop = Color(0xFF080E15);
const _kGrooveBottom = Color(0xFF162030);

// Knob colours (idle vs. active)
// const _kKnobIdle = Color(0xFF4A5E72);
// const _kKnobIdleDark = Color(0xFF2A3A4A);
// const _kKnobIdleBorder = Color(0xFF1C2C3C);

// ─────────────────────────────────────────────────────────────────────────────
// ToggleSwitchButton
// ─────────────────────────────────────────────────────────────────────────────

class ToggleSwitchButton extends StatefulWidget {
  const ToggleSwitchButton({
    super.key,
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.activeColorLight,
    required this.isActive,
    required this.isDisabled,
    required this.isSpringReturn,
    required this.onCommandChanged,
    this.style = const ButtonStyleConfig(),
    this.rotation = ButtonRotation.none,
    this.mode,
    this.position,
    this.topLabel,
    this.bottomLabel,
    this.onPositionChanged,
    this.onReleased,
    this.leftIsSpringReturn,
    this.rightIsSpringReturn,
  });

  // ── Legacy API (preserved) ───────────────────────────────────────────────
  final String label;
  final IconData icon;
  final Color activeColor;
  final Color activeColorLight;
  final bool isActive;
  final bool isDisabled;
  final bool isSpringReturn;
  final ValueChanged<ControlState> onCommandChanged;
  final ButtonStyleConfig style;
  final ButtonRotation rotation;

  // ── Extended API ─────────────────────────────────────────────────────────
  final ToggleSwitchMode? mode;
  final ToggleSwitchPosition? position;
  final String? topLabel;
  final String? bottomLabel;
  final ValueChanged<ToggleSwitchPosition>? onPositionChanged;
  final VoidCallback? onReleased;
  final bool? leftIsSpringReturn;
  final bool? rightIsSpringReturn;

  // ── Computed helpers ─────────────────────────────────────────────────────

  ToggleSwitchMode get resolvedMode =>
      mode ??
      (isSpringReturn
          ? ToggleSwitchMode.springReturnOneSide
          : ToggleSwitchMode.latchingOneSide);

  bool get isThreePosition => switch (resolvedMode) {
    ToggleSwitchMode.springReturnBoth ||
    ToggleSwitchMode.latchingBoth ||
    ToggleSwitchMode.mixed => true,
    _ => false,
  };

  String get resolvedTopLabel =>
      topLabel ??
      switch (resolvedMode) {
        ToggleSwitchMode.springReturnOneSide ||
        ToggleSwitchMode.latchingOneSide => 'O',
        ToggleSwitchMode.springReturnBoth => 'R',
        ToggleSwitchMode.latchingBoth => 'T',
        ToggleSwitchMode.mixed => 'T',
      };

  String get resolvedBottomLabel =>
      bottomLabel ??
      switch (resolvedMode) {
        ToggleSwitchMode.springReturnOneSide => 'T',
        ToggleSwitchMode.latchingOneSide => 'R',
        ToggleSwitchMode.springReturnBoth => 'R',
        ToggleSwitchMode.latchingBoth => 'T',
        ToggleSwitchMode.mixed => 'R',
      };

  bool get topSideIsSpring => switch (resolvedMode) {
    ToggleSwitchMode.springReturnBoth => true,
    ToggleSwitchMode.mixed => leftIsSpringReturn ?? false,
    _ => false,
  };

  bool get bottomSideIsSpring => switch (resolvedMode) {
    ToggleSwitchMode.springReturnOneSide => true,
    ToggleSwitchMode.springReturnBoth => true,
    ToggleSwitchMode.mixed => rightIsSpringReturn ?? true,
    _ => false,
  };

  @override
  State<ToggleSwitchButton> createState() => _ToggleSwitchButtonState();
}

// ─────────────────────────────────────────────────────────────────────────────
// _ToggleSwitchButtonState
// ─────────────────────────────────────────────────────────────────────────────

class _ToggleSwitchButtonState extends State<ToggleSwitchButton>
    with TickerProviderStateMixin {
  // ── Logical state ─────────────────────────────────────────────────────────
  ToggleSwitchPosition _pos = ToggleSwitchPosition.center;

  // ── Gesture state ─────────────────────────────────────────────────────────
  bool _topHeld = false;
  bool _bottomHeld = false;
  double? _dragStartDy; // pointer-down y in Listener coordinates
  double _dragStartKnobY = 0.0; // knob y when drag started
  double _dragVelocityPxS = 0.0; // drag velocity in px/s
  double _lastDragDy = 0.0;
  int _lastDragMicros = 0;
  ToggleSwitchPosition? _pendingPos;

  // Identifies the single pointer currently driving this lever so late/
  // duplicate events from any other pointer can't reactivate or re-release
  // it (duplicate-gesture-emission guard).
  int? _activePointerId;

  // Set the instant a local release/cancel returns a spring side to centre,
  // cleared on the next fresh pointer-down. While true, external
  // isActive/position updates (which may be a stale/delayed PLC status echo
  // of the press just released) must not resync this lever off centre again;
  // only a new physical pointer down may reactivate it.
  bool _suppressExternalReactivation = false;

  // ── Animation controllers ─────────────────────────────────────────────────
  late final AnimationController
  _knobCtrl; // unbounded: drives knob y-alignment
  late final AnimationController _scaleCtrl; // 0–1: drives press scale feedback

  // Stored from the last LayoutBuilder pass; used for velocity conversion.
  double _lastLeverH = 120.0;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _knobCtrl = AnimationController.unbounded(vsync: this);
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _pos = _wantedPosition() ?? ToggleSwitchPosition.center;
    _knobCtrl.value = _knobYForPos(_pos);
  }

  @override
  void dispose() {
    _knobCtrl.dispose();
    _scaleCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ToggleSwitchButton old) {
    super.didUpdateWidget(old);

    // A gesture already in progress on this button always wins. Rebuilds
    // triggered by unrelated buttons (or BLE/status stream ticks feeding the
    // same shared ChangeNotifier) must never yank the lever out from under
    // an active press/drag, and must never be queued to replay afterwards.
    final gestureInProgress =
        _topHeld || _bottomHeld || _pendingPos != null || _dragStartDy != null;
    if (gestureInProgress) return;

    // Only resync from external state when it actually changed for *this*
    // button — not on every rebuild of the shared parent. This is what
    // stops sibling buttons (and unrelated notifyListeners() calls) from
    // forcing a stale/no-op resync that fights this button's own state.
    if (widget.position == old.position &&
        widget.isActive == old.isActive &&
        widget.isThreePosition == old.isThreePosition) {
      return;
    }

    final want = _wantedPosition();

    // A lever just locally released must stay at centre until a new
    // physical press; a late/stale external "active" echo (e.g. a delayed
    // PLC status notification for the press just released) is ignored so it
    // can't flip the lever off centre again on its own.
    if (_suppressExternalReactivation &&
        want != null &&
        want != ToggleSwitchPosition.center) {
      ButtonStateLog.log(
        'PLC_STATUS_ACTIVE ignored (stale, post-release) [${widget.label}]',
      );
      return;
    }

    if (want != null && want != _pos) {
      setState(() => _pos = want);
      _springTo(_knobYForPos(want));
    }
  }

  ToggleSwitchPosition? _wantedPosition() {
    if (widget.position != null) return widget.position;
    if (!widget.isThreePosition) {
      return widget.isActive
          ? ToggleSwitchPosition.right
          : ToggleSwitchPosition.center;
    }
    return null;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  bool get _enabled => !widget.isDisabled;

  double _knobYForPos(ToggleSwitchPosition pos) => switch (pos) {
    ToggleSwitchPosition.left => _kKnobTopY,
    ToggleSwitchPosition.center => widget.isThreePosition ? 0.0 : _kKnobTopY,
    ToggleSwitchPosition.right => _kKnobBotY,
  };

  // ── Physics ───────────────────────────────────────────────────────────────

  void _springTo(double target, {double velocity = 0.0}) {
    _knobCtrl.animateWith(
      SpringSimulation(_kSpring, _knobCtrl.value, target, velocity),
    );
  }

  // ── Scale feedback ────────────────────────────────────────────────────────

  void _pressDown() => _scaleCtrl.forward();
  void _pressUp() => _scaleCtrl.reverse();

  // ── Velocity tracking ─────────────────────────────────────────────────────

  void _trackVelocity(double dy) {
    final now = DateTime.now().microsecondsSinceEpoch;
    if (_lastDragMicros > 0) {
      final dt = (now - _lastDragMicros) / 1e6;
      if (dt > 0.001) _dragVelocityPxS = (dy - _lastDragDy) / dt;
    }
    _lastDragDy = dy;
    _lastDragMicros = now;
  }

  /// Converts current px/s velocity to alignment-unit/s for SpringSimulation.
  double get _alignVelocity {
    // (H - C) / 2 ≈ leverH * 0.35  for knobSz = w * 0.58, w = h * 110/210
    final pixPerUnit = (_lastLeverH * 0.35).clamp(20.0, 100.0);
    return _dragVelocityPxS / pixPerUnit;
  }

  // ── Command dispatch ──────────────────────────────────────────────────────

  ControlState _commandFor(ToggleSwitchPosition pos) {
    if (!widget.isThreePosition) {
      return pos == ToggleSwitchPosition.right
          ? ControlState.slow
          : ControlState.idle;
    }
    return switch (pos) {
      ToggleSwitchPosition.left => ControlState.slow,
      ToggleSwitchPosition.center => ControlState.idle,
      ToggleSwitchPosition.right => ControlState.fast,
    };
  }

  void _moveTo(ToggleSwitchPosition next) {
    if (_pos == next) return;
    setState(() => _pos = next);
    ButtonStateLog.log(
      '${next == ToggleSwitchPosition.center ? 'VISUAL_IDLE' : 'VISUAL_ACTIVE'} '
      '[${widget.label}] -> ${next.name}',
    );
    widget.onPositionChanged?.call(next);
    widget.onCommandChanged(_commandFor(next));
  }

  // ── Latch intents ─────────────────────────────────────────────────────────

  ToggleSwitchPosition _latchTopIntent() {
    if (!widget.isThreePosition) return ToggleSwitchPosition.center;
    return _pos == ToggleSwitchPosition.left
        ? ToggleSwitchPosition.center
        : ToggleSwitchPosition.left;
  }

  ToggleSwitchPosition _latchBottomIntent() =>
      _pos == ToggleSwitchPosition.right
      ? ToggleSwitchPosition.center
      : ToggleSwitchPosition.right;

  // ── Pointer handlers ──────────────────────────────────────────────────────

  void _onPointerDown(PointerDownEvent event, double areaH, double leverH) {
    if (!_enabled) return;
    // A pointer already driving this lever owns the gesture; ignore a
    // second/late pointer trying to start a new one on top of it.
    if (_activePointerId != null) return;
    _activePointerId = event.pointer;
    _suppressExternalReactivation = false;
    ButtonStateLog.log('USER_DOWN [${widget.label}] pointer=${event.pointer}');
    _dragStartDy = event.localPosition.dy;
    _dragStartKnobY = _knobCtrl.value;
    _dragVelocityPxS = 0.0;
    _lastDragMicros = 0;
    _pendingPos = null;
    _pressDown();

    final frac = (_dragStartDy! / areaH).clamp(0.0, 1.0);

    if (frac < _kTopZone) {
      // ── Top zone ──────────────────────────────────────────────────────────
      if (widget.topSideIsSpring) {
        _topHeld = true;
        HapticFeedback.selectionClick();
        _moveTo(ToggleSwitchPosition.left);
        _springTo(_kKnobTopY);
      } else {
        _pendingPos = _latchTopIntent();
        _springTo(_knobYForPos(_pendingPos!)); // animate preview
      }
    } else if (frac > _kBottomZone) {
      // ── Bottom zone ───────────────────────────────────────────────────────
      if (widget.bottomSideIsSpring) {
        _bottomHeld = true;
        HapticFeedback.selectionClick();
        _moveTo(ToggleSwitchPosition.right);
        _springTo(_kKnobBotY);
      } else {
        _pendingPos = _latchBottomIntent();
        _springTo(_knobYForPos(_pendingPos!));
      }
    }
    // Dead zone: no commit yet; drag will handle it.
  }

  void _onPointerMove(PointerMoveEvent event, double areaH, double leverH) {
    if (!_enabled || _dragStartDy == null) return;
    if (event.pointer != _activePointerId) return;

    final dy = event.localPosition.dy;
    final delta = dy - _dragStartDy!;
    _trackVelocity(dy);

    // ── Spring side: direction-switch mid-drag ─────────────────────────────
    if (_topHeld || _bottomHeld) {
      final frac = (dy / areaH).clamp(0.0, 1.0);
      if (_topHeld && frac > _kBottomZone && widget.bottomSideIsSpring) {
        _topHeld = false;
        _bottomHeld = true;
        HapticFeedback.selectionClick();
        _moveTo(ToggleSwitchPosition.right);
        _springTo(_kKnobBotY, velocity: _alignVelocity);
      } else if (_bottomHeld && frac < _kTopZone && widget.topSideIsSpring) {
        _bottomHeld = false;
        _topHeld = true;
        HapticFeedback.selectionClick();
        _moveTo(ToggleSwitchPosition.left);
        _springTo(_kKnobTopY, velocity: _alignVelocity);
      }
      return;
    }

    // ── Live drag tracking: knob follows finger ────────────────────────────
    if (delta.abs() > 2.0) {
      _knobCtrl.stop(); // cancel preview spring so drag is direct
      final pixPerUnit = (leverH * 0.35).clamp(20.0, 100.0);
      _knobCtrl.value = (_dragStartKnobY + delta / pixPerUnit).clamp(
        _kKnobTopY - 0.10,
        _kKnobBotY + 0.10,
      );
    }

    // ── Update direction intent once past threshold ────────────────────────
    if (delta.abs() >= _kDragMin) {
      if (delta < 0) {
        // Dragging upward
        if (widget.topSideIsSpring && !_topHeld) {
          _topHeld = true;
          HapticFeedback.selectionClick();
          _moveTo(ToggleSwitchPosition.left);
          _springTo(_kKnobTopY, velocity: _alignVelocity);
        } else if (!widget.topSideIsSpring) {
          _pendingPos = widget.isThreePosition
              ? ToggleSwitchPosition.left
              : ToggleSwitchPosition.center;
        }
      } else {
        // Dragging downward
        if (widget.bottomSideIsSpring && !_bottomHeld) {
          _bottomHeld = true;
          HapticFeedback.selectionClick();
          _moveTo(ToggleSwitchPosition.right);
          _springTo(_kKnobBotY, velocity: _alignVelocity);
        } else if (!widget.bottomSideIsSpring) {
          _pendingPos = ToggleSwitchPosition.right;
        }
      }
    }
  }

  void _onPointerUp(PointerUpEvent event, double areaH) {
    if (!_enabled) return;
    // Late/duplicate pointer-up for a pointer id that never started this
    // gesture is ignored — it cannot reactivate or re-release this lever.
    if (event.pointer != _activePointerId) return;
    ButtonStateLog.log('USER_UP [${widget.label}] pointer=${event.pointer}');
    _activePointerId = null;
    _pressUp();
    final vel = _alignVelocity;
    final wasSpringHeld = _topHeld || _bottomHeld;

    if (_topHeld) {
      _topHeld = false;
      _moveTo(ToggleSwitchPosition.center);
      _springTo(_knobYForPos(ToggleSwitchPosition.center), velocity: vel);
      widget.onReleased?.call();
    } else if (_bottomHeld) {
      _bottomHeld = false;
      _moveTo(ToggleSwitchPosition.center);
      _springTo(_knobYForPos(ToggleSwitchPosition.center), velocity: vel);
      widget.onReleased?.call();
    } else if (_pendingPos != null) {
      HapticFeedback.selectionClick();
      _moveTo(_pendingPos!);
      _springTo(_knobYForPos(_pendingPos!), velocity: vel);
    } else {
      // Dead-zone tap or no-drag: spring back to committed position.
      _springTo(_knobYForPos(_pos), velocity: vel);
    }

    // Arm the guard only for the spring-return sides: a stale PLC_STATUS
    // echo for the side just released must not resync the lever off centre
    // again until a fresh USER_DOWN. Latching sides are untouched — their
    // position is toggle-driven, not spring-driven.
    if (wasSpringHeld) _suppressExternalReactivation = true;

    _pendingPos = null;
    _dragStartDy = null;
    _dragVelocityPxS = 0.0;
    _lastDragMicros = 0;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointerId) return;
    ButtonStateLog.log(
      'USER_CANCEL [${widget.label}] pointer=${event.pointer}',
    );
    _activePointerId = null;
    _pressUp();
    final wasSpringHeld = _topHeld || _bottomHeld;
    if (_topHeld) {
      _topHeld = false;
      _moveTo(ToggleSwitchPosition.center);
      widget.onReleased?.call();
    }
    if (_bottomHeld) {
      _bottomHeld = false;
      _moveTo(ToggleSwitchPosition.center);
      widget.onReleased?.call();
    }
    if (wasSpringHeld) _suppressExternalReactivation = true;
    _springTo(_knobYForPos(_pos));
    _pendingPos = null;
    _dragStartDy = null;
    _dragVelocityPxS = 0.0;
    _lastDragMicros = 0;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final isOn = _pos != ToggleSwitchPosition.center;

    return Semantics(
      button: true,
      enabled: _enabled,
      toggled: isOn,
      label: widget.label,
      child: Opacity(
        opacity: _enabled ? 1.0 : 0.5,
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Industrial lever ─────────────────────────────────────────
              Expanded(
                child: LayoutBuilder(
                  builder: (ctx, cons) {
                    final areaH = cons.maxHeight;
                    final areaW = cons.maxWidth;
                    final leverH = areaH.clamp(90.0, 260.0);
                    final leverW = (leverH * (110.0 / 210.0)).clamp(
                      56.0,
                      areaW * 0.92,
                    );
                    _lastLeverH = leverH;

                    return Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (e) => _onPointerDown(e, areaH, leverH),
                      onPointerMove: (e) => _onPointerMove(e, areaH, leverH),
                      onPointerUp: (e) => _onPointerUp(e, areaH),
                      onPointerCancel: (e) => _onPointerCancel(e),
                      child: SizedBox.expand(
                        child: Center(
                          // AnimatedBuilder: rebuilds on every spring frame
                          // AND on every scale-feedback frame.
                          child: AnimatedBuilder(
                            animation: Listenable.merge([
                              _knobCtrl,
                              _scaleCtrl,
                            ]),
                            builder: (ctx, _) {
                              final scale = 1.0 - _scaleCtrl.value * 0.030;
                              return Transform.scale(
                                scale: scale,
                                child: SizedBox(
                                  width: leverW,
                                  height: leverH,
                                  child: _LeverBody(
                                    knobY: _knobCtrl.value,
                                    isOn: isOn,
                                    activeColor: widget.activeColor,
                                    activeColorLight: widget.activeColorLight,
                                    mode: widget.resolvedMode,
                                    position: _pos,
                                    topLabel: widget.resolvedTopLabel,
                                    bottomLabel: widget.resolvedBottomLabel,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // ── Compact footer ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(top: 5, bottom: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: ControlButtonVisualMetrics.rowHeight,
                        child: ControlButtonLabelIcon(
                          label: widget.label,
                          icon: widget.icon,
                          style: style,
                          color: isOn
                              ? widget.activeColorLight
                              : AppColors.darkText,
                          iconColor: isOn
                              ? widget.activeColorLight
                              : AppColors.darkTextMuted,
                          rotation: widget.rotation,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _HintLabel(mode: widget.resolvedMode, pos: _pos),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LeverBody
//
// Pure-visual industrial toggle switch housing. Compact O/T/R indicators are
// drawn on top of the switch face only as visual labels; state and output are
// still driven exclusively by the knob position and existing callbacks.
// ─────────────────────────────────────────────────────────────────────────────

class _LeverBody extends StatelessWidget {
  const _LeverBody({
    required this.knobY,
    required this.isOn,
    required this.activeColor,
    required this.activeColorLight,
    required this.mode,
    required this.position,
    required this.topLabel,
    required this.bottomLabel,
  });

  final double knobY;
  final bool isOn;
  final Color activeColor;
  final Color activeColorLight;
  final ToggleSwitchMode mode;
  final ToggleSwitchPosition position;
  final String topLabel;
  final String bottomLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final radius = w * 0.5;
        final knobSz = w * 0.58;
        final grooveW = w * 0.36;
        final grooveH = h * 0.70;

        return DecoratedBox(
          // Outer drop shadow lives here so it paints OUTSIDE the clipped
          // stack and is not swallowed by Clip.hardEdge.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(130),
                blurRadius: 22,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            alignment: Alignment.center,
            children: [
              // ── Body shell ───────────────────────────────────────────────
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [_kBodyGradStart, _kBodyGradEnd],
                    ),
                    border: Border.all(color: _kBodyBorder, width: 3.0),
                    boxShadow: [
                      // inner depth shadow
                      BoxShadow(
                        color: Colors.black.withAlpha(200),
                        blurRadius: 10,
                        spreadRadius: -4,
                      ),
                    ],
                  ),
                ),
              ),

              // ── Active colour wash (animates with _kColorDur) ────────────
              Positioned.fill(
                child: AnimatedContainer(
                  duration: _kColorDur,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    color: isOn
                        ? activeColor.withAlpha(22)
                        : Colors.transparent,
                  ),
                ),
              ),

              // ── Top rim glass highlight ──────────────────────────────────
              Positioned(
                top: 3,
                left: 3,
                right: 3,
                height: h * 0.15,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(radius),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white.withAlpha(22), Colors.transparent],
                    ),
                  ),
                ),
              ),

              // ── Center groove / gate ─────────────────────────────────────
              Container(
                width: grooveW,
                height: grooveH,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(grooveW * 0.5),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_kGrooveTop, _kGrooveBottom],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(220),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),

              // ── Knob (driven by AnimationController via Align) ───────────
              Align(
                alignment: Alignment(
                  0.0,
                  knobY.clamp(-_kKnobVisualLimit, _kKnobVisualLimit),
                ),
                child: _Knob(
                  size: knobSz,
                  isOn: isOn,
                  activeColor: activeColor,
                  activeDark: Color.alphaBlend(
                    Colors.black.withAlpha(65),
                    activeColor,
                  ),
                ),
              ),

              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: _PositionIndicators(
                      mode: mode,
                      position: position,
                      topLabel: topLabel,
                      bottomLabel: bottomLabel,
                      activeColor: activeColorLight,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PositionIndicators extends StatelessWidget {
  const _PositionIndicators({
    required this.mode,
    required this.position,
    required this.topLabel,
    required this.bottomLabel,
    required this.activeColor,
  });

  final ToggleSwitchMode mode;
  final ToggleSwitchPosition position;
  final String topLabel;
  final String bottomLabel;
  final Color activeColor;

  bool get _isThreePosition => switch (mode) {
    ToggleSwitchMode.springReturnBoth ||
    ToggleSwitchMode.latchingBoth ||
    ToggleSwitchMode.mixed => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        if (w < 42 || h < 78) return const SizedBox.shrink();

        final labelSize = math.min(w * 0.30, h * 0.105).clamp(12.0, 18.0);
        final right = (w * 0.06).clamp(3.0, 8.0);
        final centerLabel = _isThreePosition ? 'O' : null;

        return Stack(
          children: [
            _alignedLabel(
              label: topLabel,
              alignment: const Alignment(1.0, _kKnobTopY),
              size: labelSize,
              right: right,
              isActive: _isThreePosition
                  ? position == ToggleSwitchPosition.left
                  : position == ToggleSwitchPosition.center,
            ),
            if (centerLabel != null)
              _alignedLabel(
                label: centerLabel,
                alignment: Alignment.centerRight,
                size: labelSize,
                right: right,
                isActive: position == ToggleSwitchPosition.center,
              ),
            _alignedLabel(
              label: bottomLabel,
              alignment: const Alignment(1.0, _kKnobBotY),
              size: labelSize,
              right: right,
              isActive: position == ToggleSwitchPosition.right,
            ),
          ],
        );
      },
    );
  }

  Widget _alignedLabel({
    required String label,
    required Alignment alignment,
    required double size,
    required double right,
    required bool isActive,
  }) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: EdgeInsets.only(right: right),
        child: _PositionIndicatorLabel(
          label: label,
          size: size,
          isActive: isActive,
          activeColor: activeColor,
        ),
      ),
    );
  }
}

class _PositionIndicatorLabel extends StatelessWidget {
  const _PositionIndicatorLabel({
    required this.label,
    required this.size,
    required this.isActive,
    required this.activeColor,
  });

  final String label;
  final double size;
  final bool isActive;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    final fontSize = (size * 0.56).clamp(7.0, 10.0);
    final color = isActive ? activeColor : AppColors.darkTextSub;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(isActive ? 100 : 70),
        borderRadius: BorderRadius.circular(size * 0.35),
        border: Border.all(
          color: color.withAlpha(isActive ? 170 : 105),
          width: 1,
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.clip,
        softWrap: false,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: ControlButtonVisualMetrics.labelFontWeight,
          letterSpacing: 0,
          height: 1,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _Knob
// ─────────────────────────────────────────────────────────────────────────────

// class _Knob extends StatelessWidget {
//   const _Knob({
//     required this.size,
//     required this.isOn,
//     required this.activeColor,
//     required this.activeDark,
//   });

//   final double size;
//   final bool isOn;
//   final Color activeColor;
//   final Color activeDark;

//   @override
//   Widget build(BuildContext context) {
//     final Color base   = isOn ? activeColor      : _kKnobIdle;
//     final Color dark   = isOn ? activeDark       : _kKnobIdleDark;
//     final Color border = isOn ? activeDark       : _kKnobIdleBorder;
//     final Color glow   = isOn
//         ? activeColor.withAlpha(120)
//         : Colors.black.withAlpha(50);
//     final double bw = (size * 0.058).clamp(2.0, 5.0);

//     return AnimatedContainer(
//       duration: _kColorDur,
//       width: size,
//       height: size,
//       decoration: BoxDecoration(
//         shape: BoxShape.circle,
//         gradient: RadialGradient(
//           center: const Alignment(-0.30, -0.40),
//           radius: 0.85,
//           colors: [base, dark],
//         ),
//         border: Border.all(color: border, width: bw),
//         boxShadow: [
//           // Drop shadow
//           BoxShadow(
//             color: Colors.black.withAlpha(110),
//             blurRadius: 14,
//             offset: const Offset(0, 5),
//           ),
//           // Inner top highlight
//           BoxShadow(
//             color: Colors.white.withAlpha(40),
//             blurRadius: 6,
//             offset: const Offset(0, -2),
//             spreadRadius: -3,
//           ),
//           // Colour glow (no spreadRadius — avoids edge bleed)
//           BoxShadow(
//             color: glow,
//             blurRadius: 14,
//           ),
//         ],
//       ),
//       child: Stack(
//         children: [
//           // Top arc highlight
//           Positioned(
//             top: size * 0.11,
//             left: size * 0.17,
//             right: size * 0.17,
//             height: size * 0.26,
//             child: Container(
//               decoration: BoxDecoration(
//                 borderRadius: BorderRadius.circular(size),
//                 gradient: RadialGradient(
//                   colors: [
//                     Colors.white.withAlpha(58),
//                     Colors.transparent,
//                   ],
//                 ),
//               ),
//             ),
//           ),
//           // Centre gloss dot
//           Center(
//             child: Container(
//               width: size * 0.24,
//               height: size * 0.24,
//               decoration: BoxDecoration(
//                 shape: BoxShape.circle,
//                 gradient: RadialGradient(
//                   center: const Alignment(-0.2, -0.3),
//                   colors: [
//                     Colors.white.withAlpha(75),
//                     Colors.transparent,
//                   ],
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }F

// ─────────────────────────────────────────────────────────────────────────────
// _HintLabel
// ─────────────────────────────────────────────────────────────────────────────

class _HintLabel extends StatelessWidget {
  const _HintLabel({required this.mode, required this.pos});

  final ToggleSwitchMode mode;
  final ToggleSwitchPosition pos;

  String get _text {
    final isOn = pos != ToggleSwitchPosition.center;
    return switch (mode) {
      ToggleSwitchMode.springReturnOneSide => isOn ? 'ACTIVE' : 'HOLD',
      ToggleSwitchMode.latchingOneSide => isOn ? 'ON · TAP' : 'OFF · TAP',
      ToggleSwitchMode.springReturnBoth => isOn ? 'ACTIVE' : 'HOLD EITHER',
      ToggleSwitchMode.latchingBoth => isOn ? 'ON · TAP OFF' : 'TAP EITHER',
      ToggleSwitchMode.mixed => switch (pos) {
        ToggleSwitchPosition.left => 'ON · TAP',
        ToggleSwitchPosition.right => 'ACTIVE',
        ToggleSwitchPosition.center => 'TAP / HOLD',
      },
    };
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _text,
      style: const TextStyle(
        color: AppColors.darkTextSub,
        fontSize: 8,
        fontWeight: ControlButtonVisualMetrics.labelFontWeight,
        letterSpacing: 1.0,
      ),
    );
  }
}

// Interaction zones (fraction of the Listener/SizedBox.expand height).
// The lever is always centred in the area, so these fractions mirror the
// lever's own thirds.  A tap in the dead zone (33–67 %) does nothing on its
// own; only a drag past _kDragMin px commits to a direction.
// 0 – 33 %  → top lever-end
// 67 – 100 % → bottom lever-end
// px before a drag is directionally committed

/// Knob y-alignments.  ±0.36 keeps the knob well within the pill's rounded
/// end caps — enough visual margin so the thumb never appears to touch the
/// lever body edge.
// const _kAlignTop = Alignment(0.0, -0.36);
// const _kAlignCenter = Alignment(0.0, 0.00);
// const _kAlignBottom = Alignment(0.0, 0.36);

// Lever housing colours — direct ports from the HTML CSS variables.
// const _kBodyBorder    = Color(0xFF24394C);
// const _kGrooveTop     = Color(0xFF0A0F16);
// const _kGrooveBottom  = Color(0xFF1A2634);
const _kOffLedColor = Color(0xFFE74C3C); // --off
const _kOffLedBorder = Color(0xFFA93226);
const _kKnobOffBase = Color(0xFFE74C3C);
const _kKnobOffDark = Color(0xFFC0392B);
// const _kLabelInactive = Color(0xFF4A5568);

// ─────────────────────────────────────────────────────────────────────────────
// ToggleSwitchButton
// ─────────────────────────────────────────────────────────────────────────────

// class ToggleSwitchButton extends StatefulWidget {
//   const ToggleSwitchButton({
//     super.key,
//     // ── Preserved legacy API (required by ToggleButtonStrategy) ───────────
//     required this.label,
//     required this.icon,
//     required this.activeColor,
//     required this.activeColorLight,
//     required this.isActive,
//     required this.isDisabled,
//     required this.isSpringReturn,
//     required this.onCommandChanged,
//     this.style = const ButtonStyleConfig(),
//     // ── Extended multi-position API (all optional) ─────────────────────────
//     this.mode,
//     this.position,
//     this.topLabel,
//     this.bottomLabel,
//     this.onPositionChanged,
//     this.onReleased,
//     this.leftIsSpringReturn,
//     this.rightIsSpringReturn,
//   });

//   // ── Legacy API ───────────────────────────────────────────────────────────

//   final String label;
//   final IconData icon;

//   /// Pre-resolved primary / active color (caller handles theme lookup).
//   final Color activeColor;
//   final Color activeColorLight;

//   final bool isActive;
//   final bool isDisabled;

//   /// Controls the inferred mode when [mode] is null:
//   ///   true  → [ToggleSwitchMode.springReturnOneSide]
//   ///   false → [ToggleSwitchMode.latchingOneSide]
//   final bool isSpringReturn;

//   /// Legacy one-sided callback; emits [ControlState.slow] / [ControlState.idle].
//   final ValueChanged<ControlState> onCommandChanged;
//   final ButtonStyleConfig style;

//   // ── Extended API ─────────────────────────────────────────────────────────

//   /// Override the inferred mode.  When null the mode is derived from
//   /// [isSpringReturn].
//   final ToggleSwitchMode? mode;

//   /// Externally driven position (fully-controlled usage).  When null the
//   /// widget manages position internally, seeded from [isActive].
//   final ToggleSwitchPosition? position;

//   /// Override for the top lever end label.
//   /// Default per mode: one-sided → "O", springReturnBoth → "R",
//   ///                   latchingBoth → "T", mixed → "T".
//   final String? topLabel;

//   /// Override for the bottom lever end label.
//   /// Default per mode: springReturn* → "T", latching* → "R".
//   final String? bottomLabel;

//   /// Fired on every position change (all modes).
//   final ValueChanged<ToggleSwitchPosition>? onPositionChanged;

//   /// Fired when a spring-return lever snaps back to [ToggleSwitchPosition.center].
//   final VoidCallback? onReleased;

//   /// For [ToggleSwitchMode.mixed]: whether the TOP (left) side is
//   /// spring-return.  Defaults to false (latching).
//   final bool? leftIsSpringReturn;

//   /// For [ToggleSwitchMode.mixed]: whether the BOTTOM (right) side is
//   /// spring-return.  Defaults to true.
//   final bool? rightIsSpringReturn;

//   // ── Computed helpers ─────────────────────────────────────────────────────

//   ToggleSwitchMode get resolvedMode => mode ??
//       (isSpringReturn
//           ? ToggleSwitchMode.springReturnOneSide
//           : ToggleSwitchMode.latchingOneSide);

//   bool get isThreePosition => switch (resolvedMode) {
//     ToggleSwitchMode.springReturnBoth ||
//     ToggleSwitchMode.latchingBoth ||
//     ToggleSwitchMode.mixed => true,
//     _ => false,
//   };

//   String get resolvedTopLabel => topLabel ?? switch (resolvedMode) {
//     ToggleSwitchMode.springReturnOneSide ||
//     ToggleSwitchMode.latchingOneSide => 'O',
//     ToggleSwitchMode.springReturnBoth => 'R',
//     ToggleSwitchMode.latchingBoth => 'T',
//     ToggleSwitchMode.mixed => 'T',
//   };

//   String get resolvedBottomLabel => bottomLabel ?? switch (resolvedMode) {
//     ToggleSwitchMode.springReturnOneSide => 'T',
//     ToggleSwitchMode.latchingOneSide => 'R',
//     ToggleSwitchMode.springReturnBoth => 'R',
//     ToggleSwitchMode.latchingBoth => 'T',
//     ToggleSwitchMode.mixed => 'R',
//   };

//   /// Whether the top (left) lever end is spring-return in the current mode.
//   bool get topSideIsSpring => switch (resolvedMode) {
//     ToggleSwitchMode.springReturnBoth => true,
//     ToggleSwitchMode.mixed => leftIsSpringReturn ?? false,
//     _ => false,
//   };

//   /// Whether the bottom (right) lever end is spring-return in the current mode.
//   bool get bottomSideIsSpring => switch (resolvedMode) {
//     ToggleSwitchMode.springReturnOneSide => true,
//     ToggleSwitchMode.springReturnBoth => true,
//     ToggleSwitchMode.mixed => rightIsSpringReturn ?? true,
//     _ => false,
//   };

//   @override
//   State<ToggleSwitchButton> createState() => _ToggleSwitchButtonState();
// }

// ─────────────────────────────────────────────────────────────────────────────
// _ToggleSwitchButtonState
// ─────────────────────────────────────────────────────────────────────────────

// class _ToggleSwitchButtonState extends State<ToggleSwitchButton> {
//   ToggleSwitchPosition _pos = ToggleSwitchPosition.center;
//   bool   _topHeld    = false;  // spring-return top side actively held
//   bool   _bottomHeld = false;  // spring-return bottom side actively held
//   double? _dragStartDy;        // y of pointer-down in listener coordinates
//   // Pending latching position: shown as a live knob preview during drag and
//   // committed to _pos on pointer-up.  Null = no committed intent yet.
//   ToggleSwitchPosition? _pendingPos;

//   // ── Lifecycle ─────────────────────────────────────────────────────────────

//   @override
//   void initState() {
//     super.initState();
//     _pos = _wantedPosition() ?? ToggleSwitchPosition.center;
//   }

//   @override
//   void didUpdateWidget(ToggleSwitchButton old) {
//     super.didUpdateWidget(old);
//     final want = _wantedPosition();
//     if (want != null && want != _pos) setState(() => _pos = want);
//   }

//   /// Returns the position demanded by the widget props, or null for
//   /// uncontrolled three-position mode (fully internal state).
//   ToggleSwitchPosition? _wantedPosition() {
//     if (widget.position != null) return widget.position;
//     if (!widget.isThreePosition) {
//       return widget.isActive
//           ? ToggleSwitchPosition.right
//           : ToggleSwitchPosition.center;
//     }
//     return null;
//   }

//   // ── Computed ──────────────────────────────────────────────────────────────

//   bool get _enabled => !widget.isDisabled;

//   /// Maps the current (or pending) position to a knob [Alignment].
//   /// [_pendingPos] is used when set so the knob provides a live drag-preview
//   /// before the latching intent is committed on pointer-up.
//   Alignment get _knobAlignment {
//     final visual = _pendingPos ?? _pos;
//     return switch (visual) {
//       ToggleSwitchPosition.left   => _kAlignTop,
//       ToggleSwitchPosition.center =>
//           widget.isThreePosition ? _kAlignCenter : _kAlignTop,
//       ToggleSwitchPosition.right  => _kAlignBottom,
//     };
//   }

//   // ── Position emit ─────────────────────────────────────────────────────────

//   /// Maps a lever [ToggleSwitchPosition] to the [ControlState] emitted on
//   /// [onCommandChanged].
//   ///
//   /// One-sided modes (O-T / O-R):
//   ///   right  → slow   (the single active end)
//   ///   center → idle
//   ///   left   → idle   (never reached in practice for one-sided modes)
//   ///
//   /// Three-position modes (R-O-R / T-O-T / T-O-R):
//   ///   left   → slow   (top end — first active direction)
//   ///   center → idle   (neutral)
//   ///   right  → fast   (bottom end — second active direction / higher speed)
//   ControlState _commandFor(ToggleSwitchPosition pos) {
//     if (!widget.isThreePosition) {
//       return pos == ToggleSwitchPosition.right
//           ? ControlState.slow
//           : ControlState.idle;
//     }
//     return switch (pos) {
//       ToggleSwitchPosition.left   => ControlState.slow,
//       ToggleSwitchPosition.center => ControlState.idle,
//       ToggleSwitchPosition.right  => ControlState.fast,
//     };
//   }

//   void _moveTo(ToggleSwitchPosition next) {
//     if (_pos == next) return;
//     setState(() => _pos = next);
//     widget.onPositionChanged?.call(next);
//     widget.onCommandChanged(_commandFor(next));
//   }

//   // ── Pointer handling ──────────────────────────────────────────────────────

//   // ── Latching tap-intent helpers ───────────────────────────────────────────
//   // These are used when a tap lands in a clear zone (no drag required).
//   // Toggle semantics: if already at that position, return to center.

//   /// Intent for a tap in the top zone (latching side only).
//   ToggleSwitchPosition _latchTopIntent() {
//     // One-sided: top zone always maps to OFF (center).
//     if (!widget.isThreePosition) return ToggleSwitchPosition.center;
//     // Three-position: toggle — if already left, release to center.
//     return _pos == ToggleSwitchPosition.left
//         ? ToggleSwitchPosition.center
//         : ToggleSwitchPosition.left;
//   }

//   /// Intent for a tap in the bottom zone (latching side only).
//   ToggleSwitchPosition _latchBottomIntent() {
//     // Toggle — if already right, release to center.
//     return _pos == ToggleSwitchPosition.right
//         ? ToggleSwitchPosition.center
//         : ToggleSwitchPosition.right;
//   }

//   // ─────────────────────────────────────────────────────────────────────────

//   void _onPointerDown(PointerDownEvent event, double areaH) {
//     if (!_enabled) return;
//     _dragStartDy = event.localPosition.dy;
//     _pendingPos  = null;

//     final frac = (_dragStartDy! / areaH).clamp(0.0, 1.0);

//     if (frac < _kTopZone) {
//       // ── Top zone ─────────────────────────────────────────────────────────
//       if (widget.topSideIsSpring) {
//         _topHeld = true;
//         HapticFeedback.selectionClick();
//         _moveTo(ToggleSwitchPosition.left);
//       } else {
//         // Latching: stage intent — committed on pointer-up.
//         _pendingPos = _latchTopIntent();
//       }
//     } else if (frac > _kBottomZone) {
//       // ── Bottom zone ───────────────────────────────────────────────────────
//       if (widget.bottomSideIsSpring) {
//         _bottomHeld = true;
//         HapticFeedback.selectionClick();
//         _moveTo(ToggleSwitchPosition.right);
//       } else {
//         _pendingPos = _latchBottomIntent();
//       }
//     }
//     // Dead zone: no intent yet; _onPointerMove will set _pendingPos if dragged.
//   }

//   void _onPointerMove(PointerMoveEvent event, double areaH) {
//     if (!_enabled || _dragStartDy == null) return;
//     final delta = event.localPosition.dy - _dragStartDy!;

//     // ── Spring sides can switch direction mid-drag ─────────────────────────
//     if (_topHeld || _bottomHeld) {
//       final frac = (event.localPosition.dy / areaH).clamp(0.0, 1.0);
//       if (_topHeld && frac > _kBottomZone && widget.bottomSideIsSpring) {
//         _topHeld    = false;
//         _bottomHeld = true;
//         HapticFeedback.selectionClick();
//         _moveTo(ToggleSwitchPosition.right);
//       } else if (_bottomHeld && frac < _kTopZone && widget.topSideIsSpring) {
//         _bottomHeld = false;
//         _topHeld    = true;
//         HapticFeedback.selectionClick();
//         _moveTo(ToggleSwitchPosition.left);
//       }
//       return;
//     }

//     if (delta.abs() < _kDragMin) return; // micro-movement — no commit yet

//     // Drag direction is definitive: it overrides any zone-based pending set
//     // in _onPointerDown and always resolves to an absolute position
//     // (no toggle logic — drag up = go left/center, drag down = go right).
//     if (delta < 0) {
//       // Dragging upward
//       if (widget.topSideIsSpring && !_topHeld) {
//         _topHeld = true;
//         HapticFeedback.selectionClick();
//         _moveTo(ToggleSwitchPosition.left);
//       } else if (!widget.topSideIsSpring) {
//         final want = widget.isThreePosition
//             ? ToggleSwitchPosition.left
//             : ToggleSwitchPosition.center; // one-sided drag-up = deactivate
//         if (_pendingPos != want) setState(() => _pendingPos = want);
//       }
//     } else {
//       // Dragging downward
//       if (widget.bottomSideIsSpring && !_bottomHeld) {
//         _bottomHeld = true;
//         HapticFeedback.selectionClick();
//         _moveTo(ToggleSwitchPosition.right);
//       } else if (!widget.bottomSideIsSpring) {
//         const want = ToggleSwitchPosition.right;
//         if (_pendingPos != want) setState(() => _pendingPos = want);
//       }
//     }
//   }

//   void _onPointerUp(PointerUpEvent event, double areaH) {
//     if (!_enabled) return;

//     if (_topHeld) {
//       _topHeld = false;
//       _moveTo(ToggleSwitchPosition.center); // emits idle via _commandFor
//       widget.onReleased?.call();
//     } else if (_bottomHeld) {
//       _bottomHeld = false;
//       _moveTo(ToggleSwitchPosition.center); // emits idle via _commandFor
//       widget.onReleased?.call();
//     } else if (_pendingPos != null) {
//       // Commit the latching intent that was staged or updated during drag.
//       HapticFeedback.selectionClick();
//       _moveTo(_pendingPos!);
//     }
//     // Dead-zone tap with no drag → _pendingPos is null → intentional no-op.

//     _pendingPos  = null;
//     _dragStartDy = null;
//   }

//   void _onPointerCancel() {
//     if (_topHeld) {
//       _topHeld = false;
//       _moveTo(ToggleSwitchPosition.center);
//       widget.onReleased?.call();
//     }
//     if (_bottomHeld) {
//       _bottomHeld = false;
//       _moveTo(ToggleSwitchPosition.center);
//       widget.onReleased?.call();
//     }
//     _pendingPos  = null;
//     _dragStartDy = null;
//   }

//   // ── Build ─────────────────────────────────────────────────────────────────

//   @override
//   Widget build(BuildContext context) {
//     final style    = widget.style;
//     final iconSz   = style.iconSize ?? 14.0;
//     final labelFsz = style.labelFontSize ?? 10.0;
//     final labelFw  = style.labelFontWeight ?? FontWeight.w700;

//     final isOn = _pos != ToggleSwitchPosition.center;

//     // No outer background card — the parent control grid/card owns that layer.
//     // Layout: lever fills the Expanded area; icon + label + hint sit in a
//     // compact single-line footer so the lever gets maximum vertical space.
//     return Semantics(
//       button: true,
//       enabled: _enabled,
//       toggled: isOn,
//       label: widget.label,
//       child: Opacity(
//         opacity: _enabled ? 1.0 : 0.5,
//         child: SizedBox(
//           width: double.infinity,
//           height: double.infinity,
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               // ── Industrial lever ─────────────────────────────────────────
//               // Fills all available height before the footer row.
//               // The Listener covers the full SizedBox.expand so any tap in
//               // the upper/lower half activates the corresponding direction.
//               // areaH / 2 == lever's visual centre because the lever is
//               // centred inside the expanded area.
//               Expanded(
//                 child: LayoutBuilder(
//                   builder: (ctx, cons) {
//                     final areaH = cons.maxHeight;
//                     final areaW = cons.maxWidth;
//                     final leverH = areaH.clamp(90.0, 260.0);
//                     final leverW = (leverH * (110.0 / 210.0))
//                         .clamp(56.0, areaW * 0.92);
//                     return Listener(
//                       behavior: HitTestBehavior.opaque,
//                       onPointerDown:   (e) => _onPointerDown(e, areaH),
//                       onPointerMove:   (e) => _onPointerMove(e, areaH),
//                       onPointerUp:     (e) => _onPointerUp(e, areaH),
//                       onPointerCancel: (_)  => _onPointerCancel(),
//                       child: SizedBox.expand(
//                         child: Center(
//                           child: SizedBox(
//                             width: leverW,
//                             height: leverH,
//                             child: _LeverBody(
//                               pos: _pos,
//                               isThreePosition: widget.isThreePosition,
//                               topLabel: widget.resolvedTopLabel,
//                               bottomLabel: widget.resolvedBottomLabel,
//                               activeColor: widget.activeColor,
//                               activeColorLight: widget.activeColorLight,
//                               knobAlignment: _knobAlignment,
//                             ),
//                           ),
//                         ),
//                       ),
//                     );
//                   },
//                 ),
//               ),
//               // ── Compact footer: icon · label · mode hint ─────────────────
//               Padding(
//                 padding: const EdgeInsets.only(top: 5, bottom: 3),
//                 child: Row(
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     Icon(
//                       widget.icon,
//                       size: iconSz,
//                       color: isOn
//                           ? widget.activeColorLight
//                           : AppColors.darkTextMuted,
//                     ),
//                     if (style.showLabel) ...[
//                       const SizedBox(width: 4),
//                       Flexible(
//                         child: Text(
//                           widget.label,
//                           maxLines: 1,
//                           overflow: TextOverflow.ellipsis,
//                           style: TextStyle(
//                             color: isOn
//                                 ? widget.activeColorLight
//                                 : AppColors.darkText,
//                             fontSize: labelFsz,
//                             fontWeight: labelFw,
//                             letterSpacing: 0.4,
//                           ),
//                         ),
//                       ),
//                     ],
//                     const SizedBox(width: 6),
//                     _HintLabel(mode: widget.resolvedMode, pos: _pos),
//                   ],
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

// ─────────────────────────────────────────────────────────────────────────────
// _LeverBody
//
// Pure-visual pill-shaped industrial toggle switch housing.  Renders the body
// shell, center groove, LED indicators, position labels, and animated knob.
// All gesture detection is handled by the parent Listener.
// ─────────────────────────────────────────────────────────────────────────────

// class _LeverBody extends StatelessWidget {
//   const _LeverBody({
//     required this.pos,
//     required this.isThreePosition,
//     required this.topLabel,
//     required this.bottomLabel,
//     required this.activeColor,
//     required this.activeColorLight,
//     required this.knobAlignment,
//   });

//   final ToggleSwitchPosition pos;
//   final bool isThreePosition;
//   final String topLabel;
//   final String bottomLabel;
//   final Color activeColor;
//   final Color activeColorLight;
//   final Alignment knobAlignment;

//   bool get _isTopOn    => pos == ToggleSwitchPosition.left;
//   bool get _isBottomOn => pos == ToggleSwitchPosition.right;
//   bool get _isCenter   => pos == ToggleSwitchPosition.center;

//   @override
//   Widget build(BuildContext context) {
//     return LayoutBuilder(
//       builder: (context, constraints) {
//         final w = constraints.maxWidth;
//         final h = constraints.maxHeight;

//         // Proportional sizes — mirror the HTML 110×210 px reference geometry.
//         final knobSz   = w * 0.57;           // reduced from 0.655 for edge clearance
//         final grooveW  = w * 0.418;          // 46 / 110
//         final grooveH  = h * 0.457;          // 96 / 210
//         final labelFsz = (w * 0.30).clamp(10.0, 32.0);
//         final ledSz    = (w * 0.073).clamp(5.0, 10.0);
//         final edgePad  = h * 0.062;          // 13 / 210

//         // ── Colour resolution ─────────────────────────────────────────────

//         // Top label: white when at the top position, or when one-sided and OFF
//         // (matching HTML  `.toggle:not(.active) .label.top { color: var(--text) }`).
//         final Color topLblColor;
//         final Color btmLblColor;
//         if (isThreePosition) {
//           topLblColor = _isTopOn    ? activeColorLight : _kLabelInactive;
//           btmLblColor = _isBottomOn ? activeColorLight : _kLabelInactive;
//         } else {
//           topLblColor = _isCenter   ? AppColors.darkText : _kLabelInactive;
//           btmLblColor = _isBottomOn ? activeColorLight   : _kLabelInactive;
//         }

//         // Top LED: red OFF indicator (one-sided) or active colour (three-pos).
//         final bool topLedOn;
//         final Color topLedColor;
//         if (isThreePosition) {
//           topLedOn   = _isTopOn;
//           topLedColor = activeColor;
//         } else {
//           topLedOn   = _isCenter; // red glow while at the OFF position
//           topLedColor = _kOffLedColor;
//         }

//         return Stack(
//           clipBehavior: Clip.hardEdge,  // prevent knob glow from bleeding past pill
//           alignment: Alignment.center,
//           children: [
//             // ── Outer body shell ──────────────────────────────────────────
//             Positioned.fill(
//               child: Container(
//                 decoration: BoxDecoration(
//                   borderRadius: BorderRadius.circular(w * 0.5),
//                   gradient: const LinearGradient(
//                     begin: Alignment.topCenter,
//                     end: Alignment.bottomCenter,
//                     colors: [_kBodyGradStart, _kBodyGradEnd],
//                   ),
//                   border: Border.all(color: _kBodyBorder, width: 3.0),
//                   boxShadow: [
//                     BoxShadow(
//                       color: Colors.black.withAlpha(102),
//                       blurRadius: 16,
//                       offset: const Offset(0, 4),
//                     ),
//                     BoxShadow(
//                       color: Colors.black.withAlpha(178),
//                       blurRadius: 10,
//                       spreadRadius: -6,
//                     ),
//                   ],
//                 ),
//               ),
//             ),

//             // ── Top rim highlight ─────────────────────────────────────────
//             Positioned(
//               top: 3, left: 3, right: 3,
//               height: h * 0.12,
//               child: Container(
//                 decoration: BoxDecoration(
//                   borderRadius: BorderRadius.vertical(
//                     top: Radius.circular(w * 0.5),
//                   ),
//                   gradient: LinearGradient(
//                     begin: Alignment.topCenter,
//                     end: Alignment.bottomCenter,
//                     colors: [
//                       Colors.white.withAlpha(15),
//                       Colors.transparent,
//                     ],
//                   ),
//                 ),
//               ),
//             ),

//             // ── Center groove / gate ──────────────────────────────────────
//             Center(
//               child: Container(
//                 width: grooveW,
//                 height: grooveH,
//                 decoration: BoxDecoration(
//                   borderRadius: BorderRadius.circular(grooveW * 0.5),
//                   gradient: const LinearGradient(
//                     begin: Alignment.topCenter,
//                     end: Alignment.bottomCenter,
//                     colors: [_kGrooveTop, _kGrooveBottom],
//                   ),
//                   boxShadow: [
//                     BoxShadow(
//                       color: Colors.black.withAlpha(153),
//                       blurRadius: 8,
//                       offset: const Offset(0, 3),
//                     ),
//                   ],
//                 ),
//               ),
//             ),

//             // ── Top LED + label ───────────────────────────────────────────
//             Positioned(
//               top: edgePad, left: 0, right: 0,
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   _Led(isOn: topLedOn, color: topLedColor, size: ledSz),
//                   AnimatedDefaultTextStyle(
//                     duration: _kColorDur,
//                     style: TextStyle(
//                       color: topLblColor,
//                       fontSize: labelFsz,
//                       fontWeight: FontWeight.w900,
//                       height: 1.0,
//                       shadows: topLedOn
//                           ? [
//                               Shadow(
//                                 color: topLedColor.withAlpha(160),
//                                 blurRadius: 8,
//                               ),
//                             ]
//                           : null,
//                     ),
//                     child: Text(topLabel, textAlign: TextAlign.center),
//                   ),
//                 ],
//               ),
//             ),

//             // ── Center "O" label (three-position neutral) ─────────────────
//             if (isThreePosition)
//               Center(
//                 child: AnimatedDefaultTextStyle(
//                   duration: _kColorDur,
//                   style: TextStyle(
//                     color: _isCenter ? AppColors.darkText : _kLabelInactive,
//                     fontSize: (labelFsz * 0.55).clamp(7.0, 18.0),
//                     fontWeight: FontWeight.w900,
//                     height: 1.0,
//                   ),
//                   child: const Text('O', textAlign: TextAlign.center),
//                 ),
//               ),

//             // ── Bottom label + LED ────────────────────────────────────────
//             Positioned(
//               bottom: edgePad, left: 0, right: 0,
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   AnimatedDefaultTextStyle(
//                     duration: _kColorDur,
//                     style: TextStyle(
//                       color: btmLblColor,
//                       fontSize: labelFsz,
//                       fontWeight: FontWeight.w900,
//                       height: 1.0,
//                       shadows: _isBottomOn
//                           ? [
//                               Shadow(
//                                 color: activeColor.withAlpha(160),
//                                 blurRadius: 8,
//                               ),
//                             ]
//                           : null,
//                     ),
//                     child: Text(bottomLabel, textAlign: TextAlign.center),
//                   ),
//                   _Led(isOn: _isBottomOn, color: activeColor, size: ledSz),
//                 ],
//               ),
//             ),

//             // ── Animated knob ─────────────────────────────────────────────
//             AnimatedAlign(
//               duration: _kKnobDur,
//               curve: _kSpring,
//               alignment: knobAlignment,
//               child: IgnorePointer(
//                 child: _Knob(
//                   size: knobSz,
//                   isOn: pos != ToggleSwitchPosition.center,
//                   activeColor: activeColor,
//                   activeDark: Color.alphaBlend(
//                     Colors.black.withAlpha(51),
//                     activeColor,
//                   ),
//                 ),
//               ),
//             ),
//           ],
//         );
//       },
//     );
//   }
// }

// ─────────────────────────────────────────────────────────────────────────────
// _Knob
// ─────────────────────────────────────────────────────────────────────────────

class _Knob extends StatelessWidget {
  const _Knob({
    required this.size,
    required this.isOn,
    required this.activeColor,
    required this.activeDark,
  });

  final double size;
  final bool isOn;
  final Color activeColor;
  final Color activeDark;

  @override
  Widget build(BuildContext context) {
    final Color base = isOn ? activeColor : _kKnobOffBase;
    final Color dark = isOn ? activeDark : _kKnobOffDark;
    final Color border = isOn ? activeDark : _kOffLedBorder;
    final Color glow = isOn
        ? activeColor.withAlpha(140)
        : _kOffLedColor.withAlpha(90);
    final double bw = (size * 0.055).clamp(2.0, 5.0);

    return AnimatedContainer(
      duration: _kColorDur,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          // Maps CSS `radial-gradient(circle at 35% 30%, …)` → Alignment(-0.30, -0.40)
          center: const Alignment(-0.30, -0.40),
          radius: 0.85,
          colors: [base, dark],
        ),
        border: Border.all(color: border, width: bw),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(102),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          // CSS  inset 0 3px 8px rgba(255,255,255,0.2) approximation
          BoxShadow(
            color: Colors.white.withAlpha(51),
            blurRadius: 8,
            offset: const Offset(0, -3),
            spreadRadius: -2,
          ),
          BoxShadow(color: glow, blurRadius: 20, spreadRadius: 1),
        ],
      ),
      child: Stack(
        children: [
          // CSS ::before — elliptical top highlight
          Positioned(
            top: size * 0.13,
            left: size * 0.18,
            right: size * 0.18,
            height: size * 0.28,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size),
                gradient: RadialGradient(
                  colors: [Colors.white.withAlpha(64), Colors.transparent],
                ),
              ),
            ),
          ),
          // CSS ::after — centre gloss dot
          Center(
            child: SizedBox(
              width: size * 0.26,
              height: size * 0.26,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.2, -0.3),
                    colors: [Colors.white.withAlpha(89), Colors.transparent],
                  ),
                  border: Border.all(
                    color: Colors.white.withAlpha(26),
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _Led
// ─────────────────────────────────────────────────────────────────────────────

// class _Led extends StatelessWidget {
//   const _Led({required this.isOn, required this.color, required this.size});

//   final bool isOn;
//   final Color color;
//   final double size;

//   @override
//   Widget build(BuildContext context) {
//     return AnimatedContainer(
//       duration: _kColorDur,
//       width: size,
//       height: size,
//       margin: EdgeInsets.symmetric(vertical: size * 0.3),
//       decoration: BoxDecoration(
//         shape: BoxShape.circle,
//         color: isOn ? color : const Color(0xFF2C3E50),
//         boxShadow: isOn
//             ? [
//                 BoxShadow(
//                   color: color.withAlpha(140),
//                   blurRadius: 16,
//                   spreadRadius: 2,
//                 ),
//               ]
//             : [
//                 BoxShadow(
//                   color: Colors.black.withAlpha(128),
//                   blurRadius: 3,
//                   offset: const Offset(0, 1),
//                 ),
//               ],
//       ),
//     );
//   }
// // }

// ─────────────────────────────────────────────────────────────────────────────
// _HintLabel
// ─────────────────────────────────────────────────────────────────────────────

// class _HintLabel extends StatelessWidget {
//   const _HintLabel({required this.mode, required this.pos});

//   final ToggleSwitchMode mode;
//   final ToggleSwitchPosition pos;

//   String get _text {
//     final isOn = pos != ToggleSwitchPosition.center;
//     return switch (mode) {
//       ToggleSwitchMode.springReturnOneSide =>
//           isOn ? '⚡ ACTIVE' : 'HOLD',
//       ToggleSwitchMode.latchingOneSide =>
//           isOn ? 'ON · TAP' : 'OFF · TAP',
//       ToggleSwitchMode.springReturnBoth =>
//           isOn ? '⚡ ACTIVE' : 'HOLD EITHER',
//       ToggleSwitchMode.latchingBoth =>
//           isOn ? 'ON · TAP OFF' : 'TAP EITHER',
//       ToggleSwitchMode.mixed => switch (pos) {
//         ToggleSwitchPosition.left   => 'ON · TAP',
//         ToggleSwitchPosition.right  => '⚡ ACTIVE',
//         ToggleSwitchPosition.center => 'TAP / HOLD',
//       },
//     };
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Text(
//       _text,
//       style: const TextStyle(
//         color: AppColors.darkTextSub,
//         fontSize: 8,
//         fontWeight: FontWeight.w700,
//         letterSpacing: 1.0,
//       ),
//     );
//   }
// }
