import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'package:rev_crane_control_ops/models/button_rotation.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_orientation.dart';
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

/// Which end zone (top third / bottom third of the interaction area) a
/// track-originated (off-knob) pointer landed in. The middle third has no
/// corresponding value — it is the dead zone and never yields a tap intent.
enum _TrackZone { top, bottom }

// ─────────────────────────────────────────────────────────────────────────────
// Private constants
// ─────────────────────────────────────────────────────────────────────────────

/// Physics spring: mass=1, stiffness=460, damping=26 → ζ≈0.60 (underdamped).
/// Produces a crisp snap with a subtle one-cycle bounce — premium toggle feel.
const _kSpring = SpringDescription(mass: 1.0, stiffness: 460.0, damping: 26.0);

const Duration _kColorDur = Duration(milliseconds: 150);

/// Mechanical detent centres. The wider ±0.74 travel keeps adjacent states
/// physically separated by at least 48px at the operational minimum size.
const double _kKnobTopY = -0.74;
const double _kKnobBotY = 0.74;
const double _kKnobVisualLimit = 0.80;

// Interaction zones (fraction of the full Listener area height).
const double _kTopZone = 0.33; // 0 – 33 %
const double _kBottomZone = 0.67; // 67 – 100 %
const double _kDragMin = 18.0; // minimum px before leaving the current detent

/// Three-position thresholds in lever-alignment coordinates. An end detent
/// is entered only beyond ±0.50 but is retained until the pointer crosses
/// back inside ±0.28. The gap between those thresholds is the hysteresis
/// band; the full -0.50…+0.50 interval is the deliberately wide neutral zone.
const double _kEndDetentEnter = 0.50; ////////////////////////
const double _kEndDetentExit = 0.28; ///////////
const double _kNeutralDwellBand = 0.22; //////////////
const Duration _kNeutralGateDwell = Duration(milliseconds: 90); ////////////

/// The label row is 22px high with 5px above and 3px below it.
const double _kFooterExtent = ControlButtonVisualMetrics.rowHeight + 8.0;

/// Below this height the footer yields its space to the lever. Compact grid
/// cells remain usable, while the documented operational size still provides
/// three full-size position bands and the complete footer.
const double _kCompactFooterThreshold = 128.0;

/// The operational-width footer prioritizes the control identity. The
/// secondary mode hint joins it only once both can fit without hiding the
/// button label.
const double _kHintVisibilityWidth = 160.0;

// Lever housing colours
const _kBodyGradStart = Color(0xFF1A2634);
const _kBodyGradEnd = Color(0xFF0D1520);
const _kBodyBorder = Color(0xFF24394C);
const _kGrooveTop = Color(0xFF04080C);
const _kGrooveBottom = Color(0xFF0B141D);
const _kGrooveBorder = Color(0xFF3B5062);

// Neutral steel keeps OFF visually quiet; active colors remain role-specific.
const _kKnobOffBase = Color(0xFF8294A3);
const _kKnobOffDark = Color(0xFF425565);
const _kKnobOffBorder = Color(0xFFBBC8D2);

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
    this.orientation = ControlOrientation.vertical,
    this.mode,
    this.position,
    this.topLabel,
    this.bottomLabel,
    this.topIcon,
    this.bottomIcon,
    this.onPositionChanged,
    this.onReleased,
    this.leftIsSpringReturn,
    this.rightIsSpringReturn,
    this.topDisabled = false,
    this.bottomDisabled = false,
  });

  /// Smallest size at which adjacent lever detents remain at least 48px apart
  /// while the standard icon/label footer remains visible — the vertical
  /// (native) orientation. See [minimumOperationalSizeFor] for the
  /// orientation-aware version; this constant is kept as-is (still the
  /// vertical case) so existing call sites/tests keep working unchanged.
  static const Size minimumOperationalSize = Size(
    ButtonConfig.minToggleButtonWidthPx,
    ButtonConfig.minToggleButtonHeightPx,
  );

  /// [minimumOperationalSize], swapped for horizontal orientation.
  static Size minimumOperationalSizeFor(ControlOrientation orientation) =>
      orientation == ControlOrientation.vertical
      ? minimumOperationalSize
      : Size(minimumOperationalSize.height, minimumOperationalSize.width);

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

  /// Lever axis — vertical (default, today's only behavior) or horizontal.
  /// See [ToggleButtonConfig.orientation].
  final ControlOrientation orientation;

  // ── Extended API ─────────────────────────────────────────────────────────
  final ToggleSwitchMode? mode;
  final ToggleSwitchPosition? position;
  final String? topLabel;
  final String? bottomLabel;

  /// Shown in place of the top/bottom position-indicator glyph when set —
  /// see ToggleButtonConfig.leftIconKey/rightIconKey.
  final IconData? topIcon;
  final IconData? bottomIcon;
  final ValueChanged<ToggleSwitchPosition>? onPositionChanged;
  final VoidCallback? onReleased;
  final bool? leftIsSpringReturn;
  final bool? rightIsSpringReturn;

  /// Forces the top (left) / bottom (right) lever end permanently inert,
  /// regardless of [resolvedMode] — see ToggleButtonConfig.disableLeft/
  /// disableRight. Defaults to false: today's exact behavior.
  final bool topDisabled;
  final bool bottomDisabled;

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
  double? _dragStartDy; // pointer-down y in Listener coordinates
  double _dragStartKnobY = 0.0; // knob y when drag started
  double _dragVelocityPxS = 0.0; // drag velocity in px/s
  double _lastDragDy = 0.0;
  int _lastDragMicros = 0;

  // Whether the pointer that is currently down landed on the knob itself.
  // Only a knob-started pointer may *drag* the lever — a pointer that starts
  // on the track/housing can still register as a tap (see below) but can
  // never live-drag the knob (mechanical selectors are moved by the lever,
  // not by pressing the housing around it).
  bool _downOnKnob = false;

  // Track (off-knob) gesture bookkeeping. `_trackZone` is the end zone the
  // pointer went down in (null = dead zone). `_trackVoided` becomes/starts
  // true once this gesture can no longer commit anything — either because it
  // already resolved immediately (see _onPointerDown) or because it moved
  // past the tap tolerance and forfeited its chance to register as a tap.
  // `_trackSpringHeld` marks a momentary spring end that was activated
  // immediately on down and must snap back to centre on release/cancel or if
  // the pointer wanders out of the zone it was pressed in.
  _TrackZone? _trackZone;
  bool _trackVoided = true;
  bool _trackSpringHeld = false;

  // Three-position mechanical gate state. Crossing from one active end to
  // the other arms a mandatory neutral dwell; until that dwell completes,
  // the opposite detent is physically and logically unavailable.
  bool _threePositionDragged = false;
  ToggleSwitchPosition? _neutralGateBlockedEnd;
  Duration? _neutralGateEnteredAt;
  bool _neutralGateArmed = false;
  bool _springDetentEntered = false;

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
  double _lastLeverW = 64.0;

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
    final gestureInProgress = _dragStartDy != null;
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

  bool _isSpringPosition(ToggleSwitchPosition position) => switch (position) {
    ToggleSwitchPosition.left => widget.topSideIsSpring,
    ToggleSwitchPosition.center => false,
    ToggleSwitchPosition.right => widget.bottomSideIsSpring,
  };

  double _pixelsPerAlignmentUnit(double leverH, double leverW) {
    final knobSize = leverW * 0.58;
    return math.max(20.0, (leverH - knobSize) / 2.0);
  }

  double get _currentPixelsPerAlignmentUnit =>
      _pixelsPerAlignmentUnit(_lastLeverH, _lastLeverW);

  bool _pointerStartsOnKnob(
    Offset localPosition, {
    required double areaW,
    required double areaH,
    required double leverW,
    required double leverH,
  }) {
    final knobSize = leverW * 0.58;
    final travel = math.max(0.0, (leverH - knobSize) / 2.0);
    final knobCenter = Offset(
      areaW / 2.0,
      areaH / 2.0 +
          _knobCtrl.value.clamp(-_kKnobVisualLimit, _kKnobVisualLimit) * travel,
    );
    final hitRadius = math.max(24.0, knobSize / 2.0 + 6.0);
    return (localPosition - knobCenter).distance <= hitRadius;
  }

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
  double get _alignVelocity =>
      _dragVelocityPxS / _currentPixelsPerAlignmentUnit;

  // ── Command dispatch ──────────────────────────────────────────────────────

  ControlState _commandFor(ToggleSwitchPosition pos) {
    if (!widget.isThreePosition) {
      return pos == ToggleSwitchPosition.right
          ? ControlState.level1
          : ControlState.idle;
    }
    return switch (pos) {
      ToggleSwitchPosition.left => ControlState.level1,
      ToggleSwitchPosition.center => ControlState.idle,
      ToggleSwitchPosition.right => ControlState.level2,
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

  void _resetNeutralGate() {
    _neutralGateBlockedEnd = null;
    _neutralGateEnteredAt = null;
    _neutralGateArmed = false;
  }

  void _beginNeutralGateFrom(ToggleSwitchPosition previousEnd) {
    _neutralGateBlockedEnd = previousEnd == ToggleSwitchPosition.left
        ? ToggleSwitchPosition.right
        : ToggleSwitchPosition.left;
    _neutralGateEnteredAt = null;
    _neutralGateArmed = false;
  }

  void _updateNeutralGate(double pointerY, Duration timeStamp) {
    if (_neutralGateBlockedEnd == null || _neutralGateArmed) return;
    if (pointerY.abs() > _kNeutralDwellBand) {
      _neutralGateEnteredAt = null;
      return;
    }

    final enteredAt = _neutralGateEnteredAt;
    if (enteredAt == null) {
      _neutralGateEnteredAt = timeStamp;
      return;
    }
    if (timeStamp - enteredAt >= _kNeutralGateDwell) {
      _neutralGateArmed = true;
    }
  }

  bool _enterThreePositionDetent(
    ToggleSwitchPosition next, {
    double velocity = 0.0,
  }) {
    if (_pos == next) return false;
    _moveTo(next);
    HapticFeedback.selectionClick();
    if (_isSpringPosition(next)) _springDetentEntered = true;
    _springTo(_knobYForPos(next), velocity: velocity);
    return true;
  }

  bool _updateThreePositionDetent(double pointerY, Duration timeStamp) {
    switch (_pos) {
      case ToggleSwitchPosition.left:
        if (pointerY >= -_kEndDetentExit) {
          _beginNeutralGateFrom(ToggleSwitchPosition.left);
          final changed = _enterThreePositionDetent(
            ToggleSwitchPosition.center,
            velocity: _alignVelocity,
          );
          _updateNeutralGate(pointerY, timeStamp);
          return changed;
        }
        return false;
      case ToggleSwitchPosition.right:
        if (pointerY <= _kEndDetentExit) {
          _beginNeutralGateFrom(ToggleSwitchPosition.right);
          final changed = _enterThreePositionDetent(
            ToggleSwitchPosition.center,
            velocity: _alignVelocity,
          );
          _updateNeutralGate(pointerY, timeStamp);
          return changed;
        }
        return false;
      case ToggleSwitchPosition.center:
        _updateNeutralGate(pointerY, timeStamp);
        final mayEnterLeft =
            _neutralGateBlockedEnd != ToggleSwitchPosition.left ||
            _neutralGateArmed;
        final mayEnterRight =
            _neutralGateBlockedEnd != ToggleSwitchPosition.right ||
            _neutralGateArmed;

        if (widget.isThreePosition &&
            pointerY <= -_kEndDetentEnter &&
            mayEnterLeft &&
            !widget.topDisabled) {
          _resetNeutralGate();
          return _enterThreePositionDetent(
            ToggleSwitchPosition.left,
            velocity: _alignVelocity,
          );
        }
        if (pointerY >= _kEndDetentEnter &&
            mayEnterRight &&
            !widget.bottomDisabled) {
          _resetNeutralGate();
          return _enterThreePositionDetent(
            ToggleSwitchPosition.right,
            velocity: _alignVelocity,
          );
        }
    }
    return false;
  }

  void _onThreePositionPointerMove(
    PointerMoveEvent event,
    double leverW,
    double leverH,
  ) {
    final dy = event.localPosition.dy;
    final delta = dy - _dragStartDy!;
    _trackVelocity(dy);

    final minimumDrag = math.max(_kDragMin, leverH * 0.10);
    if (!_threePositionDragged && delta.abs() < minimumDrag) return;
    _threePositionDragged = true;

    final pointerY =
        (_dragStartKnobY + delta / _pixelsPerAlignmentUnit(leverH, leverW))
            .clamp(-1.0, 1.0);
    _knobCtrl.stop();
    final changed = _updateThreePositionDetent(pointerY, event.timeStamp);
    if (changed) return;

    // Keep the lever captured by its current detent, with only a small
    // elastic deflection to communicate drag direction before the next snap.
    final detent = _knobYForPos(_pos);
    final deflection = (pointerY - detent).clamp(-0.18, 0.18);
    _knobCtrl.value = (detent + deflection).clamp(
      -_kKnobVisualLimit,
      _kKnobVisualLimit,
    );
  }

  void _finishThreePositionGesture({required bool cancelled}) {
    final velocity = cancelled ? 0.0 : _alignVelocity;
    final springPositionOnRelease = _isSpringPosition(_pos);

    if (springPositionOnRelease) {
      _enterThreePositionDetent(
        ToggleSwitchPosition.center,
        velocity: velocity,
      );
    } else {
      _springTo(_knobYForPos(_pos), velocity: velocity);
    }

    final endedNeutralAfterSpring =
        _pos == ToggleSwitchPosition.center && _springDetentEntered;
    if (endedNeutralAfterSpring) {
      _suppressExternalReactivation = true;
      widget.onReleased?.call();
    }

    _threePositionDragged = false;
    _springDetentEntered = false;
    _resetNeutralGate();
  }

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

  // ── Track (off-knob) tap intents ─────────────────────────────────────────
  //
  // A pointer that lands away from the knob can still register as a tap, but
  // never as a drag (the lever itself must be grabbed to be dragged). What a
  // track tap resolves to depends on where it landed and where the lever
  // currently sits:
  //   • the opposite end is currently active  → step to centre only (a
  //     single gesture may never jump straight between the two ends);
  //   • otherwise                              → the zone's natural target
  //     (which itself toggles off if that end is already latched active).

  ToggleSwitchPosition _oppositeEnd(ToggleSwitchPosition end) =>
      end == ToggleSwitchPosition.left
          ? ToggleSwitchPosition.right
          : ToggleSwitchPosition.left;

  ToggleSwitchPosition _resolveTapIntent(ToggleSwitchPosition requested) {
    if (requested == ToggleSwitchPosition.center) return requested;
    if (_pos == _oppositeEnd(requested)) return ToggleSwitchPosition.center;
    return requested;
  }

  ToggleSwitchPosition? _rawZoneIntent(_TrackZone zone) => switch (zone) {
    _TrackZone.top => widget.topDisabled ? null : _latchTopIntent(),
    _TrackZone.bottom => widget.bottomDisabled ? null : _latchBottomIntent(),
  };

  _TrackZone? _classifyTrackZone(double frac) {
    if (frac < _kTopZone) return _TrackZone.top;
    if (frac > _kBottomZone) return _TrackZone.bottom;
    return null;
  }

  /// Snaps a momentary track-held spring end back to centre — used on
  /// release, cancel, and when the pointer wanders out of the pressed zone.
  void _cancelTrackSpringHold() {
    _trackSpringHeld = false;
    _trackVoided = true;
    final wasEntered = _enterThreePositionDetent(ToggleSwitchPosition.center);
    if (wasEntered) {
      _suppressExternalReactivation = true;
      widget.onReleased?.call();
    }
  }

  /// Commits a track tap that stayed within tolerance for the whole gesture
  /// (a clean, deliberate tap rather than an off-knob drag). Only ever
  /// reached for a *latching* target — spring targets are resolved
  /// immediately on pointer-down (see _onPointerDown) since they are always
  /// safe to preview live.
  void _commitDeferredTrackTap(_TrackZone zone) {
    final requested = _rawZoneIntent(zone);
    if (requested == null) return;
    final resolved = _resolveTapIntent(requested);
    if (resolved == _pos) return;
    if (!_enterThreePositionDetent(resolved)) return;
    if (_isSpringPosition(resolved)) {
      _enterThreePositionDetent(ToggleSwitchPosition.center);
      _suppressExternalReactivation = true;
      widget.onReleased?.call();
    }
  }

  // ── Pointer handlers ──────────────────────────────────────────────────────

  void _onPointerDown(
    PointerDownEvent event,
    double areaW,
    double areaH,
    double leverW,
    double leverH,
  ) {
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
    _pressDown();

    _threePositionDragged = false;
    _springDetentEntered = _isSpringPosition(_pos);
    _resetNeutralGate();

    _downOnKnob = _pointerStartsOnKnob(
      event.localPosition,
      areaW: areaW,
      areaH: areaH,
      leverW: leverW,
      leverH: leverH,
    );
    _trackZone = null;
    _trackSpringHeld = false;
    _trackVoided = true; // default inert; a fresh latch-on request re-arms it

    if (_downOnKnob) return; // knob-driven drag: handled by move/up below

    // ── Track (off-knob) press ────────────────────────────────────────────
    // Dragging must begin from the knob, but a direct tap on a valid end
    // zone still activates it. Since we can't yet know whether this pointer
    // will stay a tap or turn into a disallowed off-knob drag, only actions
    // that are safe to preview immediately (deactivating, or a momentary
    // spring end) commit right away; a fresh latch-on request waits for a
    // clean release (see _onPointerUp / _commitDeferredTrackTap).
    final frac = (_dragStartDy! / areaH).clamp(0.0, 1.0);
    final zone = _classifyTrackZone(frac);
    _trackZone = zone;
    if (zone == null) return; // dead-zone press: inert this gesture

    final requested = _rawZoneIntent(zone);
    if (requested == null) return; // disabled side: inert

    final resolved = _resolveTapIntent(requested);
    if (resolved == _pos) return;

    if (resolved == ToggleSwitchPosition.center) {
      _enterThreePositionDetent(ToggleSwitchPosition.center);
      return;
    }
    if (_isSpringPosition(resolved)) {
      _enterThreePositionDetent(resolved);
      _trackSpringHeld = true;
      return;
    }
    // A genuinely new latch: defer commitment to a clean pointer-up.
    _trackVoided = false;
  }

  void _onPointerMove(
    PointerMoveEvent event,
    double areaH,
    double leverW,
    double leverH,
  ) {
    if (!_enabled || _dragStartDy == null) return;
    if (event.pointer != _activePointerId) return;

    if (_downOnKnob) {
      _onThreePositionPointerMove(event, leverW, leverH);
      return;
    }

    final dy = event.localPosition.dy;

    // A momentary end stays engaged only while the pointer remains inside
    // the zone it was pressed in — wandering out cancels it early, exactly
    // like dragging off a normal button cancels the press. Checked ahead of
    // `_trackVoided` because entering this state never clears that flag (it
    // isn't a pending latch-on tap waiting for a clean release).
    if (_trackSpringHeld) {
      final frac = (dy / areaH).clamp(0.0, 1.0);
      final stillInZone = _trackZone == _TrackZone.top
          ? frac < _kTopZone
          : frac > _kBottomZone;
      if (!stillInZone) _cancelTrackSpringHold();
      return;
    }

    if (_trackVoided) return; // already resolved or disqualified

    // A pending latch-on tap is disqualified the moment it moves enough to
    // be a deliberate drag — off-knob presses may never drag the lever.
    if ((dy - _dragStartDy!).abs() > _kDragMin) {
      _trackVoided = true;
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

    if (_downOnKnob) {
      _finishThreePositionGesture(cancelled: false);
    } else if (_trackSpringHeld) {
      _cancelTrackSpringHold();
    } else if (!_trackVoided && _trackZone != null) {
      _commitDeferredTrackTap(_trackZone!);
    } else {
      // Dead-zone tap or a voided off-knob drag: nothing committed, just
      // make sure the knob is visually settled on its actual position.
      _springTo(_knobYForPos(_pos));
    }

    _resetGestureTracking();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointerId) return;
    ButtonStateLog.log(
      'USER_CANCEL [${widget.label}] pointer=${event.pointer}',
    );
    _activePointerId = null;
    _pressUp();

    if (_downOnKnob) {
      _finishThreePositionGesture(cancelled: true);
    } else if (_trackSpringHeld) {
      _cancelTrackSpringHold();
    } else {
      // A pending (uncommitted) latch-on tap is simply abandoned.
      _springTo(_knobYForPos(_pos));
    }

    _resetGestureTracking();
  }

  void _resetGestureTracking() {
    _dragStartDy = null;
    _dragVelocityPxS = 0.0;
    _lastDragMicros = 0;
    _trackZone = null;
    _trackVoided = true;
    _trackSpringHeld = false;
  }

  // ── Orientation ───────────────────────────────────────────────────────────
  //
  // All gesture math above (dy/areaH/leverH/_onPointerDown etc.) is authored
  // once, exclusively for the vertical lever, and scoped entirely to the
  // local coordinate space of the LayoutBuilder+Listener it's built from
  // below. For horizontal orientation that same subtree is wrapped in a
  // RotatedBox with its own constraints pre-swapped — the same "author one
  // axis, RotatedBox the other into place" technique already used by
  // AnalogSliderControl/IndustrialMultiStepSlider — so it renders sideways
  // with NO changes to any gesture/physics/painting code: RotatedBox
  // transforms hit-testing along with painting, so `event.localPosition`
  // seen by the Listener below is already back in the widget's own
  // always-vertical frame.

  Widget _buildLeverArea(bool isOn) {
    final leverInteractionArea = LayoutBuilder(
      builder: (ctx, cons) {
        final areaH = cons.maxHeight;
        final areaW = cons.maxWidth;
        final leverH = math.min(areaH, 260.0);
        final leverW = math.min(
          math.max(32.0, leverH * (110.0 / 210.0)),
          areaW * 0.92,
        );
        _lastLeverH = leverH;
        _lastLeverW = leverW;

        return Listener(
          key: const ValueKey('toggle_lever_interaction_area'),
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) =>
              _onPointerDown(e, areaW, areaH, leverW, leverH),
          onPointerMove: (e) => _onPointerMove(e, areaH, leverW, leverH),
          onPointerUp: (e) => _onPointerUp(e, areaH),
          onPointerCancel: (e) => _onPointerCancel(e),
          child: SizedBox.expand(
            child: Center(
              // AnimatedBuilder: rebuilds on every spring frame
              // AND on every scale-feedback frame.
              child: AnimatedBuilder(
                animation: Listenable.merge([_knobCtrl, _scaleCtrl]),
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
                        topIcon: widget.topIcon,
                        bottomIcon: widget.bottomIcon,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );

    if (widget.orientation == ControlOrientation.vertical) {
      return leverInteractionArea;
    }

    return LayoutBuilder(
      builder: (ctx, outer) {
        return RotatedBox(
          quarterTurns: -1,
          child: SizedBox(
            width: outer.maxHeight,
            height: outer.maxWidth,
            child: leverInteractionArea,
          ),
        );
      },
    );
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
          child: LayoutBuilder(
            builder: (context, outerConstraints) {
              final showFooter =
                  outerConstraints.maxHeight >= _kCompactFooterThreshold &&
                  outerConstraints.maxWidth >= 80.0;
              final showHint =
                  outerConstraints.maxWidth >= _kHintVisibilityWidth;

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ── Industrial lever ─────────────────────────────────────────
                  Expanded(child: _buildLeverArea(isOn)),
                  // ── Compact footer ────────────────────────────────────────────
                  if (showFooter)
                    SizedBox(
                      height: _kFooterExtent,
                      child: Padding(
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
                            if (showHint) ...[
                              const SizedBox(width: 6),
                              _HintLabel(mode: widget.resolvedMode, pos: _pos),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
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
    this.topIcon,
    this.bottomIcon,
  });

  final double knobY;
  final bool isOn;
  final Color activeColor;
  final Color activeColorLight;
  final ToggleSwitchMode mode;
  final ToggleSwitchPosition position;
  final String topLabel;
  final String bottomLabel;
  final IconData? topIcon;
  final IconData? bottomIcon;

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
        final clampedKnobY = knobY
            .clamp(-_kKnobVisualLimit, _kKnobVisualLimit)
            .toDouble();
        final knobTravel = math.max(0.0, (h - knobSz) * 0.5);
        final knobCenterY = h * 0.5 + clampedKnobY * knobTravel;
        final activeTrackTop = math.min(h * 0.5, knobCenterY);
        final activeTrackHeight = (knobCenterY - h * 0.5).abs();
        final activeTrackW = grooveW * 0.62;

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
                key: const ValueKey('toggle_lever_track'),
                width: grooveW,
                height: grooveH,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(grooveW * 0.5),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_kGrooveTop, _kGrooveBottom],
                  ),
                  border: Border.all(
                    color: _kGrooveBorder,
                    width: (grooveW * 0.045).clamp(1.0, 2.0),
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

              // Illuminated portion of the track. It follows the existing
              // lever travel from neutral to the selected detent without
              // changing the control geometry or interaction area.
              Positioned(
                top: activeTrackTop,
                left: (w - activeTrackW) * 0.5,
                width: activeTrackW,
                height: activeTrackHeight,
                child: AnimatedContainer(
                  key: const ValueKey('toggle_lever_active_track'),
                  duration: _kColorDur,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(activeTrackW * 0.5),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        activeColorLight.withAlpha(isOn ? 235 : 0),
                        activeColor.withAlpha(isOn ? 255 : 0),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: activeColor.withAlpha(isOn ? 125 : 0),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),

              // ── Knob (driven by AnimationController via Align) ───────────
              Align(
                alignment: Alignment(0.0, clampedKnobY),
                child: _Knob(
                  key: const ValueKey('toggle_lever_knob'),
                  size: knobSz,
                  isOn: isOn,
                  activeColor: activeColor,
                  activeLight: activeColorLight,
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
                      topIcon: topIcon,
                      bottomIcon: bottomIcon,
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
    this.topIcon,
    this.bottomIcon,
    required this.activeColor,
  });

  final ToggleSwitchMode mode;
  final ToggleSwitchPosition position;
  final String topLabel;
  final String bottomLabel;
  final IconData? topIcon;
  final IconData? bottomIcon;
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
              icon: topIcon,
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
              icon: bottomIcon,
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
    IconData? icon,
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
          icon: icon,
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
    this.icon,
    required this.size,
    required this.isActive,
    required this.activeColor,
  });

  final String label;

  /// When set, replaces the O/T/R text glyph with this icon — see
  /// ToggleButtonConfig.leftIconKey/rightIconKey.
  final IconData? icon;
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
      child: icon != null
          ? Icon(icon, size: fontSize * 1.15, color: color)
          : Text(
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
      ToggleSwitchMode.springReturnBoth => isOn ? 'ACTIVE' : 'DRAG EITHER',
      ToggleSwitchMode.latchingBoth => isOn ? 'LATCHED · DRAG' : 'DRAG EITHER',
      ToggleSwitchMode.mixed => switch (pos) {
        ToggleSwitchPosition.left => 'LATCHED · DRAG',
        ToggleSwitchPosition.right => 'ACTIVE',
        ToggleSwitchPosition.center => 'DRAG / HOLD',
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
    super.key,
    required this.size,
    required this.isOn,
    required this.activeColor,
    required this.activeLight,
    required this.activeDark,
  });

  final double size;
  final bool isOn;
  final Color activeColor;
  final Color activeLight;
  final Color activeDark;

  @override
  Widget build(BuildContext context) {
    final Color base = isOn
        ? Color.alphaBlend(activeLight.withAlpha(78), activeColor)
        : _kKnobOffBase;
    final Color dark = isOn ? activeDark : _kKnobOffDark;
    final Color border = isOn ? activeLight : _kKnobOffBorder;
    final Color glow = isOn
        ? activeColor.withAlpha(165)
        : Colors.black.withAlpha(90);
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
                    colors: [
                      isOn
                          ? activeLight.withAlpha(210)
                          : Colors.white.withAlpha(82),
                      Colors.transparent,
                    ],
                  ),
                  border: Border.all(
                    color: isOn
                        ? activeLight.withAlpha(150)
                        : Colors.white.withAlpha(38),
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
