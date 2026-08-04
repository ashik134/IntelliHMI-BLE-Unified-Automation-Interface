import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/analog_joystick_config.dart';
import 'package:rev_crane_control_ops/models/analog_slider_config.dart';
import 'package:rev_crane_control_ops/models/button_behavior_config.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/button_icon_registry.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart'
    show PushButtonWiringConfig;
import 'package:rev_crane_control_ops/models/joystick_config.dart';
import 'package:rev_crane_control_ops/models/multi_zone_slider_config.dart';
import 'package:rev_crane_control_ops/models/potentiometer_config.dart';
import 'package:rev_crane_control_ops/models/toggle_button_config.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/general_tab.dart'
    show ButtonUpdater;
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/icon_picker_sheet.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/property_field_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FunctionTab
//
// The one genuinely type-aware tab: dispatches on ButtonType to one of 6
// per-family builders. Every field here is sourced from that type's own
// customProperties config class (JoystickConfig/PotentiometerConfig/
// AnalogSliderConfig/AnalogJoystickConfig already existed; MultiZoneSliderConfig/
// ToggleButtonConfig are new — see their own doc comments) — this file is
// pure UI over configs that already fully round-trip through ButtonConfig.
// ─────────────────────────────────────────────────────────────────────────────

class FunctionTab extends StatelessWidget {
  const FunctionTab({super.key, required this.config, required this.onUpdate});

  final ButtonConfig config;
  final ButtonUpdater onUpdate;

  void _updateCustomProperties(
    Map<String, dynamic> Function(Map<String, dynamic>) f,
  ) {
    onUpdate((b) => b.copyWith(customProperties: f(b.customProperties)));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      children: switch (config.type) {
        ButtonType.sliderButton => _sliderButtonFields(),
        ButtonType.bidirectionalSlider5Step ||
        ButtonType.bidirectionalSlider3Step => _multiZoneSliderFields(
          fiveZone: config.type == ButtonType.bidirectionalSlider5Step,
        ),
        ButtonType.pushButton => _pushButtonFields(),
        ButtonType.toggle => _toggleFields(context),
        ButtonType.joystick => _joystickFields(),
        ButtonType.potentiometer => _potentiometerFields(),
        ButtonType.analogSliderOT ||
        ButtonType.analogSliderTOT => _analogSliderFields(),
        ButtonType.analogJoystick1D ||
        ButtonType.analogJoystick2D => _analogJoystickFields(
          dualAxis: config.type == ButtonType.analogJoystick2D,
        ),
        ButtonType.horn ||
        ButtonType.alarmIndicator => const [
          PropertyInfoBanner(
            text: 'This widget type has no additional function settings.',
          ),
        ],
      },
    );
  }

  // ── Sliders ──────────────────────────────────────────────────────────────

  List<Widget> _sliderButtonFields() => const [
    PropertyInfoBanner(
      text:
          'Spring-return, two graduated steps in one direction. Colors are '
          'set on the Appearance tab; output mapping on the Output tab.',
    ),
  ];

  List<Widget> _multiZoneSliderFields({required bool fiveZone}) {
    final zoneConfig = MultiZoneSliderConfig.fromCustomProperties(
      config.customProperties,
    );
    void update(MultiZoneSliderConfig Function(MultiZoneSliderConfig) f) {
      _updateCustomProperties(
        (props) => f(zoneConfig).applyToCustomProperties(props),
      );
    }

    return [
      const PropertySectionHeader('Step Labels', padTop: 4),
      _ResyncTextField(
        label: 'Negative-side label',
        value: zoneConfig.startLabel ?? '',
        onChanged: (v) => update(
          (c) => v.trim().isEmpty
              ? c.copyWith(clearStartLabel: true)
              : c.copyWith(startLabel: v),
        ),
      ),
      _ResyncTextField(
        label: 'Positive-side label',
        value: zoneConfig.endLabel ?? '',
        onChanged: (v) => update(
          (c) => v.trim().isEmpty
              ? c.copyWith(clearEndLabel: true)
              : c.copyWith(endLabel: v),
        ),
      ),
      const PropertySectionHeader('Sensitivity'),
      PropertyLabeledSlider(
        label: 'Dead zone around center',
        value: zoneConfig.deadZoneFraction,
        min: MultiZoneSliderConfig.minDeadZoneFraction,
        max: MultiZoneSliderConfig.maxDeadZoneFraction,
        valueLabel: '${(zoneConfig.deadZoneFraction * 100).round()}%',
        onChanged: (v) => update((c) => c.copyWith(deadZoneFraction: v)),
      ),
      if (fiveZone)
        PropertyLabeledSlider(
          label: 'Near/far zone threshold',
          value: zoneConfig.farZoneFraction,
          min: MultiZoneSliderConfig.minFarZoneFraction,
          max: MultiZoneSliderConfig.maxFarZoneFraction,
          valueLabel: '${(zoneConfig.farZoneFraction * 100).round()}%',
          onChanged: (v) => update((c) => c.copyWith(farZoneFraction: v)),
        ),
      const PropertyInfoBanner(
        text:
            'Spring-return is fixed for this control type. Zone-to-output '
            'mapping is on the Output tab.',
      ),
    ];
  }

  // ── Push buttons ─────────────────────────────────────────────────────────

  List<Widget> _pushButtonFields() {
    final behavior = config.behavior;
    void update(ButtonBehaviorConfig Function(ButtonBehaviorConfig) f) {
      onUpdate((b) => b.copyWith(behavior: f(b.behavior)));
    }

    return [
      const PropertySectionHeader('Behavior', padTop: 4),
      PropertySegmented<PushButtonWiringConfig>(
        options: const [
          (PushButtonWiringConfig.offMomentary, 'Spring-return'),
          (PushButtonWiringConfig.offLatched, 'Latching'),
        ],
        selected: behavior.wiring == PushButtonWiringConfig.offLatched
            ? PushButtonWiringConfig.offLatched
            : PushButtonWiringConfig.offMomentary,
        onChanged: (w) => update((c) => c.copyWith(wiring: w)),
      ),
      const SizedBox(height: 8),
      PropertySwitchTile(
        title: 'Repeat while held',
        subtitle: 'Re-sends the active command on an interval while pressed.',
        value: behavior.repeatWhileHeld,
        onChanged: (v) => update((c) => c.copyWith(repeatWhileHeld: v)),
      ),
      if (behavior.repeatWhileHeld)
        PropertyLabeledSlider(
          label: 'Repeat interval',
          value: behavior.repeatIntervalMs.toDouble(),
          min: ButtonBehaviorConfig.minRepeatIntervalMs.toDouble(),
          max: ButtonBehaviorConfig.maxRepeatIntervalMs.toDouble(),
          valueLabel: '${behavior.repeatIntervalMs} ms',
          onChanged: (v) =>
              update((c) => c.copyWith(repeatIntervalMs: v.round())),
        ),
      const PropertySectionHeader('Press Feel'),
      PropertyLabeledSlider(
        label: 'Debounce delay',
        value: behavior.debounceMs.toDouble(),
        min: ButtonBehaviorConfig.minDebounceMs.toDouble(),
        max: ButtonBehaviorConfig.maxDebounceMs.toDouble(),
        valueLabel: behavior.debounceMs == 0
            ? 'Off'
            : '${behavior.debounceMs} ms',
        onChanged: (v) => update((c) => c.copyWith(debounceMs: v.round())),
      ),
      PropertyLabeledSlider(
        label: 'Long-press required',
        value: behavior.longPressRequiredMs.toDouble(),
        min: ButtonBehaviorConfig.minLongPressRequiredMs.toDouble(),
        max: ButtonBehaviorConfig.maxLongPressRequiredMs.toDouble(),
        valueLabel: behavior.longPressRequiredMs == 0
            ? 'Off — tap to activate'
            : '${behavior.longPressRequiredMs} ms',
        onChanged: (v) =>
            update((c) => c.copyWith(longPressRequiredMs: v.round())),
      ),
      PropertyLabeledSlider(
        label: 'Press animation strength',
        value: behavior.pressAnimationStrength,
        min: ButtonBehaviorConfig.minPressAnimationStrength,
        max: ButtonBehaviorConfig.maxPressAnimationStrength,
        valueLabel: '${(behavior.pressAnimationStrength * 100).round()}%',
        onChanged: (v) => update((c) => c.copyWith(pressAnimationStrength: v)),
      ),
    ];
  }

  // ── Toggle buttons ───────────────────────────────────────────────────────

  List<Widget> _toggleFields(BuildContext context) {
    final behavior = config.behavior;
    final toggleConfig = ToggleButtonConfig.fromCustomProperties(
      config.customProperties,
    );
    void updateBehavior(ButtonBehaviorConfig Function(ButtonBehaviorConfig) f) {
      onUpdate((b) => b.copyWith(behavior: f(b.behavior)));
    }

    void updateToggle(ToggleButtonConfig Function(ToggleButtonConfig) f) {
      _updateCustomProperties(
        (props) => f(toggleConfig).applyToCustomProperties(props),
      );
    }

    Future<void> pickIcon({required bool left}) async {
      final currentKey = left
          ? toggleConfig.leftIconKey
          : toggleConfig.rightIconKey;
      final result = await showIconPickerSheet(context, currentKey: currentKey);
      if (result == null) return;
      updateToggle(
        (c) => left
            ? c.copyWith(
                leftIconKey: result.iconKey,
                clearLeftIconKey: result.iconKey == null,
              )
            : c.copyWith(
                rightIconKey: result.iconKey,
                clearRightIconKey: result.iconKey == null,
              ),
      );
    }

    return [
      const PropertySectionHeader('Wiring', padTop: 4),
      PropertySegmented<PushButtonWiringConfig>(
        options: const [
          (PushButtonWiringConfig.offMomentary, 'O–T'),
          (PushButtonWiringConfig.offLatched, 'O–R'),
          (PushButtonWiringConfig.springReturnBoth, 'R–O–R'),
          (PushButtonWiringConfig.latchingBoth, 'T–O–T'),
          (PushButtonWiringConfig.mixedLeftLatchRightSpring, 'T–O–R'),
        ],
        selected: behavior.wiring,
        onChanged: (w) => updateBehavior((c) => c.copyWith(wiring: w)),
      ),
      const PropertySectionHeader('Left Side (Top)'),
      _ResyncTextField(
        label: 'Left label',
        value: toggleConfig.leftLabel ?? '',
        onChanged: (v) => updateToggle(
          (c) => v.trim().isEmpty
              ? c.copyWith(clearLeftLabel: true)
              : c.copyWith(leftLabel: v),
        ),
      ),
      _IconPickerRow(
        label: 'Left icon',
        iconKey: toggleConfig.leftIconKey,
        onTap: () => pickIcon(left: true),
      ),
      PropertySwitchTile(
        title: 'Disable left side',
        value: toggleConfig.disableLeft,
        onChanged: (v) => updateToggle((c) => c.copyWith(disableLeft: v)),
      ),
      const PropertySectionHeader('Right Side (Bottom)'),
      _ResyncTextField(
        label: 'Right label',
        value: toggleConfig.rightLabel ?? '',
        onChanged: (v) => updateToggle(
          (c) => v.trim().isEmpty
              ? c.copyWith(clearRightLabel: true)
              : c.copyWith(rightLabel: v),
        ),
      ),
      _IconPickerRow(
        label: 'Right icon',
        iconKey: toggleConfig.rightIconKey,
        onTap: () => pickIcon(left: false),
      ),
      PropertySwitchTile(
        title: 'Disable right side',
        value: toggleConfig.disableRight,
        onChanged: (v) => updateToggle((c) => c.copyWith(disableRight: v)),
      ),
    ];
  }

  // ── Digital joystick ─────────────────────────────────────────────────────

  List<Widget> _joystickFields() {
    final joystickConfig = JoystickConfig.fromCustomProperties(
      config.customProperties,
    );
    void update(JoystickConfig Function(JoystickConfig) f) {
      _updateCustomProperties(
        (props) => f(joystickConfig).applyToCustomProperties(props),
      );
    }

    final isDualAxis = joystickConfig.isDualAxis;

    return [
      PropertyInfoBanner(
        text:
            'Mode: ${joystickConfig.mode.label} (fixed by the catalogue '
            'variant this widget was placed from).',
      ),
      if (!isDualAxis) ...[
        const PropertySectionHeader('Axis'),
        PropertySegmented<JoystickAxis>(
          options: const [
            (JoystickAxis.vertical, 'Vertical'),
            (JoystickAxis.horizontal, 'Horizontal'),
          ],
          selected: joystickConfig.axis,
          onChanged: (a) => update((c) => c.copyWith(axis: a)),
        ),
      ],
      if (isDualAxis) ...[
        const PropertySectionHeader('Boundary'),
        PropertySegmented<JoystickBoundary>(
          options: const [
            (JoystickBoundary.circular, 'Circular'),
            (JoystickBoundary.square, 'Square'),
          ],
          selected: joystickConfig.boundary,
          onChanged: (v) => update((c) => c.copyWith(boundary: v)),
        ),
        const SizedBox(height: 8),
        PropertySwitchTile(
          title: 'Allow diagonal directions',
          value: joystickConfig.allowDiagonal,
          onChanged: (v) => update((c) => c.copyWith(allowDiagonal: v)),
        ),
      ],
      const PropertySectionHeader('Behavior'),
      PropertySwitchTile(
        title: 'Spring return to center',
        value: joystickConfig.springReturn,
        onChanged: (v) => update((c) => c.copyWith(springReturn: v)),
      ),
      PropertyLabeledSlider(
        label: 'Dead zone',
        value: joystickConfig.deadZone,
        min: 0,
        max: 0.9,
        valueLabel: '${(joystickConfig.deadZone * 100).round()}%',
        onChanged: (v) => update((c) => c.copyWith(deadZone: v)),
      ),
      PropertyLabeledSlider(
        label: 'Slow threshold',
        value: joystickConfig.slowThreshold,
        min: 0,
        max: 1,
        valueLabel: '${(joystickConfig.slowThreshold * 100).round()}%',
        onChanged: (v) => update((c) => c.copyWith(slowThreshold: v)),
      ),
      PropertyLabeledSlider(
        label: 'Fast threshold',
        value: joystickConfig.fastThreshold,
        min: 0,
        max: 1,
        valueLabel: '${(joystickConfig.fastThreshold * 100).round()}%',
        onChanged: (v) => update((c) => c.copyWith(fastThreshold: v)),
      ),
    ];
  }

  // ── Potentiometer ────────────────────────────────────────────────────────

  List<Widget> _potentiometerFields() {
    final potConfig = PotentiometerConfig.fromCustomProperties(
      config.customProperties,
    );
    void update(PotentiometerConfig Function(PotentiometerConfig) f) {
      _updateCustomProperties(
        (props) => f(potConfig).applyToCustomProperties(props),
      );
    }

    return [
      const PropertySectionHeader('Range', padTop: 4),
      _numberField(
        label: 'Minimum value',
        value: potConfig.minValue,
        onChanged: (v) => update((c) => c.copyWith(minValue: v)),
      ),
      _numberField(
        label: 'Maximum value',
        value: potConfig.maxValue,
        onChanged: (v) => update((c) => c.copyWith(maxValue: v)),
      ),
      _numberField(
        label: 'Default value',
        value: potConfig.defaultValue,
        onChanged: (v) => update((c) => c.copyWith(defaultValue: v)),
      ),
      _numberField(
        label: 'Step size',
        value: potConfig.stepSize,
        onChanged: (v) => update((c) => c.copyWith(stepSize: v)),
      ),
      _ResyncTextField(
        label: 'Unit (e.g. %, V, rpm)',
        value: potConfig.unit,
        onChanged: (v) => update((c) => c.copyWith(unit: v)),
      ),
      PropertySwitchTile(
        title: 'Show value text',
        value: potConfig.showValue,
        onChanged: (v) => update((c) => c.copyWith(showValue: v)),
      ),
    ];
  }

  // ── Analog slider ────────────────────────────────────────────────────────

  List<Widget> _analogSliderFields() {
    final sliderConfig = AnalogSliderConfig.fromCustomProperties(
      config.customProperties,
    );
    void update(AnalogSliderConfig Function(AnalogSliderConfig) f) {
      _updateCustomProperties(
        (props) => f(sliderConfig).applyToCustomProperties(props),
      );
    }

    return [
      const PropertySectionHeader('Range', padTop: 4),
      _numberField(
        label: 'Minimum value',
        value: sliderConfig.minValue,
        onChanged: (v) => update((c) => c.copyWith(minValue: v)),
      ),
      _numberField(
        label: 'Maximum value',
        value: sliderConfig.maxValue,
        onChanged: (v) => update((c) => c.copyWith(maxValue: v)),
      ),
      _numberField(
        label: 'Neutral value',
        value: sliderConfig.neutralValue,
        onChanged: (v) => update((c) => c.copyWith(neutralValue: v)),
      ),
      _numberField(
        label: 'Step size',
        value: sliderConfig.stepSize,
        onChanged: (v) => update((c) => c.copyWith(stepSize: v)),
      ),
      _ResyncTextField(
        label: 'Unit',
        value: sliderConfig.unit,
        onChanged: (v) => update((c) => c.copyWith(unit: v)),
      ),
      const PropertySectionHeader('Behavior'),
      PropertySegmented<AnalogSliderOrientation>(
        options: const [
          (AnalogSliderOrientation.vertical, 'Vertical'),
          (AnalogSliderOrientation.horizontal, 'Horizontal'),
        ],
        selected: sliderConfig.orientation,
        onChanged: (o) => update((c) => c.copyWith(orientation: o)),
      ),
      const SizedBox(height: 8),
      PropertySwitchTile(
        title: 'Invert output',
        value: sliderConfig.invert,
        onChanged: (v) => update((c) => c.copyWith(invert: v)),
      ),
      PropertySwitchTile(
        title: 'Spring return to neutral',
        value: sliderConfig.springReturnEnabled,
        onChanged: (v) => update((c) => c.copyWith(springReturnEnabled: v)),
      ),
      PropertySwitchTile(
        title: 'Show value text',
        value: sliderConfig.showValue,
        onChanged: (v) => update((c) => c.copyWith(showValue: v)),
      ),
    ];
  }

  // ── Analog joystick ──────────────────────────────────────────────────────

  List<Widget> _analogJoystickFields({required bool dualAxis}) {
    final joyConfig = AnalogJoystickConfig.fromCustomProperties(
      config.customProperties,
    );
    void update(AnalogJoystickConfig Function(AnalogJoystickConfig) f) {
      _updateCustomProperties(
        (props) => f(joyConfig).applyToCustomProperties(props),
      );
    }

    return [
      const PropertySectionHeader('Range', padTop: 4),
      _numberField(
        label: 'Minimum value',
        value: joyConfig.minValue,
        onChanged: (v) => update((c) => c.copyWith(minValue: v)),
      ),
      _numberField(
        label: 'Maximum value',
        value: joyConfig.maxValue,
        onChanged: (v) => update((c) => c.copyWith(maxValue: v)),
      ),
      _numberField(
        label: 'Neutral value',
        value: joyConfig.neutralValue,
        onChanged: (v) => update((c) => c.copyWith(neutralValue: v)),
      ),
      _numberField(
        label: 'Step size',
        value: joyConfig.stepSize,
        onChanged: (v) => update((c) => c.copyWith(stepSize: v)),
      ),
      _ResyncTextField(
        label: 'Unit',
        value: joyConfig.unit,
        onChanged: (v) => update((c) => c.copyWith(unit: v)),
      ),
      const PropertySectionHeader('Behavior'),
      if (!dualAxis)
        PropertySegmented<AnalogJoystickOrientation>(
          options: const [
            (AnalogJoystickOrientation.vertical, 'Vertical'),
            (AnalogJoystickOrientation.horizontal, 'Horizontal'),
          ],
          selected: joyConfig.orientation,
          onChanged: (o) => update((c) => c.copyWith(orientation: o)),
        ),
      if (dualAxis)
        PropertySegmented<AnalogJoystickOutputAxis>(
          options: const [
            (AnalogJoystickOutputAxis.x, 'X axis'),
            (AnalogJoystickOutputAxis.y, 'Y axis'),
          ],
          selected: joyConfig.outputAxis,
          onChanged: (a) => update((c) => c.copyWith(outputAxis: a)),
        ),
      const SizedBox(height: 8),
      PropertyLabeledSlider(
        label: 'Dead zone',
        value: joyConfig.deadZone,
        min: 0,
        max: 0.9,
        valueLabel: '${(joyConfig.deadZone * 100).round()}%',
        onChanged: (v) => update((c) => c.copyWith(deadZone: v)),
      ),
      PropertySwitchTile(
        title: 'Invert axis',
        value: joyConfig.invert,
        onChanged: (v) => update((c) => c.copyWith(invert: v)),
      ),
      PropertySwitchTile(
        title: 'Spring return to center',
        value: joyConfig.springReturnEnabled,
        onChanged: (v) => update((c) => c.copyWith(springReturnEnabled: v)),
      ),
      if (dualAxis)
        const PropertyInfoBanner(
          text:
              'Future option: send both X and Y if the PLC protocol adds '
              'dual-channel analog support. Today only one axis is '
              'transmitted per widget.',
        ),
    ];
  }
}

Widget _numberField({
  required String label,
  required double value,
  required ValueChanged<double> onChanged,
}) {
  return _ResyncTextField(
    label: label,
    value: _formatNumber(value),
    keyboardType: const TextInputType.numberWithOptions(
      decimal: true,
      signed: true,
    ),
    onChanged: (raw) {
      final parsed = double.tryParse(raw);
      if (parsed != null) onChanged(parsed);
    },
  );
}

String _formatNumber(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

/// Text field whose controller only resyncs from an external value change
/// (e.g. Reset to default) — never fights the operator's own typing/cursor,
/// mirroring GeneralTab's label field.
class _ResyncTextField extends StatefulWidget {
  const _ResyncTextField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.keyboardType,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;

  @override
  State<_ResyncTextField> createState() => _ResyncTextFieldState();
}

class _ResyncTextFieldState extends State<_ResyncTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _ResyncTextField old) {
    super.didUpdateWidget(old);
    if (widget.value != _controller.text && widget.value != old.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PropertyTextField(
      controller: _controller,
      label: widget.label,
      keyboardType: widget.keyboardType,
      onChanged: widget.onChanged,
    );
  }
}

class _IconPickerRow extends StatelessWidget {
  const _IconPickerRow({
    required this.label,
    required this.iconKey,
    required this.onTap,
  });

  final String label;
  final String? iconKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = iconForKey(iconKey);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1823),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF30363D)),
          ),
          child: Row(
            children: [
              Icon(
                icon ?? Icons.image_not_supported_outlined,
                size: 18,
                color: icon == null
                    ? const Color(0xFF94A6B7)
                    : const Color(0xFFF3F6F9),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFFF3F6F9),
                    fontSize: 13.5,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF94A6B7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
