import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/joystick_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/control_button_visuals.dart';

const double _kJoystickSlotPadding = 10.0;
const double _kSingleAxisVisualScale = 0.94;
const double _kDualAxisVisualScale = 0.90;
const double _kAnalogGimbalBoundaryFactor = 0.34;
const double _kAnalogGimbalPointerRadiusFactor = 0.105;
const double _kAnalogGimbalPointerTravelFactor = _kAnalogGimbalBoundaryFactor;

double _safeVisualExtent(
  double available, {
  required double min,
  required double max,
  required double scale,
}) {
  final boundedAvailable = math.max(0.0, available);
  if (boundedAvailable <= min) return boundedAvailable;
  return (boundedAvailable * scale)
      .clamp(min, math.min(max, boundedAvailable))
      .toDouble();
}

double _dualAxisSide(double maxWidth, double maxHeight) {
  return _safeVisualExtent(
    math.min(maxWidth, maxHeight),
    min: 92.0,
    max: 288.0,
    scale: _kDualAxisVisualScale,
  );
}

// Cross-gate proportions, all expressed against the gate's own extent (the
// side of the square the 3x3 cell arrangement actually occupies) rather
// than against the raw widget box — so the plate, cells, knob, glyphs and
// touch geometry all scale as one unit with the assigned grid footprint.
//
// The 3 cells and 2 gaps across an axis must sum to exactly the extent:
//   3 * cell + 2 * gap == gateExtent
// which is what lets the gate FILL its box instead of floating inside it.
const double _kCrossGateGapFactor = 0.0285;

// Pointer travel (in gate extents) that maps to a full-deflection value of
// 1.0. Preserves the pre-existing feel: the drag distance needed to engage
// a direction stays the same fraction of the visible control as before, so
// growing the footprint never changes the dead zone / step thresholds in
// operator-perceived terms — only their absolute pixel size.
const double _kCrossGateTravelFactor = 0.484;

/// Resolved geometry for one 2D digital joystick (cross gate) paint box.
///
/// The control is a 3x3 arrangement of square cells (neutral centre plus 4
/// or 8 directions) separated by a uniform gap, with a label band beneath.
/// [gateExtent] is the side of the square that arrangement fills: the
/// SHORTER available dimension once the label band is reserved. Everything
/// painted, and every touch radius, derives from [cell]/[gateExtent] here —
/// never from the raw box — which is what keeps the knob centred on the
/// directional zones at every size.
///
/// The gate stays square (never stretched) and is centred as a unit with
/// its label, so a non-square footprint leaves symmetric margins on the
/// longer axis rather than distorting or overflowing the control.
class _CrossGateMetrics {
  const _CrossGateMetrics._({
    required this.center,
    required this.gateExtent,
    required this.cell,
    required this.gap,
    required this.labelBand,
  });

  factory _CrossGateMetrics.forBox(Size size) {
    // Never let the label eat a tall share of a short box — on a small
    // footprint the gate itself matters more than a readable caption.
    final labelBand = math.max(
      0.0,
      math.min(ControlButtonVisualMetrics.rowHeight, size.height * 0.16),
    );
    final gateExtent = math.max(
      0.0,
      math.min(size.width, size.height - labelBand),
    );
    final gap = gateExtent * _kCrossGateGapFactor;
    final cell = math.max(0.0, (gateExtent - gap * 2) / 3);
    // Centre the gate+label as one block so the gate's own centre — which
    // every directional cell and the knob are positioned from — stays put.
    final top = (size.height - (gateExtent + labelBand)) / 2;
    return _CrossGateMetrics._(
      center: Offset(size.width / 2, top + gateExtent / 2),
      gateExtent: gateExtent,
      cell: cell,
      gap: gap,
      labelBand: labelBand,
    );
  }

  /// Centre of the 3x3 gate (NOT of the whole box — the label band below
  /// shifts it up), in the paint box's own coordinates.
  final Offset center;
  final double gateExtent;
  final double cell;
  final double gap;
  final double labelBand;

  /// Distance between adjacent cell centres — one direction step of knob
  /// travel, and the radius the knob is drawn at when fully deflected.
  double get step => cell + gap;
}

/// The side length the cross gate's 3x3 arrangement fills inside [box].
/// Exposed only so tests can assert the fill contract directly rather than
/// inferring it from a rendered box that also contains the label band.
@visibleForTesting
double digitalCrossGateExtentFor(Size box) =>
    _CrossGateMetrics.forBox(box).gateExtent;

String _formatAnalogAxisValue(double value) {
  final clamped = value.clamp(-1.0, 1.0).toDouble();
  if (clamped.abs() < 0.0005) return '0.00';
  return '${clamped > 0 ? '+' : ''}${clamped.toStringAsFixed(2)}';
}

double _joystickSlotPaddingFor(double maxWidth, double maxHeight) {
  final shortest = math.min(maxWidth, maxHeight);
  if (shortest <= 112.0) return 6.0;
  return _kJoystickSlotPadding;
}

class _JoystickDragGeometry {
  const _JoystickDragGeometry({
    required this.center,
    required this.radius,
    required this.displayRadius,
    required this.knobHitRadius,
  });

  final Offset center;
  final double radius;
  final double displayRadius;
  final double knobHitRadius;
}

class JoystickOutput {
  const JoystickOutput({
    required this.x,
    required this.y,
    required this.xStep,
    required this.yStep,
  });

  final double x;
  final double y;
  final int xStep;
  final int yStep;

  bool get isNeutral => xStep == 0 && yStep == 0 && x == 0.0 && y == 0.0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JoystickOutput &&
          other.x == x &&
          other.y == y &&
          other.xStep == xStep &&
          other.yStep == yStep;

  @override
  int get hashCode => Object.hash(x, y, xStep, yStep);
}

// ─────────────────────────────────────────────────────────────────────────────*
// IndustrialJoystickControl*
//*
// Renders one of four *visually distinct* control families, selected by*
// JoystickConfig.mode:*
//   - singleAxisAnalog     -> vertical/horizontal proportional throttle rail*
//   - singleAxisDigital5   -> stepped ladder gate with 5 physical detents*
//   - dualAxisAnalog       -> round gimbal puck, free continuous travel*
//   - dualAxisDigital4     -> cross gate with 4 latching direction cells*
//*
// The four are deliberately built from different shapes (rail vs. ladder vs.*
// disc vs. cross) rather than sharing one painter with parameter tweaks, so*
// an operator can identify the control family at a glance.*
// ─────────────────────────────────────────────────────────────────────────────*

class IndustrialJoystickControl extends StatefulWidget {
  const IndustrialJoystickControl({
    super.key,
    required this.config,
    required this.label,
    required this.activeColor,
    required this.activeColorLight,
    required this.enabled,
    required this.onChanged,
    this.icon,
  });

  final JoystickConfig config;
  final String label;
  final IconData? icon;
  final Color activeColor;
  final Color activeColorLight;
  final bool enabled;
  final ValueChanged<JoystickOutput> onChanged;

  @override
  State<IndustrialJoystickControl> createState() =>
      _IndustrialJoystickControlState();
}

class _IndustrialJoystickControlState extends State<IndustrialJoystickControl>
    with TickerProviderStateMixin {
  static const _spring = SpringDescription(
    mass: 1.0,
    stiffness: 360.0,
    damping: 25.0,
  );

  AnimationController? _springX;
  AnimationController? _springY;
  Offset _value = Offset.zero;
  bool _dragActive = false;
  Offset _grabOffset = Offset.zero;
  int _resolvedXStep = 0;
  int _resolvedYStep = 0;
  Axis? _dominantAxis;
  JoystickOutput _lastOutput = const JoystickOutput(
    x: 0,
    y: 0,
    xStep: 0,
    yStep: 0,
  );

  @override
  void dispose() {
    _cancelSpring();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant IndustrialJoystickControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) {
      _cancelSpring();
      _dragActive = false;
      _value = Offset.zero;
      _resetDigitalResolution();
      _emitNeutralAfterBuild();
    } else if (oldWidget.config != widget.config && !_lastOutput.isNeutral) {
      _cancelSpring();
      _dragActive = false;
      _value = Offset.zero;
      _resetDigitalResolution();
      _emitNeutralAfterBuild();
    }
  }

  JoystickConfig get _config => widget.config.normalizedForMode();

  void _emit() {
    final previousOutput = _lastOutput;
    final output = _config.isDigital
        ? _stableDigitalOutputFor(_value)
        : _outputFor(_value);

    // Digital controls expose raw x/y values for rendering, but those values
    // have no wire-level meaning. A command changes only when the resolved
    // detent/direction changes; movement within the same detent must not keep
    // resending the same PLC state.
    final changed = _config.isDigital
        ? output.xStep != previousOutput.xStep ||
              output.yStep != previousOutput.yStep
        : output != previousOutput;

    // Keep the latest raw values for the visual state even when the logical
    // digital output is unchanged.
    _lastOutput = output;
    if (!changed) return;
    widget.onChanged(output);
  }

  JoystickOutput _outputFor(Offset raw) {
    var x = raw.dx.clamp(-1.0, 1.0);
    var y = raw.dy.clamp(-1.0, 1.0);

    if (!_config.isDualAxis) {
      if (_config.axis == JoystickAxis.horizontal) {
        y = 0.0;
      } else {
        x = 0.0;
      }
    } else if (!_config.allowDiagonal) {
      if (x.abs() > y.abs()) {
        y = 0.0;
      } else if (y.abs() > x.abs()) {
        x = 0.0;
      }
    }

    x = _applyDeadZone(x);
    y = _applyDeadZone(y);

    return JoystickOutput(
      x: _roundAnalog(x),
      y: _roundAnalog(y),
      xStep: _stepFor(x),
      yStep: _stepFor(y),
    );
  }

  double _applyDeadZone(double value) {
    final abs = value.abs();
    if (abs < _config.deadZone) return 0.0;
    if (_config.isDigital) return value;
    final scaled = (abs - _config.deadZone) / (1.0 - _config.deadZone);
    return value.sign * scaled.clamp(0.0, 1.0);
  }

  double _roundAnalog(double value) => (value * 1000).round() / 1000.0;

  int _stepFor(double value) {
    final abs = value.abs();
    if (abs < _config.deadZone) return 0;
    if (abs >= _config.fastThreshold) return value.sign.toInt() * 2;
    if (abs >= _config.slowThreshold) return value.sign.toInt();
    return 0;
  }

  double get _slowThreshold {
    final dead = _config.deadZone.clamp(0.0, 0.92);
    return math.max(dead + 0.04, _config.slowThreshold).clamp(0.04, 0.96);
  }

  double get _fastThreshold =>
      math.max(_slowThreshold + 0.08, _config.fastThreshold).clamp(0.12, 1.0);

  JoystickOutput _stableDigitalOutputFor(Offset raw) {
    var x = raw.dx.clamp(-1.0, 1.0);
    var y = raw.dy.clamp(-1.0, 1.0);

    if (!_config.isDualAxis) {
      if (_config.axis == JoystickAxis.horizontal) {
        y = 0.0;
      } else {
        x = 0.0;
      }
    } else if (!_config.allowDiagonal) {
      final absX = x.abs();
      final absY = y.abs();
      const switchRatio = 1.22;
      final release = math.max(0.02, _config.deadZone - 0.04);

      if (_dominantAxis == Axis.horizontal) {
        if (absX <= release && absY > _slowThreshold ||
            absY > absX * switchRatio) {
          _dominantAxis = Axis.vertical;
        }
      } else if (_dominantAxis == Axis.vertical) {
        if (absY <= release && absX > _slowThreshold ||
            absX > absY * switchRatio) {
          _dominantAxis = Axis.horizontal;
        }
      } else if (math.max(absX, absY) >= _slowThreshold) {
        _dominantAxis = absX >= absY ? Axis.horizontal : Axis.vertical;
      }

      if (_dominantAxis == Axis.horizontal) {
        y = 0.0;
      } else if (_dominantAxis == Axis.vertical) {
        x = 0.0;
      }
    }

    _resolvedXStep = _stepWithHysteresis(x, _resolvedXStep);
    _resolvedYStep = _stepWithHysteresis(y, _resolvedYStep);
    return JoystickOutput(
      x: _resolvedXStep == 0 ? 0.0 : _roundAnalog(x),
      y: _resolvedYStep == 0 ? 0.0 : _roundAnalog(y),
      xStep: _resolvedXStep,
      yStep: _resolvedYStep,
    );
  }

  int _stepWithHysteresis(double value, int previous) {
    final magnitude = value.abs();
    final sign = value == 0 ? 0 : value.sign.toInt();
    const slowExitMargin = 0.045;
    const fastExitMargin = 0.055;

    if (previous == 0) {
      if (magnitude >= _fastThreshold) return sign * 2;
      if (magnitude >= _slowThreshold) return sign;
      return 0;
    }
    if (sign != previous.sign) {
      if (magnitude < _slowThreshold) return 0;
      return magnitude >= _fastThreshold ? sign * 2 : sign;
    }
    if (previous.abs() == 2) {
      if (magnitude >= _fastThreshold - fastExitMargin) return previous;
      if (magnitude >= _slowThreshold - slowExitMargin) return sign;
      return 0;
    }
    if (magnitude >= _fastThreshold) return sign * 2;
    if (magnitude >= _slowThreshold - slowExitMargin) return sign;
    return 0;
  }

  void _resetDigitalResolution() {
    _resolvedXStep = 0;
    _resolvedYStep = 0;
    _dominantAxis = null;
  }

  Offset _clampValue(Offset value) {
    var next = value;
    if (!_config.isDualAxis) {
      next = _config.axis == JoystickAxis.horizontal
          ? Offset(next.dx, 0)
          : Offset(0, next.dy);
    }

    next = Offset(next.dx.clamp(-1.0, 1.0), next.dy.clamp(-1.0, 1.0));
    if (_config.boundary == JoystickBoundary.square) return next;

    final distance = next.distance;
    if (distance <= 1.0 || distance == 0.0) return next;
    return next / distance;
  }

  /// For digital modes, the visual knob snaps to the detent/cell center*
  /// instead of following the raw drag continuously. Analog modes ignore*
  /// this and track the raw value 1:1.*
  Offset _snappedForDisplay(Offset raw) {
    if (!_config.isDigital) return raw;

    if (!_config.isDualAxis) {
      final v = _config.axis == JoystickAxis.horizontal ? raw.dx : raw.dy;
      final step = _stepFor(v).toDouble();
      final snapped = step == 0
          ? 0.0
          : (step.sign * (step.abs() == 2 ? 1.0 : 0.5));
      return _config.axis == JoystickAxis.horizontal
          ? Offset(snapped, 0)
          : Offset(0, snapped);
    }

    final xStep = _lastOutput.xStep;
    final yStep = _lastOutput.yStep;
    double cell(int step) => step == 0 ? 0.0 : step.sign.toDouble();
    return Offset(cell(xStep), cell(yStep));
  }

  void _handlePanStart(
    DragStartDetails details,
    _JoystickDragGeometry geometry,
  ) {
    if (!widget.enabled) return;
    final display = _snappedForDisplay(_value);
    final knobCenter =
        geometry.center +
        Offset(
          display.dx * geometry.displayRadius,
          -display.dy * geometry.displayRadius,
        );
    if ((details.localPosition - knobCenter).distance >
        geometry.knobHitRadius) {
      _dragActive = false;
      return;
    }
    _cancelSpring();
    _dragActive = true;
    _grabOffset = details.localPosition - knobCenter;
    HapticFeedback.selectionClick();
  }

  void _handlePanUpdate(
    DragUpdateDetails details,
    _JoystickDragGeometry geometry,
  ) {
    if (!widget.enabled || !_dragActive) return;
    final radius = geometry.radius;
    if (radius <= 0) return;
    final centerDelta = details.localPosition - _grabOffset - geometry.center;
    final next = _clampValue(
      Offset(centerDelta.dx / radius, -centerDelta.dy / radius),
    );
    final previousStepKey = '${_lastOutput.xStep}:${_lastOutput.yStep}';
    setState(() => _value = next);
    _emit();
    final nextStepKey = '${_lastOutput.xStep}:${_lastOutput.yStep}';
    if (_config.isDigital && nextStepKey != previousStepKey) {
      HapticFeedback.selectionClick();
    }
  }

  void _handlePanEnd() {
    if (!widget.enabled || !_dragActive) return;
    _dragActive = false;
    if (_config.springReturn) {
      _springBackToCenter();
    } else {
      HapticFeedback.mediumImpact();
      _emit();
    }
  }

  void _handlePanCancel() {
    if (!_dragActive) return;
    _dragActive = false;
    _cancelSpring();
    _resetDigitalResolution();
    if (mounted) setState(() => _value = Offset.zero);
    _emitNeutral();
  }

  void _springBackToCenter() {
    _cancelSpring();
    final start = _value;
    final distance = start.distance;
    if (distance == 0.0) {
      _emit();
      return;
    }

    final ctrlX = AnimationController.unbounded(vsync: this);
    final ctrlY = AnimationController.unbounded(vsync: this);
    _springX = ctrlX;
    _springY = ctrlY;
    ctrlX.value = start.dx;
    ctrlY.value = start.dy;

    void tick() {
      if (!mounted) return;
      setState(() => _value = Offset(ctrlX.value, ctrlY.value));
    }

    ctrlX.addListener(tick);
    ctrlY.addListener(tick);

    final xFuture = ctrlX.animateWith(
      SpringSimulation(_spring, start.dx, 0, 0),
    );
    final yFuture = ctrlY.animateWith(
      SpringSimulation(_spring, start.dy, 0, 0),
    );
    Future.wait([xFuture, yFuture]).whenComplete(() {
      if (_springX == ctrlX) _springX = null;
      if (_springY == ctrlY) _springY = null;
      ctrlX.dispose();
      ctrlY.dispose();
      if (!mounted) return;
      setState(() => _value = Offset.zero);
      _emit();
    });

    _emitNeutral();
  }

  void _emitNeutral() {
    const neutral = JoystickOutput(x: 0, y: 0, xStep: 0, yStep: 0);
    _resetDigitalResolution();
    if (_lastOutput == neutral) return;
    _lastOutput = neutral;
    widget.onChanged(neutral);
  }

  void _emitNeutralAfterBuild() {
    const neutral = JoystickOutput(x: 0, y: 0, xStep: 0, yStep: 0);
    _resetDigitalResolution();
    if (_lastOutput == neutral) return;
    _lastOutput = neutral;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_lastOutput != neutral) return;
      widget.onChanged(neutral);
    });
  }

  void _cancelSpring() {
    final springX = _springX;
    final springY = _springY;
    _springX = null;
    _springY = null;
    springX?.dispose();
    springY?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final output = config.isDigital ? _lastOutput : _outputFor(_value);
    final isActive = output.xStep != 0 || output.yStep != 0;
    final display = _snappedForDisplay(_value);

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: '${widget.label}, ${config.mode.label}',
      value: switch (config.mode) {
        JoystickMode.singleAxisAnalog =>
          '${config.axis == JoystickAxis.horizontal ? 'X' : 'Y'} '
              '${_formatAnalogAxisValue(config.axis == JoystickAxis.horizontal ? output.x : output.y)}',
        JoystickMode.dualAxisAnalog =>
          'X ${_formatAnalogAxisValue(output.x)}, '
              'Y ${_formatAnalogAxisValue(output.y)}',
        JoystickMode.singleAxisDigital5 ||
        JoystickMode.dualAxisDigital4 => null,
      },
      child: Opacity(
        opacity: widget.enabled ? 1.0 : 0.52,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 220.0;
            final maxH = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : 220.0;
            final slotPadding = _joystickSlotPaddingFor(maxW, maxH);
            final innerW = math.max(0.0, maxW - slotPadding * 2);
            final innerH = math.max(0.0, maxH - slotPadding * 2);

            final body = switch (config.mode) {
              JoystickMode.singleAxisAnalog => _AnalogRail(
                config: config,
                value: display,
                output: config.axis == JoystickAxis.horizontal
                    ? output.x
                    : output.y,
                isActive: isActive,
                enabled: widget.enabled,
                label: widget.label,
                icon: widget.icon,
                activeColor: widget.activeColor,
                activeColorLight: widget.activeColorLight,
                maxWidth: innerW,
                maxHeight: innerH,
              ),
              JoystickMode.singleAxisDigital5 => _DigitalLadder(
                config: config,
                rawValue: _value,
                display: display,
                isActive: isActive,
                enabled: widget.enabled,
                label: widget.label,
                icon: widget.icon,
                activeColor: widget.activeColor,
                activeColorLight: widget.activeColorLight,
                maxWidth: innerW,
                maxHeight: innerH,
              ),
              JoystickMode.dualAxisAnalog => _AnalogGimbal(
                config: config,
                value: display,
                output: Offset(output.x, output.y),
                isActive: isActive,
                enabled: widget.enabled,
                label: widget.label,
                icon: widget.icon,
                activeColor: widget.activeColor,
                activeColorLight: widget.activeColorLight,
                maxWidth: innerW,
                maxHeight: innerH,
              ),
              JoystickMode.dualAxisDigital4 => _DigitalCrossGate(
                config: config,
                display: display,
                isActive: isActive,
                enabled: widget.enabled,
                label: widget.label,
                icon: widget.icon,
                activeColor: widget.activeColor,
                activeColorLight: widget.activeColorLight,
                maxWidth: innerW,
                maxHeight: innerH,
              ),
            };

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: widget.enabled
                  ? (details) => _handlePanStart(
                      details,
                      _dragGeometryFor(config, maxW, maxH, slotPadding),
                    )
                  : null,
              onPanUpdate: widget.enabled
                  ? (details) => _handlePanUpdate(
                      details,
                      _dragGeometryFor(config, maxW, maxH, slotPadding),
                    )
                  : null,
              onPanEnd: widget.enabled ? (_) => _handlePanEnd() : null,
              onPanCancel: widget.enabled ? _handlePanCancel : null,
              child: SizedBox(
                width: maxW,
                height: maxH,
                child: Padding(
                  padding: EdgeInsets.all(slotPadding),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: UnconstrainedBox(child: body),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  _JoystickDragGeometry _dragGeometryFor(
    JoystickConfig config,
    double maxW,
    double maxH,
    double slotPadding,
  ) {
    final innerW = math.max(0.0, maxW - slotPadding * 2);
    final innerH = math.max(0.0, maxH - slotPadding * 2);
    final center = Offset(maxW / 2, maxH / 2);
    if (!config.isDualAxis) {
      final availableLength = config.axis == JoystickAxis.horizontal
          ? innerW
          : innerH;
      final length = _safeVisualExtent(
        availableLength,
        min: 96.0,
        max: 320.0,
        scale: _kSingleAxisVisualScale,
      );
      final radius = length / 2;
      return _JoystickDragGeometry(
        center: center,
        radius: radius,
        displayRadius: radius,
        knobHitRadius: math.max(24.0, radius * 0.32),
      );
    }
    if (config.mode == JoystickMode.dualAxisDigital4) {
      // Same metrics the painter uses, shifted into the gesture detector's
      // own coordinates (which include the slot padding the painter's box
      // is inset by) so the knob's hit target tracks exactly where the knob
      // is drawn — including the label band's upward shift of the centre.
      final metrics = _CrossGateMetrics.forBox(Size(innerW, innerH));
      return _JoystickDragGeometry(
        center: Offset(slotPadding, slotPadding) + metrics.center,
        radius: metrics.gateExtent * _kCrossGateTravelFactor,
        displayRadius: metrics.step,
        // Never let a small footprint shrink the grab target below a
        // usable touch area, even though the knob itself keeps scaling.
        knobHitRadius: math.max(24.0, metrics.cell * 0.72),
      );
    }
    final side = _dualAxisSide(innerW, innerH);
    final radius = side * _kAnalogGimbalPointerTravelFactor;
    return _JoystickDragGeometry(
      center: center,
      radius: radius,
      displayRadius: radius,
      knobHitRadius: math.max(24.0, side * 0.16),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────*
// 1) SINGLE-AXIS ANALOG — vertical/horizontal proportional throttle rail.*
//*
// A tall capsule track with a continuously-sliding puck and a fill trail*
// from center to puck. No steps, no notches — pure smooth-glide metaphor.*
// ─────────────────────────────────────────────────────────────────────────────*

class _AnalogRail extends StatelessWidget {
  const _AnalogRail({
    required this.config,
    required this.value,
    required this.output,
    required this.isActive,
    required this.enabled,
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.activeColorLight,
    required this.maxWidth,
    required this.maxHeight,
  });

  final JoystickConfig config;
  final Offset value;
  final double output;
  final bool isActive;
  final bool enabled;
  final String label;
  final IconData? icon;
  final Color activeColor;
  final Color activeColorLight;
  final double maxWidth;
  final double maxHeight;

  bool get _horizontal => config.axis == JoystickAxis.horizontal;

  @override
  Widget build(BuildContext context) {
    final trackThickness = _safeVisualExtent(
      _horizontal ? maxHeight : maxWidth,
      min: 58.0,
      max: 118.0,
      scale: _kSingleAxisVisualScale,
    );
    final trackLength = _safeVisualExtent(
      _horizontal ? maxWidth : maxHeight,
      min: 104.0,
      max: 312.0,
      scale: _kSingleAxisVisualScale,
    );

    return Center(
      child: SizedBox(
        width: _horizontal ? trackLength : trackThickness,
        height: _horizontal ? trackThickness : trackLength,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _AnalogRailPainter(
                  horizontal: _horizontal,
                  value: _horizontal ? value.dx : value.dy,
                  isActive: isActive,
                  enabled: enabled,
                  activeColor: activeColor,
                  activeColorLight: activeColorLight,
                  label: label,
                  icon: icon,
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: trackThickness * 0.055),
                child: SizedBox(
                  width: _horizontal
                      ? math.min(trackLength * 0.46, 118.0)
                      : trackThickness * 0.90,
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: _AnalogAxisValueChip(
                        axis: _horizontal ? 'X' : 'Y',
                        value: output,
                        directionIcon: output.abs() < 0.0005
                            ? Icons.remove_rounded
                            : _horizontal
                            ? output > 0
                                  ? Icons.arrow_forward_rounded
                                  : Icons.arrow_back_rounded
                            : output > 0
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        valueKey: ValueKey(
                          'analog-joystick-${_horizontal ? 'x' : 'y'}-value',
                        ),
                        directionKey: ValueKey(
                          'analog-joystick-${_horizontal ? 'x' : 'y'}-direction',
                        ),
                        side: trackThickness,
                        activeColorLight: activeColorLight,
                        enabled: enabled,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalogRailPainter extends CustomPainter {
  const _AnalogRailPainter({
    required this.horizontal,
    required this.value,
    required this.isActive,
    required this.enabled,
    required this.activeColor,
    required this.activeColorLight,
    required this.label,
    required this.icon,
  });

  final bool horizontal;
  final double value;
  final bool isActive;
  final bool enabled;
  final Color activeColor;
  final Color activeColorLight;
  final String label;
  final IconData? icon;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final capsule = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular(math.min(w, h) / 2),
    );

    // Outer shell shadow + body.*
    canvas.drawRRect(
      capsule.shift(const Offset(0, 3)),
      Paint()
        ..color = Colors.black.withAlpha(110)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawRRect(
      capsule,
      Paint()
        ..shader = LinearGradient(
          begin: horizontal ? Alignment.topCenter : Alignment.centerLeft,
          end: horizontal ? Alignment.bottomCenter : Alignment.centerRight,
          colors: const [Color(0xFF1B2836), Color(0xFF0E1721)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    canvas.drawRRect(
      capsule.deflate(1.2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withAlpha(24),
    );

    // Inner recessed channel (the "travel path").*
    final inset = math.min(w, h) * 0.24;
    final channelRect = horizontal
        ? Rect.fromLTWH(inset, h * 0.36, w - inset * 2, h * 0.28)
        : Rect.fromLTWH(w * 0.36, inset, w * 0.28, h - inset * 2);
    final channelRRect = RRect.fromRectAndRadius(
      channelRect,
      Radius.circular(math.min(channelRect.width, channelRect.height) / 2),
    );
    canvas.drawRRect(channelRRect, Paint()..color = const Color(0xFF060B10));
    canvas.drawRRect(
      channelRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.black.withAlpha(200),
    );

    // Fine calibration ticks along the travel path (continuous-scale cue).*
    final tickPaint = Paint()
      ..color = Colors.white.withAlpha(28)
      ..strokeWidth = 1.0;
    const tickCount = 10;
    for (var i = 0; i <= tickCount; i++) {
      final t = i / tickCount;
      if (horizontal) {
        final x = channelRect.left + channelRect.width * t;
        final tall = i == tickCount / 2;
        canvas.drawLine(
          Offset(x, channelRect.top - (tall ? 6 : 3)),
          Offset(x, channelRect.top - 1),
          tickPaint,
        );
      } else {
        final y = channelRect.top + channelRect.height * (1 - t);
        final tall = i == tickCount / 2;
        canvas.drawLine(
          Offset(channelRect.right + 1, y),
          Offset(channelRect.right + (tall ? 6 : 3), y),
          tickPaint,
        );
      }
    }

    // Center neutral notch.*
    final center = channelRect.center;
    canvas.drawCircle(center, 3.0, Paint()..color = Colors.white.withAlpha(60));

    // Fill trail from center to puck position.*
    final travel = horizontal
        ? (channelRect.width - channelRect.height) / 2
        : (channelRect.height - channelRect.width) / 2;
    final puckPos = horizontal
        ? Offset(center.dx + value * travel, center.dy)
        : Offset(center.dx, center.dy - value * travel);

    final trailColor = isActive && enabled
        ? activeColor
        : const Color(0xFF3A4E5F);
    final trailRect = horizontal
        ? Rect.fromPoints(
            Offset(math.min(center.dx, puckPos.dx), channelRect.top + 3),
            Offset(math.max(center.dx, puckPos.dx), channelRect.bottom - 3),
          )
        : Rect.fromPoints(
            Offset(channelRect.left + 3, math.min(center.dy, puckPos.dy)),
            Offset(channelRect.right - 3, math.max(center.dy, puckPos.dy)),
          );
    if (trailRect.width > 0 && trailRect.height > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          trailRect,
          Radius.circular(math.min(trailRect.width, trailRect.height) / 2),
        ),
        Paint()
          ..color = trailColor.withAlpha(isActive && enabled ? 200 : 90)
          ..maskFilter = isActive && enabled
              ? const MaskFilter.blur(BlurStyle.normal, 3)
              : null,
      );
    }

    // Puck (continuous, no snapping).*
    final puckRadius = math.min(channelRect.width, channelRect.height) / 2 - 3;
    final puckBase = isActive && enabled
        ? activeColor
        : const Color(0xFF6B7C8D);
    final puckLight = isActive && enabled
        ? activeColorLight
        : const Color(0xFFC3CDD8);
    canvas.drawCircle(
      puckPos,
      puckRadius + 3,
      Paint()
        ..color = Colors.black.withAlpha(140)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      puckPos,
      puckRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [puckLight, puckBase],
        ).createShader(Rect.fromCircle(center: puckPos, radius: puckRadius)),
    );
    canvas.drawCircle(
      puckPos,
      puckRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withAlpha(70),
    );
    if (isActive && enabled) {
      canvas.drawCircle(
        puckPos,
        puckRadius + 5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = activeColorLight.withAlpha(110),
      );
    }
    // Grip lines on puck for tactile affordance.*
    final gripPaint = Paint()
      ..color = Colors.black.withAlpha(90)
      ..strokeWidth = 1.2;
    for (var i = -1; i <= 1; i++) {
      final offset = i * puckRadius * 0.35;
      if (horizontal) {
        canvas.drawLine(
          Offset(puckPos.dx + offset, puckPos.dy - puckRadius * 0.4),
          Offset(puckPos.dx + offset, puckPos.dy + puckRadius * 0.4),
          gripPaint,
        );
      } else {
        canvas.drawLine(
          Offset(puckPos.dx - puckRadius * 0.4, puckPos.dy + offset),
          Offset(puckPos.dx + puckRadius * 0.4, puckPos.dy + offset),
          gripPaint,
        );
      }
    }

    // Label at the opposite end.*
    final labelPainter = TextPainter(
      text: ControlButtonVisualMetrics.labelIconTextSpan(
        label: label,
        icon: icon,
        color: isActive && enabled
            ? activeColorLight
            : AppColors.darkText.withAlpha(enabled ? 230 : 120),
        iconColor: isActive && enabled
            ? activeColorLight
            : AppColors.darkTextMuted.withAlpha(enabled ? 210 : 110),
        bounds: Size(w - 12, ControlButtonVisualMetrics.rowHeight),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w - 12);
    labelPainter.paint(
      canvas,
      horizontal
          ? Offset(w / 2 - labelPainter.width / 2, h - labelPainter.height - 4)
          : Offset(w / 2 - labelPainter.width / 2, h - labelPainter.height - 6),
    );
  }

  @override
  bool shouldRepaint(covariant _AnalogRailPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.isActive != isActive ||
        oldDelegate.enabled != enabled ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.activeColorLight != activeColorLight ||
        oldDelegate.label != label ||
        oldDelegate.icon != icon;
  }
}

// ─────────────────────────────────────────────────────────────────────────────*
// 2) SINGLE-AXIS DIGITAL 5-STEP (spring return) — a ladder gate with 5*
// physical detent slots (Fast-, Slow-, Neutral, Slow+, Fast+). The knob*
// visibly jumps between slot centers instead of gliding, and a center*
// spring glyph communicates the return-to-neutral behavior.*
// ─────────────────────────────────────────────────────────────────────────────*

// Drop-in replacement for the supplied _DigitalLadder and*
// _DigitalLadderPainter classes.*
//*
// This file intentionally relies on the surrounding project's existing*
// JoystickConfig, JoystickAxis, AppColors, ControlButtonVisualMetrics,*
// _safeVisualExtent, and _kSingleAxisVisualScale declarations.*

// Shell-free single-axis digital joystick visual.*
//*
// The complete widget boundary contains only the five-position gate and knob.*
// There is no surrounding card, status area, label row, padding shell, or*
// decorative outer panel.*
//*
// This file intentionally relies on the surrounding project's existing*
// JoystickConfig, JoystickAxis, AppColors, _safeVisualExtent, and*
// _kSingleAxisVisualScale declarations.*

class _DigitalLadder extends StatelessWidget {
  const _DigitalLadder({
    required this.config,
    required this.rawValue,
    required this.display,
    required this.isActive,
    required this.enabled,
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.activeColorLight,
    required this.maxWidth,
    required this.maxHeight,
  });

  final JoystickConfig config;

  // Retained to keep this a drop-in replacement. Gesture processing belongs*
  // in the parent joystick; the ladder renders the settled display value.*
  final Offset rawValue;
  final Offset display;
  final bool isActive;
  final bool enabled;
  final String label;
  final IconData? icon;
  final Color activeColor;
  final Color activeColorLight;
  final double maxWidth;
  final double maxHeight;

  bool get _horizontal => config.axis == JoystickAxis.horizontal;

  int get _step {
    final value = _horizontal ? display.dx : display.dy;
    if (value.abs() < 0.001) return 0;
    return value.sign.toInt() * (value.abs() >= 1.0 ? 2 : 1);
  }

  String get _semanticValue {
    switch (_step) {
      case -2:
        return 'negative fast';
      case -1:
        return 'negative slow';
      case 1:
        return 'positive slow';
      case 2:
        return 'positive fast';
      default:
        return 'neutral';
    }
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = _horizontal;
    final thickness = _safeVisualExtent(
      horizontal ? maxHeight : maxWidth,
      min: _DigitalLadderStyle.minimumThickness,
      max: _DigitalLadderStyle.maximumThickness,
      scale: _kSingleAxisVisualScale,
    );
    final length = _safeVisualExtent(
      horizontal ? maxWidth : maxHeight,
      min: _DigitalLadderStyle.minimumLength,
      max: _DigitalLadderStyle.maximumLength,
      scale: _kSingleAxisVisualScale,
    );

    return Semantics(
      label: label,
      value: _semanticValue,
      enabled: enabled,
      child: SizedBox(
        width: horizontal ? length : thickness,
        height: horizontal ? thickness : length,
        child: RepaintBoundary(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: _step.toDouble()),
            duration: _DigitalLadderStyle.motionDuration,
            curve: Curves.easeOutCubic,
            builder: (context, animatedStep, child) => CustomPaint(
              isComplex: true,
              willChange: animatedStep != _step,
              painter: _DigitalLadderPainter(
                horizontal: horizontal,
                step: animatedStep,
                activeStep: _step,
                isActive: isActive,
                enabled: enabled,
                activeColor: activeColor,
                activeColorLight: activeColorLight,
              ),
              child: child,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

abstract final class _DigitalLadderStyle {
  static const int slotCount = 5;
  static const double minimumThickness = 62;
  static const double maximumThickness = 82;
  static const double minimumLength = 132;
  static const double maximumLength = 312;
  static const double cellRadius = 7;
  static const double slotGap = 4;
  static const Duration motionDuration = Duration(milliseconds: 120);

  static const Color gate = Color(0xFF0D1218);
  static const Color slot = Color(0xFF171E27);
  static const Color neutral = Color(0xFF0A0E13);
  static const Color inactiveKnob = Color(0xFF607181);
  static const Color inactiveKnobLight = Color(0xFFC2CDD6);
}

class _DigitalLadderPainter extends CustomPainter {
  const _DigitalLadderPainter({
    required this.horizontal,
    required this.step,
    required this.activeStep,
    required this.isActive,
    required this.enabled,
    required this.activeColor,
    required this.activeColorLight,
  });

  final bool horizontal;
  final double step;
  final int activeStep;
  final bool isActive;
  final bool enabled;
  final Color activeColor;
  final Color activeColorLight;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = _DigitalLadderGeometry(size, horizontal: horizontal);
    _paintGate(canvas, geometry);
    _paintSlots(canvas, geometry);
    _paintKnob(canvas, geometry);
  }

  void _paintGate(Canvas canvas, _DigitalLadderGeometry g) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(g.gate, const Radius.circular(9)),
      Paint()..color = _DigitalLadderStyle.gate,
    );
  }

  void _paintSlots(Canvas canvas, _DigitalLadderGeometry g) {
    for (var index = 0; index < _DigitalLadderStyle.slotCount; index++) {
      final slotStep = g.stepForSlot(index);
      final rect = g.cellRect(index);
      final shape = RRect.fromRectAndRadius(
        rect,
        const Radius.circular(_DigitalLadderStyle.cellRadius),
      );
      final neutral = slotStep == 0;
      final lit = _isLit(slotStep);

      canvas.drawRRect(
        shape,
        Paint()
          ..color = neutral
              ? _DigitalLadderStyle.neutral
              : _DigitalLadderStyle.slot,
      );

      if (lit) {
        final color = slotStep.abs() == 2
            ? activeColor
            : Color.lerp(activeColor, Colors.white, 0.16)!;
        canvas.drawRRect(
          shape,
          Paint()
            ..color = color.withAlpha(enabled ? 225 : 95)
            ..maskFilter = enabled
                ? const MaskFilter.blur(BlurStyle.normal, 1.5)
                : null,
        );
      }

      canvas.drawRRect(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = neutral ? 1.5 : 1
          ..color = neutral
              ? Colors.white.withAlpha(enabled ? 100 : 45)
              : Colors.black.withAlpha(190),
      );

      _paintDetent(canvas, rect, g);
      _paintSlotCaption(canvas, rect, slotStep, lit);
    }
  }

  void _paintDetent(Canvas canvas, Rect rect, _DigitalLadderGeometry g) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(enabled ? 42 : 20)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    if (horizontal) {
      canvas.drawLine(
        Offset(rect.center.dx, rect.top + 2),
        Offset(rect.center.dx, rect.top + 6),
        paint,
      );
    } else {
      canvas.drawLine(
        Offset(rect.right - 2, rect.center.dy),
        Offset(rect.right - 6, rect.center.dy),
        paint,
      );
    }
  }

  void _paintSlotCaption(Canvas canvas, Rect rect, int slotStep, bool lit) {
    if (slotStep == 0) {
      canvas.drawCircle(
        rect.center,
        2.7,
        Paint()..color = Colors.white.withAlpha(enabled ? 145 : 65),
      );
      return;
    }

    final caption = slotStep.abs() == 2 ? 'FAST' : 'SLOW';
    final painter = TextPainter(
      text: TextSpan(
        text: caption,
        style: TextStyle(
          color: lit
              ? Colors.black.withAlpha(180)
              : AppColors.darkTextMuted.withAlpha(enabled ? 170 : 75),
          fontSize: 7,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.35,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        rect.center.dx - painter.width / 2,
        horizontal
            ? rect.bottom - painter.height - 3
            : rect.center.dy - painter.height / 2,
      ),
    );
  }

  void _paintKnob(Canvas canvas, _DigitalLadderGeometry g) {
    final indicatorIndex = horizontal
        ? step.clamp(-2.0, 2.0) + 2
        : 2 - step.clamp(-2.0, 2.0);
    final indicator = g.interpolatedCell(indicatorIndex);
    final knobRect = horizontal
        ? Rect.fromCenter(
            center: indicator.center,
            width: indicator.width * 0.74,
            height: g.crossExtent * 1.18,
          )
        : Rect.fromCenter(
            center: indicator.center,
            width: g.crossExtent * 1.18,
            height: indicator.height * 0.74,
          );
    final knob = RRect.fromRectAndRadius(knobRect, const Radius.circular(8));
    final active = isActive && enabled;
    final base = active ? activeColor : _DigitalLadderStyle.inactiveKnob;
    final light = active
        ? activeColorLight
        : _DigitalLadderStyle.inactiveKnobLight;

    if (active) {
      canvas.drawRRect(
        knob.inflate(3),
        Paint()
          ..color = activeColor.withAlpha(55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawRRect(
      knob.shift(const Offset(0, 2)),
      Paint()
        ..color = Colors.black.withAlpha(150)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawRRect(
      knob,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [light, base],
        ).createShader(knobRect),
    );
    canvas.drawRRect(
      knob,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withAlpha(enabled ? 105 : 45),
    );
    _paintGrip(canvas, knobRect);
  }

  void _paintGrip(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = Colors.black.withAlpha(105)
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    for (var index = -1; index <= 1; index++) {
      final offset = index * (horizontal ? rect.width : rect.height) * 0.22;
      if (horizontal) {
        canvas.drawLine(
          Offset(rect.center.dx + offset, rect.top + 4),
          Offset(rect.center.dx + offset, rect.bottom - 4),
          paint,
        );
      } else {
        canvas.drawLine(
          Offset(rect.left + 4, rect.center.dy + offset),
          Offset(rect.right - 4, rect.center.dy + offset),
          paint,
        );
      }
    }
  }

  bool _isLit(int slotStep) {
    if (slotStep == 0 || activeStep == 0) return false;
    if (activeStep.sign != slotStep.sign) return false;
    return slotStep.abs() == 1 || activeStep.abs() >= 2;
  }

  @override
  bool shouldRepaint(covariant _DigitalLadderPainter old) =>
      old.horizontal != horizontal ||
      old.step != step ||
      old.activeStep != activeStep ||
      old.isActive != isActive ||
      old.enabled != enabled ||
      old.activeColor != activeColor ||
      old.activeColorLight != activeColorLight;
}

class _DigitalLadderGeometry {
  const _DigitalLadderGeometry(this.size, {required this.horizontal});

  final Size size;
  final bool horizontal;

  Rect get bounds => Offset.zero & size;
  double get _mainInset => math.min(size.width, size.height) * 0.10;
  double get _crossInset => math.min(size.width, size.height) * 0.16;

  Rect get gate => horizontal
      ? Rect.fromLTWH(
          _mainInset,
          _crossInset,
          size.width - _mainInset * 2,
          size.height - _crossInset * 2,
        )
      : Rect.fromLTWH(
          _crossInset,
          _mainInset,
          size.width - _crossInset * 2,
          size.height - _mainInset * 2,
        );

  double get mainExtent => horizontal ? gate.width : gate.height;
  double get crossExtent => horizontal ? gate.height : gate.width;
  double get cellExtent =>
      (mainExtent -
          _DigitalLadderStyle.slotGap * (_DigitalLadderStyle.slotCount - 1)) /
      _DigitalLadderStyle.slotCount;

  Rect cellRect(int index) {
    final start =
        (horizontal ? gate.left : gate.top) +
        index * (cellExtent + _DigitalLadderStyle.slotGap);
    return horizontal
        ? Rect.fromLTWH(start, gate.top, cellExtent, crossExtent)
        : Rect.fromLTWH(gate.left, start, crossExtent, cellExtent);
  }

  int stepForSlot(int index) => horizontal ? index - 2 : 2 - index;

  Rect interpolatedCell(double index) {
    final lower = index.floor().clamp(0, _DigitalLadderStyle.slotCount - 1);
    final upper = index.ceil().clamp(0, _DigitalLadderStyle.slotCount - 1);
    if (lower == upper) return cellRect(lower);
    return Rect.lerp(cellRect(lower), cellRect(upper), index - lower)!;
  }
}

// ─────────────────────────────────────────────────────────────────────────────*
// 3) DUAL-AXIS ANALOG — round gimbal puck with free continuous 2D travel.*
// ─────────────────────────────────────────────────────────────────────────────*

class _AnalogGimbal extends StatelessWidget {
  const _AnalogGimbal({
    required this.config,
    required this.value,
    required this.output,
    required this.isActive,
    required this.enabled,
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.activeColorLight,
    required this.maxWidth,
    required this.maxHeight,
  });

  final JoystickConfig config;
  final Offset value;
  final Offset output;
  final bool isActive;
  final bool enabled;
  final String label;
  final IconData? icon;
  final Color activeColor;
  final Color activeColorLight;
  final double maxWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final side = _dualAxisSide(maxWidth, maxHeight);
    final radius = side * _kAnalogGimbalPointerTravelFactor;
    final knobRadius = side * _kAnalogGimbalPointerRadiusFactor;
    final knobOffset = Offset(value.dx * radius, -value.dy * radius);

    return Center(
      child: SizedBox(
        width: side,
        height: side,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            CustomPaint(
              painter: _GimbalPainter(
                config: config,
                value: value,
                isActive: isActive,
                enabled: enabled,
                activeColor: activeColor,
                activeColorLight: activeColorLight,
                label: label,
                icon: icon,
              ),
              child: SizedBox(width: side, height: side),
            ),
            Transform.translate(
              offset: knobOffset,
              child: _GimbalKnob(
                radius: knobRadius,
                value: value,
                activeColor: activeColor,
                activeColorLight: activeColorLight,
                isActive: isActive,
                enabled: enabled,
              ),
            ),
            Positioned(
              top: side * 0.055,
              left: side * 0.10,
              right: side * 0.10,
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: _AnalogAxisReadout(
                    side: side,
                    output: output,
                    activeColorLight: activeColorLight,
                    enabled: enabled,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalogAxisReadout extends StatelessWidget {
  const _AnalogAxisReadout({
    required this.side,
    required this.output,
    required this.activeColorLight,
    required this.enabled,
  });

  final double side;
  final Offset output;
  final Color activeColorLight;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _AnalogAxisValueChip(
            axis: 'X',
            value: output.dx,
            directionIcon: output.dx.abs() < 0.0005
                ? Icons.remove_rounded
                : output.dx > 0
                ? Icons.arrow_forward_rounded
                : Icons.arrow_back_rounded,
            valueKey: const ValueKey('analog-joystick-x-value'),
            directionKey: const ValueKey('analog-joystick-x-direction'),
            side: side,
            activeColorLight: activeColorLight,
            enabled: enabled,
          ),
        ),
        SizedBox(width: side * 0.025),
        Expanded(
          child: _AnalogAxisValueChip(
            axis: 'Y',
            value: output.dy,
            directionIcon: output.dy.abs() < 0.0005
                ? Icons.remove_rounded
                : output.dy > 0
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            valueKey: const ValueKey('analog-joystick-y-value'),
            directionKey: const ValueKey('analog-joystick-y-direction'),
            side: side,
            activeColorLight: activeColorLight,
            enabled: enabled,
          ),
        ),
      ],
    );
  }
}

class _AnalogAxisValueChip extends StatelessWidget {
  const _AnalogAxisValueChip({
    required this.axis,
    required this.value,
    required this.directionIcon,
    required this.valueKey,
    required this.directionKey,
    required this.side,
    required this.activeColorLight,
    required this.enabled,
  });

  final String axis;
  final double value;
  final IconData directionIcon;
  final Key valueKey;
  final Key directionKey;
  final double side;
  final Color activeColorLight;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isMoving = enabled && value.abs() >= 0.0005;
    final accent = isMoving
        ? activeColorLight
        : AppColors.darkTextMuted.withAlpha(enabled ? 180 : 95);
    final fontSize = (side * 0.046).clamp(8.0, 12.0).toDouble();
    final chipHeight = (side * 0.105).clamp(18.0, 28.0).toDouble();

    return Container(
      height: chipHeight,
      padding: EdgeInsets.symmetric(horizontal: side * 0.025),
      decoration: BoxDecoration(
        color: const Color(0xE6111820),
        borderRadius: BorderRadius.circular(chipHeight / 2),
        border: Border.all(color: accent.withAlpha(isMoving ? 135 : 55)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(100),
            blurRadius: side * 0.025,
            offset: Offset(0, side * 0.008),
          ),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              axis,
              style: TextStyle(
                color: accent,
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(width: side * 0.018),
            Text(
              _formatAnalogAxisValue(value),
              key: valueKey,
              style: TextStyle(
                color: AppColors.darkText.withAlpha(enabled ? 245 : 115),
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            SizedBox(width: side * 0.012),
            Icon(
              directionIcon,
              key: directionKey,
              size: fontSize * 1.15,
              color: accent,
            ),
          ],
        ),
      ),
    );
  }
}

class _GimbalKnob extends StatelessWidget {
  const _GimbalKnob({
    required this.radius,
    required this.value,
    required this.activeColor,
    required this.activeColorLight,
    required this.isActive,
    required this.enabled,
  });

  final double radius;
  final Offset value;
  final Color activeColor;
  final Color activeColorLight;
  final bool isActive;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    return CustomPaint(
      painter: _GimbalKnobPainter(
        value: value,
        activeColor: activeColor,
        activeColorLight: activeColorLight,
        isActive: isActive,
        enabled: enabled,
      ),
      size: Size.square(size),
    );
  }
}

class _GimbalKnobPainter extends CustomPainter {
  const _GimbalKnobPainter({
    required this.value,
    required this.activeColor,
    required this.activeColorLight,
    required this.isActive,
    required this.enabled,
  });

  final Offset value;
  final Color activeColor;
  final Color activeColorLight;
  final bool isActive;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final r = side / 2;
    final active = isActive && enabled;
    final base = active ? activeColor : const Color(0xFF50606E);
    final light = active ? activeColorLight : const Color(0xFFC8D2DC);
    final dark = Color.alphaBlend(Colors.black.withAlpha(135), base);
    final thumbRect = Rect.fromCircle(center: center, radius: r);

    final travel = value.distance.clamp(0.0, 1.0);
    final tilt = value.distance == 0
        ? Offset.zero
        : Offset(value.dx, -value.dy) / value.distance;

    canvas.drawCircle(
      center + Offset(0, r * 0.22),
      r * 0.92,
      Paint()
        ..color = Colors.black.withAlpha(145)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.24),
    );

    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(-0.35 + tilt.dx * 0.12, -0.45 + tilt.dy * 0.12),
          radius: 1.05,
          colors: [light, base, dark],
          stops: const [0.0, 0.54, 1.0],
        ).createShader(thumbRect),
    );
    canvas.drawCircle(
      center,
      r - 0.8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.1, side * 0.055)
        ..color = Colors.white.withAlpha(enabled ? 56 : 24),
    );

    if (active) {
      canvas.drawCircle(
        center,
        r * 0.82,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, side * 0.035)
          ..color = activeColorLight.withAlpha((80 + travel * 70).round()),
      );
    }

    final insertR = r * 0.48;
    final insertRect = Rect.fromCircle(center: center, radius: insertR);
    canvas.drawCircle(
      center,
      insertR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.25, -0.35),
          radius: 1.0,
          colors: [
            Colors.white.withAlpha(enabled ? 78 : 34),
            Colors.black.withAlpha(34),
          ],
        ).createShader(insertRect),
    );
    canvas.drawCircle(
      center,
      insertR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, side * 0.028)
        ..color = Colors.black.withAlpha(110),
    );

    final groovePaint = Paint()
      ..color = Colors.black.withAlpha(92)
      ..strokeWidth = math.max(0.8, side * 0.032)
      ..strokeCap = StrokeCap.round;
    for (final offset in [-0.34, 0.0, 0.34]) {
      final y = center.dy + r * offset;
      canvas.drawLine(
        Offset(center.dx - r * 0.30, y),
        Offset(center.dx + r * 0.30, y),
        groovePaint,
      );
    }

    canvas.drawCircle(
      center + Offset(-r * 0.26, -r * 0.30),
      r * 0.13,
      Paint()..color = Colors.white.withAlpha(enabled ? 82 : 34),
    );
  }

  @override
  bool shouldRepaint(covariant _GimbalKnobPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.activeColorLight != activeColorLight ||
        oldDelegate.isActive != isActive ||
        oldDelegate.enabled != enabled;
  }
}

class _GimbalPainter extends CustomPainter {
  const _GimbalPainter({
    required this.config,
    required this.value,
    required this.isActive,
    required this.enabled,
    required this.activeColor,
    required this.activeColorLight,
    required this.label,
    required this.icon,
  });

  final JoystickConfig config;
  final Offset value;
  final bool isActive;
  final bool enabled;
  final Color activeColor;
  final Color activeColorLight;
  final String label;
  final IconData? icon;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = side * 0.48;
    final boundaryR = side * _kAnalogGimbalBoundaryFactor;
    final pointerTravelR = side * _kAnalogGimbalPointerTravelFactor;

    canvas.drawCircle(
      center + Offset(0, side * 0.025),
      outerR,
      Paint()
        ..color = Colors.black.withAlpha(130)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );

    // Circular bezel — smooth radial dish (distinct from the ladder's flat*
    // rounded-rect body and the cross-gate's angular plate).*
    final plateRect = Rect.fromCircle(center: center, radius: outerR);
    canvas.drawCircle(
      center,
      outerR,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.36, -0.5),
          radius: 1.2,
          colors: [Color(0xFF2C3B4C), Color(0xFF17222E), Color(0xFF080D13)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(plateRect),
    );
    canvas.drawCircle(
      center,
      outerR - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = Colors.white.withAlpha(30),
    );

    // Concentric travel rings (continuous-field cue, no wedge divisions).*
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.white.withAlpha(18);
    for (final f in [0.34, 0.67, 1.0]) {
      canvas.drawCircle(center, boundaryR * f, ringPaint);
    }

    final boundaryPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = side * 0.014
      ..color = enabled
          ? AppColors.darkBorder.withAlpha(230)
          : AppColors.disabled.withAlpha(120);
    if (config.boundary == JoystickBoundary.circular) {
      canvas.drawCircle(center, boundaryR, boundaryPaint);
    } else {
      final rect = Rect.fromCenter(
        center: center,
        width: boundaryR * 2,
        height: boundaryR * 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(side * 0.05)),
        boundaryPaint,
      );
    }

    // Faint crosshair (fine, not gate-like).*
    final crossPaint = Paint()
      ..color = Colors.white.withAlpha(22)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(center.dx - boundaryR, center.dy),
      Offset(center.dx + boundaryR, center.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - boundaryR),
      Offset(center.dx, center.dy + boundaryR),
      crossPaint,
    );

    final target = Offset(
      center.dx + value.dx * pointerTravelR,
      center.dy - value.dy * pointerTravelR,
    );

    // Smooth proportional vector from center to the current X/Y output.*
    if (isActive && enabled) {
      canvas.drawLine(
        center,
        target,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = side * 0.02
          ..strokeCap = StrokeCap.round
          ..color = activeColorLight.withAlpha(200)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
      canvas.drawCircle(
        target,
        side * 0.018,
        Paint()..color = activeColorLight.withAlpha(210),
      );
    }

    canvas.drawCircle(
      center,
      side * 0.05,
      Paint()
        ..color = isActive && enabled
            ? activeColor.withAlpha(160)
            : const Color(0xFF263748),
    );

    final labelPainter = TextPainter(
      text: ControlButtonVisualMetrics.labelIconTextSpan(
        label: label,
        icon: icon,
        color: isActive && enabled
            ? activeColorLight
            : AppColors.darkText.withAlpha(enabled ? 230 : 120),
        iconColor: isActive && enabled
            ? activeColorLight
            : AppColors.darkTextMuted.withAlpha(enabled ? 210 : 110),
        bounds: Size(side * 0.66, ControlButtonVisualMetrics.rowHeight),
      ),
      maxLines: 1,
      ellipsis: '…',
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: side * 0.66);
    labelPainter.paint(
      canvas,
      Offset(center.dx - labelPainter.width / 2, size.height - side * 0.13),
    );
  }

  @override
  bool shouldRepaint(covariant _GimbalPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.config != config ||
        oldDelegate.isActive != isActive ||
        oldDelegate.enabled != enabled ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.activeColorLight != activeColorLight ||
        oldDelegate.label != label ||
        oldDelegate.icon != icon;
  }
}

// ─────────────────────────────────────────────────────────────────────────────*
// 4) DUAL-AXIS DIGITAL 4-STEP (friction/maintained) — a cross/H-gate with 4*
// chunky latching cells (N/E/S/W). The knob jumps to a cell and *stays**
// there (no spring animation), reinforcing the maintained-friction feel.*
// ─────────────────────────────────────────────────────────────────────────────*

class _DigitalCrossGate extends StatelessWidget {
  const _DigitalCrossGate({
    required this.config,
    required this.display,
    required this.isActive,
    required this.enabled,
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.activeColorLight,
    required this.maxWidth,
    required this.maxHeight,
  });

  final JoystickConfig config;
  final Offset display;
  final bool isActive;
  final bool enabled;
  final String label;
  final IconData? icon;
  final Color activeColor;
  final Color activeColorLight;
  final double maxWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final cellX = display.dx.round().clamp(-1, 1);
    final cellY = display.dy.round().clamp(-1, 1);

    // Paint across the FULL assigned box rather than pre-squaring it: the
    // gate squares itself from whichever dimension is binding (see
    // _CrossGateMetrics), which on a tall footprint yields a larger gate
    // than squaring to the shorter side up front would allow.
    return Center(
      child: SizedBox(
        width: maxWidth,
        height: maxHeight,
        child: TweenAnimationBuilder<Offset>(
          tween: Tween(
            begin: Offset.zero,
            end: Offset(cellX.toDouble(), cellY.toDouble()),
          ),
          duration: config.springReturn
              ? const Duration(milliseconds: 90)
              : const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          builder: (context, animatedCell, _) {
            return CustomPaint(
              painter: _CrossGatePainter(
                config: config,
                animatedCell: animatedCell,
                activeCellX: cellX,
                activeCellY: cellY,
                isActive: isActive,
                enabled: enabled,
                activeColor: activeColor,
                activeColorLight: activeColorLight,
                label: label,
                icon: icon,
              ),
              child: SizedBox(width: maxWidth, height: maxHeight),
            );
          },
        ),
      ),
    );
  }
}

class _CrossGatePainter extends CustomPainter {
  const _CrossGatePainter({
    required this.config,
    required this.animatedCell,
    required this.activeCellX,
    required this.activeCellY,
    required this.isActive,
    required this.enabled,
    required this.activeColor,
    required this.activeColorLight,
    required this.label,
    required this.icon,
  });

  final JoystickConfig config;
  final Offset animatedCell;
  final int activeCellX;
  final int activeCellY;
  final bool isActive;
  final bool enabled;
  final Color activeColor;
  final Color activeColorLight;
  final String label;
  final IconData? icon;

  @override
  void paint(Canvas canvas, Size size) {
    final metrics = _CrossGateMetrics.forBox(size);
    final gateExtent = metrics.gateExtent;
    if (gateExtent <= 0) return;
    final center = metrics.center;
    final plateR = gateExtent * 0.5;

    canvas.drawCircle(
      center + Offset(0, gateExtent * 0.025),
      plateR,
      Paint()
        ..color = Colors.black.withAlpha(130)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, gateExtent * 0.06),
    );

    //   Paint()
    //     ..shader = const LinearGradient(
    //       begin: Alignment.topLeft,
    //       end: Alignment.bottomRight,
    //       colors: [Color.fromARGB(255, 7, 53, 180), Color(0xFF121319)],
    //     ).createShader(plateRect),
    // );
    // canvas.drawRRect(
    //   plateRRect.deflate(1.2),
    //   Paint()
    //     ..style = PaintingStyle.stroke
    //     ..strokeWidth = 1.6
    //     ..color = Colors.white.withAlpha(24),
    // );

    // Cross-shaped gate carved from 5 cells: center + N/E/S/W. Each is a*
    // distinct angular block with a visible seam — reads as "gated slots"*
    // rather than a free field.*
    final cell = metrics.cell;
    final step = metrics.step;

    Rect cellRect(int cx, int cy) {
      final dx = cx * step;
      final dy = -cy * step;
      return Rect.fromCenter(
        center: center + Offset(dx, dy),
        width: cell,
        height: cell,
      );
    }

    final positions = <(int, int)>[
      (0, 0),
      (0, 1),
      (0, -1),
      (-1, 0),
      (1, 0),
      if (config.allowDiagonal) ...[(-1, 1), (1, 1), (-1, -1), (1, -1)],
    ];

    for (final (cx, cy) in positions) {
      final rect = cellRect(cx, cy);
      final rrect = RRect.fromRectAndRadius(
        rect,
        Radius.circular(cell * 0.136),
      );
      final isNeutral = cx == 0 && cy == 0;
      final isEngaged =
          !isNeutral && activeCellX == cx && activeCellY == cy && isActive;

      canvas.drawRRect(
        rrect,
        Paint()
          ..color = isNeutral
              ? const Color(0xFF0B0D11)
              : const Color(0xFF161920),
      );
      if (isEngaged && enabled) {
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = activeColor.withAlpha(230)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.033),
        );
      }
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isNeutral
              ? math.max(1.0, cell * 0.027)
              : math.max(0.8, cell * 0.018)
          ..color = isNeutral
              ? Colors.white.withAlpha(100)
              : Colors.black.withAlpha(210),
      );

      // Direction glyph on each active cell.
      if (!isNeutral) {
        final glyphColor = isEngaged && enabled
            ? Colors.black.withAlpha(190)
            : AppColors.darkTextMuted.withAlpha(enabled ? 150 : 80);
        _drawChevron(canvas, rect.center, cx, cy, cell * 0.226, glyphColor);
      } else {
        canvas.drawCircle(
          rect.center,
          cell * 0.082,
          Paint()..color = Colors.white.withAlpha(110),
        );
      }
    }

    // Connective seams between center and arms (visual "gate track").*
    final seamPaint = Paint()
      ..color = Colors.black.withAlpha(160)
      ..strokeWidth = math.max(0.8, gateExtent * 0.017);
    final seamHalf = gateExtent * 0.148;
    canvas.drawLine(
      center + Offset(0, -seamHalf),
      center + Offset(0, seamHalf),
      seamPaint,
    );
    canvas.drawLine(
      center + Offset(-seamHalf, 0),
      center + Offset(seamHalf, 0),
      seamPaint,
    );

    // Latching knob — square-ish puck that jumps between cells and holds.*
    final knobCenter =
        center + Offset(animatedCell.dx * step, -animatedCell.dy * step);
    final knobSize = cell * 0.54;
    final knobRect = Rect.fromCenter(
      center: knobCenter,
      width: knobSize,
      height: knobSize,
    );
    final knobRRect = RRect.fromRectAndRadius(
      knobRect,
      Radius.circular(cell * 0.113),
    );
    final base = isActive && enabled ? activeColor : const Color(0xFF576675);
    final light = isActive && enabled
        ? activeColorLight
        : const Color(0xFFC0CAD3);

    canvas.drawRRect(
      knobRRect.shift(Offset(0, cell * 0.05)),
      Paint()
        ..color = Colors.black.withAlpha(170)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.1),
    );
    canvas.drawRRect(
      knobRRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, base],
        ).createShader(knobRect),
    );
    canvas.drawRRect(
      knobRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, cell * 0.027)
        ..color = Colors.white.withAlpha(90),
    );
    if (isActive && enabled) {
      canvas.drawRRect(
        knobRRect.inflate(cell * 0.068),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, cell * 0.033)
          ..color = activeColorLight.withAlpha(110),
      );
    }

    final labelPainter = TextPainter(
      text: ControlButtonVisualMetrics.labelIconTextSpan(
        label: label,
        icon: icon,
        color: isActive && enabled
            ? activeColorLight
            : AppColors.darkText.withAlpha(enabled ? 230 : 120),
        iconColor: isActive && enabled
            ? activeColorLight
            : AppColors.darkTextMuted.withAlpha(enabled ? 210 : 110),
        bounds: Size(gateExtent * 0.9, ControlButtonVisualMetrics.rowHeight),
      ),
      maxLines: 1,
      ellipsis: '…',
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: gateExtent * 0.9);
    // Sits in the band reserved beneath the gate, so it can never overlap
    // the directional cells nor spill past the bottom of the paint box.
    labelPainter.paint(
      canvas,
      Offset(
        center.dx - labelPainter.width / 2,
        center.dy +
            gateExtent / 2 +
            math.max(0.0, metrics.labelBand - labelPainter.height) / 2,
      ),
    );
  }

  void _drawChevron(
    Canvas canvas,
    Offset center,
    int dx,
    int dy,
    double size,
    Color color,
  ) {
    final path = Path();
    final dir = Offset(dx.toDouble(), -dy.toDouble());
    final perp = Offset(-dir.dy, dir.dx);
    final tip = center + dir * size * 0.5;
    final baseA = center - dir * size * 0.35 + perp * size * 0.4;
    final baseB = center - dir * size * 0.35 - perp * size * 0.4;
    path.moveTo(baseA.dx, baseA.dy);
    path.lineTo(tip.dx, tip.dy);
    path.lineTo(baseB.dx, baseB.dy);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.22
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _CrossGatePainter oldDelegate) {
    return oldDelegate.animatedCell != animatedCell ||
        oldDelegate.activeCellX != activeCellX ||
        oldDelegate.activeCellY != activeCellY ||
        oldDelegate.isActive != isActive ||
        oldDelegate.enabled != enabled ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.activeColorLight != activeColorLight ||
        oldDelegate.label != label ||
        oldDelegate.icon != icon;
  }
}
