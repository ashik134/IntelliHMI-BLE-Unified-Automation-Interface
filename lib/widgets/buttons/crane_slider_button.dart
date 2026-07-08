import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/button_state_log.dart';

class CraneSliderButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isUp;
  final bool isDisabled;
  final ControlState externalState;
  final Color? axisColor;
  final ValueChanged<ControlState> onCommandChanged;

  const CraneSliderButton({
    super.key,
    required this.label,
    required this.icon,
    required this.isUp,
    this.isDisabled = false,
    this.externalState = ControlState.idle,
    this.axisColor,
    required this.onCommandChanged,
  });

  @override
  State<CraneSliderButton> createState() => _CraneSliderButtonState();
}

class _CraneSliderButtonState extends State<CraneSliderButton> {
  static const double _fastThreshold = 0.55;
  static const double _idleDeadZone = 0.01;

  ControlState _state = ControlState.idle;
  double _sliderValue = 0.0;
  bool _isTouching = false;

  // Set the instant a local release returns this slider to idle, cleared on
  // the next fresh touch. While true, external state updates (which may be a
  // stale/delayed PLC status echo of the drag just released) must not resync
  // this slider active again; only a new physical touch may do that.
  bool _suppressExternalReactivation = false;

  @override
  void initState() {
    super.initState();
    _syncFromExternalState(widget.externalState);
  }

  @override
  void didUpdateWidget(covariant CraneSliderButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isDisabled && !oldWidget.isDisabled) {
      _resetLocalState();
      return;
    }

    if (_isTouching || widget.externalState == oldWidget.externalState) {
      return;
    }

    if (_suppressExternalReactivation &&
        widget.externalState != ControlState.idle) {
      ButtonStateLog.log(
        'PLC_STATUS_ACTIVE ignored (stale, post-release) [${widget.label}]',
      );
      return;
    }

    _syncFromExternalState(widget.externalState);
  }

  void _syncFromExternalState(ControlState state) {
    if (state != _state) {
      ButtonStateLog.log(
        '${state == ControlState.idle ? 'VISUAL_IDLE' : 'VISUAL_ACTIVE'} '
        '[${widget.label}] (external) -> ${state.name}',
      );
    }
    _state = state;
    _sliderValue = _sliderValueForState(state);
  }

  void _resetLocalState() {
    setState(() {
      _isTouching = false;
      _state = ControlState.idle;
      _sliderValue = 0.0;
    });
  }

  double _sliderValueForState(ControlState state) {
    switch (state) {
      case ControlState.idle:
        return 0.0;
      case ControlState.slow:
        return 0.5;
      case ControlState.fast:
        return 1.0;
    }
  }

  ControlState _stateFromSlider(double value) {
    if (value <= _idleDeadZone) return ControlState.idle;
    if (value < _fastThreshold) return ControlState.slow;
    return ControlState.fast;
  }

  void _onSliderChanged(double value) {
    if (widget.isDisabled) return;

    final nextState = _stateFromSlider(value);
    final hasStateChanged = nextState != _state;

    setState(() {
      _sliderValue = value;
      _isTouching = true;
      _state = nextState;
    });

    if (hasStateChanged) {
      _notifyState(nextState);
    }
  }

  void _onSliderChangeStart(double _) {
    if (widget.isDisabled) return;
    ButtonStateLog.log('USER_DOWN [${widget.label}]');
    _isTouching = true;
    _suppressExternalReactivation = false;
  }

  void _onSliderChangeEnd(double _) {
    if (widget.isDisabled) return;
    ButtonStateLog.log('USER_UP [${widget.label}]');

    final shouldNotifyIdle = _state != ControlState.idle;

    setState(() {
      _isTouching = false;
      _sliderValue = 0.0;
      _state = ControlState.idle;
    });
    // Arm the guard: a stale PLC_STATUS echo for the drag just released must
    // not resync this slider active again until a fresh USER_DOWN.
    _suppressExternalReactivation = true;

    if (shouldNotifyIdle) {
      _notifyState(ControlState.idle);
    }
  }

  void _notifyState(ControlState state) {
    widget.onCommandChanged(state);
    _vibrateForState(state);

    assert(() {
      debugPrint('${widget.label} command: ${state.name.toUpperCase()}');
      return true;
    }());
  }

  void _vibrateForState(ControlState state) {
    switch (state) {
      case ControlState.idle:
        Vibration.vibrate(duration: 15);
        break;
      case ControlState.slow:
        Vibration.vibrate(duration: 25, amplitude: 100);
        break;
      case ControlState.fast:
        Vibration.vibrate(duration: 55, amplitude: 255);
        break;
    }
  }

  Color get _axisColor =>
      widget.axisColor ??
      (widget.isUp ? AppColors.upColor : AppColors.downColor);

  Color get _activeSliderColor {
    if (widget.isDisabled) return AppColors.idleColor;
    return _sliderValue >= _fastThreshold ? AppColors.fastColor : _axisColor;
  }

  Color get _overlayColor {
    if (widget.isDisabled) return Colors.transparent;

    switch (_state) {
      case ControlState.idle:
        return AppColors.idleColor.withAlpha(35);
      case ControlState.slow:
        return _axisColor.withAlpha(50);
      case ControlState.fast:
        return AppColors.fastColor.withAlpha(55);
    }
  }

  bool get _isIdle => _state == ControlState.idle;

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
        final footerHeight = showFooter ? 24.0 : 0.0;
        final bodyHeight = (height - footerHeight).clamp(0.0, height);

        const showScale = false;
        // const scaleWidth =  0.0;
        const gap = 0.0;

        final sliderLaneWidth = width.clamp(56.0, 72.0).toDouble();
        final trackLength = bodyHeight.clamp(90.0, 360.0).toDouble();

        final thumbW = (sliderLaneWidth * 0.58).clamp(0.0, 36.0).toDouble();
        final thumbH = (sliderLaneWidth * 0.82).clamp(0.0, 52.0).toDouble();
        final trackH = (sliderLaneWidth * 0.28).clamp(0.0, 16.0).toDouble();

        return Opacity(
          opacity: widget.isDisabled ? 0.55 : 1.0,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: bodyHeight,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // if (showScale)
                    //   SizedBox(
                    //     width: scaleWidth,
                    //     child: _SliderScale(
                    //       value: _sliderValue,
                    //       isUp: widget.isUp,
                    //       fastThreshold: _fastThreshold,
                    //       activeColor: _activeSliderColor,
                    //       axisColor: _axisColor,
                    //       isDisabled: widget.isDisabled,
                    //     ),
                    //   ),
                    if (showScale) SizedBox(width: gap),
                    SizedBox(
                      width: sliderLaneWidth,
                      height: bodyHeight,
                      child: Center(
                        child: RotatedBox(
                          quarterTurns: widget.isUp ? -1 : 1,
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
                    isDisabled: widget.isDisabled,
                    maxWidth: width,
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

    return Stack(
      alignment: Alignment.center,
      children: [
        IgnorePointer(
          child: CustomPaint(
            size: Size(trackLength, laneWidth),
            painter: _CraneTrackPainter(
              value: _sliderValue,
              thumbWidth: thumbW,
              trackHeight: trackH,
              deadZone: _idleDeadZone,
              fastThreshold: _fastThreshold,
              fillColor: _activeSliderColor.withAlpha(
                widget.isDisabled ? 70 : 200,
              ),
              isActive: !widget.isDisabled,
            ),
          ),
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: trackH,
            activeTrackColor: Colors.transparent,
            inactiveTrackColor: Colors.transparent,
            disabledActiveTrackColor: Colors.transparent,
            disabledInactiveTrackColor: Colors.transparent,
            thumbColor: _activeSliderColor,
            disabledThumbColor: AppColors.idleColor,
            overlayColor: _overlayColor,
            overlayShape: RoundSliderOverlayShape(
              overlayRadius: (laneWidth * 0.24).clamp(0.0, 14.0).toDouble(),
            ),
            thumbShape: RectSliderThumbShape(
              width: thumbW,
              height: thumbH,
              borderRadius: 6,
              color: _activeSliderColor,
              isDragging: _isTouching,
              isDisabled: widget.isDisabled,
            ),
          ),
          child: Slider(
            value: _sliderValue,
            onChanged: widget.isDisabled ? null : _onSliderChanged,
            onChangeStart: widget.isDisabled ? null : _onSliderChangeStart,
            onChangeEnd: widget.isDisabled ? null : _onSliderChangeEnd,
          ),
        ),
      ],
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

  const _SliderFooter({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.isDisabled,
    required this.maxWidth,
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isActive && !isDisabled
                ? activeColor
                : AppColors.darkTextMuted,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderScale extends StatelessWidget {
  final double value;
  final bool isUp;
  final double fastThreshold;
  final Color activeColor;
  final Color axisColor;
  final bool isDisabled;

  const _SliderScale({
    required this.value,
    required this.isUp,
    required this.fastThreshold,
    required this.activeColor,
    required this.axisColor,
    required this.isDisabled,
  });

  bool get _isIdle => value <= 0.01;
  bool get _isSlow => value > 0.01 && value < fastThreshold;
  bool get _isFast => value >= fastThreshold;

  @override
  Widget build(BuildContext context) {
    final labels = isUp
        ? <Widget>[
            _ScaleLabel(
              text: 'IDLE',
              active: _isIdle,
              activeColor: AppColors.darkTextSub,
            ),
            _ScaleLabel(text: 'SLOW', active: _isSlow, activeColor: axisColor),
            _ScaleLabel(
              text: 'FAST',
              active: _isFast,
              activeColor: AppColors.fastColor,
            ),
          ]
        : <Widget>[
            _ScaleLabel(
              text: 'FAST',
              active: _isFast,
              activeColor: AppColors.fastColor,
            ),
            _ScaleLabel(text: 'SLOW', active: _isSlow, activeColor: axisColor),
            _ScaleLabel(
              text: 'IDLE',
              active: _isIdle,
              activeColor: AppColors.darkTextSub,
            ),
          ];

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ...labels,
        const SizedBox(height: 5),
        _StatusDot(
          isDisabled: isDisabled,
          isIdle: _isIdle,
          activeColor: activeColor,
        ),
      ],
    );
  }
}

class _ScaleLabel extends StatelessWidget {
  final String text;
  final bool active;
  final Color activeColor;

  const _ScaleLabel({
    required this.text,
    required this.active,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.clip,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 7.5,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
          color: active ? activeColor : AppColors.darkTextMuted.withAlpha(90),
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final bool isDisabled;
  final bool isIdle;
  final Color activeColor;

  const _StatusDot({
    required this.isDisabled,
    required this.isIdle,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    if (isDisabled) {
      return const Text(
        '—',
        style: TextStyle(
          fontSize: 9,
          color: AppColors.darkTextMuted,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    return Text(
      '●',
      style: TextStyle(
        fontSize: 9,
        color: isIdle ? AppColors.idleColor : activeColor,
      ),
    );
  }
}

class _CraneTrackPainter extends CustomPainter {
  final double value;
  final double thumbWidth;
  final double trackHeight;
  final double deadZone;
  final double fastThreshold;
  final Color fillColor;
  final bool isActive;

  const _CraneTrackPainter({
    required this.value,
    required this.thumbWidth,
    required this.trackHeight,
    required this.deadZone,
    required this.fastThreshold,
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
      ..color = const Color.fromARGB(255, 192, 25, 25)
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
    drawMarker(fastThreshold);
  }

  @override
  bool shouldRepaint(_CraneTrackPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.thumbWidth != thumbWidth ||
      oldDelegate.trackHeight != trackHeight ||
      oldDelegate.deadZone != deadZone ||
      oldDelegate.fastThreshold != fastThreshold ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.isActive != isActive;
}

class RectSliderThumbShape extends SliderComponentShape {
  final double width;
  final double height;
  final double borderRadius;
  final Color? color;
  final bool isDragging;
  final bool isDisabled;

  const RectSliderThumbShape({
    this.width = 12,
    this.height = 24,
    this.borderRadius = 5,
    this.color,
    this.isDragging = false,
    this.isDisabled = false,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size(width, height);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    if (width <= 0 || height <= 0) return;

    final canvas = context.canvas;
    final activeColor = color ?? sliderTheme.thumbColor ?? Colors.grey;
    final visualDragging = isDragging || activationAnimation.value > 0.05;

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
          ..color = activeColor.withAlpha(85)
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
}
