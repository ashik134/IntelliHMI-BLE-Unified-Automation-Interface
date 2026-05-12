import 'dart:math';

import 'package:flutter/material.dart';
import 'package:rev6_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev6_crane_control_ops/controllers/hmi_layout_controller.dart';
import 'package:rev6_crane_control_ops/models/hmi_layout_models.dart';
import 'package:rev6_crane_control_ops/utils/constants.dart';
import 'package:rev6_crane_control_ops/widgets/crane_slider_button.dart';
import 'package:rev6_crane_control_ops/widgets/estop_swipe_button.dart';

class HmiRuntimeWidget extends StatelessWidget {
  const HmiRuntimeWidget({
    super.key,
    required this.config,
    required this.craneController,
    required this.hmiController,
    required this.editMode,
    required this.selected,
    required this.onTap,
    this.onDragUpdate,
    this.onDragEnd,
    this.onResizeUpdate,
    this.onResizeEnd,
  });

  final HmiWidgetConfig config;
  final CraneController craneController;
  final HmiLayoutController hmiController;
  final bool editMode;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<DragUpdateDetails>? onDragUpdate;
  final VoidCallback? onDragEnd;
  final ValueChanged<DragUpdateDetails>? onResizeUpdate;
  final VoidCallback? onResizeEnd;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? config.color : AppColors.border;
    final child = Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: selected ? 1.8 : 1),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: config.color.withValues(alpha: 0.28),
                  blurRadius: 10,
                  spreadRadius: 1,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          _WidgetHeader(config: config),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
              child: IgnorePointer(ignoring: editMode, child: _buildContent()),
            ),
          ),
        ],
      ),
    );

    if (!editMode) {
      return child;
    }

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            onPanUpdate: onDragUpdate,
            onPanEnd: (_) => onDragEnd?.call(),
            child: child,
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: onResizeUpdate,
            onPanEnd: (_) => onResizeEnd?.call(),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: config.color.withValues(alpha: 0.95),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
              ),
              child: const Icon(
                Icons.open_in_full,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    return switch (config.type) {
      HmiWidgetType.estop => _EmergencyStopCard(
        label: config.label,
        estopLatched: craneController.estopLatched,
        onEStop: hmiController.triggerEmergencyStop,
        onReset: hmiController.resetEmergencyStop,
      ),
      HmiWidgetType.hoistSlider => _HoistSliderCard(
        config: config,
        craneController: craneController,
        hmiController: hmiController,
      ),
      HmiWidgetType.potentiometer => _PotentiometerCard(
        config: config,
        hmiController: hmiController,
      ),
      HmiWidgetType.analogJoystick => _AnalogJoystickCard(
        config: config,
        hmiController: hmiController,
      ),
      HmiWidgetType.digitalJoystick => _DigitalJoystickCard(
        config: config,
        hmiController: hmiController,
      ),
      HmiWidgetType.toggleSwitch => _IndustrialToggleCard(
        config: config,
        hmiController: hmiController,
      ),
      HmiWidgetType.analogMeter => _AnalogMeterCard(
        config: config,
        hmiController: hmiController,
      ),
      HmiWidgetType.valueIndicator => _ValueIndicatorCard(
        config: config,
        hmiController: hmiController,
      ),
    };
  }
}

class _WidgetHeader extends StatelessWidget {
  const _WidgetHeader({required this.config});

  final HmiWidgetConfig config;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 5),
      decoration: BoxDecoration(
        color: AppColors.panelAlt,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(7),
          topRight: Radius.circular(7),
        ),
        border: Border(
          bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.7)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              config.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            config.type.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _EmergencyStopCard extends StatelessWidget {
  const _EmergencyStopCard({
    required this.label,
    required this.estopLatched,
    required this.onEStop,
    required this.onReset,
  });

  final String label;
  final bool estopLatched;
  final Future<void> Function() onEStop;
  final Future<void> Function() onReset;

  @override
  Widget build(BuildContext context) {
    if (estopLatched) {
      return Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.eStopColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.eStopColor.withValues(alpha: 0.45),
                ),
              ),
              child: const Center(
                child: Text(
                  'Emergency Stop Active',
                  style: TextStyle(
                    color: AppColors.eStopColorLight,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.lock_open_rounded, size: 14),
              label: const Text(
                'Reset E-Stop',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.eStopColorLight,
                side: const BorderSide(color: AppColors.eStopColorLight),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: EStopSwipeButton(
            onActivated: () {
              onEStop();
            },
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 9.5),
        ),
      ],
    );
  }
}

class _HoistSliderCard extends StatelessWidget {
  const _HoistSliderCard({
    required this.config,
    required this.craneController,
    required this.hmiController,
  });

  final HmiWidgetConfig config;
  final CraneController craneController;
  final HmiLayoutController hmiController;

  @override
  Widget build(BuildContext context) {
    final isUp = !config.binding.primaryTag.toUpperCase().contains('DOWN');
    final externalState = switch (craneController.hoistState) {
      HoistState.upSlow when isUp => ControlState.slow,
      HoistState.upFast when isUp => ControlState.fast,
      HoistState.downSlow when !isUp => ControlState.slow,
      HoistState.downFast when !isUp => ControlState.fast,
      _ => ControlState.idle,
    };
    final oppositeActive = isUp
        ? craneController.hoistState == HoistState.downSlow ||
              craneController.hoistState == HoistState.downFast
        : craneController.hoistState == HoistState.upSlow ||
              craneController.hoistState == HoistState.upFast;

    return CraneSliderButton(
      label: config.label,
      icon: isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
      isUp: isUp,
      isDisabled:
          craneController.estopLatched ||
          !craneController.isConnected ||
          oppositeActive,
      externalState: externalState,
      onCommandChanged: (state) {
        hmiController.setHoistControl(config.binding.primaryTag, state);
      },
    );
  }
}

class _PotentiometerCard extends StatefulWidget {
  const _PotentiometerCard({required this.config, required this.hmiController});

  final HmiWidgetConfig config;
  final HmiLayoutController hmiController;

  @override
  State<_PotentiometerCard> createState() => _PotentiometerCardState();
}

class _PotentiometerCardState extends State<_PotentiometerCard> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = _currentFromController();
  }

  @override
  void didUpdateWidget(covariant _PotentiometerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.binding.primaryTag !=
        widget.config.binding.primaryTag) {
      _value = _currentFromController();
    }
  }

  double _currentFromController() {
    return widget.hmiController.getAnalogValue(
      widget.config.binding.primaryTag,
    );
  }

  @override
  Widget build(BuildContext context) {
    final behavior = widget.config.behavior;
    final minValue = min(behavior.minValue, behavior.maxValue);
    final maxValue = max(behavior.minValue, behavior.maxValue);
    final range = maxValue - minValue;
    final clampedValue = _value.clamp(minValue, maxValue).toDouble();
    final normalized = range <= 0.001 ? 0.0 : (clampedValue - minValue) / range;

    return Column(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 18,
              activeTrackColor: widget.config.color,
              inactiveTrackColor: AppColors.idleColor,
              thumbColor: widget.config.color,
              overlayColor: widget.config.color.withValues(alpha: 0.18),
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Slider(
              value: normalized.clamp(0.0, 1.0),
              onChanged: (value) {
                final mapped = minValue + (range * value);
                setState(() {
                  _value = mapped;
                });
                widget.hmiController.setAnalogOutputValue(
                  widget.config.binding.primaryTag,
                  mapped,
                );
              },
              onChangeEnd: (_) {
                if (behavior.holdMode == ControlHoldMode.springReturn) {
                  setState(() {
                    _value = 0;
                  });
                  widget.hmiController.setAnalogOutputValue(
                    widget.config.binding.primaryTag,
                    0,
                  );
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${clampedValue.toStringAsFixed(1)} ${behavior.unit}'.trim(),
          style: TextStyle(
            color: widget.config.color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _AnalogJoystickCard extends StatefulWidget {
  const _AnalogJoystickCard({
    required this.config,
    required this.hmiController,
  });

  final HmiWidgetConfig config;
  final HmiLayoutController hmiController;

  @override
  State<_AnalogJoystickCard> createState() => _AnalogJoystickCardState();
}

class _AnalogJoystickCardState extends State<_AnalogJoystickCard> {
  Offset _stick = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final behavior = widget.config.behavior;
    final deadZone = behavior.deadZonePercent / 100;
    final minValue = min(behavior.minValue, behavior.maxValue);
    final maxValue = max(behavior.minValue, behavior.maxValue);
    final range = max(0.001, maxValue - minValue);

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = min(constraints.maxWidth, constraints.maxHeight);
        final radius = side / 2;
        final knobRadius = max(12.0, side * 0.11);

        void updateStick(Offset localPosition) {
          final center = Offset(radius, radius);
          var dx = (localPosition.dx - center.dx) / radius;
          var dy = (localPosition.dy - center.dy) / radius;
          final distance = sqrt((dx * dx) + (dy * dy));
          if (distance > 1) {
            dx /= distance;
            dy /= distance;
          }
          final normalized = Offset(dx, dy);
          setState(() => _stick = normalized);

          final xValue = normalized.dx.abs() < deadZone ? 0.0 : normalized.dx;
          final yValue = normalized.dy.abs() < deadZone ? 0.0 : -normalized.dy;
          final xMapped = minValue + ((xValue + 1) / 2) * range;
          final yMapped = minValue + ((yValue + 1) / 2) * range;

          widget.hmiController.setAnalogOutputValue(
            widget.config.binding.primaryTag,
            xMapped,
          );
          if (behavior.twoAxis &&
              behavior.enableYAxis &&
              (widget.config.binding.secondaryTag?.isNotEmpty ?? false)) {
            widget.hmiController.setAnalogOutputValue(
              widget.config.binding.secondaryTag!,
              yMapped,
            );
          }
        }

        void resetStick() {
          if (behavior.holdMode != ControlHoldMode.springReturn) {
            return;
          }
          setState(() => _stick = Offset.zero);
          widget.hmiController.setAnalogOutputValue(
            widget.config.binding.primaryTag,
            0,
          );
          if (widget.config.binding.secondaryTag != null) {
            widget.hmiController.setAnalogOutputValue(
              widget.config.binding.secondaryTag!,
              0,
            );
          }
        }

        return Center(
          child: GestureDetector(
            onPanDown: (details) => updateStick(details.localPosition),
            onPanUpdate: (details) => updateStick(details.localPosition),
            onPanEnd: (_) => resetStick(),
            onPanCancel: resetStick,
            child: SizedBox(
              width: side,
              height: side,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: side,
                    height: side,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.panelAlt,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: CustomPaint(
                      painter: _CrosshairPainter(color: widget.config.color),
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(
                      _stick.dx * (radius - knobRadius),
                      -_stick.dy * (radius - knobRadius),
                    ),
                    child: Container(
                      width: knobRadius * 2,
                      height: knobRadius * 2,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.config.color,
                        border: Border.all(color: Colors.white24),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  const _CrosshairPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.42)
      ..strokeWidth = 1.1;

    canvas.drawLine(
      Offset(size.width / 2, 6),
      Offset(size.width / 2, size.height - 6),
      paint,
    );
    canvas.drawLine(
      Offset(6, size.height / 2),
      Offset(size.width - 6, size.height / 2),
      paint,
    );
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width * 0.18,
      paint..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _DigitalJoystickCard extends StatefulWidget {
  const _DigitalJoystickCard({
    required this.config,
    required this.hmiController,
  });

  final HmiWidgetConfig config;
  final HmiLayoutController hmiController;

  @override
  State<_DigitalJoystickCard> createState() => _DigitalJoystickCardState();
}

class _DigitalJoystickCardState extends State<_DigitalJoystickCard> {
  int _yStep = 0;

  @override
  Widget build(BuildContext context) {
    final behavior = widget.config.behavior;
    final upTag = widget.config.binding.primaryTag;
    final downTag = widget.config.binding.secondaryTag ?? '';
    final showY = behavior.enableYAxis || downTag.isNotEmpty;

    ControlState upState() {
      if (!behavior.twoStepMode || behavior.stepCountY <= 1) {
        return _yStep > 0 ? ControlState.slow : ControlState.idle;
      }
      if (_yStep <= 0) return ControlState.idle;
      return _yStep == 1 ? ControlState.slow : ControlState.fast;
    }

    ControlState downState() {
      if (!behavior.twoStepMode || behavior.stepCountY <= 1) {
        return _yStep < 0 ? ControlState.slow : ControlState.idle;
      }
      if (_yStep >= 0) return ControlState.idle;
      return _yStep == -1 ? ControlState.slow : ControlState.fast;
    }

    Future<void> applyStep() async {
      final up = upState();
      final down = downState();
      if (up != ControlState.idle) {
        await widget.hmiController.setHoistControl(upTag, up);
        return;
      }
      if (down != ControlState.idle) {
        await widget.hmiController.setHoistControl(downTag, down);
        return;
      }
      await widget.hmiController.setHoistControl(upTag, ControlState.idle);
    }

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: showY
                      ? () {
                          setState(() {
                            final maxSteps = behavior.twoStepMode
                                ? max(1, behavior.stepCountY)
                                : 1;
                            _yStep = (_yStep + 1).clamp(0, maxSteps);
                          });
                          applyStep();
                        }
                      : null,
                  child: const Icon(Icons.keyboard_arrow_up_rounded),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() => _yStep = 0);
                    applyStep();
                  },
                  child: const Icon(Icons.radio_button_unchecked_rounded),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  onPressed: showY
                      ? () {
                          setState(() {
                            final minSteps = behavior.twoStepMode
                                ? -max(1, behavior.stepCountY)
                                : -1;
                            _yStep = (_yStep - 1).clamp(minSteps, 0);
                          });
                          applyStep();
                        }
                      : null,
                  child: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          behavior.twoStepMode
              ? 'Step $_yStep'
              : (_yStep == 0 ? 'Idle' : 'Active'),
          style: TextStyle(
            color: widget.config.color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _IndustrialToggleCard extends StatefulWidget {
  const _IndustrialToggleCard({
    required this.config,
    required this.hmiController,
  });

  final HmiWidgetConfig config;
  final HmiLayoutController hmiController;

  @override
  State<_IndustrialToggleCard> createState() => _IndustrialToggleCardState();
}

class _IndustrialToggleCardState extends State<_IndustrialToggleCard> {
  int _position = 0;

  @override
  Widget build(BuildContext context) {
    final pattern = widget.config.behavior.togglePattern;
    final labels = switch (pattern) {
      TogglePattern.zeroMomentary => const ['0', 'T'],
      TogglePattern.zeroLatched => const ['0', 'R'],
      TogglePattern.latchedZeroLatched => const ['R', '0', 'R'],
      TogglePattern.momentaryZeroLatched => const ['T', '0', 'R'],
      TogglePattern.momentaryZeroMomentary => const ['T', '0', 'T'],
    };
    final isThreePosition = labels.length == 3;
    final primaryTag = widget.config.binding.primaryTag;
    final secondaryTag = widget.config.binding.secondaryTag;

    Future<void> applyPosition() async {
      if (!isThreePosition) {
        final on = _position == 1;
        await widget.hmiController.setDigitalOverride(primaryTag, on);
        return;
      }

      final pos = _position - 1; // -1, 0, +1
      if (pos == 0) {
        await widget.hmiController.setDigitalOverride(primaryTag, false);
        if (secondaryTag != null && secondaryTag.isNotEmpty) {
          await widget.hmiController.setDigitalOverride(secondaryTag, false);
        }
      } else if (pos > 0) {
        await widget.hmiController.setDigitalOverride(primaryTag, true);
      } else if (secondaryTag != null && secondaryTag.isNotEmpty) {
        await widget.hmiController.setDigitalOverride(secondaryTag, true);
      } else {
        await widget.hmiController.setDigitalOverride(primaryTag, true);
      }
    }

    return Column(
      children: [
        SegmentedButton<int>(
          segments: [
            for (var i = 0; i < labels.length; i++)
              ButtonSegment<int>(
                value: i,
                label: Text(
                  labels[i],
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
          selected: {_position},
          onSelectionChanged: (selection) {
            final value = selection.first;
            setState(() => _position = value);
            applyPosition();
            if (pattern == TogglePattern.zeroMomentary ||
                pattern == TogglePattern.momentaryZeroMomentary) {
              Future.delayed(const Duration(milliseconds: 220), () {
                if (!mounted) {
                  return;
                }
                setState(() => _position = isThreePosition ? 1 : 0);
                applyPosition();
              });
            }
          },
          showSelectedIcon: false,
        ),
        const Spacer(),
        Text(
          pattern.key,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _AnalogMeterCard extends StatelessWidget {
  const _AnalogMeterCard({required this.config, required this.hmiController});

  final HmiWidgetConfig config;
  final HmiLayoutController hmiController;

  @override
  Widget build(BuildContext context) {
    final behavior = config.behavior;
    final minValue = min(behavior.minValue, behavior.maxValue);
    final maxValue = max(behavior.minValue, behavior.maxValue);
    final range = max(0.001, maxValue - minValue);
    final value = hmiController.getAnalogValue(config.binding.primaryTag);
    final normalized = ((value - minValue) / range).clamp(0.0, 1.0).toDouble();
    final warning = behavior.warningThreshold;
    final alarm = behavior.alarmThreshold;

    Color stateColor() {
      if (alarm != null && value >= alarm) {
        return AppColors.eStopColor;
      }
      if (warning != null && value >= warning) {
        return AppColors.fastColor;
      }
      return config.color;
    }

    final meterColor = stateColor();

    return Row(
      children: [
        Expanded(
          child: CustomPaint(
            painter: _GaugePainter(
              progress: normalized,
              color: meterColor,
              warningMarker: warning == null
                  ? null
                  : ((warning - minValue) / range).clamp(0.0, 1.0),
              alarmMarker: alarm == null
                  ? null
                  : ((alarm - minValue) / range).clamp(0.0, 1.0),
            ),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value.toStringAsFixed(0),
                style: TextStyle(
                  color: meterColor,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                behavior.unit,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({
    required this.progress,
    required this.color,
    this.warningMarker,
    this.alarmMarker,
  });

  final double progress;
  final Color color;
  final double? warningMarker;
  final double? alarmMarker;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = min(size.width * 0.48, size.height * 0.88);
    const start = pi;
    const sweep = pi;

    final trackPaint = Paint()
      ..color = AppColors.idleColor
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final valuePaint = Paint()
      ..color = color
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, start, sweep, false, trackPaint);
    canvas.drawArc(
      rect,
      start,
      sweep * progress.clamp(0.0, 1.0),
      false,
      valuePaint,
    );

    void marker(double markerValue, Color markerColor) {
      final angle = start + sweep * markerValue.clamp(0.0, 1.0);
      final inner = Offset(
        center.dx + cos(angle) * (radius - 6),
        center.dy + sin(angle) * (radius - 6),
      );
      final outer = Offset(
        center.dx + cos(angle) * (radius + 2),
        center.dy + sin(angle) * (radius + 2),
      );
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = markerColor
          ..strokeWidth = 2,
      );
    }

    if (warningMarker != null) {
      marker(warningMarker!, AppColors.fastColor);
    }
    if (alarmMarker != null) {
      marker(alarmMarker!, AppColors.eStopColor);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.warningMarker != warningMarker ||
        oldDelegate.alarmMarker != alarmMarker;
  }
}

class _ValueIndicatorCard extends StatelessWidget {
  const _ValueIndicatorCard({
    required this.config,
    required this.hmiController,
  });

  final HmiWidgetConfig config;
  final HmiLayoutController hmiController;

  @override
  Widget build(BuildContext context) {
    final value = hmiController.getAnalogValue(config.binding.primaryTag);
    final trend = hmiController.analogTrend(config.binding.primaryTag);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                config.binding.primaryTag,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: config.color,
                ),
              ),
            ],
          ),
        ),
        if (config.behavior.trendEnabled)
          SizedBox(
            width: 80,
            height: 34,
            child: CustomPaint(
              painter: _SparklinePainter(points: trend, color: config.color),
            ),
          ),
      ],
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.points, required this.color});

  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) {
      return;
    }
    var minY = points.first;
    var maxY = points.first;
    for (final value in points.skip(1)) {
      if (value < minY) minY = value;
      if (value > maxY) maxY = value;
    }
    final range = max(1e-6, maxY - minY);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = (i / (points.length - 1)) * size.width;
      final y = size.height - (((points[i] - minY) / range) * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.color != color;
  }
}
