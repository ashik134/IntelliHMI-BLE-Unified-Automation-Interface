import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:vibration/vibration.dart';

import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/utils/button_state_log.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/widgets/buttons/control_button_visuals.dart';

abstract final class MultiStepSliderStateId {
  static const String idle = 'idle';
  static const String step1 = 'step1';
  static const String step2 = 'step2';

  static const Set<String> values = {idle, step1, step2};

  static String normalize(String stateId) =>
      values.contains(stateId) ? stateId : idle;
}

class MultiStepSliderButton extends StatelessWidget {
  const MultiStepSliderButton({
    super.key,
    required this.label,
    required this.icon,
    this.isDisabled = false,
    this.externalStateId = MultiStepSliderStateId.idle,
    this.activeColor,
    this.step2Color,
    this.style,
    required this.onStateChanged,
  });

  final String label;
  final IconData icon;
  final bool isDisabled;
  final String externalStateId;
  final Color? activeColor;
  final Color? step2Color;
  final ButtonStyleConfig? style;
  final ValueChanged<String> onStateChanged;

  @override
  Widget build(BuildContext context) {
    return IndustrialMultiStepSlider(
      label: label,
      icon: icon,
      enabled: !isDisabled,
      stateId: MultiStepSliderStateId.normalize(externalStateId),
      activeColor: activeColor,
      step2Color: step2Color,
      style: style,
      onStateChanged: onStateChanged,
    );
  }
}

/// Reusable industrial slider surface with three neutral state IDs.
///
/// It owns presentation, drag behavior, haptics, and local visual state only.
/// PLC outputs and packet composition stay outside it.
class IndustrialMultiStepSlider extends StatefulWidget {
  const IndustrialMultiStepSlider({
    super.key,
    required this.label,
    required this.icon,
    this.enabled = true,
    this.activeColor,
    this.step2Color,
    this.stateId = MultiStepSliderStateId.idle,
    this.style,
    required this.onStateChanged,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final String stateId;
  final Color? activeColor;
  final Color? step2Color;
  final ButtonStyleConfig? style;
  final ValueChanged<String> onStateChanged;

  @override
  State<IndustrialMultiStepSlider> createState() =>
      _IndustrialMultiStepSliderState();
}

class _IndustrialMultiStepSliderState extends State<IndustrialMultiStepSlider>
    with SingleTickerProviderStateMixin {
  static const double _step2Threshold = 0.55;
  static const double _idleDeadZone = 0.01;
  static const double _thumbHitSlop = 12.0;

  String _stateId = MultiStepSliderStateId.idle;
  double _sliderValue = 0.0;
  bool _isTouching = false;
  bool _pointerStartedOnThumb = false;

  bool _suppressExternalReactivation = false;

  late final AnimationController _springCtrl;

  @override
  void initState() {
    super.initState();
    _springCtrl = AnimationController.unbounded(vsync: this)
      ..addListener(_onSpringTick);
    _syncFromExternalStateId(widget.stateId);
  }

  @override
  void didUpdateWidget(covariant IndustrialMultiStepSlider oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!widget.enabled && oldWidget.enabled) {
      _springCtrl.stop();
      _resetLocalState();
      return;
    }

    if (_isTouching || widget.stateId == oldWidget.stateId) {
      return;
    }

    if (_suppressExternalReactivation) {
      final normalizedStateId = MultiStepSliderStateId.normalize(
        widget.stateId,
      );
      if (normalizedStateId != MultiStepSliderStateId.idle) {
        ButtonStateLog.log(
          'EXTERNAL_STATE_ACTIVE ignored (stale, post-release) '
          '[${widget.label}]',
        );
        return;
      }
      if (_springCtrl.isAnimating) {
        return;
      }
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
    final stateId = MultiStepSliderStateId.normalize(externalStateId);
    if (stateId != _stateId) {
      ButtonStateLog.log(
        '${stateId == MultiStepSliderStateId.idle ? 'VISUAL_IDLE' : 'VISUAL_ACTIVE'} '
        '[${widget.label}] (external) -> $stateId',
      );
    }
    _stateId = stateId;
    _sliderValue = _sliderValueForStateId(stateId);
  }

  void _resetLocalState() {
    _springCtrl.stop();
    setState(() {
      _isTouching = false;
      _pointerStartedOnThumb = false;
      _stateId = MultiStepSliderStateId.idle;
      _sliderValue = 0.0;
    });
  }

  double _sliderValueForStateId(String stateId) => switch (stateId) {
    MultiStepSliderStateId.step1 => 0.5,
    MultiStepSliderStateId.step2 => 1.0,
    _ => 0.0,
  };

  String _stateIdFromSlider(double value) {
    if (value <= _idleDeadZone) return MultiStepSliderStateId.idle;
    if (value < _step2Threshold) return MultiStepSliderStateId.step1;
    return MultiStepSliderStateId.step2;
  }

  Rect _thumbHitRect({
    required double trackLength,
    required double laneWidth,
    required double thumbW,
    required double thumbH,
  }) {
    final trackWidth = (trackLength - thumbW)
        .clamp(0.0, trackLength)
        .toDouble();
    final thumbCenterX =
        thumbW / 2.0 + _sliderValue.clamp(0.0, 1.0).toDouble() * trackWidth;
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
    if (!_isTouching) {
      _pointerStartedOnThumb = false;
    }
  }

  void _onPointerCancel(PointerCancelEvent _) {
    _pointerStartedOnThumb = false;
  }

  void _setSliderValueFromDrag(double value) {
    final nextStateId = _stateIdFromSlider(value);
    final hasStateChanged = nextStateId != _stateId;

    setState(() {
      _sliderValue = value;
      _isTouching = true;
      _stateId = nextStateId;
    });

    if (hasStateChanged) {
      _notifyStateId(nextStateId);
    }
  }

  void _onDragStart(DragStartDetails _, double trackWidth) {
    if (!widget.enabled || !_pointerStartedOnThumb || trackWidth <= 0) {
      return;
    }

    ButtonStateLog.log('POINTER_START [${widget.label}]');
    _springCtrl.stop();
    _suppressExternalReactivation = false;
    setState(() => _isTouching = true);
  }

  void _onDragUpdate(DragUpdateDetails details, double trackWidth) {
    if (!_isTouching || !widget.enabled || trackWidth <= 0) return;

    final nextValue = (_sliderValue + details.delta.dx / trackWidth)
        .clamp(0.0, 1.0)
        .toDouble();
    _setSliderValueFromDrag(nextValue);
  }

  void _onDragEnd(DragEndDetails _) {
    if (!_isTouching) {
      _pointerStartedOnThumb = false;
      return;
    }

    if (!widget.enabled) return;
    ButtonStateLog.log('POINTER_END [${widget.label}]');
    _release();
  }

  void _onDragCancel() {
    if (!_isTouching) {
      _pointerStartedOnThumb = false;
      return;
    }

    ButtonStateLog.log('POINTER_CANCEL [${widget.label}]');
    _release();
  }

  void _release() {
    final shouldNotifyIdle = _stateId != MultiStepSliderStateId.idle;

    setState(() {
      _isTouching = false;
      _stateId = MultiStepSliderStateId.idle;
    });
    _pointerStartedOnThumb = false;
    // Arm the guard so a stale external update cannot reactivate the slider
    // until the next fresh pointer interaction.
    _suppressExternalReactivation = true;

    if (shouldNotifyIdle) {
      _notifyStateId(MultiStepSliderStateId.idle);
    }
    _springReturn();
  }

  void _onSpringTick() {
    if (_isTouching) return;
    setState(() => _sliderValue = _springCtrl.value.clamp(0.0, 1.0).toDouble());
  }

  void _springReturn() {
    if (_sliderValue <= 0.0) {
      _springCtrl.stop();
      return;
    }

    _springCtrl.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 0.5, stiffness: 280.0, damping: 20.0),
        _sliderValue,
        0.0,
        0.0,
      ),
    );
  }

  void _notifyStateId(String stateId) {
    widget.onStateChanged(stateId);
    _vibrateForStateId(stateId);

    assert(() {
      debugPrint('${widget.label} slider state: $stateId');
      return true;
    }());
  }

  void _vibrateForStateId(String stateId) {
    switch (stateId) {
      case MultiStepSliderStateId.idle:
        Vibration.vibrate(duration: 15);
        break;
      case MultiStepSliderStateId.step1:
        Vibration.vibrate(duration: 25, amplitude: 100);
        break;
      case MultiStepSliderStateId.step2:
        Vibration.vibrate(duration: 55, amplitude: 255);
        break;
    }
  }

  Color get _activeColor => widget.activeColor ?? AppColors.accent;
  Color get _step2Color =>
      widget.step2Color ?? Color.lerp(_activeColor, Colors.white, 0.18)!;

  Color get _activeSliderColor {
    if (!widget.enabled) return AppColors.idleColor;
    return _stateId == MultiStepSliderStateId.step2
        ? _step2Color
        : _activeColor;
  }

  Color get _overlayColor {
    if (!widget.enabled) return Colors.transparent;

    switch (_stateId) {
      case MultiStepSliderStateId.idle:
        return AppColors.idleColor.withAlpha(35);
      case MultiStepSliderStateId.step1:
        return _activeColor.withAlpha(50);
      case MultiStepSliderStateId.step2:
        return _step2Color.withAlpha(55);
    }
    return AppColors.idleColor.withAlpha(35);
  }

  bool get _isIdle => _stateId == MultiStepSliderStateId.idle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 140.0;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 120.0;

        if (width <= 0 || height <= 0) {
          return const SizedBox.shrink();
        }

        final showFooter = widget.label.trim().isNotEmpty && height >= 96;
        final footerHeight = showFooter ? 28.0 : 0.0;
        final bodyHeight = (height - footerHeight).clamp(0.0, height);

        final sliderLaneWidth = width.clamp(56.0, 72.0).toDouble();
        final trackLength = bodyHeight.clamp(90.0, 360.0).toDouble();

        final thumbW = (sliderLaneWidth * 0.58).clamp(0.0, 36.0).toDouble();
        final thumbH = (sliderLaneWidth * 0.82).clamp(0.0, 52.0).toDouble();
        final trackH = (sliderLaneWidth * 0.28).clamp(0.0, 16.0).toDouble();

        return Opacity(
          opacity: widget.enabled ? 1.0 : 0.55,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: bodyHeight,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: sliderLaneWidth,
                      height: bodyHeight,
                      child: Center(
                        child: RotatedBox(
                          quarterTurns: -1,
                          child: SizedBox(
                            width: trackLength,
                            height: sliderLaneWidth,
                            child: _buildSliderStage(
                              trackLength: trackLength,
                              laneWidth: sliderLaneWidth,
                              thumbW: thumbW,
                              thumbH: thumbH,
                              trackH: trackH,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (showFooter)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: _SliderFooter(
                    icon: widget.icon,
                    label: widget.label,
                    isActive: !_isIdle,
                    activeColor: _activeSliderColor,
                    isDisabled: !widget.enabled,
                    maxWidth: width,
                    style: widget.style,
                  ),
                ),
            ],
          ),
        );
      },
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
    final thumbCenterX =
        thumbW / 2.0 + _sliderValue.clamp(0.0, 1.0).toDouble() * trackWidth;
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
                painter: _MultiStepTrackPainter(
                  value: _sliderValue,
                  thumbWidth: thumbW,
                  trackHeight: trackH,
                  deadZone: _idleDeadZone,
                  step2Threshold: _step2Threshold,
                  fillColor: _activeSliderColor.withAlpha(
                    widget.enabled ? 200 : 70,
                  ),
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
                child: _MultiStepThumb(
                  key: const ValueKey('multi_step_slider_thumb'),
                  width: thumbW,
                  height: thumbH,
                  borderRadius: 6,
                  color: _activeSliderColor,
                  overlayColor: _overlayColor,
                  isDragging: _isTouching,
                  isDisabled: !widget.enabled,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderFooter extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final bool isDisabled;
  final double maxWidth;
  final ButtonStyleConfig? style;

  const _SliderFooter({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.isDisabled,
    required this.maxWidth,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDisabled
        ? AppColors.darkTextMuted
        : isActive
        ? activeColor
        : AppColors.darkText;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth.clamp(0.0, 180.0)),
      child: SizedBox(
        height: ControlButtonVisualMetrics.rowHeight,
        child: ControlButtonLabelIcon(
          label: label,
          icon: icon,
          color: textColor,
          iconColor: isActive && !isDisabled
              ? activeColor
              : AppColors.darkTextMuted,
          style: style,
        ),
      ),
    );
  }
}

// class _StatusDot extends StatelessWidget {
//   final bool isDisabled;
//   final bool isIdle;
//   final Color activeColor;

//   const _StatusDot({
//     required this.isDisabled,
//     required this.isIdle,
//     required this.activeColor,
//   });

//   @override
//   Widget build(BuildContext context) {
//     if (isDisabled) {
//       return const Text(
//         '—',
//         style: TextStyle(
//           fontSize: 9,
//           color: AppColors.darkTextMuted,
//           fontWeight: FontWeight.bold,
//         ),
//       );
//     }

//     return Text(
//       '●',
//       style: TextStyle(
//         fontSize: 9,
//         color: isIdle ? AppColors.idleColor : activeColor,
//       ),
//     );
//   }
// }

class _MultiStepTrackPainter extends CustomPainter {
  final double value;
  final double thumbWidth;
  final double trackHeight;
  final double deadZone;
  final double step2Threshold;
  final Color fillColor;
  final bool isActive;

  const _MultiStepTrackPainter({
    required this.value,
    required this.thumbWidth,
    required this.trackHeight,
    required this.deadZone,
    required this.step2Threshold,
    required this.fillColor,
    required this.isActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || trackHeight <= 0) return;

    final trackLeft = thumbWidth / 2.0;
    final trackRight = size.width - thumbWidth / 2.0;

    if (trackRight <= trackLeft) return;

    final trackWidth = trackRight - trackLeft;
    final trackTop = (size.height - trackHeight) / 2.0;
    final trackRect = Rect.fromLTWH(
      trackLeft,
      trackTop,
      trackWidth,
      trackHeight,
    );

    final radius = Radius.circular(trackHeight / 2.0);

    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),
      Paint()..color = const Color.fromARGB(255, 255, 252, 252),
    );

    if (isActive && value > deadZone) {
      final activeRight = trackLeft + value.clamp(0.0, 1.0) * trackWidth;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            trackLeft,
            trackTop,
            activeRight,
            trackTop + trackHeight,
          ),
          radius,
        ),
        Paint()..color = fillColor,
      );
    }

    final markerPaint = Paint()
      ..color = AppColors.darkBorder.withAlpha(180)
      ..strokeWidth = 1.0;

    void drawMarker(double fraction) {
      final dx = trackLeft + fraction.clamp(0.0, 1.0) * trackWidth;
      canvas.drawLine(
        Offset(dx, trackTop),
        Offset(dx, trackTop + trackHeight),
        markerPaint,
      );
    }

    drawMarker(deadZone);
    drawMarker(step2Threshold);
  }

  @override
  bool shouldRepaint(_MultiStepTrackPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.thumbWidth != thumbWidth ||
      oldDelegate.trackHeight != trackHeight ||
      oldDelegate.deadZone != deadZone ||
      oldDelegate.step2Threshold != step2Threshold ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.isActive != isActive;
}

class _MultiStepThumb extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;
  final Color color;
  final Color overlayColor;
  final bool isDragging;
  final bool isDisabled;

  const _MultiStepThumb({
    super.key,
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.color,
    required this.overlayColor,
    required this.isDragging,
    required this.isDisabled,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _MultiStepThumbPainter(
        width: width,
        height: height,
        borderRadius: borderRadius,
        color: color,
        overlayColor: overlayColor,
        isDragging: isDragging,
        isDisabled: isDisabled,
      ),
    );
  }
}

class _MultiStepThumbPainter extends CustomPainter {
  final double width;
  final double height;
  final double borderRadius;
  final Color color;
  final Color overlayColor;
  final bool isDragging;
  final bool isDisabled;

  const _MultiStepThumbPainter({
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.color,
    required this.overlayColor,
    required this.isDragging,
    required this.isDisabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (width <= 0 || height <= 0) return;

    final center = Offset(width / 2.0, height / 2.0);
    final activeColor = color;
    final visualDragging = isDragging;

    final borderColor = isDisabled
        ? AppColors.idleColor
        : visualDragging
        ? activeColor
        : activeColor.withAlpha(160);

    final fillColor = isDisabled
        ? AppColors.darkBg
        : visualDragging
        ? activeColor.withAlpha(28)
        : AppColors.darkBg;

    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: width, height: height),
      Radius.circular(borderRadius),
    );

    if (visualDragging && !isDisabled) {
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
        ..strokeWidth = visualDragging ? 2.5 : 1.5,
    );

    final gripColor = isDisabled
        ? AppColors.idleColor
        : activeColor.withAlpha(160);

    final gripPaint = Paint()
      ..color = gripColor
      ..style = PaintingStyle.fill;

    final gripHeight = height * 0.38;
    const gripWidth = 2.0;
    final spacing = width * 0.16;

    for (final dx in [-spacing, 0.0, spacing]) {
      final gripRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center.dx + dx, center.dy),
          width: gripWidth,
          height: gripHeight,
        ),
        const Radius.circular(1),
      );

      canvas.drawRRect(gripRect, gripPaint);
    }
  }

  @override
  bool shouldRepaint(_MultiStepThumbPainter oldDelegate) =>
      oldDelegate.width != width ||
      oldDelegate.height != height ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.color != color ||
      oldDelegate.overlayColor != overlayColor ||
      oldDelegate.isDragging != isDragging ||
      oldDelegate.isDisabled != isDisabled;
}
