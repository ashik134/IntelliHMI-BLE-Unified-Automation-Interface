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
    this.deadZone = kMultiZoneSliderDefaultDeadZone,
    this.farZone = kMultiZoneSliderDefaultFarZone,
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

  /// Fraction of half-track (from centre) treated as the neutral/idle dead
  /// band. See [kMultiZoneSliderDefaultDeadZone].
  final double deadZone;

  /// Fraction of half-track beyond which a five-zone slider reports the far
  /// (zone1/zone5) rather than near (zone2/zone4) state. Unused in
  /// three-zone mode. See [kMultiZoneSliderDefaultFarZone].
  final double farZone;

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
      deadZone: deadZone,
      farZone: farZone,
      isStartZoneBlocked: isStartZoneBlocked,
      isEndZoneBlocked: isEndZoneBlocked,
      onStateChanged: onStateChanged,
    );
  }
}

/// Default centre dead-band, matching this widget's original hardcoded
/// constant — every existing (never-customized) placement renders identically.
const double kMultiZoneSliderDefaultDeadZone = 0.12;

/// Default near/far zone boundary (five-zone mode only), matching this
/// widget's original hardcoded constant.
const double kMultiZoneSliderDefaultFarZone = 0.62;

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
    this.deadZone = kMultiZoneSliderDefaultDeadZone,
    this.farZone = kMultiZoneSliderDefaultFarZone,
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
  final double deadZone;
  final double farZone;
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
  static const double _thumbHitSlop = 12.0;

  /// Normalised thumb position: -1.0 = full negative · 0.0 = centre · +1.0 = full positive
  double _value = 0.0;
  bool _isDragging = false;
  bool _pointerStartedOnThumb = false;
  String _stateId = MultiZoneSliderStateId.center;

  bool _suppressExternalReactivation = false;

  late final AnimationController _springCtrl;

  // ── Thresholds (fraction of half-track from centre) ──────────────────────
  // Sourced from widget.deadZone/widget.farZone (see MultiZoneSliderConfig) —
  // these accessors keep every reference below unchanged in shape.
  double get _deadZone => widget.deadZone;
  double get _farZone => widget.farZone;

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
        _pointerStartedOnThumb = false;
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
    _springCtrl.stop();
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
    if (zoneId == MultiZoneSliderStateId.center) {
      Vibration.vibrate(duration: 15);
    } else {
      final isFarZone =
          zoneId == MultiZoneSliderStateId.zone1 ||
          zoneId == MultiZoneSliderStateId.zone5;
      Vibration.vibrate(
        duration: isFarZone ? 55 : 25,
        amplitude: isFarZone ? 255 : 100,
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
    if (_value == 0.0) {
      _springCtrl.stop();
      return;
    }

    _springCtrl.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 0.5, stiffness: 280.0, damping: 20.0),
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
    if (!widget.enabled || !_pointerStartedOnThumb || halfTrack <= 0) return;
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
    if (!_isDragging) {
      _pointerStartedOnThumb = false;
      return;
    }
    ButtonStateLog.log('USER_UP [${widget.startLabel}/${widget.endLabel}]');
    _release();
  }

  void _dragCancel() {
    if (!_isDragging) {
      _pointerStartedOnThumb = false;
      return;
    }
    ButtonStateLog.log('USER_CANCEL [${widget.startLabel}/${widget.endLabel}]');
    _release();
  }

  void _release() {
    if (!_isDragging) return;
    setState(() => _isDragging = false);
    _pointerStartedOnThumb = false;
    _emitZone(
      MultiZoneSliderStateId.center,
    ); // Safety: emit centre immediately.
    // Arm the guard so a stale external update cannot reactivate the slider
    // until the next fresh pointer interaction.
    _suppressExternalReactivation = true;
    _springReturn();
  }

  Rect _thumbHitRect({
    required double trackLength,
    required double laneWidth,
    required double thumbW,
    required double thumbH,
  }) {
    final travel = (trackLength - thumbW).clamp(0.0, trackLength).toDouble();
    final thumbCenterX = thumbW / 2.0 + ((_value + 1.0) / 2.0) * travel;
    final hitWidth = (thumbW + _thumbHitSlop * 2)
        .clamp(48.0, trackLength)
        .toDouble();
    final hitHeight = (thumbH + _thumbHitSlop * 2)
        .clamp(48.0, laneWidth)
        .toDouble();
    return Rect.fromCenter(
      center: Offset(thumbCenterX, laneWidth / 2.0),
      width: hitWidth,
      height: hitHeight,
    );
  }

  void _onPointerDown(
    PointerDownEvent event, {
    required double trackLength,
    required double laneWidth,
    required double thumbW,
    required double thumbH,
  }) {
    _pointerStartedOnThumb =
        widget.enabled &&
        _thumbHitRect(
          trackLength: trackLength,
          laneWidth: laneWidth,
          thumbW: thumbW,
          thumbH: thumbH,
        ).contains(event.localPosition);
  }

  void _onPointerUp(PointerUpEvent _) {
    if (!_isDragging) _pointerStartedOnThumb = false;
  }

  void _onPointerCancel(PointerCancelEvent _) {
    _pointerStartedOnThumb = false;
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

  Color get _overlayColor {
    if (!widget.enabled) return Colors.transparent;
    if (_stateId == MultiZoneSliderStateId.center) {
      return AppColors.idleColor.withAlpha(35);
    }
    return _isFarZone
        ? _farColor.withAlpha(55)
        : _nearColor.withAlpha(50);
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
    final laneWidth = h.clamp(56.0, 72.0).toDouble();
    final thumbW = (laneWidth * 0.58).clamp(0.0, 36.0).toDouble();
    final thumbH = (laneWidth * 0.82).clamp(0.0, 52.0).toDouble();
    final trackH = (laneWidth * 0.28).clamp(0.0, 16.0).toDouble();
    const footerHeight = ControlButtonVisualMetrics.rowHeight;
    final bodyHeight = math.max(0.0, h - footerHeight - 6);

    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.55,
      child: SizedBox(
        width: w,
        height: h,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: w,
              height: bodyHeight,
              child: Center(
                child: SizedBox(
                  width: w,
                  height: laneWidth,
                  child: _buildSliderStage(
                    trackLength: w,
                    laneWidth: laneWidth,
                    thumbW: thumbW,
                    thumbH: thumbH,
                    trackH: trackH,
                  ),
                ),
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
    );
  }

  Widget _buildSliderStage({
    required double trackLength,
    required double laneWidth,
    required double thumbW,
    required double thumbH,
    required double trackH,
  }) {
    if (trackLength <= 0 || laneWidth <= 0) {
      return const SizedBox.shrink();
    }

    final trackWidth = (trackLength - thumbW)
        .clamp(0.0, trackLength)
        .toDouble();
    final halfTrack = trackWidth / 2.0;
    final thumbCenterX =
        thumbW / 2.0 + ((_value + 1.0) / 2.0) * trackWidth;
    final hitWidth = (thumbW + _thumbHitSlop * 2)
        .clamp(48.0, trackLength)
        .toDouble();
    final hitHeight = (thumbH + _thumbHitSlop * 2)
        .clamp(48.0, laneWidth)
        .toDouble();

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) => _onPointerDown(
        event,
        trackLength: trackLength,
        laneWidth: laneWidth,
        thumbW: thumbW,
        thumbH: thumbH,
      ),
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (details) => _dragStart(details, halfTrack),
        onHorizontalDragUpdate: (details) => _dragUpdate(details, halfTrack),
        onHorizontalDragEnd: _dragEnd,
        onHorizontalDragCancel: _dragCancel,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            IgnorePointer(
              child: CustomPaint(
                size: Size(trackLength, laneWidth),
                painter: _TrackPainter(
                  value: _value,
                  thumbWidth: thumbW,
                  trackHeight: trackH,
                  deadZone: _deadZone,
                  farZone: _farZone,
                  showFarMarkers: widget.isFiveZone,
                  fillColor: _trackColor.withAlpha(widget.enabled ? 200 : 70),
                  isActive: widget.enabled,
                ),
              ),
            ),
            Positioned(
              left: thumbCenterX - hitWidth / 2.0,
              top: (laneWidth - hitHeight) / 2.0,
              width: hitWidth,
              height: hitHeight,
              child: Center(
                child: _Thumb(
                  key: const ValueKey('multi_zone_slider_thumb'),
                  width: thumbW,
                  height: thumbH,
                  color: _trackColor,
                  overlayColor: _overlayColor,
                  isDragging: _isDragging,
                  isDisabled: !widget.enabled,
                ),
              ),
            ),
          ],
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
    required this.thumbWidth,
    required this.trackHeight,
    required this.deadZone,
    required this.farZone,
    required this.showFarMarkers,
    required this.fillColor,
    required this.isActive,
  });

  final double value;
  final double thumbWidth;
  final double trackHeight;
  final double deadZone;
  final double farZone;
  final bool showFarMarkers;
  final Color fillColor;
  final bool isActive;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || trackHeight <= 0) return;
    final trackLeft = thumbWidth / 2.0;
    final trackRight = size.width - thumbWidth / 2.0;
    if (trackRight <= trackLeft) return;
    final trackWidth = trackRight - trackLeft;
    final cx = size.width / 2.0;
    final trackTop = (size.height - trackHeight) / 2.0;
    final r = Radius.circular(trackHeight / 2.0);
    final trackRect = Rect.fromLTWH(
      trackLeft,
      trackTop,
      trackWidth,
      trackHeight,
    );

    // ── Background track ──────────────────────────────────────────────────
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, r),
      Paint()..color = const Color.fromARGB(255, 255, 252, 252),
    );

    // ── Active fill (centre → thumb) ──────────────────────────────────────
    if (isActive && value.abs() > deadZone) {
      final thumbX = cx + value * trackWidth / 2.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            math.min(cx, thumbX),
            trackTop,
            math.max(cx, thumbX),
            trackTop + trackHeight,
          ),
          r,
        ),
        Paint()..color = fillColor,
      );
    }

    // ── Zone boundary markers ─────────────────────────────────────────────
    final markerPaint = Paint()
      ..color = AppColors.darkBorder.withAlpha(180)
      ..strokeWidth = 1.0;
    for (final sign in [-1.0, 1.0]) {
      // Dead zone edge
      final dx = cx + sign * deadZone * trackWidth / 2.0;
      canvas.drawLine(
        Offset(dx, trackTop),
        Offset(dx, trackTop + trackHeight),
        markerPaint,
      );
      if (showFarMarkers) {
        // Far zone edge
        final fx = cx + sign * farZone * trackWidth / 2.0;
        canvas.drawLine(
          Offset(fx, trackTop),
          Offset(fx, trackTop + trackHeight),
          markerPaint,
        );
      }
    }

    // ── Centre tick ───────────────────────────────────────────────────────
    canvas.drawLine(
      Offset(cx, trackTop),
      Offset(cx, trackTop + trackHeight),
      Paint()
        ..color = Colors.white.withAlpha(100)
        ..strokeWidth = 2.0,
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.value != value ||
      old.thumbWidth != thumbWidth ||
      old.trackHeight != trackHeight ||
      old.deadZone != deadZone ||
      old.farZone != farZone ||
      old.showFarMarkers != showFarMarkers ||
      old.fillColor != fillColor ||
      old.isActive != isActive;
}

// ─────────────────────────────────────────────────────────────────────────────
// Thumb
// ─────────────────────────────────────────────────────────────────────────────

class _Thumb extends StatelessWidget {
  const _Thumb({
    super.key,
    required this.width,
    required this.height,
    required this.color,
    required this.overlayColor,
    required this.isDragging,
    required this.isDisabled,
  });

  final double width;
  final double height;
  final Color color;
  final Color overlayColor;
  final bool isDragging;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _ThumbPainter(
        width: width,
        height: height,
        color: color,
        overlayColor: overlayColor,
        isDragging: isDragging,
        isDisabled: isDisabled,
      ),
    );
  }
}

class _ThumbPainter extends CustomPainter {
  const _ThumbPainter({
    required this.width,
    required this.height,
    required this.color,
    required this.overlayColor,
    required this.isDragging,
    required this.isDisabled,
  });

  final double width;
  final double height;
  final Color color;
  final Color overlayColor;
  final bool isDragging;
  final bool isDisabled;

  @override
  void paint(Canvas canvas, Size size) {
    if (width <= 0 || height <= 0) return;
    final center = Offset(width / 2.0, height / 2.0);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: width, height: height),
      const Radius.circular(6),
    );
    final borderColor = isDisabled
        ? AppColors.idleColor
        : isDragging
        ? color
        : color.withAlpha(160);
    final fillColor = isDisabled
        ? AppColors.darkBg
        : isDragging
        ? color.withAlpha(28)
        : AppColors.darkBg;

    if (isDragging && !isDisabled) {
      canvas.drawRRect(
        rect.inflate(2),
        Paint()
          ..color = overlayColor
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
    canvas.drawRRect(rect, Paint()..color = fillColor);
    canvas.drawRRect(
      rect,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = isDragging ? 2.5 : 1.5,
    );

    final gripPaint = Paint()
      ..color = isDisabled ? AppColors.idleColor : color.withAlpha(160);
    final gripHeight = height * 0.38;
    final spacing = width * 0.16;
    for (final dx in [-spacing, 0.0, spacing]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(center.dx + dx, center.dy),
            width: 2,
            height: gripHeight,
          ),
          const Radius.circular(1),
        ),
        gripPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ThumbPainter old) =>
      old.width != width ||
      old.height != height ||
      old.color != color ||
      old.overlayColor != overlayColor ||
      old.isDragging != isDragging ||
      old.isDisabled != isDisabled;
}
