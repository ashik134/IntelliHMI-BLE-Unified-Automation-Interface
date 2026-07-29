import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:vibration/vibration.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/button_state_log.dart';
import 'package:rev_crane_control_ops/widgets/buttons/control_button_visuals.dart';

// ── Generic zone ids ─────────────────────────────────────────────────────────
//
// These are the ONLY values this widget ever emits. They are plain logical
// state ids — exactly the same shape as any other button type's stateId
// (see ButtonTypeLogicalStates) — with no notion of direction (left/right),
// speed (slow/fast), or any crane-specific concept baked in. A caller wires
// [MultiZoneSliderButton.onZoneChanged] to whatever it wants (typically
// ButtonConfig.stateMappings lookups performed by a ButtonTypeStrategy) —
// this widget never resolves or asserts a PLC output itself.

/// Zone id for the resting/dead-zone position, in both variants.
const String kZoneCenter = 'center';

/// Zone ids for [MultiZoneSliderVariant.threeZone] (one zone per side) and
/// the near/inner zones of [MultiZoneSliderVariant.fiveZone].
const String kZone1 = 'zone1';
const String kZone2 = 'zone2';
const String kZone3 = 'zone3';
const String kZone4 = 'zone4';
const String kZone5 = 'zone5';

enum MultiZoneSliderVariant { fiveZone, threeZone }

// ─────────────────────────────────────────────────────────────────────────────
// MultiZoneSliderButton
//
// A generic drag-to-zone slider: the operator drags a thumb along a
// horizontal track and this widget reports which discrete zone the thumb
// currently sits in via [onZoneChanged]. It owns UI, gesture handling, zone
// math, and its own visual state only — it never decides what a zone means
// (that is entirely up to the caller, via ButtonConfig.stateMappings) and
// never composes or sends any PLC/BLE output itself.
// ─────────────────────────────────────────────────────────────────────────────

class MultiZoneSliderButton extends StatefulWidget {
  final bool isDisabled;

  /// Label for the negative-drag end of the track (drawn on the left).
  final String startLabel;

  /// Label for the positive-drag end of the track (drawn on the right).
  final String endLabel;

  /// Fires whenever the reported zone changes: one of [kZoneCenter],
  /// [kZone1]/[kZone2]/[kZone4]/[kZone5] (five-zone) or [kZoneCenter]/
  /// [kZone1]/[kZone3] (three-zone).
  final void Function(String zoneId) onZoneChanged;

  final MultiZoneSliderVariant variant;

  /// True blocks the thumb from entering the negative (start-side) zone(s) —
  /// used when an external owner already claims that zone's output.
  final bool isStartZoneBlocked;

  /// True blocks the thumb from entering the positive (end-side) zone(s).
  final bool isEndZoneBlocked;

  const MultiZoneSliderButton({
    super.key,
    this.isDisabled = false,
    this.startLabel = 'LEFT',
    this.endLabel = 'RIGHT',
    this.variant = MultiZoneSliderVariant.fiveZone,
    this.isStartZoneBlocked = false,
    this.isEndZoneBlocked = false,
    required this.onZoneChanged,
  });

  @override
  State<MultiZoneSliderButton> createState() => _MultiZoneSliderButtonState();
}

class _MultiZoneSliderButtonState extends State<MultiZoneSliderButton>
    with SingleTickerProviderStateMixin {
  /// Normalised thumb position: -1.0 = full negative · 0.0 = centre · +1.0 = full positive
  double _value = 0.0;
  bool _isDragging = false;
  String _lastEmitted = kZoneCenter;

  late final AnimationController _springCtrl;

  // ── Thresholds (fraction of half-track from centre) ──────────────────────
  static const double _deadZone = 0.12; // ±12 % → centre dead band
  static const double _farZone = 0.62; // beyond ±62 % → outer zone

  // Margin applied when clamping to the dead-zone boundary so the value stays
  // strictly INSIDE the centre region (abs < _deadZone), preventing the zone
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
  void didUpdateWidget(MultiZoneSliderButton old) {
    super.didUpdateWidget(old);
    // Snap to centre whenever the widget becomes disabled (e-stop / disconnect).
    if (widget.isDisabled && !old.isDisabled) {
      _springCtrl.stop();
      // If disabled mid-drag, emit centre before clearing _isDragging.
      // Without this, _release() will bail on `if (!_isDragging) return`
      // and the caller's ownership bookkeeping stays permanently claimed,
      // which keeps isDisabled=true even after the operator releases.
      if (_isDragging && _lastEmitted != kZoneCenter) {
        widget.onZoneChanged(kZoneCenter);
      }
      setState(() {
        _value = 0.0;
        _isDragging = false;
        _lastEmitted = kZoneCenter;
      });
      return;
    }

    // Push the thumb back inside the dead zone if a zone just became blocked
    // mid-drag (e.g. a sibling slider claimed ownership of a shared output).
    // The ownership system prevents two sliders from both being in their
    // blocked zones simultaneously, so this path is a defensive safeguard.
    if (_isDragging) {
      var clamped = _value;
      if (widget.isEndZoneBlocked && _value >= _deadZone) {
        clamped = _deadZone - _zoneClampMargin;
      }
      if (widget.isStartZoneBlocked && _value <= -_deadZone) {
        clamped = -_deadZone + _zoneClampMargin;
      }
      if (clamped != _value) {
        setState(() => _value = clamped);
        _emitZone(_zoneIdFor(clamped)); // emits centre since clamped < _deadZone
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

  String _zoneIdFor(double v) {
    if (widget.isDisabled) return kZoneCenter;
    final abs = v.abs();
    if (abs < _deadZone) return kZoneCenter;
    final isNegativeSide = v < 0;
    if (widget.variant == MultiZoneSliderVariant.threeZone) {
      return isNegativeSide ? kZone1 : kZone3;
    }
    final isFarZone = abs >= _farZone;
    if (isNegativeSide) return isFarZone ? kZone1 : kZone2;
    return isFarZone ? kZone5 : kZone4;
  }

  void _emitZone(String zoneId) {
    if (zoneId == _lastEmitted) return;
    _lastEmitted = zoneId;
    ButtonStateLog.log(
      '${zoneId == kZoneCenter ? 'VISUAL_IDLE / SEND_IDLE' : 'VISUAL_ACTIVE / SEND_ACTIVE'} '
      '[${widget.startLabel}/${widget.endLabel}] -> $zoneId',
    );
    if (zoneId != kZoneCenter) {
      final isFarZone = zoneId == kZone1 || zoneId == kZone5;
      Vibration.vibrate(
        duration: isFarZone ? 28 : 18,
        amplitude: isFarZone ? 180 : 80,
      );
    }
    widget.onZoneChanged(zoneId);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Spring physics
  // ─────────────────────────────────────────────────────────────────────────

  void _onSpringTick() {
    if (_isDragging) return;
    setState(() => _value = _springCtrl.value.clamp(-1.0, 1.0));
    // No zone emissions during visual return — centre was already emitted on release.
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
    ButtonStateLog.log('USER_DOWN [${widget.startLabel}/${widget.endLabel}]');
    _springCtrl.stop();
    setState(() => _isDragging = true);
  }

  void _dragUpdate(DragUpdateDetails details, double halfTrack) {
    if (!_isDragging || widget.isDisabled) return;
    final delta = halfTrack > 0 ? details.delta.dx / halfTrack : 0.0;
    var newValue = (_value + delta).clamp(-1.0, 1.0);

    // Clamp at the dead-zone boundary when the zone is locked by another
    // owner claiming the same output. Keeping the value strictly inside the
    // dead zone (abs < _deadZone) ensures the zone check returns centre so
    // no zone change is emitted in the blocked direction.
    if (widget.isEndZoneBlocked && newValue >= _deadZone) {
      newValue = _deadZone - _zoneClampMargin;
    }
    if (widget.isStartZoneBlocked && newValue <= -_deadZone) {
      newValue = -_deadZone + _zoneClampMargin;
    }

    setState(() => _value = newValue);
    _emitZone(_zoneIdFor(_value));
  }

  void _dragEnd(DragEndDetails _) {
    ButtonStateLog.log('USER_UP [${widget.startLabel}/${widget.endLabel}]');
    _release();
  }

  void _dragCancel() {
    ButtonStateLog.log('USER_CANCEL [${widget.startLabel}/${widget.endLabel}]');
    _release();
  }

  void _release() {
    if (!_isDragging) return;
    setState(() => _isDragging = false);
    _emitZone(kZoneCenter); // Safety: emit centre immediately on release.
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

        final zoneId = _zoneIdFor(_value);
        final isFarZone = zoneId == kZone1 || zoneId == kZone5;
        final isStartActive = zoneId == kZone1 || zoneId == kZone2;
        final isEndActive = zoneId == kZone4 || zoneId == kZone5;
        final isThreeZone = widget.variant == MultiZoneSliderVariant.threeZone;

        final Color trackColor = widget.isDisabled
            ? AppColors.idleColor
            : isFarZone
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
                  child: isThreeZone
                      ? Row(
                          children: [
                            _zoneLabel(
                              '< ${widget.startLabel}',
                              zoneId == kZone1,
                              AppColors.traverseColor,
                            ),
                            const Spacer(),
                            _zoneLabel(
                              'ACTIVE',
                              isStartActive || isEndActive,
                              AppColors.traverseColor,
                            ),
                            const Spacer(),
                            _zoneLabel(
                              '${widget.endLabel} >',
                              zoneId == kZone3,
                              AppColors.traverseColor,
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            _zoneLabel(
                              '< ${widget.startLabel}',
                              zoneId == kZone1,
                              AppColors.fastColor,
                            ),
                            const Spacer(),
                            _zoneLabel(
                              'ZONE 2',
                              zoneId == kZone2,
                              AppColors.traverseColor,
                            ),
                            const SizedBox(width: 10),
                            _zoneLabel(
                              'ZONE 4',
                              zoneId == kZone4,
                              AppColors.traverseColor,
                            ),
                            const Spacer(),
                            _zoneLabel(
                              '${widget.endLabel} >',
                              zoneId == kZone5,
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
                          farZone: _farZone,
                          showFarMarkers: !isThreeZone,
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

                // ── Endpoint labels (bottom row) ────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      _endpointLabel(
                        widget.startLabel,
                        Icons.arrow_back_rounded,
                        isStartActive || zoneId == kZone1,
                      ),
                      const SizedBox(width: 8),
                      _statusDot(zoneId, trackColor),
                      const SizedBox(width: 8),
                      _endpointLabel(
                        widget.endLabel,
                        Icons.arrow_forward_rounded,
                        isEndActive || zoneId == kZone3,
                      ),
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
    return Flexible(
      fit: FlexFit.loose,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        textAlign: TextAlign.center,
        style: ControlButtonVisualMetrics.labelTextStyle(
          color: active ? color : AppColors.darkTextMuted.withAlpha(90),
          bounds: const Size(96, ControlButtonVisualMetrics.rowHeight),
        ),
      ),
    );
  }

  Widget _endpointLabel(String text, IconData icon, bool active) {
    return Expanded(
      child: SizedBox(
        height: ControlButtonVisualMetrics.rowHeight,
        child: ControlButtonLabelIcon(
          label: text,
          icon: icon,
          color: active ? AppColors.traverseColorLight : AppColors.darkText,
          iconColor: active
              ? AppColors.traverseColorLight
              : AppColors.darkTextMuted,
        ),
      ),
    );
  }

  Widget _statusDot(String zoneId, Color activeColor) {
    if (widget.isDisabled) {
      return const Text(
        '— DISABLED —',
        style: TextStyle(fontSize: 7, color: AppColors.darkTextMuted),
      );
    }
    final isIdle = zoneId == kZoneCenter;
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
    required this.farZone,
    required this.showFarMarkers,
    required this.fillColor,
    required this.isActive,
  });

  final double value;
  final double halfTrack;
  final double deadZone;
  final double farZone;
  final bool showFarMarkers;
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
      if (showFarMarkers) {
        // Far zone edge
        final fx = cx + sign * farZone * halfTrack;
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
      old.showFarMarkers != showFarMarkers ||
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
