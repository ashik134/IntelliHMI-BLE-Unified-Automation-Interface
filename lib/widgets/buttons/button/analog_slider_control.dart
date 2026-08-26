import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter/physics.dart';

import 'package:flutter/services.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';

import 'package:rev_crane_control_ops/models/analog_slider_config.dart';

import 'package:rev_crane_control_ops/models/button_rotation.dart';

import 'package:rev_crane_control_ops/widgets/buttons/control_button_visuals.dart';

// ─────────────────────────────────────────────────────────────────────────────

// AnalogSliderControl

//

// Continuous linear drag control backing both ButtonType.analogSliderOT and

// .analogSliderTOT — the one-side/two-side distinction is entirely a

// property of where AnalogSliderConfig.neutralValue sits in [minValue,

// maxValue], not a separate rendering mode (an OT config with

// neutral == minValue naturally rests the thumb at one end; a TOT config

// with neutral at the midpoint rests it in the middle). Internal layout is

// always built horizontal, then rotated into place for vertical

// presentation — the same technique IndustrialMultiStepSlider uses.

// ─────────────────────────────────────────────────────────────────────────────

class AnalogSliderControl extends StatefulWidget {
  const AnalogSliderControl({
    super.key,

    required this.config,

    required this.label,

    this.icon,

    required this.activeColor,

    required this.activeColorLight,

    required this.enabled,

    required this.onChanged,

    this.rotation = ButtonRotation.none,

    this.unit,
  });

  final AnalogSliderConfig config;

  final String label;

  final IconData? icon;

  final Color activeColor;

  final Color activeColorLight;

  final ButtonRotation rotation;

  /// Optional display-unit override, for example `mm`, `bar`, `kg`, or `%`.
  /// When omitted, [AnalogSliderConfig.unit] is used.
  final String? unit;

  final bool enabled;

  final ValueChanged<double> onChanged;

  @override
  State<AnalogSliderControl> createState() => _AnalogSliderControlState();
}

class _AnalogSliderControlState extends State<AnalogSliderControl>
    with SingleTickerProviderStateMixin {
  static const double _thumbHitSlop = 12.0;

  static const _spring = SpringDescription(
    mass: 0.5,

    stiffness: 280.0,

    damping: 20.0,
  );

  /// Absolute thumb position in [0, 1] across the full min..max range —

  /// see AnalogRangeMixin.normalizedValueFor/valueForNormalized.

  late double _normalized;

  bool _isDragging = false;

  bool _pointerStartedOnThumb = false;

  late final AnimationController _springCtrl;

  AnalogSliderConfig get _config => widget.config.normalized();

  /// Physical track position (0 = the track's uninverted min-side end) for

  /// [value]. [AnalogSliderConfig.invert] flips which physical end

  /// corresponds to minValue vs maxValue without changing the drag-to-track

  /// mapping itself — see [_valueForTrackPosition] for the inverse.

  double _trackPositionForValue(double value) {
    final t = _config.normalizedValueFor(value);

    return _config.invert ? 1.0 - t : t;
  }

  double _valueForTrackPosition(double normalized) {
    final t = _config.invert ? 1.0 - normalized : normalized;

    return _config.valueForNormalized(t);
  }

  @override
  void initState() {
    super.initState();

    _normalized = _trackPositionForValue(_config.neutralValue);

    _springCtrl = AnimationController.unbounded(vsync: this)
      ..addListener(_onSpringTick);
  }

  @override
  void dispose() {
    _springCtrl.dispose();

    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AnalogSliderControl oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!widget.enabled && oldWidget.enabled) {
      _springCtrl.stop();

      _isDragging = false;

      _pointerStartedOnThumb = false;
    }
  }

  void _emit(double normalized) {
    setState(() => _normalized = normalized);

    widget.onChanged(_valueForTrackPosition(normalized));
  }

  Rect _thumbHitRect({
    required double trackLength,

    required double laneWidth,

    required double thumbW,

    required double thumbH,
  }) {
    final trackWidth = (trackLength - thumbW).clamp(0.0, trackLength);

    final thumbCenterX = thumbW / 2.0 + _normalized * trackWidth;

    // Lower bound must never exceed trackLength/laneWidth — a fine grid

    // preset (e.g. 4x5) can allocate this control less than 48px in either

    // axis, and clamp(lower, upper) throws if lower > upper.

    final hitWidth = (thumbW + _thumbHitSlop * 2)
        .clamp(math.min(48.0, trackLength), trackLength)
        .toDouble();

    final hitHeight = (thumbH + _thumbHitSlop * 2)
        .clamp(math.min(48.0, laneWidth), laneWidth)
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

  void _onDragStart(DragStartDetails _, double trackWidth) {
    if (!widget.enabled || !_pointerStartedOnThumb || trackWidth <= 0) return;

    _springCtrl.stop();

    setState(() => _isDragging = true);

    HapticFeedback.selectionClick();
  }

  void _onDragUpdate(DragUpdateDetails details, double trackWidth) {
    if (!_isDragging || !widget.enabled || trackWidth <= 0) return;

    final next = (_normalized + details.delta.dx / trackWidth)
        .clamp(0.0, 1.0)
        .toDouble();

    _emit(next);
  }

  void _onDragEnd(DragEndDetails _) => _release();

  void _onDragCancel() => _release();

  void _release() {
    if (!_isDragging) {
      _pointerStartedOnThumb = false;

      return;
    }

    setState(() => _isDragging = false);

    _pointerStartedOnThumb = false;

    HapticFeedback.lightImpact();

    if (_config.springReturnEnabled) _springReturn();
  }

  void _springReturn() {
    final target = _trackPositionForValue(_config.neutralValue);

    if ((_normalized - target).abs() < 0.001) return;

    _springCtrl.animateWith(
      SpringSimulation(_spring, _normalized, target, 0.0),
    );
  }

  void _onSpringTick() {
    if (_isDragging) return;

    final next = _springCtrl.value.clamp(0.0, 1.0).toDouble();

    if (next == _normalized) return;

    _emit(next);
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;

    final value = _valueForTrackPosition(_normalized);

    final numberText = value.toStringAsFixed(config.decimalPlaces);

    final unitText = _resolvedAnalogUnit(config, widget.unit);

    final valueText = _formatAnalogValue(
      config,

      value,

      unitOverride: widget.unit,
    );

    return Semantics(
      slider: true,

      enabled: widget.enabled,

      label: widget.label,

      value: valueText,

      child: Opacity(
        opacity: widget.enabled ? 1.0 : 0.55,

        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 140.0;

            final height = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : 120.0;

            if (width <= 0 || height <= 0) return const SizedBox.shrink();

            final trimmedLabel = widget.label.trim();

            final showFooter =
                (trimmedLabel.isNotEmpty || config.showValue) && height >= 48;

            // Must match the footer's actual rendered height below exactly

            // (Padding's 4+2 vertical inset + ControlButtonVisualMetrics

            // .rowHeight) — a mismatch here starves/overshoots bodyHeight

            // and overflows the outer Column by the difference.

            final footerHeight = showFooter
                ? 6.0 + ControlButtonVisualMetrics.rowHeight
                : 0.0;

            final bodyHeight = (height - footerHeight).clamp(0.0, height);

            final vertical =
                config.orientation == AnalogSliderOrientation.vertical;

            // Upper-bound-only clamps: a preferred cap keeps the lane/track

            // from becoming absurdly thick/long in a huge cell, but must

            // never force either dimension ABOVE what's actually available

            // (bodyHeight/width) — doing so previously caused a RenderFlex

            // overflow in short cells, since the RotatedBox below reports

            // its swapped size straight back into this exact box.

            final Widget stage;

            if (vertical) {
              final laneWidth = width.clamp(0.0, 84.0).toDouble();

              final trackLength = bodyHeight.clamp(0.0, 480.0).toDouble();

              stage = SizedBox(
                width: laneWidth,

                height: bodyHeight,

                child: Center(
                  child: RotatedBox(
                    quarterTurns: -1,

                    child: SizedBox(
                      width: trackLength,

                      height: laneWidth,

                      child: _buildStage(
                        trackLength: trackLength,

                        laneWidth: laneWidth,
                      ),
                    ),
                  ),
                ),
              );
            } else {
              final laneWidth = bodyHeight.clamp(0.0, 84.0).toDouble();

              final trackLength = width.clamp(0.0, double.infinity).toDouble();

              stage = SizedBox(
                width: trackLength,

                height: bodyHeight,

                child: Center(
                  child: SizedBox(
                    width: trackLength,

                    height: laneWidth,

                    child: _buildStage(
                      trackLength: trackLength,

                      laneWidth: laneWidth,
                    ),
                  ),
                ),
              );
            }

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,

              children: [
                SizedBox(
                  height: bodyHeight,
                  child: Center(child: stage),
                ),

                if (showFooter)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2),

                    child: SizedBox(
                      height: ControlButtonVisualMetrics.rowHeight,

                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,

                        children: [
                          if (trimmedLabel.isNotEmpty)
                            Expanded(
                              child: ControlButtonLabelIcon(
                                label: widget.label,

                                icon: widget.icon,

                                color: widget.enabled
                                    ? AppColors.darkText
                                    : AppColors.darkBorder,

                                iconColor: widget.activeColorLight,

                                rotation: widget.rotation,
                              ),
                            ),

                          if (trimmedLabel.isNotEmpty && config.showValue)
                            const SizedBox(width: 6),

                          if (config.showValue)
                            Flexible(
                              child: _AnalogValueReadout(
                                value: numberText,

                                unit: unitText,

                                activeColor: widget.activeColor,

                                enabled: widget.enabled,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStage({required double trackLength, required double laneWidth}) {
    if (trackLength <= 0 || laneWidth <= 0) return const SizedBox.shrink();

    final thumbW = (laneWidth * 0.58).clamp(0.0, 34.0).toDouble();

    final thumbH = (laneWidth * 0.82).clamp(0.0, 48.0).toDouble();

    final trackH = (laneWidth * 0.30).clamp(0.0, 14.0).toDouble();

    final trackWidth = (trackLength - thumbW)
        .clamp(0.0, trackLength)
        .toDouble();

    final thumbCenterX = thumbW / 2.0 + _normalized * trackWidth;

    return Listener(
      behavior: HitTestBehavior.opaque,

      onPointerDown: (event) => _onPointerDown(
        event,

        trackLength: trackLength,

        laneWidth: laneWidth,

        thumbW: thumbW,

        thumbH: thumbH,
      ),

      onPointerUp: (_) {
        if (!_isDragging) _pointerStartedOnThumb = false;
      },

      onPointerCancel: (_) => _pointerStartedOnThumb = false,

      child: GestureDetector(
        behavior: HitTestBehavior.opaque,

        onHorizontalDragStart: (details) => _onDragStart(details, trackWidth),

        onHorizontalDragUpdate: (details) => _onDragUpdate(details, trackWidth),

        onHorizontalDragEnd: _onDragEnd,

        onHorizontalDragCancel: _onDragCancel,

        child: Stack(
          clipBehavior: Clip.none,

          alignment: Alignment.center,

          children: [
            IgnorePointer(
              child: CustomPaint(
                size: Size(trackLength, laneWidth),

                painter: _AnalogSliderTrackPainter(
                  normalized: _normalized,

                  neutralNormalized: _trackPositionForValue(
                    _config.neutralValue,
                  ),

                  thumbWidth: thumbW,

                  trackHeight: trackH,

                  fillColor: widget.activeColor,

                  enabled: widget.enabled,

                  isDragging: _isDragging,
                ),
              ),
            ),

            Positioned(
              left: thumbCenterX - thumbW / 2,

              top: (laneWidth - thumbH) / 2,

              child: IgnorePointer(
                child: CustomPaint(
                  size: Size(thumbW, thumbH),

                  painter: _AnalogSliderThumbPainter(
                    isDragging: _isDragging,

                    enabled: widget.enabled,

                    activeColor: widget.activeColor,

                    activeColorLight: widget.activeColorLight,
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

String _formatAnalogValue(
  AnalogSliderConfig config,

  double value, {

  String? unitOverride,
}) {
  final number = value.toStringAsFixed(config.decimalPlaces);

  final unit = _resolvedAnalogUnit(config, unitOverride);

  return unit.isEmpty ? number : '$number $unit';
}

String _resolvedAnalogUnit(AnalogSliderConfig config, String? unitOverride) {
  return (unitOverride?.trim().isNotEmpty ?? false)
      ? unitOverride!.trim()
      : config.unit.trim();
}

class _AnalogValueReadout extends StatelessWidget {
  const _AnalogValueReadout({
    required this.value,

    required this.unit,

    required this.activeColor,

    required this.enabled,
  });

  final String value;

  final String unit;

  final Color activeColor;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final foreground = enabled ? activeColor : AppColors.darkTextMuted;

    return Semantics(
      liveRegion: true,

      label: unit.isEmpty
          ? 'Current value $value'
          : 'Current value $value $unit',

      child: Container(
        constraints: const BoxConstraints(minWidth: 48, maxWidth: 108),

        height: 24,

        padding: const EdgeInsets.symmetric(horizontal: 8),

        decoration: BoxDecoration(
          color: const Color(0xFF090C0F),

          borderRadius: BorderRadius.circular(5),

          border: Border.all(
            color: foreground.withAlpha(enabled ? 150 : 65),

            width: 1,
          ),

          boxShadow: enabled
              ? [
                  BoxShadow(color: activeColor.withAlpha(45), blurRadius: 6),

                  const BoxShadow(
                    color: Color(0x66000000),

                    offset: Offset(0, 1),

                    blurRadius: 2,
                  ),
                ]
              : null,
        ),

        child: FittedBox(
          fit: BoxFit.scaleDown,

          child: RichText(
            maxLines: 1,

            text: TextSpan(
              children: [
                TextSpan(
                  text: value,

                  style: TextStyle(
                    color: foreground,

                    fontSize: 13,

                    fontWeight: FontWeight.w700,

                    fontFeatures: const [FontFeature.tabularFigures()],

                    letterSpacing: 0.4,
                  ),
                ),

                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',

                    style: TextStyle(
                      color: foreground.withAlpha(enabled ? 205 : 100),

                      fontSize: 9,

                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnalogSliderTrackPainter extends CustomPainter {
  const _AnalogSliderTrackPainter({
    required this.normalized,

    required this.neutralNormalized,

    required this.thumbWidth,

    required this.trackHeight,

    required this.fillColor,

    required this.enabled,

    required this.isDragging,
  });

  final double normalized;

  final double neutralNormalized;

  final double thumbWidth;

  final double trackHeight;

  final Color fillColor;

  final bool enabled;

  final bool isDragging;

  @override
  void paint(Canvas canvas, Size size) {
    final trackWidth = (size.width - thumbWidth).clamp(0.0, size.width);

    if (trackWidth <= 0 || trackHeight <= 0) return;

    final left = thumbWidth / 2;

    final centerY = size.height / 2;

    final radius = Radius.circular(trackHeight / 2);

    final trackRect = Rect.fromCenter(
      center: Offset(size.width / 2, centerY),

      width: trackWidth,

      height: trackHeight,
    );

    final outerRect = trackRect.inflate(2.0);

    // Cast shadow and a metallic bezel make the rail feel recessed.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        outerRect.shift(const Offset(0, 1.5)),

        Radius.circular(trackHeight / 2 + 2),
      ),

      Paint()
        ..color = Colors.black.withAlpha(enabled ? 125 : 70)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(outerRect, Radius.circular(trackHeight / 2 + 2)),

      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,

          end: Alignment.bottomCenter,

          colors: [Color(0xFF626A73), Color(0xFF20252B), Color(0xFF0C0F12)],

          stops: [0.0, 0.48, 1.0],
        ).createShader(outerRect),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),

      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,

          end: Alignment.bottomCenter,

          colors: [Color(0xFF07090B), Color(0xFF1A1F24), Color(0xFF060708)],
        ).createShader(trackRect),
    );

    final neutralX = left + neutralNormalized * trackWidth;

    final currentX = left + normalized * trackWidth;

    final fillLeft = math.min(neutralX, currentX);

    final fillRight = math.max(neutralX, currentX);

    if (fillRight - fillLeft > 0.5) {
      final fillRect = Rect.fromLTRB(
        fillLeft,

        centerY - trackHeight / 2,

        fillRight,

        centerY + trackHeight / 2,
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(fillRect, radius),

        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,

            end: Alignment.bottomCenter,

            colors: enabled
                ? [
                    Color.lerp(fillColor, Colors.white, 0.34)!,

                    fillColor,

                    Color.lerp(fillColor, Colors.black, 0.28)!,
                  ]
                : [AppColors.disabled, AppColors.disabled, AppColors.disabled],
          ).createShader(fillRect),
      );

      canvas.drawLine(
        Offset(fillLeft + 2, fillRect.top + 1),

        Offset(fillRight - 2, fillRect.top + 1),

        Paint()
          ..color = Colors.white.withAlpha(enabled ? 80 : 25)
          ..strokeWidth = 0.8,
      );
    }

    // Eleven engraved scale ticks; the centre and end ticks are emphasized.
    final tickPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withAlpha(enabled ? 95 : 38);

    for (var i = 0; i <= 10; i++) {
      final major = i == 0 || i == 5 || i == 10;

      final x = left + trackWidth * i / 10.0;

      final tickLength = major ? 5.0 : 3.0;

      tickPaint.strokeWidth = major ? 1.4 : 0.8;

      canvas.drawLine(
        Offset(x, trackRect.top - 4),

        Offset(x, trackRect.top - 4 - tickLength),

        tickPaint,
      );

      canvas.drawLine(
        Offset(x, trackRect.bottom + 4),

        Offset(x, trackRect.bottom + 4 + tickLength),

        tickPaint,
      );
    }

    canvas.drawLine(
      Offset(neutralX, centerY - trackHeight / 2 - 3),

      Offset(neutralX, centerY + trackHeight / 2 + 3),

      Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withAlpha(enabled ? 140 : 60),
    );
  }

  @override
  bool shouldRepaint(covariant _AnalogSliderTrackPainter oldDelegate) {
    return oldDelegate.normalized != normalized ||
        oldDelegate.neutralNormalized != neutralNormalized ||
        oldDelegate.thumbWidth != thumbWidth ||
        oldDelegate.trackHeight != trackHeight ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.enabled != enabled ||
        oldDelegate.isDragging != isDragging;
  }
}

class _AnalogSliderThumbPainter extends CustomPainter {
  const _AnalogSliderThumbPainter({
    required this.isDragging,

    required this.enabled,

    required this.activeColor,

    required this.activeColorLight,
  });

  final bool isDragging;

  final bool enabled;

  final Color activeColor;

  final Color activeColorLight;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,

      Radius.circular(math.min(7.0, size.width * 0.26)),
    );

    if (isDragging && enabled) {
      canvas.drawRRect(
        rrect.inflate(3),

        Paint()
          ..color = activeColor.withAlpha(90)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
    }

    canvas.drawRRect(
      rrect.shift(const Offset(0, 1.5)),

      Paint()
        ..color = Colors.black.withAlpha(155)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    canvas.drawRRect(
      rrect,

      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,

          end: Alignment.bottomCenter,

          colors: enabled
              ? const [Color(0xFF77818B), Color(0xFF343B42), Color(0xFF15191D)]
              : [AppColors.disabled, AppColors.disabled, AppColors.disabled],

          stops: const [0.0, 0.46, 1.0],
        ).createShader(Offset.zero & size),
    );

    canvas.drawRRect(
      rrect,

      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isDragging ? 2.4 : 1.6
        ..color = enabled
            ? activeColor.withAlpha(isDragging ? 255 : 205)
            : Colors.white.withAlpha(65),
    );

    canvas.drawLine(
      Offset(rrect.left + 5, rrect.top + 3),

      Offset(rrect.right - 5, rrect.top + 3),

      Paint()
        ..color = Colors.white.withAlpha(enabled ? 90 : 30)
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.round,
    );

    final gripPaint = Paint()
      ..strokeWidth = 1.5
      ..color = Colors.black.withAlpha(enabled ? 150 : 55);

    final cx = size.width / 2;

    final cy = size.height / 2;

    final gripSpacing = math.min(4.0, size.width * 0.14);

    final gripHalfHeight = math.min(8.0, size.height * 0.24);

    for (final dx in [-gripSpacing, 0.0, gripSpacing]) {
      canvas.drawLine(
        Offset(cx + dx, cy - gripHalfHeight),

        Offset(cx + dx, cy + gripHalfHeight),

        gripPaint,
      );
    }

    canvas.drawCircle(
      Offset(cx, size.height - 5),

      isDragging ? 2.2 : 1.7,

      Paint()..color = enabled ? activeColorLight : AppColors.disabled,
    );
  }

  @override
  bool shouldRepaint(covariant _AnalogSliderThumbPainter oldDelegate) {
    return oldDelegate.isDragging != isDragging ||
        oldDelegate.enabled != enabled ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.activeColorLight != activeColorLight;
  }
}
