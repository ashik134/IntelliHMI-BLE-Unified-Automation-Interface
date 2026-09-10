import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/analog_joystick_config.dart';
import 'package:rev_crane_control_ops/models/analog_slider_config.dart';
import 'package:rev_crane_control_ops/models/analog_wire_config.dart'
    show AnalogOutputChannel, analogOutputChannelOf;
import 'package:rev_crane_control_ops/models/app_enums.dart'
    show LayoutBucket, PlcType;
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/button_logical_state.dart';
import 'package:rev_crane_control_ops/models/button_state_output_mapping.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/models/detented_selector_config.dart';
import 'package:rev_crane_control_ops/models/joystick_config.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/models/potentiometer_config.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart'
    show selectableVariantsFor;
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
// already support. Analog types: the wired outputEnabled switch plus an
// A1..A6 channel picker — CraneController.setAnalogButtonValue addresses
// every analog write to config.outputChannel over the firmware's
// RANGE:/DATA: protocol, so output stays inert until both are set. A channel
// already claimed by another analog widget in [allButtons] is disabled here
// (see _channelsClaimedByOthers) — two widgets racing to write the same
// firmware channel would otherwise silently stomp on each other's DATA
// values with no error either widget could see.
// PotentiometerConfig.outputVariantId is unrelated to this and still isn't
// read by anything that talks to the PLC.
// ─────────────────────────────────────────────────────────────────────────────

class OutputTab extends StatelessWidget {
  const OutputTab({
    super.key,
    required this.config,
    required this.allButtons,
    required this.onUpdate,
    required this.plcType,
  });

  final ButtonConfig config;

  /// Every widget on the active layout, keyed by id — used to find analog
  /// channels already claimed by widgets other than [config].
  final Map<String, ButtonConfig> allButtons;
  final ButtonUpdater onUpdate;

  /// The connected device's PLC model — determines which digital output
  /// variants are offered below. PLC14 exposes DF2..DF5 (3 digital outputs +
  /// relay), PLC21 DF2..DF4, PLC38 the full DF2..DF10 — see
  /// [PlcType.digitalFieldCount] / [selectableVariantsFor]. Never lets an
  /// operator configure an output the connected PLC cannot physically drive.
  final PlcType plcType;

  /// The digital output variants selectable for the connected PLC type.
  List<PlcOutputVariant> get _configurableVariants =>
      selectableVariantsFor(LayoutBucket.forPlcType(plcType));

  List<(String, String)> get _variantOptions => [
    for (final v in _configurableVariants) (v.storageKey, v.genericLabel),
  ];

  /// Channels assigned to some other analog widget on this layout — never
  /// includes [config]'s own current channel, so the picker never blocks the
  /// operator from keeping (or clearing) what's already selected.
  Set<AnalogOutputChannel> get _channelsClaimedByOthers => {
    for (final b in allButtons.values)
      if (b.id != config.id) ?analogOutputChannelOf(b),
  };

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      children: switch (config.type) {
        ButtonType.potentiometer ||
        ButtonType.potentiometerCenterOff => _potentiometerOutput(),
        ButtonType.analogSliderOT ||
        ButtonType.analogSliderTOT => _analogSliderOutput(),
        ButtonType.analogJoystick1D ||
        ButtonType.analogJoystick2D => _analogJoystickOutput(),
        ButtonType.joystick => _joystickOutput(),
        ButtonType.detentedSelector => _detentedSelectorOutput(),
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

  // ── Detented selector: one row per configured position ───────────────────

  List<Widget> _detentedSelectorOutput() {
    final selectorConfig = DetentedSelectorConfig.fromCustomProperties(
      config.customProperties,
    ).normalized();

    return [
      const PropertyInfoBanner(
        text:
            'Each detent position asserts its own set of PLC outputs while '
            'selected — unlike push/toggle, no position is forced inert.',
      ),
      for (final position in selectorConfig.positions)
        _positionMappingRow(position),
    ];
  }

  Widget _positionMappingRow(SelectorPosition position) {
    final mapping = config.stateMappings[position.id];
    final selected = mapping?.activeVariants.map((v) => v.storageKey).toSet() ?? {};
    final label = position.label?.trim().isNotEmpty == true
        ? position.label!.trim()
        : position.id;

    void toggle(String key) {
      final variant = PlcOutputVariant.fromStorageKey(key);
      if (variant == null) return;
      final current = Set<PlcOutputVariant>.from(
        config.stateMappings[position.id]?.activeVariants ?? const {},
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
            position.id: ButtonStateOutputMapping(
              stateId: position.id,
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
            label,
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
      _channelPickerRow(
        selected: potConfig.outputChannel,
        onSelect: (channel) => onUpdate(
          (b) => b.copyWith(
            customProperties: potConfig
                .copyWith(
                  outputChannel: channel,
                  clearOutputChannel: channel == null,
                )
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
      _channelPickerRow(
        selected: sliderConfig.outputChannel,
        onSelect: (channel) => onUpdate(
          (b) => b.copyWith(
            customProperties: sliderConfig
                .copyWith(
                  outputChannel: channel,
                  clearOutputChannel: channel == null,
                )
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
      _channelPickerRow(
        selected: joyConfig.outputChannel,
        onSelect: (channel) => onUpdate(
          (b) => b.copyWith(
            customProperties: joyConfig
                .copyWith(
                  outputChannel: channel,
                  clearOutputChannel: channel == null,
                )
                .applyToCustomProperties(b.customProperties),
          ),
        ),
      ),
    ];
  }

  // ── Shared A1..A6 channel picker ─────────────────────────────────────────

  Widget _channelPickerRow({
    required AnalogOutputChannel? selected,
    required ValueChanged<AnalogOutputChannel?> onSelect,
  }) {
    final claimedByOthers = _channelsClaimedByOthers;

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selected != null && claimedByOthers.contains(selected))
            PropertyInfoBanner(
              isWarning: true,
              text:
                  '${selected.label} is already assigned to another '
                  'analog widget on this layout — both would write '
                  'conflicting values to the same PLC channel. Pick a '
                  'different channel.',
            ),
          const Text(
            'PLC Analog Channel',
            style: TextStyle(
              color: Color(0xFFF3F6F9),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          PropertySegmented<AnalogOutputChannel?>(
            options: [
              (null, 'None'),
              for (final channel in AnalogOutputChannel.values)
                (channel, channel.label),
            ],
            selected: selected,
            disabledValues: claimedByOthers,
            onChanged: onSelect,
          ),
        ],
      ),
    );
  }
}
