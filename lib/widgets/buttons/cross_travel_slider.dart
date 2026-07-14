import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:vibration/vibration.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/button_state_log.dart';

// ── Internal zone ─────────────────────────────────────────────────────────────

enum _TravZone { idle, leftSlow, leftFast, rightSlow, rightFast }

enum CrossTravelSliderVariant { fiveZone, threeZoneSlowOnly }

// ─────────────────────────────────────────────────────────────────────────────
// CrossTravelSlider
// ─────────────────────────────────────────────────────────────────────────────

/// Horizontal spring-return cross-travel slider for the PLC38 HMI.
///
/// The thumb rests at centre (value = 0.0 → idle).  Dragging left or right
/// enters SLOW then FAST zones.  On release the thumb springs back to centre
/// and an IDLE command is emitted immediately — no motion remains active after
/// the operator lets go.
///
/// Output mapping
/// ──────────────
///   Centre idle zone (±[_deadZone]):  LEFT=0, RIGHT=0, FAST_LR=0
///   Left slow zone:  LEFT=1, FAST_LR=0
///   Left fast zone:  LEFT=1, FAST_LR=1
///   Right slow zone: RIGHT=1, FAST_LR=0
///   Right fast zone: RIGHT=1, FAST_LR=1
class CrossTravelSlider extends StatefulWidget {
  /// Disables interaction and snaps the thumb to centre (e.g. when e-stop
  /// is latched or the BLE link is down).
  final bool isDisabled;

  /// Custom labels for the left/right direction text.
  final String leftLabel;
  final String rightLabel;

  /// Fired on every zone transition.  [isLeft] selects the output direction;
  /// [state] encodes speed (idle / slow / fast).
  final void Function({required bool isLeft, required ControlState state})
  onCommandChanged;

  /// Five-zone emits slow and fast. Three-zone emits idle/left-slow/right-slow
  /// only, even at the far end of the track.
  final CrossTravelSliderVariant variant;

  /// When true, the drag is physically clamped at the dead-zone boundary in
  /// the corresponding direction. The thumb cannot enter that zone — it feels
  /// "stuck" — because the PLC field it would assert is currently owned by
  /// another button. No visual change to the button is made; only the gesture
  /// is constrained.
  final bool isLeftZoneBlocked;
  final bool isRightZoneBlocked;

  const CrossTravelSlider({
    super.key,
    this.isDisabled = false,
    this.leftLabel = 'LEFT',
    this.rightLabel = 'RIGHT',
    this.variant = CrossTravelSliderVariant.fiveZone,
    this.isLeftZoneBlocked = false,
    this.isRightZoneBlocked = false,
    required this.onCommandChanged,
  });

  @override
  State<CrossTravelSlider> createState() => _CrossTravelSliderState();
}

class _CrossTravelSliderState extends State<CrossTravelSlider>
    with SingleTickerProviderStateMixin {
  /// Normalised thumb position: -1.0 = full left · 0.0 = centre · +1.0 = full right
  double _value = 0.0;
  bool _isDragging = false;
  _TravZone _lastEmitted = _TravZone.idle;

  late final AnimationController _springCtrl;

  // ── Thresholds (fraction of half-track from centre) ──────────────────────
  static const double _deadZone = 0.12; // ±12 % → idle dead band
  static const double _fastZone = 0.62; // beyond ±62 % → fast

  // Margin applied when clamping to the dead-zone boundary so the value stays
  // strictly INSIDE the idle region (abs < _deadZone), preventing the zone
  // check from firing at the exact boundary value.
  static const double _zoneClampMargin = 0.001;

  // ── Thumb / track geometry ────────────────────────────────────────────────
  static const double _thumbW = 36.0;
  static const double _thumbH = 52.0;
  static const double _trackH = 16.0;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _springCtrl = AnimationController.unbounded(vsync: this)
      ..addListener(_onSpringTick);
  }

  @override
  void didUpdateWidget(CrossTravelSlider old) {
    super.didUpdateWidget(old);
    // Snap to centre whenever the widget becomes disabled (e-stop / disconnect).
    if (widget.isDisabled && !old.isDisabled) {
      _springCtrl.stop();
      // If disabled mid-drag, emit idle before clearing _isDragging.
      // Without this, _release() will bail on `if (!_isDragging) return`
      // and the parent's _localActive entry stays permanently true, which
      // keeps isDisabled=true even after the operator releases the slider.
      if (_isDragging && _lastEmitted != _TravZone.idle) {
        widget.onCommandChanged(isLeft: true, state: ControlState.idle);
      }
      setState(() {
        _value = 0.0;
        _isDragging = false;
        _lastEmitted = _TravZone.idle;
      });
      return;
    }

    // Push the thumb back inside the dead zone if a zone just became blocked
    // mid-drag (e.g. the other traverse slider claimed ownership of fast_lr).
    // The ownership system prevents two sliders from both being in their
    // blocked zones simultaneously, so this path is a defensive safeguard.
    if (_isDragging) {
      var clamped = _value;
      if (widget.isRightZoneBlocked && _value >= _deadZone) {
        clamped = _deadZone - _zoneClampMargin;
      }
      if (widget.isLeftZoneBlocked && _value <= -_deadZone) {
        clamped = -_deadZone + _zoneClampMargin;
      }
      if (clamped != _value) {
        setState(() => _value = clamped);
        _emitZone(_zoneFor(clamped)); // emits idle since clamped < _deadZone
      }
    }
  }

  @override
  void dispose() {
    _springCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Zone logic
  // ─────────────────────────────────────────────────────────────────────────

  _TravZone _zoneFor(double v) {
    if (widget.isDisabled) return _TravZone.idle;
    final abs = v.abs();
    if (abs < _deadZone) return _TravZone.idle;
    if (v < 0) {
      if (widget.variant == CrossTravelSliderVariant.threeZoneSlowOnly) {
        return _TravZone.leftSlow;
      }
      return abs >= _fastZone ? _TravZone.leftFast : _TravZone.leftSlow;
    }
    if (widget.variant == CrossTravelSliderVariant.threeZoneSlowOnly) {
      return _TravZone.rightSlow;
    }
    return v >= _fastZone ? _TravZone.rightFast : _TravZone.rightSlow;
  }

  void _emitZone(_TravZone zone) {
    if (zone == _lastEmitted) return;
    _lastEmitted = zone;
    ButtonStateLog.log(
      '${zone == _TravZone.idle ? 'VISUAL_IDLE / SEND_IDLE' : 'VISUAL_ACTIVE / SEND_ACTIVE'} '
      '[${widget.leftLabel}/${widget.rightLabel}] -> ${zone.name}',
    );
    switch (zone) {
      case _TravZone.idle:
        widget.onCommandChanged(isLeft: true, state: ControlState.idle);
      case _TravZone.leftSlow:
        Vibration.vibrate(duration: 18, amplitude: 80);
        widget.onCommandChanged(isLeft: true, state: ControlState.slow);
      case _TravZone.leftFast:
        Vibration.vibrate(duration: 28, amplitude: 180);
        widget.onCommandChanged(isLeft: true, state: ControlState.fast);
      case _TravZone.rightSlow:
        Vibration.vibrate(duration: 18, amplitude: 80);
        widget.onCommandChanged(isLeft: false, state: ControlState.slow);
      case _TravZone.rightFast:
        Vibration.vibrate(duration: 28, amplitude: 180);
        widget.onCommandChanged(isLeft: false, state: ControlState.fast);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Spring physics
  // ─────────────────────────────────────────────────────────────────────────

  void _onSpringTick() {
    if (_isDragging) return;
    setState(() => _value = _springCtrl.value.clamp(-1.0, 1.0));
    // No commands during visual return — IDLE was already sent on release.
  }

  void _springReturn() {
    _springCtrl.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 0.5, stiffness: 280.0, damping: 17.0),
        _value,
        0.0, // target = centre
        0.0, // initial velocity
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Drag handlers
  // ─────────────────────────────────────────────────────────────────────────

  void _dragStart(DragStartDetails _, double halfTrack) {
    if (widget.isDisabled) return;
    ButtonStateLog.log('USER_DOWN [${widget.leftLabel}/${widget.rightLabel}]');
    _springCtrl.stop();
    setState(() => _isDragging = true);
  }

  void _dragUpdate(DragUpdateDetails details, double halfTrack) {
    if (!_isDragging || widget.isDisabled) return;
    final delta = halfTrack > 0 ? details.delta.dx / halfTrack : 0.0;
    var newValue = (_value + delta).clamp(-1.0, 1.0);

    // Clamp at the dead-zone boundary when the zone is locked by another
    // button's ownership of the same PLC field. Keeping the value strictly
    // inside the dead zone (abs < _deadZone) ensures the zone check returns
    // idle so no command is emitted in the blocked direction.
    if (widget.isRightZoneBlocked && newValue >= _deadZone) {
      newValue = _deadZone - _zoneClampMargin;
    }
    if (widget.isLeftZoneBlocked && newValue <= -_deadZone) {
      newValue = -_deadZone + _zoneClampMargin;
    }

    setState(() => _value = newValue);
    _emitZone(_zoneFor(_value));
  }

  void _dragEnd(DragEndDetails _) {
    ButtonStateLog.log('USER_UP [${widget.leftLabel}/${widget.rightLabel}]');
    _release();
  }

  void _dragCancel() {
    ButtonStateLog.log(
      'USER_CANCEL [${widget.leftLabel}/${widget.rightLabel}]',
    );
    _release();
  }

  void _release() {
    if (!_isDragging) return;
    setState(() => _isDragging = false);
    _emitZone(_TravZone.idle); // Safety: send IDLE immediately on release.
    _springReturn();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, box) {
        final w = box.maxWidth;
        final halfTrack = (w - _thumbW) / 2.0;
        final thumbCX = w / 2.0 + _value * halfTrack;

        final zone = _zoneFor(_value);
        final isFast =
            zone == _TravZone.leftFast || zone == _TravZone.rightFast;
        final isLeft = zone == _TravZone.leftSlow || zone == _TravZone.leftFast;
        final isRight =
            zone == _TravZone.rightSlow || zone == _TravZone.rightFast;
        final slowOnly =
            widget.variant == CrossTravelSliderVariant.threeZoneSlowOnly;

        final Color trackColor = widget.isDisabled
            ? AppColors.idleColor
            : isFast
            ? AppColors.fastColor
            : AppColors.traverseColor;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => _dragStart(d, halfTrack),
          onHorizontalDragUpdate: (d) => _dragUpdate(d, halfTrack),
          onHorizontalDragEnd: _dragEnd,
          onHorizontalDragCancel: _dragCancel,
          child: SizedBox(
            width: w,
            height: box.maxHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Zone labels (top row) ─────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: slowOnly
                      ? Row(
                          children: [
                            _zoneLabel(
                              '< ${widget.leftLabel}',
                              zone == _TravZone.leftSlow,
                              AppColors.traverseColor,
                            ),
                            const Spacer(),
                            _zoneLabel(
                              'SLOW ONLY',
                              isLeft || isRight,
                              AppColors.traverseColor,
                            ),
                            const Spacer(),
                            _zoneLabel(
                              '${widget.rightLabel} >',
                              zone == _TravZone.rightSlow,
                              AppColors.traverseColor,
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            _zoneLabel(
                              '< ${widget.leftLabel} FAST',
                              zone == _TravZone.leftFast,
                              AppColors.fastColor,
                            ),
                            const Spacer(),
                            _zoneLabel(
                              'SLOW',
                              zone == _TravZone.leftSlow,
                              AppColors.traverseColor,
                            ),
                            const SizedBox(width: 10),
                            _zoneLabel(
                              'SLOW',
                              zone == _TravZone.rightSlow,
                              AppColors.traverseColor,
                            ),
                            const Spacer(),
                            _zoneLabel(
                              'FAST ${widget.rightLabel} >',
                              zone == _TravZone.rightFast,
                              AppColors.fastColor,
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 5),

                // ── Track + thumb ─────────────────────────────────────────────
                SizedBox(
                  width: w,
                  height: _thumbH,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      // Track
                      CustomPaint(
                        size: Size(w, _trackH),
                        painter: _TrackPainter(
                          value: _value,
                          halfTrack: halfTrack,
                          deadZone: _deadZone,
                          fastZone: _fastZone,
                          showFastMarkers: !slowOnly,
                          fillColor: widget.isDisabled
                              ? AppColors.idleColor.withAlpha(70)
                              : trackColor.withAlpha(200),
                          isActive: !widget.isDisabled,
                        ),
                      ),
                      // Thumb
                      Positioned(
                        left: thumbCX - _thumbW / 2,
                        child: _Thumb(
                          width: _thumbW,
                          height: _thumbH,
                          color: trackColor,
                          isDragging: _isDragging,
                          isDisabled: widget.isDisabled,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),

                // ── Direction labels (bottom row) ─────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      _dirLabel(widget.leftLabel, isLeft),
                      const Spacer(),
                      _statusDot(zone, trackColor),
                      const Spacer(),
                      _dirLabel(widget.rightLabel, isRight),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Label helpers ─────────────────────────────────────────────────────────

  Widget _zoneLabel(String text, bool active, Color color) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 7.5,
        fontWeight: active ? FontWeight.bold : FontWeight.normal,
        color: active ? color : AppColors.darkTextMuted.withAlpha(90),
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _dirLabel(String text, bool active) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.bold,
        color: active ? AppColors.traverseColorLight : AppColors.darkTextMuted,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _statusDot(_TravZone zone, Color activeColor) {
    if (widget.isDisabled) {
      return const Text(
        '— DISABLED —',
        style: TextStyle(fontSize: 7, color: AppColors.darkTextMuted),
      );
    }
    final isIdle = zone == _TravZone.idle;
    return Text(
      '●',
      style: TextStyle(
        fontSize: 9,
        color: isIdle ? AppColors.idleColor : activeColor,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Track painter
// ─────────────────────────────────────────────────────────────────────────────

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.value,
    required this.halfTrack,
    required this.deadZone,
    required this.fastZone,
    required this.showFastMarkers,
    required this.fillColor,
    required this.isActive,
  });

  final double value;
  final double halfTrack;
  final double deadZone;
  final double fastZone;
  final bool showFastMarkers;
  final Color fillColor;
  final bool isActive;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2.0;
    final r = Radius.circular(size.height / 2.0);

    // ── Background track ──────────────────────────────────────────────────
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), r),
      Paint()..color = const Color.fromARGB(255, 255, 252, 252),
    );

    // ── Active fill (centre → thumb) ──────────────────────────────────────
    if (isActive && value.abs() > deadZone) {
      final thumbX = cx + value * halfTrack;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            math.min(cx, thumbX),
            0,
            math.max(cx, thumbX),
            size.height,
          ),
          r,
        ),
        Paint()..color = fillColor,
      );
    }

    // ── Zone boundary markers ─────────────────────────────────────────────
    final markerPaint = Paint()
      ..color = const Color.fromARGB(255, 192, 25, 25).withAlpha(255)
      ..strokeWidth = 1.0;
    for (final sign in [-1.0, 1.0]) {
      // Dead zone edge
      final dx = cx + sign * deadZone * halfTrack;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), markerPaint);
      if (showFastMarkers) {
        // Fast zone edge
        final fx = cx + sign * fastZone * halfTrack;
        canvas.drawLine(Offset(fx, 0), Offset(fx, size.height), markerPaint);
      }
    }

    // ── Centre tick ───────────────────────────────────────────────────────
    canvas.drawLine(
      Offset(cx, -3),
      Offset(cx, size.height + 3),
      Paint()
        ..color = Colors.white.withAlpha(100)
        ..strokeWidth = 2.0,
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.value != value ||
      old.showFastMarkers != showFastMarkers ||
      old.fillColor != fillColor ||
      old.isActive != isActive;
}

// ─────────────────────────────────────────────────────────────────────────────
// Thumb
// ─────────────────────────────────────────────────────────────────────────────

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.width,
    required this.height,
    required this.color,
    required this.isDragging,
    required this.isDisabled,
  });

  final double width;
  final double height;
  final Color color;
  final bool isDragging;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    final borderColor = isDisabled
        ? AppColors.idleColor
        : isDragging
        ? color
        : color.withAlpha(160);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDisabled
            ? AppColors.darkBg
            : isDragging
            ? color.withAlpha(28)
            : AppColors.darkBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: isDragging ? 2.5 : 1.5),
        boxShadow: isDragging && !isDisabled
            ? [
                BoxShadow(
                  color: color.withAlpha(85),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ]
            : const [],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _grip(0),
          const SizedBox(height: 5),
          _grip(1),
          const SizedBox(height: 5),
          _grip(2),
        ],
      ),
    );
  }

  Widget _grip(int _) => Container(
    width: width * 0.38,
    height: 2,
    decoration: BoxDecoration(
      color: isDisabled ? AppColors.idleColor : color.withAlpha(160),
      borderRadius: BorderRadius.circular(1),
    ),
  );
}
