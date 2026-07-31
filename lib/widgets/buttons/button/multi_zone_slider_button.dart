import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:vibration/vibration.dart';

import 'package:rev_crane_control_ops/models/button_rotation.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/utils/button_state_log.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/widgets/buttons/control_button_visuals.dart';

abstract final class MultiZoneSliderStateId {
  static const String center = 'center';
  static const String zone1 = 'zone1';
  static const String zone2 = 'zone2';
  static const String zone3 = 'zone3';
  static const String zone4 = 'zone4';
  static const String zone5 = 'zone5';

  static const Set<String> fiveZoneValues = {
    center,
    zone1,
    zone2,
    zone4,
    zone5,
  };
  static const Set<String> threeZoneValues = {center, zone1, zone3};

  static String normalize(String stateId, {required bool fiveZone}) {
    final values = fiveZone ? fiveZoneValues : threeZoneValues;
    return values.contains(stateId) ? stateId : center;
  }
}

enum MultiZoneSliderVariant { fiveZone, threeZone }

// ─────────────────────────────────────────────────────────────────────────────
// MultiZoneSliderButton

class MultiZoneSliderButton extends StatelessWidget {
  const MultiZoneSliderButton({
    super.key,
    required this.startLabel,
    required this.endLabel,
    required this.startIcon,
    required this.endIcon,
    this.isDisabled = false,
    this.externalStateId = MultiZoneSliderStateId.center,
    this.variant = MultiZoneSliderVariant.fiveZone,
    this.nearColor,
    this.farColor,
    this.style,
    this.rotation = ButtonRotation.none,
    this.isStartZoneBlocked = false,
    this.isEndZoneBlocked = false,
    required this.onStateChanged,
  });

  /// Label for the negative-drag end of the track.
  final String startLabel;

  /// Label for the positive-drag end of the track.
  final String endLabel;

  final IconData startIcon;
  final IconData endIcon;

  final bool isDisabled;

  /// Externally-reported zone id (e.g. PLC-confirmed state), applied only
  /// while the operator isn't actively dragging — mirrors
  /// IndustrialMultiStepSlider's externalStateId sync.
  final String externalStateId;

  final MultiZoneSliderVariant variant;

  /// Color for the near/center-adjacent zones (zone2/zone4, or zone1/zone3
  /// in three-zone mode). Defaults to [AppColors.accent]. Callers that want
  /// role-specific theming (e.g. the crane traverse role buttons) pass an
  /// explicit override.
  final Color? nearColor;

  /// Color for the far/outermost zones (zone1/zone5). Defaults to
  /// [AppColors.fastColor]. Unused in three-zone mode.
  final Color? farColor;

  final ButtonStyleConfig? style;

  final ButtonRotation rotation;

  /// True blocks the thumb from entering the negative (start-side) zone(s) —
  /// used when an external owner already claims that zone's output.
  final bool isStartZoneBlocked;

  /// True blocks the thumb from entering the positive (end-side) zone(s).
  final bool isEndZoneBlocked;

  /// Fires whenever the reported zone changes: one of [MultiZoneSliderStateId]
  /// values for [variant].
  final ValueChanged<String> onStateChanged;

  @override
  Widget build(BuildContext context) {
    final fiveZone = variant == MultiZoneSliderVariant.fiveZone;
    return IndustrialMultiZoneSlider(
      startLabel: startLabel,
      endLabel: endLabel,
      startIcon: startIcon,
      endIcon: endIcon,
      enabled: !isDisabled,
      stateId: MultiZoneSliderStateId.normalize(
        externalStateId,
        fiveZone: fiveZone,
      ),
      variant: variant,
      nearColor: nearColor,
      farColor: farColor,
      style: style,
      rotation: rotation,
      isStartZoneBlocked: isStartZoneBlocked,
      isEndZoneBlocked: isEndZoneBlocked,
      onStateChanged: onStateChanged,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// IndustrialMultiZoneSlider
//
// Reusable industrial multi-zone drag surface: the operator drags a thumb
// along a track and this widget reports which discrete zone the thumb
// currently sits in via [onStateChanged]. It owns presentation, drag
// gesture handling, zone math, spring-return physics, haptics, and local
// visual state only — it never decides what a zone MEANS (entirely up to
// the caller, via ButtonConfig.stateMappings) and never composes or sends
// any PLC/BLE output itself. Auto-orients horizontally or vertically to fit
// whatever bounds it's given (see build()'s RotatedBox use, matching
// MultiStepSliderButton's own technique for a vertical layout).
// ─────────────────────────────────────────────────────────────────────────────

class IndustrialMultiZoneSlider extends StatefulWidget {
  const IndustrialMultiZoneSlider({
    super.key,
    required this.startLabel,
    required this.endLabel,
    required this.startIcon,
    required this.endIcon,
    this.enabled = true,
    this.stateId = MultiZoneSliderStateId.center,
    this.variant = MultiZoneSliderVariant.fiveZone,
    this.nearColor,
    this.farColor,
    this.style,
    this.rotation = ButtonRotation.none,
    this.isStartZoneBlocked = false,
    this.isEndZoneBlocked = false,
    required this.onStateChanged,
  });

  final String startLabel;
  final String endLabel;
  final IconData startIcon;
  final IconData endIcon;
  final bool enabled;
  final String stateId;
  final MultiZoneSliderVariant variant;
  final Color? nearColor;
  final Color? farColor;
  final ButtonStyleConfig? style;
  final ButtonRotation rotation;
  final bool isStartZoneBlocked;
  final bool isEndZoneBlocked;
  final ValueChanged<String> onStateChanged;

  bool get isFiveZone => variant == MultiZoneSliderVariant.fiveZone;

  @override
  State<IndustrialMultiZoneSlider> createState() =>
      _IndustrialMultiZoneSliderState();
}

class _IndustrialMultiZoneSliderState extends State<IndustrialMultiZoneSlider>
    with SingleTickerProviderStateMixin {
  /// Normalised thumb position: -1.0 = full negative · 0.0 = centre · +1.0 = full positive
  double _value = 0.0;
  bool _isDragging = false;
  String _stateId = MultiZoneSliderStateId.center;

  bool _suppressExternalReactivation = false;

  late final AnimationController _springCtrl;

  // ── Thresholds (fraction of half-track from centre) ──────────────────────
  static const double _deadZone = 0.12; // ±12 % → centre dead band
  static const double _farZone = 0.62; // beyond ±62 % → far/outer zone

  // Margin applied when clamping to the dead-zone boundary so the value stays
  // strictly INSIDE the centre region (abs < _deadZone), preventing the zone
  // check from firing at the exact boundary value.
  static const double _zoneClampMargin = 0.001;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _springCtrl = AnimationController.unbounded(vsync: this)
      ..addListener(_onSpringTick);
    _syncFromExternalStateId(widget.stateId);
  }

  @override
  void didUpdateWidget(covariant IndustrialMultiZoneSlider old) {
    super.didUpdateWidget(old);

    // Snap to centre whenever the widget becomes disabled (e-stop / disconnect).
    if (!widget.enabled && old.enabled) {
      _springCtrl.stop();
      // If disabled mid-drag, emit centre before clearing _isDragging.
      // Without this, _release() will bail on `if (!_isDragging) return`
      // and the caller's ownership bookkeeping stays permanently claimed,
      // which keeps isDisabled=true even after the operator releases.
      if (_isDragging && _stateId != MultiZoneSliderStateId.center) {
        widget.onStateChanged(MultiZoneSliderStateId.center);
      }
      setState(() {
        _value = 0.0;
        _isDragging = false;
        _stateId = MultiZoneSliderStateId.center;
      });
      return;
    }

    // Push the thumb back inside the dead zone if a zone just became blocked
    // mid-drag (e.g. a sibling control claimed ownership of a shared output).
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
        _emitZone(
          _zoneIdFor(clamped),
        ); // emits centre since clamped < _deadZone
      }
      return;
    }

    if (widget.stateId == old.stateId) return;

    if (_suppressExternalReactivation &&
        MultiZoneSliderStateId.normalize(
              widget.stateId,
              fiveZone: widget.isFiveZone,
            ) !=
            MultiZoneSliderStateId.center) {
      ButtonStateLog.log(
        'EXTERNAL_STATE_ACTIVE ignored (stale, post-release) '
        '[${widget.startLabel}/${widget.endLabel}]',
      );
      return;
    }

    _syncFromExternalStateId(widget.stateId);
  }

  @override
  void dispose() {
    _springCtrl.dispose();
    super.dispose();
  }

  void _syncFromExternalStateId(String externalStateId) {
    final stateId = MultiZoneSliderStateId.normalize(
      externalStateId,
      fiveZone: widget.isFiveZone,
    );
    if (stateId != _stateId) {
      ButtonStateLog.log(
        '${stateId == MultiZoneSliderStateId.center ? 'VISUAL_IDLE' : 'VISUAL_ACTIVE'} '
        '[${widget.startLabel}/${widget.endLabel}] (external) -> $stateId',
      );
    }
    setState(() {
      _stateId = stateId;
      _value = _valueForStateId(stateId);
    });
  }

  double _valueForStateId(String stateId) {
    if (!widget.isFiveZone) {
      return switch (stateId) {
        MultiZoneSliderStateId.zone1 => -0.5,
        MultiZoneSliderStateId.zone3 => 0.5,
        _ => 0.0,
      };
    }
    return switch (stateId) {
      MultiZoneSliderStateId.zone1 => -0.85,
      MultiZoneSliderStateId.zone2 => -0.35,
      MultiZoneSliderStateId.zone4 => 0.35,
      MultiZoneSliderStateId.zone5 => 0.85,
      _ => 0.0,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Zone logic
  // ─────────────────────────────────────────────────────────────────────────

  String _zoneIdFor(double v) {
    if (!widget.enabled) return MultiZoneSliderStateId.center;
    final abs = v.abs();
    if (abs < _deadZone) return MultiZoneSliderStateId.center;
    final isNegativeSide = v < 0;
    if (!widget.isFiveZone) {
      return isNegativeSide
          ? MultiZoneSliderStateId.zone1
          : MultiZoneSliderStateId.zone3;
    }
    final isFarZone = abs >= _farZone;
    if (isNegativeSide) {
      return isFarZone
          ? MultiZoneSliderStateId.zone1
          : MultiZoneSliderStateId.zone2;
    }
    return isFarZone
        ? MultiZoneSliderStateId.zone5
        : MultiZoneSliderStateId.zone4;
  }

  void _emitZone(String zoneId) {
    if (zoneId == _stateId) return;
    _stateId = zoneId;
    ButtonStateLog.log(
      '${zoneId == MultiZoneSliderStateId.center ? 'VISUAL_IDLE / SEND_IDLE' : 'VISUAL_ACTIVE / SEND_ACTIVE'} '
      '[${widget.startLabel}/${widget.endLabel}] -> $zoneId',
    );
    if (zoneId != MultiZoneSliderStateId.center) {
      final isFarZone =
          zoneId == MultiZoneSliderStateId.zone1 ||
          zoneId == MultiZoneSliderStateId.zone5;
      Vibration.vibrate(
        duration: isFarZone ? 28 : 18,
        amplitude: isFarZone ? 180 : 80,
      );
    }
    widget.onStateChanged(zoneId);
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
    if (!widget.enabled) return;
    ButtonStateLog.log('USER_DOWN [${widget.startLabel}/${widget.endLabel}]');
    _springCtrl.stop();
    _suppressExternalReactivation = false;
    setState(() => _isDragging = true);
  }

  void _dragUpdate(DragUpdateDetails details, double halfTrack) {
    if (!_isDragging || !widget.enabled) return;
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
    _emitZone(
      MultiZoneSliderStateId.center,
    ); // Safety: emit centre immediately.
    // Arm the guard so a stale external update cannot reactivate the slider
    // until the next fresh pointer interaction.
    _suppressExternalReactivation = true;
    _springReturn();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Colors
  // ─────────────────────────────────────────────────────────────────────────

  Color get _nearColor => widget.nearColor ?? AppColors.accent;
  Color get _farColor => widget.farColor ?? AppColors.fastColor;

  bool get _isFarZone =>
      _stateId == MultiZoneSliderStateId.zone1 ||
      _stateId == MultiZoneSliderStateId.zone5;
  bool get _isStartActive =>
      _stateId == MultiZoneSliderStateId.zone1 ||
      _stateId == MultiZoneSliderStateId.zone2;
  bool get _isEndActive =>
      _stateId == MultiZoneSliderStateId.zone4 ||
      _stateId == MultiZoneSliderStateId.zone5;

  Color get _trackColor {
    if (!widget.enabled) return AppColors.idleColor;
    return _isFarZone ? _farColor : _nearColor;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, box) {
        final boundedW = box.maxWidth.isFinite ? box.maxWidth : 220.0;
        final boundedH = box.maxHeight.isFinite ? box.maxHeight : 96.0;
        if (boundedW <= 0 || boundedH <= 0) return const SizedBox.shrink();

        // Auto-orient: a cell noticeably taller than it is wide (e.g. a 1x2
        // vertical grid placement) renders as a vertical drag surface via the
        // same RotatedBox technique MultiStepSliderButton uses for its own
        // always-vertical layout — the inner content is authored exactly as
        // if horizontal (trackLength=boundedH, thickness=boundedW) and
        // rotated into place, so gesture hit-testing is transformed for free.
        final isVertical = boundedH > boundedW * 1.15;
        final trackLength = isVertical ? boundedH : boundedW;
        final thickness = isVertical ? boundedW : boundedH;

        final core = SizedBox(
          width: trackLength,
          height: thickness,
          child: _buildCore(trackLength, thickness),
        );

        return SizedBox(
          width: boundedW,
          height: boundedH,
          child: Center(
            child: isVertical
                ? RotatedBox(quarterTurns: -1, child: core)
                : core,
          ),
        );
      },
    );
  }

  Widget _buildCore(double w, double h) {
    final thumbH = h.clamp(60.0, 200.0) * 0.42;
    final thumbW = (thumbH * 0.68).clamp(22.0, 36.0);
    final trackH = (h * 0.14).clamp(8.0, 16.0);
    final halfTrack = (w - thumbW) / 2.0;
    final thumbCX = w / 2.0 + _value * halfTrack;
    const footerHeight = ControlButtonVisualMetrics.rowHeight;
    final bodyHeight = (h - footerHeight - 6).clamp(thumbH, h);

    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.6,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) => _dragStart(d, halfTrack),
        onHorizontalDragUpdate: (d) => _dragUpdate(d, halfTrack),
        onHorizontalDragEnd: _dragEnd,
        onHorizontalDragCancel: _dragCancel,
        child: SizedBox(
          width: w,
          height: h,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Track + thumb ─────────────────────────────────────────────
              SizedBox(
                width: w,
                height: bodyHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: Size(w, trackH),
                      painter: _TrackPainter(
                        value: _value,
                        halfTrack: halfTrack,
                        deadZone: _deadZone,
                        farZone: _farZone,
                        showFarMarkers: widget.isFiveZone,
                        fillColor: widget.enabled
                            ? _trackColor.withAlpha(200)
                            : AppColors.idleColor.withAlpha(70),
                        isActive: widget.enabled,
                      ),
                    ),
                    Positioned(
                      left: thumbCX - thumbW / 2,
                      child: _Thumb(
                        width: thumbW,
                        height: thumbH,
                        color: _trackColor,
                        isDragging: _isDragging,
                        isDisabled: !widget.enabled,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // ── Endpoint labels (configurable) ──────────────────────────
              SizedBox(
                height: footerHeight,
                child: Row(
                  children: [
                    _endpointLabel(
                      widget.startLabel,
                      widget.startIcon,
                      _isStartActive,
                    ),
                    const SizedBox(width: 6),
                    _statusDot(),
                    const SizedBox(width: 6),
                    _endpointLabel(
                      widget.endLabel,
                      widget.endIcon,
                      _isEndActive,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _endpointLabel(String text, IconData icon, bool active) {
    return Expanded(
      child: ControlButtonLabelIcon(
        label: text,
        icon: icon,
        color: active ? _nearColor : AppColors.darkText,
        iconColor: active ? _nearColor : AppColors.darkTextMuted,
        style: widget.style,
        rotation: widget.rotation,
      ),
    );
  }

  Widget _statusDot() {
    final isCenter = _stateId == MultiZoneSliderStateId.center;
    return Text(
      '●',
      style: TextStyle(
        fontSize: 9,
        color: !widget.enabled
            ? AppColors.darkTextMuted
            : isCenter
            ? AppColors.idleColor
            : _trackColor,
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
          _grip(),
          const SizedBox(height: 4),
          _grip(),
          const SizedBox(height: 4),
          _grip(),
        ],
      ),
    );
  }

  Widget _grip() => Container(
    width: width * 0.38,
    height: 2,
    decoration: BoxDecoration(
      color: isDisabled ? AppColors.idleColor : color.withAlpha(160),
      borderRadius: BorderRadius.circular(1),
    ),
  );
}
