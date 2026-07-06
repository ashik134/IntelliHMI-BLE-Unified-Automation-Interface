import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';

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

    if (!_isTouching && widget.externalState != oldWidget.externalState) {
      _syncFromExternalState(widget.externalState);
    }
  }

  void _syncFromExternalState(ControlState state) {
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
    _isTouching = true;
  }

  void _onSliderChangeEnd(double _) {
    if (widget.isDisabled) return;

    final shouldNotifyIdle = _state != ControlState.idle;

    setState(() {
      _isTouching = false;
      _sliderValue = 0.0;
      _state = ControlState.idle;
    });

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
    if (widget.isDisabled) return Colors.grey.shade400;
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

        final showIndicator = width >= 92 && height >= 88;
        final sliderWidth = (showIndicator ? width - 68 : width).clamp(
          0.0,
          54.0,
        );
        final trackLength = (height - 6).clamp(0.0, 160.0);

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (showIndicator)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 3, 6, 7),
                child: _SliderIndicator(
                  value: _sliderValue,
                  isUp: widget.isUp,
                  isTouching: _isTouching,
                  axisColor: _axisColor,
                  fastThreshold: _fastThreshold,
                  maxHeight: height,
                ),
              ),
            SizedBox(
              width: sliderWidth,
              child: Center(
                child: RotatedBox(
                  quarterTurns: widget.isUp ? -1 : 1,
                  child: SizedBox(
                    width: trackLength,
                    height: sliderWidth,
                    child: _buildSliderTheme(sliderWidth),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSliderTheme(double sliderWidth) {
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: (sliderWidth * 0.32).clamp(0.0, 16.0),
        thumbShape: RectSliderThumbShape(
          width: (sliderWidth * 0.38).clamp(0.0, 20.0),
          height: (sliderWidth * 0.64).clamp(0.0, 34.0),
          borderRadius: 5,
        ),
        overlayShape: RoundSliderOverlayShape(
          overlayRadius: (sliderWidth * 0.22).clamp(0.0, 10.0),
        ),
        activeTrackColor: _activeSliderColor,
        inactiveTrackColor: Colors.grey.shade200,
        thumbColor: _activeSliderColor,
        overlayColor: _overlayColor,
      ),
      child: Slider(
        value: _sliderValue,
        onChanged: widget.isDisabled ? null : _onSliderChanged,
        onChangeStart: widget.isDisabled ? null : _onSliderChangeStart,
        onChangeEnd: widget.isDisabled ? null : _onSliderChangeEnd,
      ),
    );
  }
}

class _SliderIndicator extends StatelessWidget {
  final double value;
  final bool isUp;
  final bool isTouching;
  final Color axisColor;
  final double fastThreshold;
  final double maxHeight;

  const _SliderIndicator({
    required this.value,
    required this.isUp,
    required this.isTouching,
    required this.axisColor,
    required this.fastThreshold,
    required this.maxHeight,
  });

  Color get _indicatorColor =>
      value >= fastThreshold ? AppColors.fastColor : axisColor;

  @override
  Widget build(BuildContext context) {
    final barHeight = (maxHeight - 42).clamp(38.0, 70.0);
    final percent = (value * 100).round();

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 28, child: _buildLabels()),
        const SizedBox(width: 6),
        SizedBox(
          width: 22,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                isUp ? Icons.arrow_upward : Icons.arrow_downward,
                size: 10,
                color: value > 0.01 ? _indicatorColor : AppColors.darkTextMuted,
              ),
              const SizedBox(height: 2),
              _buildProgressBar(barHeight),
              const SizedBox(height: 2),
              Text(
                '$percent%',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: isTouching ? _indicatorColor : AppColors.darkTextMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLabels() {
    final labels = isUp
        ? <Widget>[
            _ScaleLabel(
              text: 'IDLE',
              active: value <= 0.01,
              activeColor: AppColors.darkTextSub,
            ),
            _ScaleLabel(
              text: 'SLOW',
              active: value > 0.01 && value < fastThreshold,
              activeColor: _indicatorColor,
            ),
            _ScaleLabel(
              text: 'FAST',
              active: value >= fastThreshold,
              activeColor: AppColors.fastColor,
            ),
          ]
        : <Widget>[
            _ScaleLabel(
              text: 'FAST',
              active: value >= fastThreshold,
              activeColor: AppColors.fastColor,
            ),
            _ScaleLabel(
              text: 'SLOW',
              active: value > 0.01 && value < fastThreshold,
              activeColor: _indicatorColor,
            ),
            _ScaleLabel(
              text: 'IDLE',
              active: value <= 0.01,
              activeColor: AppColors.darkTextSub,
            ),
          ];

    return Column(mainAxisSize: MainAxisSize.min, children: labels);
  }

  Widget _buildProgressBar(double height) {
    return Container(
      width: 6,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: isUp ? height * (1 - fastThreshold) : height * fastThreshold,
            child: Container(
              height: 1,
              color: AppColors.fastColor.withAlpha(77),
            ),
          ),
          Align(
            alignment: isUp ? Alignment.bottomCenter : Alignment.topCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              width: 6,
              height: height * value,
              decoration: BoxDecoration(
                color: _indicatorColor,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ),
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
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 8,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
          color: active ? activeColor : AppColors.idleColor,
        ),
      ),
    );
  }
}

class RectSliderThumbShape extends SliderComponentShape {
  final double width;
  final double height;
  final double borderRadius;

  const RectSliderThumbShape({
    this.width = 12,
    this.height = 24,
    this.borderRadius = 5,
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
    final paint = Paint()
      ..color = sliderTheme.thumbColor ?? Colors.grey
      ..style = PaintingStyle.fill;

    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: width, height: height),
      Radius.circular(borderRadius),
    );

    context.canvas.drawRRect(rect, paint);
  }
}
