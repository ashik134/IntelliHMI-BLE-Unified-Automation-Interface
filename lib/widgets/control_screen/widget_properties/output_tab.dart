import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/analog_joystick_config.dart';
import 'package:rev_crane_control_ops/models/analog_slider_config.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/button_logical_state.dart';
import 'package:rev_crane_control_ops/models/button_state_output_mapping.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/models/joystick_config.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/models/potentiometer_config.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/general_tab.dart'
    show ButtonUpdater;
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/property_field_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// OutputTab
//
// Digital types: one PLC-output-variant multi-select per logical state (or
// per joystick virtual sub-button), backed by ButtonConfig.stateMappings /
// .joystickSubButtonMappings exactly as CraneController already composes
// from them — this tab can't express anything the wire protocol doesn't
// already support. Analog types: only the real, wired outputEnabled switch
// — no PLC-output-variant/channel picker, since PotentiometerConfig
// .outputVariantId/.outputChannel are stored but never read by anything
// that talks to the PLC (confirmed against CraneController/BleService), and
// AnalogSliderConfig/AnalogJoystickConfig don't even have those fields.
// ─────────────────────────────────────────────────────────────────────────────

final List<PlcOutputVariant> _kConfigurableVariants = PlcOutputVariant.values
    .where((v) => v.isUserConfigurable)
    .toList();

List<(String, String)> get _variantOptions => [
  for (final v in _kConfigurableVariants) (v.storageKey, v.genericLabel),
];

class OutputTab extends StatelessWidget {
  const OutputTab({super.key, required this.config, required this.onUpdate});

  final ButtonConfig config;
  final ButtonUpdater onUpdate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      children: switch (config.type) {
        ButtonType.potentiometer => _potentiometerOutput(),
        ButtonType.analogSliderOT ||
        ButtonType.analogSliderTOT => _analogSliderOutput(),
        ButtonType.analogJoystick1D ||
        ButtonType.analogJoystick2D => _analogJoystickOutput(),
        ButtonType.joystick => _joystickOutput(),
        ButtonType.horn || ButtonType.alarmIndicator => const [
          PropertyInfoBanner(
            text:
                'Feedback widgets read PLC status — they have no output '
                'mapping of their own.',
          ),
        ],
        _ => _digitalOutput(),
      },
    );
  }

  // ── Digital: pushButton / toggle / sliderButton / bidirectional sliders ──

  List<Widget> _digitalOutput() {
    final states = config.type.logicalStates;
    return [
      const PropertyInfoBanner(
        text:
            'Idle/center states are always inert for safety — only the '
            'states below can assert a PLC output.',
      ),
      for (final state in states) _stateMappingRow(state),
    ];
  }

  Widget _stateMappingRow(ButtonLogicalState state) {
    if (state.isIdle) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(
          '${state.label} — always inert',
          style: const TextStyle(
            color: Color(0xFF94A6B7),
            fontSize: 12.5,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    final mapping = config.stateMappings[state.id];
    final selected = mapping?.activeVariants.map((v) => v.storageKey).toSet() ?? {};

    void toggle(String key) {
      final variant = PlcOutputVariant.fromStorageKey(key);
      if (variant == null) return;
      final current = Set<PlcOutputVariant>.from(
        config.stateMappings[state.id]?.activeVariants ?? const {},
      );
      if (current.contains(variant)) {
        current.remove(variant);
      } else {
        current.add(variant);
      }
      onUpdate(
        (b) => b.copyWith(
          stateMappings: {
            ...b.stateMappings,
            state.id: ButtonStateOutputMapping(
              stateId: state.id,
              activeVariants: current,
            ),
          },
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.label,
            style: const TextStyle(
              color: Color(0xFFF3F6F9),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          PropertyMultiSelect(
            options: _variantOptions,
            selectedKeys: selected,
            onToggle: toggle,
          ),
        ],
      ),
    );
  }

  // ── Digital joystick: up to 4 virtual sub-buttons ────────────────────────

  List<Widget> _joystickOutput() {
    final joystickConfig = JoystickConfig.fromCustomProperties(
      config.customProperties,
    ).normalizedForMode();
    final directions = joystickConfig.isDualAxis
        ? const [
            JoystickDirection.posY,
            JoystickDirection.negY,
            JoystickDirection.posX,
            JoystickDirection.negX,
          ]
        : const [JoystickDirection.posX, JoystickDirection.negX];

    return [
      const PropertyInfoBanner(
        text:
            'A joystick asserts one PLC output set per direction, per step '
            '(1 = slow, 2 = fast).',
      ),
      for (final direction in directions) ..._joystickDirectionRows(direction),
    ];
  }

  List<Widget> _joystickDirectionRows(JoystickDirection direction) {
    final virtualId = joystickVirtualButtonId(config.id, direction);
    final table = config.joystickSubButtonMappings[virtualId] ?? const {};

    void toggle(String stateId, String key) {
      final variant = PlcOutputVariant.fromStorageKey(key);
      if (variant == null) return;
      final current = Set<PlcOutputVariant>.from(
        table[stateId]?.activeVariants ?? const {},
      );
      if (current.contains(variant)) {
        current.remove(variant);
      } else {
        current.add(variant);
      }
      onUpdate(
        (b) => b.copyWith(
          joystickSubButtonMappings: {
            ...b.joystickSubButtonMappings,
            virtualId: {
              ...(b.joystickSubButtonMappings[virtualId] ?? const {}),
              stateId: ButtonStateOutputMapping(
                stateId: stateId,
                activeVariants: current,
              ),
            },
          },
        ),
      );
    }

    return [
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Text(
          _directionLabel(direction),
          style: const TextStyle(
            color: Color(0xFF8B5CF6),
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
      for (final state in kThreeStepLogicalStates)
        if (!state.isIdle)
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.label,
                  style: const TextStyle(
                    color: Color(0xFFF3F6F9),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                PropertyMultiSelect(
                  options: _variantOptions,
                  selectedKeys:
                      table[state.id]?.activeVariants
                          .map((v) => v.storageKey)
                          .toSet() ??
                      const {},
                  onToggle: (key) => toggle(state.id, key),
                ),
              ],
            ),
          ),
    ];
  }

  String _directionLabel(JoystickDirection direction) => switch (direction) {
    JoystickDirection.posX => 'Right',
    JoystickDirection.negX => 'Left',
    JoystickDirection.posY => 'Up',
    JoystickDirection.negY => 'Down',
  };

  // ── Analog types ─────────────────────────────────────────────────────────

  static const _analogNote = PropertyInfoBanner(
    text:
        'Analog controls send a continuous value directly to the PLC — '
        'there is no per-state output-variant mapping to configure.',
  );

  List<Widget> _potentiometerOutput() {
    final potConfig = PotentiometerConfig.fromCustomProperties(
      config.customProperties,
    );
    return [
      _analogNote,
      PropertySwitchTile(
        title: 'Send to PLC',
        subtitle: 'Stays inert until enabled, even after placement.',
        value: potConfig.outputEnabled,
        onChanged: (v) => onUpdate(
          (b) => b.copyWith(
            customProperties: potConfig
                .copyWith(outputEnabled: v)
                .applyToCustomProperties(b.customProperties),
          ),
        ),
      ),
    ];
  }

  List<Widget> _analogSliderOutput() {
    final sliderConfig = AnalogSliderConfig.fromCustomProperties(
      config.customProperties,
    );
    return [
      _analogNote,
      PropertySwitchTile(
        title: 'Send to PLC',
        subtitle: 'Stays inert until enabled, even after placement.',
        value: sliderConfig.outputEnabled,
        onChanged: (v) => onUpdate(
          (b) => b.copyWith(
            customProperties: sliderConfig
                .copyWith(outputEnabled: v)
                .applyToCustomProperties(b.customProperties),
          ),
        ),
      ),
    ];
  }

  List<Widget> _analogJoystickOutput() {
    final joyConfig = AnalogJoystickConfig.fromCustomProperties(
      config.customProperties,
    );
    return [
      _analogNote,
      PropertySwitchTile(
        title: 'Send to PLC',
        subtitle: 'Stays inert until enabled, even after placement.',
        value: joyConfig.outputEnabled,
        onChanged: (v) => onUpdate(
          (b) => b.copyWith(
            customProperties: joyConfig
                .copyWith(outputEnabled: v)
                .applyToCustomProperties(b.customProperties),
          ),
        ),
      ),
    ];
  }
}
