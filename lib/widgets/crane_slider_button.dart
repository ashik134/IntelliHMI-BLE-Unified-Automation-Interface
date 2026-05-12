import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

import 'package:rev6_crane_control_ops/utils/constants.dart';

class CraneSliderButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isUp;
  final bool isDisabled;

  final void Function(ControlState state) onCommandChanged;
  final ControlState externalState;

  const CraneSliderButton({
    super.key,
    required this.label,
    required this.icon,
    required this.isUp,
    this.isDisabled = false,

    required this.onCommandChanged,
    this.externalState = ControlState.idle,
  });

  @override
  State<CraneSliderButton> createState() => _CraneSliderButtonState();
}

class _CraneSliderButtonState extends State<CraneSliderButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulsecontroller;
  late Animation<double> _pulseAnim;

  ControlState _state = ControlState.idle;
  double _sliderValue = 0.0; // 0.0 = idle, 0.0-0.55 = slow, 0.55-1.0 = fast
  bool _isTouching = false;

  static const double _fastThreshold = 0.55;

  @override
  void initState() {
    super.initState();
    _state = widget.externalState;
    _pulsecontroller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulsecontroller, curve: Curves.easeInOut),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(CraneSliderButton old) {
    super.didUpdateWidget(old);
    if (widget.isDisabled && !old.isDisabled) {
      setState(() {
        _isTouching = false;
        _sliderValue = 0.0;
        _state = ControlState.idle;
      });
      _syncAnimation();
      return;
    }
    if (widget.externalState != old.externalState && !_isTouching) {
      setState(() {
        _state = widget.externalState;
        _sliderValue = _state == ControlState.fast
            ? 1.0
            : _state == ControlState.slow
            ? 0.5
            : 0.0;
      });
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    switch (_state) {
      case ControlState.idle:
        _pulsecontroller.stop();
        _pulsecontroller.value = 0;
        break;
      case ControlState.slow:
        _pulsecontroller.repeat(
          reverse: true,
          period: const Duration(milliseconds: 900),
        );
        break;
      case ControlState.fast:
        _pulsecontroller.repeat(
          reverse: true,
          period: const Duration(milliseconds: 420),
        );
        break;
    }
  }

  ControlState _getStateFromSlider(double value) {
    if (value <= 0.01) return ControlState.idle;
    if (value < _fastThreshold) return ControlState.slow;
    return ControlState.fast;
  }

  void _emitCommand(ControlState newState) {
    if (_state == newState) return;
    setState(() {
      _state = newState;
    });
    _syncAnimation();
    widget.onCommandChanged(newState);

    switch (newState) {
      case ControlState.idle:
        Vibration.vibrate(duration: 15);
        debugPrint("${widget.label} command: IDLE");
        break;
      case ControlState.slow:
        Vibration.vibrate(duration: 25, amplitude: 100);
        debugPrint("${widget.label} command: SLOW");
        break;
      case ControlState.fast:
        Vibration.vibrate(duration: 55, amplitude: 255);
        debugPrint("${widget.label} command: FAST");
        break;
    }
  }

  void _onSliderChanged(double value) {
    if (widget.isDisabled) return;

    setState(() {
      _sliderValue = value;
      _isTouching = true;
    });

    final newState = _getStateFromSlider(value);
    _emitCommand(newState);

    debugPrint(
      "${widget.label} slider: ${(value * 100).toStringAsFixed(1)}% - ${newState.name}",
    );
  }

  void _onSliderChangeStart(double value) {
    if (widget.isDisabled) return;
    _isTouching = true;
    debugPrint("Slider touch started: ${widget.label}");
  }

  void _onSliderChangeEnd(double value) {
    _isTouching = false;
    setState(() {
      _sliderValue = 0.0;
    });
    _emitCommand(ControlState.idle);
    _pulsecontroller.forward(from: 0.0);
    debugPrint("Slider released: ${widget.label}");
  }

  Color get _primaryColor {
    if (widget.isDisabled) return Colors.grey.shade400;

    switch (_state) {
      case ControlState.idle:
        return AppColors.idleColor;
      case ControlState.slow:
        return widget.isUp ? AppColors.upColor : AppColors.downColor;
      case ControlState.fast:
        return AppColors.fastColor;
    }
  }

  // ignore: unused_element
  Color get _bgColor {
    if (widget.isDisabled) return AppColors.idleColor.withAlpha(25);

    switch (_state) {
      case ControlState.idle:
        return AppColors.panelAlt;
      case ControlState.slow:
        return (widget.isUp ? AppColors.upColorLight : AppColors.downColorLight)
            .withAlpha((0.25 * 255).toInt());
      case ControlState.fast:
        return AppColors.fastColorLight.withAlpha((0.33 * 255).toInt());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, _) {
        // ignore: unused_local_variable
        final glow = _state != ControlState.idle
            ? _primaryColor.withAlpha(
                (0.14 + 0.26 * _pulseAnim.value * 255).toInt(),
              )
            : Colors.transparent;

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(6, 0, 6, 0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // _stageDots(),
                  // const SizedBox(height: 10),
                  // Icon(widget.icon, size: 16, color: _primaryColor),
                  // const SizedBox(height: 3),
                  // Text(
                  //   widget.label,
                  //   textAlign: TextAlign.center,
                  //   style: TextStyle(
                  //     fontSize: 13,
                  //     fontWeight: FontWeight.bold,
                  //     color: _primaryColor,
                  //     letterSpacing: 0.5,
                  //     height: 1.25,
                  //   ),
                  // ),
                  // const SizedBox(height: 6),
                  // _statusBadge(),
                ],
              ),
            ),

            // Vertical Slider Section
            Row(
              children: [
                Padding(
              padding: const EdgeInsets.fromLTRB(6, 3, 6, 7),
              child: Column(
                children: [
                  _sliderIndicator(),
                  // const SizedBox(height: 5),
                  // _plcOutputDisplay(),
                ],
              ),
            ),
                Center(
                  child: RotatedBox(
                    quarterTurns: widget.isUp ? -1 : 1,
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 16,
                        thumbShape: const RectSliderThumbShape(
                          width: 20,
                          height: 34,
                          borderRadius: 5,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 10
                        ),
                        activeTrackColor: _sliderValue >= _fastThreshold
                            ? AppColors.fastColor
                            : (widget.isUp
                                  ? AppColors.upColor
                                  : AppColors.downColor),
                        inactiveTrackColor: Colors.grey.shade200,
                        thumbColor: _sliderValue >= _fastThreshold
                            ? AppColors.fastColor
                            : (widget.isUp
                                  ? AppColors.upColor
                                  : AppColors.downColor),
                        overlayColor: _primaryColor.withAlpha(50),
                      ),
                      child: Slider(
                        value: _sliderValue,
                        onChanged: widget.isDisabled ? null : _onSliderChanged,
                        onChangeStart: _onSliderChangeStart,
                        onChangeEnd: _onSliderChangeEnd,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Bottom info section
            
          ],
        );
      },
    );
  }

  // Widget _stageDots() {
  //   final slowColor = widget.isUp ? AppColors.upColor : AppColors.downColor;
  //   final slowactive =
  //       _state == ControlState.slow || _state == ControlState.fast;
  //   final fastactive = _state == ControlState.fast;

  //   return Row(
  //     mainAxisAlignment: MainAxisAlignment.center,
  //     children: [
  //       _dot(label: 'Slow', active: slowactive, color: slowColor),
  //       const SizedBox(width: 8),
  //       _dot(label: 'Fast', active: fastactive, color: AppColors.fastColor),
  //     ],
  //   );
  // }

  // Widget _dot({
  //   required String label,
  //   required bool active,
  //   required Color color,
  // }) {
  //   return Column(
  //     children: [
  //       AnimatedContainer(
  //         duration: const Duration(milliseconds: 200),
  //         width: 10,
  //         height: 10,
  //         decoration: BoxDecoration(
  //           color: active ? color : Colors.grey.shade300,
  //           shape: BoxShape.circle,
  //           boxShadow: active
  //               ? [
  //                   BoxShadow(
  //                     color: color.withAlpha((0.5 * 255).toInt()),
  //                     blurRadius: 5,
  //                   ),
  //                 ]
  //               : [],
  //         ),
  //       ),
  //       const SizedBox(height: 2),
  //       Text(
  //         label,
  //         style: TextStyle(
  //           fontSize: 8,
  //           fontWeight: FontWeight.w600,
  //           color: active ? color : Colors.grey.shade400,
  //         ),
  //       ),
  //     ],
  //   );
  // }

  // Widget _statusBadge() {
    
  //   String label;
  //   Color color;
  //   switch (_state) {
  //     case ControlState.idle:
  //       label = "IDLE";
  //       color = AppColors.idleColor;
  //       break;
  //     case ControlState.slow:
  //       label = "SLOW";
  //       color = widget.isUp ? AppColors.upColor : AppColors.downColor;
  //       break;
  //     case ControlState.fast:
  //       label = "FAST";
  //       color = AppColors.fastColor;
  //       break;
  //   }

  //   return Text(
  //     label,
  //     style: TextStyle(
  //       color: color,
  //       fontSize: 8,
  //       fontWeight: FontWeight.bold,
  //       letterSpacing: 0.5,
  //     ),
  //   );
  // }

Widget _sliderIndicator() {
    final pct = (_sliderValue * 100).toInt();
    final indicatorColor = _sliderValue >= _fastThreshold
        ? AppColors.fastColor
        : (widget.isUp ? AppColors.upColor : AppColors.downColor);
    final isUpDirection = widget.isUp;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
      
        SizedBox(
          width: 28,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: isUpDirection
                ? [
                    // UP: IDLE (top) → FAST (bottom)
                    _buildLabel('IDLE', active: _sliderValue <= 0.01, color: AppColors.idleColor),
                    _buildLabel('SLOW', active: _sliderValue > 0.01 && _sliderValue < _fastThreshold, color: indicatorColor),
                    _buildLabel('FAST', active: _sliderValue >= _fastThreshold, color: AppColors.fastColor),
                  ]
                : [
                    // DOWN: FAST (top) → IDLE (bottom)
                    _buildLabel('FAST', active: _sliderValue >= _fastThreshold, color: AppColors.fastColor),
                    _buildLabel('SLOW', active: _sliderValue > 0.01 && _sliderValue < _fastThreshold, color: indicatorColor),
                    _buildLabel('IDLE', active: _sliderValue <= 0.01, color: AppColors.idleColor),
                  ],
          ),
        ),

        const SizedBox(width: 6),

        // ── Vertical Progress Bar with Threshold Lines ──
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Direction icon
            Icon(
              isUpDirection ? Icons.arrow_upward : Icons.arrow_downward,
              size: 10,
              color: _sliderValue > 0.01 ? indicatorColor : AppColors.textMuted,
            ),
            const SizedBox(height: 2),
            
            // Progress bar
            Container(
              width: 6,
              height: 70,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Stack(
                children: [
                  // Fast threshold line (at 70%)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: isUpDirection ? 70 * (1 - _fastThreshold) : 70 * _fastThreshold,
                    child: Container(
                      height: 1,
                      color: AppColors.fastColor.withAlpha((0.3 * 255).toInt()),
                    ),
                  ),
                  // Fill
                  Align(
                    alignment: isUpDirection
                        ? Alignment.bottomCenter
                        : Alignment.topCenter,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOutCubic,
                      height: 70 * _sliderValue,
                      decoration: BoxDecoration(
                        color: indicatorColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 2),
            // Percentage
            Text(
              '$pct%',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: _isTouching ? indicatorColor : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLabel(String text, {required bool active, required Color color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 8,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
          color: active ? color : AppColors.textMuted,
        ),
      ),
    );
  }

  // Widget _plcOutputDisplay() {
  //   // final List<int> output = widget.inConflict
  //   //     ? plcConflict
  //   //     :
  //   final List<int> output = widget.isUp ? plcOutputUp[_state]! : plcOutputDown[_state]!;

  //   return Row(
  //     mainAxisAlignment: MainAxisAlignment.center,
  //     children: [
  //       ...output.map((bit) {
  //         final active = bit == 1;
  //         return Container(
  //           margin: const EdgeInsets.only(right: 3),
  //           padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
  //           decoration: BoxDecoration(
  //             color: active
  //                 ? _primaryColor.withAlpha((0.2 * 255).toInt())
  //                 : Colors.grey.shade200,
  //             borderRadius: BorderRadius.circular(3),
  //           ),
  //           child: Text(
  //             '$bit',
  //             style: TextStyle(
  //               fontSize: 9,
  //               fontWeight: FontWeight.bold,
  //               color: active ? _primaryColor : Colors.grey.shade400,
  //               fontFamily: 'monospace',
  //             ),
  //           ),
  //         );
  //       }),
  //     ],
  //   );
  // }

  @override
  void dispose() {
    _pulsecontroller.dispose();
    super.dispose();
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
    final canvas = context.canvas;
    final paint = Paint()
      ..color = sliderTheme.thumbColor ?? Colors.grey
      ..style = PaintingStyle.fill;

    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: width, height: height),
      Radius.circular(borderRadius),
    );
    canvas.drawRRect(rect, paint);
  }
}
