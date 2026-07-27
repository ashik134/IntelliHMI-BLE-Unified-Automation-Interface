import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/customization_mode_controller.dart';
import 'package:rev_crane_control_ops/models/alarm_indicator_config.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/button_logical_state.dart';
import 'package:rev_crane_control_ops/models/button_state_output_mapping.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/models/horn_config.dart';
import 'package:rev_crane_control_ops/models/joystick_config.dart';
import 'package:rev_crane_control_ops/models/plc_condition_config.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/models/potentiometer_config.dart';
import 'package:rev_crane_control_ops/services/layout_validation_service.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';
import 'package:rev_crane_control_ops/widgets/buttons/role_appearance.dart';
import 'package:rev_crane_control_ops/widgets/customization/axis_type_preview.dart';
import 'package:rev_crane_control_ops/widgets/customization/confirm_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ButtonEditSheet
//
// Per-control editing surface, opened via the pencil badge on an
// EditableControlTile. Two entry points because sliders render a whole axis
// as one combined widget (CrossTravelSlider / the hoist slider pair) while
// push/toggle buttons are per-role individual widgets:
//   - .forRole(role)  → editing a single push/toggle button
//   - .forAxis(axis)  → editing a slider pair (both directions at once)
//
// Every field change flows through CustomizationModeController.applyDraftChange
// — this sheet never talks to LayoutSettingsController directly. Because the
// real control screen behind the sheet reads the same draft, most edits are
// visible live behind the (partially transparent) sheet as they're made.
// ─────────────────────────────────────────────────────────────────────────────

class ButtonEditSheet extends StatefulWidget {
  const ButtonEditSheet.forRole({super.key, required this.role})
    : axis = null,
      buttonId = null,
      preferredPageIndex = null,
      preferredSlot = null;

  const ButtonEditSheet.forAxis({super.key, required this.axis})
    : role = null,
      buttonId = null,
      preferredPageIndex = null,
      preferredSlot = null;

  const ButtonEditSheet.forButton({super.key, required this.buttonId})
    : role = null,
      axis = null,
      preferredPageIndex = null,
      preferredSlot = null;

  const ButtonEditSheet.forNewButton({
    super.key,
    required this.preferredPageIndex,
    this.preferredSlot,
  }) : role = null,
       axis = null,
       buttonId = null;

  final ControlRole? role;
  final AxisKind? axis;
  final String? buttonId;
  final int? preferredPageIndex;
  final int? preferredSlot;

  AxisKind get resolvedAxis => axis ?? role!.axis!;
  bool get isCustomButtonFlow => buttonId != null || preferredPageIndex != null;
  bool get isNewButtonFlow => buttonId == null && preferredPageIndex != null;

  static Future<void> showForRole(BuildContext context, ControlRole role) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ButtonEditSheet.forRole(role: role),
    );
  }

  static Future<void> showForAxis(BuildContext context, AxisKind axis) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ButtonEditSheet.forAxis(axis: axis),
    );
  }

  static Future<void> showForButton(BuildContext context, String buttonId) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ButtonEditSheet.forButton(buttonId: buttonId),
    );
  }

  static Future<void> showForNewButton(
    BuildContext context, {
    int? preferredPageIndex,
    int? preferredSlot,
  }) {
    final customCtrl = context.read<CustomizationModeController>();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ButtonEditSheet.forNewButton(
        preferredPageIndex: preferredPageIndex ?? customCtrl.activeControlPage,
        preferredSlot: preferredSlot,
      ),
    );
  }

  @override
  State<ButtonEditSheet> createState() => _ButtonEditSheetState();
}

class _ButtonEditSheetState extends State<ButtonEditSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  ButtonConfig? _pendingNewButton;
  String? _newButtonError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _title {
    if (widget.isNewButtonFlow) return 'ADD CONTROL';
    if (widget.buttonId != null) return 'CUSTOM CONTROL';
    return widget.role != null
        ? _roleTitle(widget.role!)
        : '${widget.resolvedAxis.displayName} AXIS';
  }

  static String _roleTitle(ControlRole role) => switch (role) {
    ControlRole.hoistUp => 'HOIST · UP',
    ControlRole.hoistDown => 'HOIST · DOWN',
    ControlRole.traverseLeft => 'TRAVERSE · LEFT',
    ControlRole.traverseRight => 'TRAVERSE · RIGHT',
    ControlRole.travelForward => 'TRAVEL · FORWARD',
    ControlRole.travelReverse => 'TRAVEL · REVERSE',
    ControlRole.estop => 'E-STOP',
    ControlRole.resetEstop => 'RESET E-STOP',
  };

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              _header(context),
              if (widget.isCustomButtonFlow)
                Expanded(child: _customButtonEditor(scrollController))
              else ...[
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  indicatorColor: AppColors.accent,
                  labelColor: AppColors.accent,
                  unselectedLabelColor: AppColors.darkTextSub,
                  labelStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  tabs: const [
                    Tab(text: 'TYPE'),
                    Tab(text: 'LABEL'),
                    Tab(text: 'APPEARANCE'),
                    Tab(text: 'BEHAVIOR'),
                  ],
                ),
                const Divider(height: 1, color: AppColors.darkBorder),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _TypeTab(
                        axis: widget.resolvedAxis,
                        editRole: widget.role,
                        scrollController: scrollController,
                      ),
                      _LabelTab(
                        role: widget.role,
                        axis: widget.resolvedAxis,
                        scrollController: scrollController,
                      ),
                      _AppearanceTab(
                        role: widget.role,
                        axis: widget.resolvedAxis,
                        scrollController: scrollController,
                      ),
                      _BehaviorTab(
                        axis: widget.resolvedAxis,
                        editRole: widget.role,
                        scrollController: scrollController,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _title,
              style: const TextStyle(
                color: AppColors.darkText,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.darkTextSub),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _customButtonEditor(ScrollController scrollController) {
    final customCtrl = context.watch<CustomizationModeController>();
    final config = widget.isNewButtonFlow
        ? _pendingNewButton
        : customCtrl.draft.resolvedButtons[widget.buttonId];

    if (!widget.isNewButtonFlow && config == null) {
      return const Center(
        child: Text(
          'Button not found',
          style: TextStyle(color: AppColors.darkText),
        ),
      );
    }

    void update(ButtonConfig? next) {
      setState(() => _newButtonError = null);
      if (widget.isNewButtonFlow) {
        setState(() => _pendingNewButton = next);
        return;
      }

      final current = customCtrl.draft.resolvedButtons[widget.buttonId];
      if (current == null || next == null) return;
      final layout = customCtrl.draft.withButton(current.id, next);
      if (!next.visible) {
        customCtrl.applyDraftChangeAndCompact(layout);
      } else {
        customCtrl.applyDraftChange(layout);
      }
    }

    return Column(
      children: [
        const Divider(height: 1, color: AppColors.darkBorder),
        Expanded(
          child: _CustomButtonConfigEditor(
            config: config,
            bucket: customCtrl.activeBucket,
            scrollController: scrollController,
            errorText: _newButtonError,
            isPendingCreate: widget.isNewButtonFlow,
            onChanged: update,
          ),
        ),
        if (widget.isNewButtonFlow)
          _NewButtonFooter(
            isNoneSelected: config == null,
            onCancel: () => Navigator.of(context).pop(),
            onSave: () => _savePendingButton(config),
          ),
      ],
    );
  }

  void _savePendingButton(ButtonConfig? config) {
    if (config == null) {
      Navigator.of(context).pop();
      return;
    }

    final label = config.label.trim();
    if (label.isEmpty) {
      setState(() => _newButtonError = 'Add a label before saving.');
      return;
    }
    if (!config.plcMappingEnabled) {
      setState(() => _newButtonError = 'Assign a PLC output before saving.');
      return;
    }

    final customCtrl = context.read<CustomizationModeController>();
    final result = customCtrl.addControlButton(
      config.copyWith(label: label),
      preferredPageIndex: widget.preferredPageIndex,
      preferredSlot: widget.preferredSlot,
    );
    if (!result.isValid) {
      setState(
        () => _newButtonError = result.message ?? kWidgetPlacementMessage,
      );
      return;
    }
    Navigator.of(context).pop();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared card chrome
// ─────────────────────────────────────────────────────────────────────────────

class _TabCard extends StatelessWidget {
  const _TabCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panelAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.darkTextSub,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          Material(type: MaterialType.transparency, child: child),
        ],
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.message, this.color = AppColors.darkInfo});
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 13, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 11, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _OutputMappingEditor
//
// Shared per-state PLC output variant editor, reused by both the legacy
// per-role BEHAVIOR tab (_BehaviorCard, below _MutualExclusionEditor) and the
// custom/new-button flow's OUTPUT MAPPING card. Renders one row per
// config.type.logicalStates:
//   - isIdle states (idle/center) are locked to [] and non-editable — an
//     idle/center state that could assert arbitrary outputs would be a
//     safety footgun ("never truly off").
//   - non-idle states are an editable multi-select chip group over
//     DF2..DF10 (DF1/E-STOP structurally excluded from the list itself, not
//     just by convention), further restricted to DF2..DF4 for a PLC14/PLC21
//     layout, since those PLC types only ever emit a 4-field wire packet.
//
// Master invariant: this editor only ever writes exactly what the user
// selects into config.stateMappings[state.id] — never a derived/implied
// extra variant.
// ─────────────────────────────────────────────────────────────────────────────

class _OutputMappingEditor extends StatelessWidget {
  const _OutputMappingEditor({
    required this.config,
    required this.bucket,
    required this.onChanged,
  });

  final ButtonConfig config;
  final LayoutBucket bucket;
  final ValueChanged<ButtonConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    if (config.type == ButtonType.potentiometer) {
      return _PotentiometerOutputEditor(
        config: config,
        bucket: bucket,
        onChanged: onChanged,
      );
    }

    if (config.type == ButtonType.joystick) {
      return _JoystickOutputMappingEditor(
        config: config,
        bucket: bucket,
        onChanged: onChanged,
      );
    }

    // horn/alarmIndicator never reach here — ButtonEditSheet skips the
    // OUTPUT MAPPING tab entirely for both (see the realConfig.type checks
    // around the OUTPUT MAPPING _TabCard), since neither type has any
    // ButtonConfig.stateMappings-backed output at all; their PLC trigger
    // condition is configured in their own dedicated HORN/ALARM INDICATOR
    // tab instead (_HornConfigEditor/_AlarmIndicatorConfigEditor).
    final states = config.type.logicalStates;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final state in states) ...[
          Text(
            state.label,
            style: const TextStyle(
              color: AppColors.darkTextSub,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          if (state.isIdle)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: _InfoNote(
                message:
                    'Idle / center is always off — no output variant '
                    'can be assigned to this state.',
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _VariantChipGroup(
                selectable: selectableVariantsFor(bucket),
                selected:
                    config.stateMappings[state.id]?.activeVariants ?? const {},
                onChanged: (next) {
                  final updated = Map<String, ButtonStateOutputMapping>.from(
                    config.stateMappings,
                  );
                  updated[state.id] = ButtonStateOutputMapping(
                    stateId: state.id,
                    activeVariants: next,
                  );
                  onChanged(config.copyWith(stateMappings: updated));
                },
              ),
            ),
        ],
      ],
    );
  }
}

class _JoystickOutputMappingEditor extends StatelessWidget {
  const _JoystickOutputMappingEditor({
    required this.config,
    required this.bucket,
    required this.onChanged,
  });

  final ButtonConfig config;
  final LayoutBucket bucket;
  final ValueChanged<ButtonConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final endpoints = _joystickOutputEndpointsFor(config);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final endpoint in endpoints) ...[
          Text(
            endpoint.label,
            style: const TextStyle(
              color: AppColors.darkTextSub,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          for (final state in kThreeStepLogicalStates)
            if (!state.isIdle) ...[
              Text(
                state.label,
                style: const TextStyle(
                  color: AppColors.darkTextMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _VariantChipGroup(
                  selectable: selectableVariantsFor(bucket),
                  selected: _selectedVariants(endpoint.id, state.id),
                  onChanged: (next) =>
                      _updateEndpoint(endpoint, state.id, next),
                ),
              ),
            ],
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  void _updateEndpoint(
    _JoystickOutputEndpoint endpoint,
    String stateId,
    Set<PlcOutputVariant> activeVariants,
  ) {
    final shouldSeedFromParent =
        config.joystickSubButtonMappings.isEmpty &&
        config.stateMappings.isNotEmpty;
    final Map<String, Map<String, ButtonStateOutputMapping>> updated;
    if (shouldSeedFromParent) {
      updated = _joystickMappingsSeededFromParent(config);
    } else {
      updated = {
        for (final entry in config.joystickSubButtonMappings.entries)
          entry.key: Map<String, ButtonStateOutputMapping>.from(entry.value),
      };
    }
    final states = Map<String, ButtonStateOutputMapping>.from(
      updated[endpoint.id] ?? _emptyJoystickStateMappings(),
    );
    states['idle'] = const ButtonStateOutputMapping(stateId: 'idle');
    states[stateId] = ButtonStateOutputMapping(
      stateId: stateId,
      activeVariants: activeVariants,
    );
    updated[endpoint.id] = states;
    onChanged(config.copyWith(joystickSubButtonMappings: updated));
  }

  Set<PlcOutputVariant> _selectedVariants(String endpointId, String stateId) {
    final states = config.joystickSubButtonMappings[endpointId];
    if (states != null) {
      return states[stateId]?.activeVariants ?? const {};
    }
    if (config.joystickSubButtonMappings.isEmpty) {
      return config.stateMappings[stateId]?.activeVariants ?? const {};
    }
    return const {};
  }
}

class _PotentiometerOutputEditor extends StatelessWidget {
  const _PotentiometerOutputEditor({
    required this.config,
    required this.bucket,
    required this.onChanged,
  });

  final ButtonConfig config;
  final LayoutBucket bucket;
  final ValueChanged<ButtonConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final potentiometer = PotentiometerConfig.fromCustomProperties(
      config.customProperties,
    ).normalized();
    final selectable = selectableVariantsFor(bucket);

    void save(PotentiometerConfig next) {
      onChanged(
        config.copyWith(
          customProperties: next.applyToCustomProperties(
            config.customProperties,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoNote(
          message: potentiometer.outputEnabled
              ? 'Analog output is on. Dragging this control streams an '
                    'encrypted min,max,value packet to the PLC over BLE '
                    '(never while Customization Mode is active).'
              : 'Analog output is off. These values are saved with the '
                    'layout, but nothing is sent to the PLC until you '
                    'enable it below.',
          color: potentiometer.outputEnabled
              ? AppColors.darkInfo
              : AppColors.fastColor,
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          value: potentiometer.outputEnabled,
          activeThumbColor: AppColors.accent,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Send to PLC',
            style: TextStyle(color: AppColors.darkText, fontSize: 12),
          ),
          onChanged: (value) =>
              save(potentiometer.copyWith(outputEnabled: value)),
        ),
        const SizedBox(height: 6),
        const Text(
          'OUTPUT VARIANT',
          style: TextStyle(
            color: AppColors.darkTextSub,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('None'),
              selected: potentiometer.outputVariantId == null,
              selectedColor: AppColors.accent.withAlpha(55),
              labelStyle: TextStyle(
                color: potentiometer.outputVariantId == null
                    ? AppColors.accent
                    : AppColors.darkTextSub,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
              onSelected: (_) =>
                  save(potentiometer.copyWith(clearOutputVariantId: true)),
            ),
            for (final variant in selectable)
              ChoiceChip(
                label: Text(variant.genericLabel),
                selected: potentiometer.outputVariantId == variant.variantId,
                selectedColor: AppColors.accent.withAlpha(55),
                labelStyle: TextStyle(
                  color: potentiometer.outputVariantId == variant.variantId
                      ? AppColors.accent
                      : AppColors.darkTextSub,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) => save(
                  potentiometer.copyWith(outputVariantId: variant.variantId),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _ConfigTextField(
          label: 'Analog channel',
          value: potentiometer.outputChannel,
          hint: 'AO1, CH0, DAC_A...',
          onChanged: (value) =>
              save(potentiometer.copyWith(outputChannel: value)),
        ),
      ],
    );
  }
}

class _VariantChipGroup extends StatelessWidget {
  const _VariantChipGroup({
    required this.selectable,
    required this.selected,
    required this.onChanged,
  });

  final List<PlcOutputVariant> selectable;
  final Set<PlcOutputVariant> selected;
  final ValueChanged<Set<PlcOutputVariant>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final variant in selectable)
          ChoiceChip(
            label: Text(variant.genericLabel),
            selected: selected.contains(variant),
            selectedColor: AppColors.accent.withAlpha(55),
            labelStyle: TextStyle(
              color: selected.contains(variant)
                  ? AppColors.accent
                  : AppColors.darkTextSub,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
            onSelected: (isSelected) {
              final next = {...selected};
              if (isSelected) {
                next.add(variant);
              } else {
                next.remove(variant);
              }
              onChanged(next);
            },
          ),
      ],
    );
  }
}

class _JoystickOutputEndpoint {
  const _JoystickOutputEndpoint({required this.id, required this.label});

  final String id;
  final String label;
}

List<_JoystickOutputEndpoint> _joystickOutputEndpointsFor(ButtonConfig config) {
  final joystick = JoystickConfig.fromCustomProperties(
    config.customProperties,
  ).normalizedForMode();

  final roles = joystick.isDualAxis
      ? const [
          ControlRole.traverseRight,
          ControlRole.traverseLeft,
          ControlRole.travelForward,
          ControlRole.travelReverse,
        ]
      : switch (config.role?.axis ?? AxisKind.hoist) {
          AxisKind.hoist => const [ControlRole.hoistUp, ControlRole.hoistDown],
          AxisKind.traverse => const [
            ControlRole.traverseRight,
            ControlRole.traverseLeft,
          ],
          AxisKind.travel => const [
            ControlRole.travelForward,
            ControlRole.travelReverse,
          ],
        };

  return [
    for (final role in roles)
      _JoystickOutputEndpoint(
        id: joystickVirtualButtonId(config.id, role.plcMapping!),
        label: role.defaultLabel,
      ),
  ];
}

Map<String, ButtonStateOutputMapping> _emptyJoystickStateMappings() => const {
  'idle': ButtonStateOutputMapping(stateId: 'idle'),
  'step1': ButtonStateOutputMapping(stateId: 'step1'),
  'step2': ButtonStateOutputMapping(stateId: 'step2'),
};

Map<String, Map<String, ButtonStateOutputMapping>>
_joystickMappingsSeededFromParent(ButtonConfig config) => {
  for (final endpoint in _joystickOutputEndpointsFor(config))
    endpoint.id: _joystickStateMappingsFromParent(config),
};

Map<String, ButtonStateOutputMapping> _joystickStateMappingsFromParent(
  ButtonConfig config,
) {
  final states = <String, ButtonStateOutputMapping>{
    'idle': const ButtonStateOutputMapping(stateId: 'idle'),
  };
  for (final state in kThreeStepLogicalStates) {
    if (state.isIdle) continue;
    states[state.id] = ButtonStateOutputMapping(
      stateId: state.id,
      activeVariants:
          config.stateMappings[state.id]?.activeVariants ?? const {},
    );
  }
  return states;
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom/new button editor
// ─────────────────────────────────────────────────────────────────────────────

class _CustomButtonConfigEditor extends StatelessWidget {
  const _CustomButtonConfigEditor({
    required this.config,
    required this.bucket,
    required this.scrollController,
    required this.errorText,
    required this.isPendingCreate,
    required this.onChanged,
  });

  final ButtonConfig? config;
  final LayoutBucket bucket;
  final ScrollController scrollController;
  final String? errorText;
  final bool isPendingCreate;
  final ValueChanged<ButtonConfig?> onChanged;

  @override
  Widget build(BuildContext context) {
    final realConfig = config != null && config!.visible ? config : null;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        if (errorText != null) ...[
          _InfoNote(message: errorText!, color: AppColors.eStopColor),
          const SizedBox(height: 10),
        ],
        _TabCard(
          title: 'CONTROL TYPE',
          child: _CustomTypePicker(
            config: config,
            isPendingCreate: isPendingCreate,
            onChanged: onChanged,
          ),
        ),
        if (realConfig == null)
          const _TabCard(
            title: 'VACANT SLOT',
            child: _InfoNote(
              message:
                  'None leaves this slot empty. No control is created and no PLC output is mapped.',
            ),
          )
        else ...[
          _TabCard(
            title: 'LABEL',
            child: _CustomLabelField(config: realConfig, onChanged: onChanged),
          ),
          if (realConfig.type != ButtonType.horn &&
              realConfig.type != ButtonType.alarmIndicator)
            _TabCard(
              title: 'OUTPUT MAPPING',
              child: _OutputMappingEditor(
                config: realConfig,
                bucket: bucket,
                onChanged: onChanged,
              ),
            ),
          if (realConfig.type != ButtonType.horn &&
              realConfig.type != ButtonType.alarmIndicator)
            _TabCard(
              title: 'BEHAVIOR',
              child: _CustomBehaviorPicker(
                config: realConfig,
                onChanged: onChanged,
              ),
            ),
          _TabCard(
            title: 'APPEARANCE',
            child: _CustomAppearancePicker(
              config: realConfig,
              onChanged: onChanged,
            ),
          ),
          if (realConfig.type == ButtonType.joystick)
            _TabCard(
              title: 'JOYSTICK',
              child: _CustomJoystickConfigEditor(
                config: realConfig,
                onChanged: onChanged,
              ),
            ),
          if (realConfig.type == ButtonType.potentiometer)
            _TabCard(
              title: 'POTENTIOMETER',
              child: _PotentiometerConfigEditor(
                config: realConfig,
                onChanged: onChanged,
              ),
            ),
          if (realConfig.type == ButtonType.horn)
            _TabCard(
              title: 'HORN / BUZZER',
              child: _HornConfigEditor(
                config: realConfig,
                bucket: bucket,
                onChanged: onChanged,
              ),
            ),
          if (realConfig.type == ButtonType.alarmIndicator)
            _TabCard(
              title: 'ALARM INDICATOR',
              child: _AlarmIndicatorConfigEditor(
                config: realConfig,
                bucket: bucket,
                onChanged: onChanged,
              ),
            ),
          if (realConfig.type != ButtonType.joystick &&
              realConfig.type != ButtonType.potentiometer &&
              realConfig.type != ButtonType.horn &&
              realConfig.type != ButtonType.alarmIndicator)
            const _TabCard(
              title: 'CUSTOM PARAMETERS',
              child: _InfoNote(
                message:
                    'No advanced custom fields are defined for this control type yet.',
              ),
            ),
        ],
      ],
    );
  }
}

class _NewButtonFooter extends StatelessWidget {
  const _NewButtonFooter({
    required this.isNoneSelected,
    required this.onCancel,
    required this.onSave,
  });

  final bool isNoneSelected;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(top: BorderSide(color: AppColors.darkBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onSave,
                  icon: Icon(
                    isNoneSelected ? Icons.block_rounded : Icons.check_rounded,
                    size: 18,
                  ),
                  label: Text(isNoneSelected ? 'Leave Empty' : 'Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomTypeEntry {
  const _CustomTypeEntry({
    required this.type,
    required this.label,
    required this.icon,
    required this.available,
    required this.note,
    this.isNone = false,
  });

  final ButtonType? type;
  final String label;
  final IconData icon;
  final bool available;
  final String note;
  final bool isNone;
}

const _customTypeEntries = [
  _CustomTypeEntry(
    type: null,
    label: 'None',
    icon: Icons.block_rounded,
    available: true,
    note: 'Leave this slot empty.',
    isNone: true,
  ),
  _CustomTypeEntry(
    type: ButtonType.pushButton,
    label: 'Push Button',
    icon: Icons.touch_app_rounded,
    available: true,
    note: 'Momentary or latched output control.',
  ),
  _CustomTypeEntry(
    type: ButtonType.toggle,
    label: 'Toggle Button',
    icon: Icons.toggle_on_rounded,
    available: true,
    note: 'Switch-style maintained or spring-return control.',
  ),
  _CustomTypeEntry(
    type: ButtonType.sliderButton,
    label: 'Slider Button',
    icon: Icons.linear_scale_rounded,
    available: true,
    note: 'Drag for slow or fast output states.',
  ),
  _CustomTypeEntry(
    type: ButtonType.potentiometer,
    label: 'Potentiometer',
    icon: Icons.tune_rounded,
    available: true,
    note: 'Rotary analog value control. Output transport is pending.',
  ),
  _CustomTypeEntry(
    type: ButtonType.joystick,
    label: 'Joystick',
    icon: Icons.gamepad_rounded,
    available: true,
    note: 'Digital or analog joystick-style control.',
  ),
  _CustomTypeEntry(
    type: ButtonType.horn,
    label: 'Horn / Buzzer',
    icon: Icons.campaign_rounded,
    available: true,
    note: 'Momentary or latched horn output, with glow and beep feedback.',
  ),
  _CustomTypeEntry(
    type: ButtonType.alarmIndicator,
    label: 'Alarm Indicator',
    icon: Icons.notification_important_rounded,
    available: true,
    note:
        'Status monitor for PLC alarm feedback. View-only unless '
        'acknowledge is enabled.',
  ),
  _CustomTypeEntry(
    type: null,
    label: 'Gauge',
    icon: Icons.speed_rounded,
    available: false,
    note: 'Coming soon.',
  ),
];

class _CustomTypePicker extends StatelessWidget {
  const _CustomTypePicker({
    required this.config,
    required this.isPendingCreate,
    required this.onChanged,
  });

  final ButtonConfig? config;
  final bool isPendingCreate;
  final ValueChanged<ButtonConfig?> onChanged;

  @override
  Widget build(BuildContext context) {
    final isNoneSelected = config == null || !config!.visible;

    return Column(
      children: [
        for (final entry in _customTypeEntries)
          _CustomTypeTile(
            entry: entry,
            isSelected: entry.isNone
                ? isNoneSelected
                : config?.visible == true && config!.type == entry.type,
            onTap: entry.available ? () => _selectType(context, entry) : null,
          ),
      ],
    );
  }

  void _selectType(BuildContext context, _CustomTypeEntry entry) {
    if (entry.isNone) {
      if (config == null) {
        onChanged(null);
      } else {
        onChanged(
          config!.copyWith(
            visible: false,
            enabled: false,
            plcMappingEnabled: false,
          ),
        );
      }
      return;
    }

    final type = entry.type;
    if (type == null) return;
    final current =
        config ??
        _newCustomButtonSeed(
          type: type,
          pageIndex: context
              .read<CustomizationModeController>()
              .activeControlPage,
        );
    final (columns, rows) = ButtonConfig.defaultGridSizeFor(
      type,
      customProperties: current.customProperties,
    );
    final next = current.copyWith(
      type: type,
      visible: true,
      // Selecting a real control type is what activates this slot now that
      // PLC OUTPUT is no longer a single-value picker — PlcOutputVariant/
      // plcMappingEnabled are demoted to a cosmetic hint (see ButtonConfig
      // doc comment), but 'enabled' still gates whether the control renders
      // interactive vs. grayed-out, so it must flip true here.
      enabled: true,
      plcMappingEnabled: true,
      gridColumns: columns,
      gridRows: rows,
      columnSpan: columns,
    );

    if (isPendingCreate) {
      onChanged(next);
      return;
    }

    final customCtrl = context.read<CustomizationModeController>();
    final result = buildButtonResize(
      buttons: customCtrl.draft.resolvedButtons,
      selected: next,
      gridColumns: columns,
      gridRows: rows,
    );
    if (!result.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? kWidgetPlacementMessage)),
      );
      return;
    }
    onChanged(result.buttons![next.id]);
  }
}

class _CustomTypeTile extends StatelessWidget {
  const _CustomTypeTile({
    required this.entry,
    required this.isSelected,
    required this.onTap,
  });

  final _CustomTypeEntry entry;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppColors.accent : AppColors.darkTextSub;
    return Opacity(
      opacity: entry.available ? 1.0 : 0.5,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: isSelected ? AppColors.accent.withAlpha(24) : AppColors.darkBg,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? AppColors.accent.withAlpha(100)
                      : AppColors.darkBorder,
                ),
              ),
              child: Row(
                children: [
                  Icon(entry.icon, color: color, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                entry.label,
                                style: TextStyle(
                                  color: isSelected
                                      ? AppColors.accent
                                      : AppColors.darkText,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (!entry.available) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.fastColor.withAlpha(35),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Coming Soon',
                                  style: TextStyle(
                                    color: AppColors.fastColorLight,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          entry.note,
                          style: const TextStyle(
                            color: AppColors.darkTextMuted,
                            fontSize: 10,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.accent,
                      size: 18,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomLabelField extends StatefulWidget {
  const _CustomLabelField({required this.config, required this.onChanged});

  final ButtonConfig config;
  final ValueChanged<ButtonConfig?> onChanged;

  @override
  State<_CustomLabelField> createState() => _CustomLabelFieldState();
}

class _CustomLabelFieldState extends State<_CustomLabelField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.config.label);
  }

  @override
  void didUpdateWidget(covariant _CustomLabelField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.label != widget.config.label &&
        _controller.text != widget.config.label) {
      _controller.text = widget.config.label;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      maxLength: ControlLabelConfig.maxLabelLength,
      style: const TextStyle(color: AppColors.darkText, fontSize: 14),
      decoration: const InputDecoration(
        filled: true,
        fillColor: AppColors.darkBg,
        border: OutlineInputBorder(borderSide: BorderSide.none),
        hintText: 'Control label',
        hintStyle: TextStyle(color: AppColors.darkTextMuted, fontSize: 12),
        counterStyle: TextStyle(color: AppColors.darkTextMuted, fontSize: 10),
      ),
      onChanged: (value) =>
          widget.onChanged(widget.config.copyWith(label: value.trim())),
    );
  }
}

class _CustomBehaviorPicker extends StatelessWidget {
  const _CustomBehaviorPicker({required this.config, required this.onChanged});

  final ButtonConfig config;
  final ValueChanged<ButtonConfig?> onChanged;

  @override
  Widget build(BuildContext context) {
    final wiringApplicable =
        config.type == ButtonType.pushButton ||
        config.type == ButtonType.toggle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          value: config.enabled,
          dense: true,
          contentPadding: EdgeInsets.zero,
          activeThumbColor: AppColors.accent,
          title: const Text(
            'Enabled',
            style: TextStyle(color: AppColors.darkText, fontSize: 13),
          ),
          onChanged: config.plcMappingEnabled
              ? (value) => onChanged(config.copyWith(enabled: value))
              : null,
        ),
        if (wiringApplicable) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final wiring in PushButtonWiringConfig.values)
                if (!wiring.isToggleOnly || config.type == ButtonType.toggle)
                  ChoiceChip(
                    label: Text(wiring.label),
                    selected: config.behavior.wiring == wiring,
                    selectedColor: AppColors.accent.withAlpha(55),
                    labelStyle: TextStyle(
                      color: config.behavior.wiring == wiring
                          ? AppColors.accent
                          : AppColors.darkTextSub,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                    onSelected: (_) => onChanged(
                      config.copyWith(
                        behavior: config.behavior.copyWith(wiring: wiring),
                      ),
                    ),
                  ),
            ],
          ),
        ] else
          const _InfoNote(
            message:
                'This control type does not use push-button latching or spring-return wiring.',
          ),
      ],
    );
  }
}

class _SwitchWiringPicker extends StatelessWidget {
  const _SwitchWiringPicker({required this.config, required this.onChanged});

  final ButtonConfig config;
  final ValueChanged<PushButtonWiringConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final modes = PushButtonWiringConfig.values.where((wiring) {
      return !wiring.isToggleOnly || config.type == ButtonType.toggle;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final wiring in modes)
              ChoiceChip(
                label: Text(wiring.label),
                selected: config.behavior.wiring == wiring,
                selectedColor: AppColors.accent.withAlpha(55),
                labelStyle: TextStyle(
                  color: config.behavior.wiring == wiring
                      ? AppColors.accent
                      : AppColors.darkTextSub,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) => onChanged(wiring),
              ),
          ],
        ),
        const SizedBox(height: 8),
        _InfoNote(message: config.behavior.wiring.description),
      ],
    );
  }
}

class _CustomAppearancePicker extends StatelessWidget {
  const _CustomAppearancePicker({
    required this.config,
    required this.onChanged,
  });

  final ButtonConfig config;
  final ValueChanged<ButtonConfig?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PRIMARY COLOR',
          style: TextStyle(
            color: AppColors.darkTextSub,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final color in _swatches)
              _SwatchDot(
                color: color,
                isSelected: config.style.primaryColor == color,
                onTap: () => onChanged(
                  config.copyWith(
                    style: config.style.copyWith(primaryColor: color),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'ICON',
          style: TextStyle(
            color: AppColors.darkTextSub,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final icon in _iconPalette)
              _IconDot(
                icon: icon,
                isSelected: config.icon == icon,
                onTap: () => onChanged(config.copyWith(icon: icon)),
              ),
          ],
        ),
      ],
    );
  }
}

class _CustomJoystickConfigEditor extends StatelessWidget {
  const _CustomJoystickConfigEditor({
    required this.config,
    required this.onChanged,
  });

  final ButtonConfig config;
  final ValueChanged<ButtonConfig?> onChanged;

  @override
  Widget build(BuildContext context) {
    final joystick = JoystickConfig.fromCustomProperties(
      config.customProperties,
    ).normalizedForMode();

    void save(JoystickConfig next) {
      final normalized = next.normalizedForMode();
      final customProperties = normalized.applyToCustomProperties(
        config.customProperties,
      );
      final (columns, rows) = ButtonConfig.defaultGridSizeFor(
        config.type,
        customProperties: customProperties,
      );
      onChanged(
        config.copyWith(
          customProperties: customProperties,
          gridColumns: columns,
          gridRows: rows,
          columnSpan: columns,
        ),
      );
    }

    Widget segmented<T>({
      required String label,
      required T value,
      required List<T> values,
      required String Function(T) text,
      required ValueChanged<T> onChanged,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.darkTextMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final item in values)
                  ChoiceChip(
                    label: Text(text(item)),
                    selected: item == value,
                    selectedColor: AppColors.accent.withAlpha(50),
                    labelStyle: TextStyle(
                      color: item == value
                          ? AppColors.accent
                          : AppColors.darkTextSub,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                    onSelected: (_) => onChanged(item),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    Widget slider({
      required String label,
      required double value,
      required double min,
      required double max,
      required ValueChanged<double> onChanged,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label ${value.toStringAsFixed(2)}',
            style: const TextStyle(
              color: AppColors.darkTextMuted,
              fontSize: 11,
            ),
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: 20,
            activeColor: AppColors.accent,
            inactiveColor: AppColors.darkBorder,
            onChanged: onChanged,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        segmented<JoystickMode>(
          label: 'Mode',
          value: joystick.mode,
          values: JoystickMode.values,
          text: (mode) => mode.label,
          onChanged: (mode) => save(
            joystick.copyWith(
              mode: mode,
              boundary: switch (mode) {
                JoystickMode.dualAxisAnalog => JoystickBoundary.circular,
                JoystickMode.singleAxisAnalog ||
                JoystickMode.singleAxisDigital5 ||
                JoystickMode.dualAxisDigital4 => joystick.boundary,
              },
              springReturn: switch (mode) {
                JoystickMode.singleAxisDigital5 ||
                JoystickMode.dualAxisAnalog => true,
                JoystickMode.dualAxisDigital4 => false,
                JoystickMode.singleAxisAnalog => joystick.springReturn,
              },
              allowDiagonal: switch (mode) {
                JoystickMode.dualAxisAnalog => true,
                JoystickMode.singleAxisAnalog ||
                JoystickMode.singleAxisDigital5 ||
                JoystickMode.dualAxisDigital4 => joystick.allowDiagonal,
              },
            ),
          ),
        ),
        segmented<JoystickAxis>(
          label: 'Single-axis orientation',
          value: joystick.axis,
          values: JoystickAxis.values,
          text: (axis) =>
              axis == JoystickAxis.vertical ? 'Vertical' : 'Horizontal',
          onChanged: (axis) => save(joystick.copyWith(axis: axis)),
        ),
        if (joystick.mode != JoystickMode.dualAxisAnalog)
          segmented<JoystickBoundary>(
            label: 'Movement bound',
            value: joystick.boundary,
            values: JoystickBoundary.values,
            text: (bound) =>
                bound == JoystickBoundary.circular ? 'Circular' : 'Square',
            onChanged: (bound) => save(joystick.copyWith(boundary: bound)),
          ),
        if (joystick.mode != JoystickMode.singleAxisDigital5 &&
            joystick.mode != JoystickMode.dualAxisAnalog)
          SwitchListTile(
            value: joystick.springReturn,
            activeThumbColor: AppColors.accent,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Spring return',
              style: TextStyle(color: AppColors.darkText, fontSize: 12),
            ),
            onChanged: (value) => save(joystick.copyWith(springReturn: value)),
          ),
        if (joystick.isDualAxis && joystick.mode != JoystickMode.dualAxisAnalog)
          SwitchListTile(
            value: joystick.allowDiagonal,
            activeThumbColor: AppColors.accent,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Allow diagonals',
              style: TextStyle(color: AppColors.darkText, fontSize: 12),
            ),
            onChanged: (value) => save(joystick.copyWith(allowDiagonal: value)),
          ),
        slider(
          label: 'Dead zone',
          value: joystick.deadZone,
          min: 0.0,
          max: 0.45,
          onChanged: (value) => save(joystick.copyWith(deadZone: value)),
        ),
        slider(
          label: 'Slow threshold',
          value: joystick.slowThreshold,
          min: 0.05,
          max: 0.75,
          onChanged: (value) => save(joystick.copyWith(slowThreshold: value)),
        ),
        slider(
          label: 'Fast threshold',
          value: joystick.fastThreshold,
          min: 0.30,
          max: 1.0,
          onChanged: (value) => save(joystick.copyWith(fastThreshold: value)),
        ),
      ],
    );
  }
}

class _PotentiometerConfigEditor extends StatelessWidget {
  const _PotentiometerConfigEditor({
    required this.config,
    required this.onChanged,
  });

  final ButtonConfig config;
  final ValueChanged<ButtonConfig?> onChanged;

  @override
  Widget build(BuildContext context) {
    final potentiometer = PotentiometerConfig.fromCustomProperties(
      config.customProperties,
    ).normalized();

    void save(PotentiometerConfig next) {
      onChanged(
        config.copyWith(
          customProperties: next.applyToCustomProperties(
            config.customProperties,
          ),
        ),
      );
    }

    void saveNumber(
      String raw,
      PotentiometerConfig Function(double value) update,
    ) {
      final parsed = double.tryParse(raw.trim());
      if (parsed == null) return;
      save(update(parsed));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _PotentiometerPresetChip(
              label: '0-100%',
              onTap: () => save(
                const PotentiometerConfig(
                  minValue: 0,
                  maxValue: 100,
                  stepSize: 1,
                  defaultValue: 0,
                  unit: '%',
                ),
              ),
            ),
            _PotentiometerPresetChip(
              label: '0-255',
              onTap: () => save(
                const PotentiometerConfig(
                  minValue: 0,
                  maxValue: 255,
                  stepSize: 1,
                  defaultValue: 0,
                  unit: '',
                ),
              ),
            ),
            _PotentiometerPresetChip(
              label: '0-1023',
              onTap: () => save(
                const PotentiometerConfig(
                  minValue: 0,
                  maxValue: 1023,
                  stepSize: 1,
                  defaultValue: 0,
                  unit: '',
                ),
              ),
            ),
            _PotentiometerPresetChip(
              label: '-100% to +100%',
              onTap: () => save(
                const PotentiometerConfig(
                  minValue: -100,
                  maxValue: 100,
                  stepSize: 1,
                  defaultValue: 0,
                  unit: '%',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ConfigTextField(
                label: 'Minimum',
                value: _numberText(potentiometer.minValue),
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                onChanged: (raw) => saveNumber(
                  raw,
                  (value) => potentiometer.copyWith(minValue: value),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ConfigTextField(
                label: 'Maximum',
                value: _numberText(potentiometer.maxValue),
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                onChanged: (raw) => saveNumber(
                  raw,
                  (value) => potentiometer.copyWith(maxValue: value),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ConfigTextField(
                label: 'Step size',
                value: _numberText(potentiometer.stepSize),
                keyboardType: const TextInputType.numberWithOptions(
                  signed: false,
                  decimal: true,
                ),
                onChanged: (raw) => saveNumber(
                  raw,
                  (value) => potentiometer.copyWith(stepSize: value),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ConfigTextField(
                label: 'Default',
                value: _numberText(potentiometer.defaultValue),
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                onChanged: (raw) => saveNumber(
                  raw,
                  (value) => potentiometer.copyWith(defaultValue: value),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _ConfigTextField(
          label: 'Unit / suffix',
          value: potentiometer.unit,
          hint: '%, V, rpm...',
          onChanged: (value) => save(potentiometer.copyWith(unit: value)),
        ),
        SwitchListTile(
          value: potentiometer.showValue,
          activeThumbColor: AppColors.accent,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Show value',
            style: TextStyle(color: AppColors.darkText, fontSize: 12),
          ),
          onChanged: (value) => save(potentiometer.copyWith(showValue: value)),
        ),
      ],
    );
  }
}

class _PotentiometerPresetChip extends StatelessWidget {
  const _PotentiometerPresetChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      avatar: const Icon(Icons.tune_rounded, size: 14),
      backgroundColor: AppColors.darkBg,
      side: const BorderSide(color: AppColors.darkBorder),
      labelStyle: const TextStyle(
        color: AppColors.darkTextSub,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
      onPressed: onTap,
    );
  }
}

/// Shared "which PLC output/status variants trigger this feedback widget"
/// editor: a variant chip picker (reusing _VariantChipGroup) plus an any-of/
/// all-of combinator toggle. Used by both HORN/BUZZER (one trigger) and
/// ALARM INDICATOR (one per severity) — the exact UI the task calls for:
/// "If A2 is ON", "If A5 and A6 are ON", "any selected output variant ON".
class _PlcConditionEditor extends StatelessWidget {
  const _PlcConditionEditor({
    required this.bucket,
    required this.condition,
    required this.onChanged,
  });

  final LayoutBucket bucket;
  final PlcConditionConfig condition;
  final ValueChanged<PlcConditionConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TRIGGER VARIANTS',
          style: TextStyle(
            color: AppColors.darkTextSub,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        _VariantChipGroup(
          selectable: selectableVariantsFor(bucket),
          selected: condition.watchedFields,
          onChanged: (next) =>
              onChanged(condition.copyWith(watchedFields: next)),
        ),
        const SizedBox(height: 10),
        if (condition.watchedFields.length > 1) ...[
          const Text(
            'CONDITION',
            style: TextStyle(
              color: AppColors.darkTextSub,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final combinator in PlcConditionCombinator.values)
                ChoiceChip(
                  label: Text(
                    combinator == PlcConditionCombinator.any
                        ? 'Any selected ON'
                        : 'All selected ON',
                  ),
                  selected: condition.combinator == combinator,
                  selectedColor: AppColors.accent.withAlpha(55),
                  labelStyle: TextStyle(
                    color: condition.combinator == combinator
                        ? AppColors.accent
                        : AppColors.darkTextSub,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                  onSelected: (_) =>
                      onChanged(condition.copyWith(combinator: combinator)),
                ),
            ],
          ),
        ] else
          const _InfoNote(
            message: 'Select 2 or more variants to choose any-of vs all-of.',
          ),
      ],
    );
  }
}

/// One severity's titled PlcConditionConfig section within
/// _AlarmIndicatorConfigEditor — same trigger-picker UI as the horn's, just
/// repeated per severity (warning/alarm/critical) with a colored heading.
class _SeverityConditionSection extends StatelessWidget {
  const _SeverityConditionSection({
    required this.title,
    required this.color,
    required this.bucket,
    required this.condition,
    required this.onChanged,
  });

  final String title;
  final Color color;
  final LayoutBucket bucket;
  final PlcConditionConfig condition;
  final ValueChanged<PlcConditionConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        _PlcConditionEditor(
          bucket: bucket,
          condition: condition,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _HornConfigEditor extends StatelessWidget {
  const _HornConfigEditor({
    required this.config,
    required this.bucket,
    required this.onChanged,
  });

  final ButtonConfig config;
  final LayoutBucket bucket;
  final ValueChanged<ButtonConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final horn = HornConfig.fromCustomProperties(config.customProperties);

    void save(HornConfig next) {
      onChanged(
        config.copyWith(
          customProperties: next.applyToCustomProperties(
            config.customProperties,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _InfoNote(
          message:
              'The buzzer never sends a PLC output — it only sounds when '
              'the trigger condition below reads true from live PLC status.',
        ),
        const SizedBox(height: 10),
        _PlcConditionEditor(
          bucket: bucket,
          condition: horn.trigger,
          onChanged: (next) => save(horn.copyWith(trigger: next)),
        ),
        const SizedBox(height: 14),
        const Text(
          'SOUND PATTERN',
          style: TextStyle(
            color: AppColors.darkTextSub,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final pattern in HornSoundPattern.values)
              ChoiceChip(
                label: Text(_hornPatternLabel(pattern)),
                selected: horn.soundPattern == pattern,
                selectedColor: AppColors.accent.withAlpha(55),
                labelStyle: TextStyle(
                  color: horn.soundPattern == pattern
                      ? AppColors.accent
                      : AppColors.darkTextSub,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) => save(horn.copyWith(soundPattern: pattern)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          value: horn.soundEnabled,
          activeThumbColor: AppColors.accent,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Sound enabled',
            style: TextStyle(color: AppColors.darkText, fontSize: 12),
          ),
          onChanged: (value) => save(horn.copyWith(soundEnabled: value)),
        ),
        SwitchListTile(
          value: horn.visualPulseEnabled,
          activeThumbColor: AppColors.accent,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Visual pulse / glow',
            style: TextStyle(color: AppColors.darkText, fontSize: 12),
          ),
          onChanged: (value) => save(horn.copyWith(visualPulseEnabled: value)),
        ),
        SwitchListTile(
          value: horn.hapticFeedback,
          activeThumbColor: AppColors.accent,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Haptic feedback',
            style: TextStyle(color: AppColors.darkText, fontSize: 12),
          ),
          onChanged: (value) => save(horn.copyWith(hapticFeedback: value)),
        ),
        const SizedBox(height: 8),
        const Text(
          'ALARM PRIORITY',
          style: TextStyle(
            color: AppColors.darkTextSub,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final priority in AlarmPriority.values)
              ChoiceChip(
                label: Text(_alarmPriorityLabel(priority)),
                selected: horn.priority == priority,
                selectedColor: AppColors.accent.withAlpha(55),
                labelStyle: TextStyle(
                  color: horn.priority == priority
                      ? AppColors.accent
                      : AppColors.darkTextSub,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) => save(horn.copyWith(priority: priority)),
              ),
          ],
        ),
      ],
    );
  }
}

String _hornPatternLabel(HornSoundPattern pattern) => switch (pattern) {
  HornSoundPattern.steady => 'Steady',
  HornSoundPattern.pulsing => 'Pulsing',
  HornSoundPattern.doubleBeep => 'Double beep',
};

String _alarmPriorityLabel(AlarmPriority priority) => switch (priority) {
  AlarmPriority.low => 'Low',
  AlarmPriority.normal => 'Normal',
  AlarmPriority.high => 'High',
};

class _AlarmIndicatorConfigEditor extends StatelessWidget {
  const _AlarmIndicatorConfigEditor({
    required this.config,
    required this.bucket,
    required this.onChanged,
  });

  final ButtonConfig config;
  final LayoutBucket bucket;
  final ValueChanged<ButtonConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final alarm = AlarmIndicatorConfig.fromCustomProperties(
      config.customProperties,
    );

    void save(AlarmIndicatorConfig next) {
      onChanged(
        config.copyWith(
          customProperties: next.applyToCustomProperties(
            config.customProperties,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _InfoNote(
          message:
              'This indicator never sends a PLC output — severity is read '
              'directly from live PLC status against the conditions below, '
              'checked Critical, then Alarm, then Warning.',
        ),
        const SizedBox(height: 12),
        _SeverityConditionSection(
          title: 'WARNING CONDITION',
          color: AppColors.fastColor,
          bucket: bucket,
          condition: alarm.warningTrigger,
          onChanged: (next) => save(alarm.copyWith(warningTrigger: next)),
        ),
        const SizedBox(height: 14),
        _SeverityConditionSection(
          title: 'ALARM CONDITION',
          color: AppColors.darkDanger,
          bucket: bucket,
          condition: alarm.alarmTrigger,
          onChanged: (next) => save(alarm.copyWith(alarmTrigger: next)),
        ),
        const SizedBox(height: 14),
        _SeverityConditionSection(
          title: 'CRITICAL CONDITION',
          color: AppColors.eStopColor,
          bucket: bucket,
          condition: alarm.criticalTrigger,
          onChanged: (next) => save(alarm.copyWith(criticalTrigger: next)),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          value: alarm.acknowledgeEnabled,
          activeThumbColor: AppColors.accent,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Allow acknowledge',
            style: TextStyle(color: AppColors.darkText, fontSize: 12),
          ),
          subtitle: const Text(
            'Lets the operator tap to mute the display for the current '
            'alarm occurrence. Purely local — never sends a PLC output.',
            style: TextStyle(color: AppColors.darkTextSub, fontSize: 10.5),
          ),
          onChanged: (value) => save(alarm.copyWith(acknowledgeEnabled: value)),
        ),
        SwitchListTile(
          value: alarm.showStatusText,
          activeThumbColor: AppColors.accent,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Show status text',
            style: TextStyle(color: AppColors.darkText, fontSize: 12),
          ),
          onChanged: (value) => save(alarm.copyWith(showStatusText: value)),
        ),
        SwitchListTile(
          value: alarm.showTimestamp,
          activeThumbColor: AppColors.accent,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Show timestamp area',
            style: TextStyle(color: AppColors.darkText, fontSize: 12),
          ),
          onChanged: (value) => save(alarm.copyWith(showTimestamp: value)),
        ),
      ],
    );
  }
}

class _ConfigTextField extends StatefulWidget {
  const _ConfigTextField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.keyboardType,
  });

  final String label;
  final String value;
  final String? hint;
  final TextInputType? keyboardType;
  final ValueChanged<String> onChanged;

  @override
  State<_ConfigTextField> createState() => _ConfigTextFieldState();
}

class _ConfigTextFieldState extends State<_ConfigTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode()..addListener(_syncWhenIdle);
  }

  @override
  void didUpdateWidget(covariant _ConfigTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus &&
        oldWidget.value != widget.value &&
        _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_syncWhenIdle)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _syncWhenIdle() {
    if (_focusNode.hasFocus || _controller.text == widget.value) return;
    _controller.text = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: widget.keyboardType,
      style: const TextStyle(color: AppColors.darkText, fontSize: 13),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        labelStyle: const TextStyle(
          color: AppColors.darkTextMuted,
          fontSize: 11,
        ),
        hintStyle: const TextStyle(
          color: AppColors.darkTextMuted,
          fontSize: 11,
        ),
        filled: true,
        fillColor: AppColors.darkBg,
        border: const OutlineInputBorder(borderSide: BorderSide.none),
        isDense: true,
      ),
      onChanged: widget.onChanged,
    );
  }
}

String _numberText(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

ButtonConfig _newCustomButtonSeed({
  required ButtonType type,
  required int pageIndex,
}) {
  final (columns, rows) = ButtonConfig.defaultGridSizeFor(type);
  return ButtonConfig(
    id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
    type: type,
    plcMapping: PlcOutputVariant.df2,
    label: '',
    enabled: false,
    plcMappingEnabled: false,
    pageIndex: pageIndex,
    gridColumns: columns,
    gridRows: rows,
    columnSpan: columns,
  );
}

/// ButtonType -> ControlWidgetType, purely for feeding the existing
/// AxisTypePreview widget's API (presentation-only — the model itself reads
/// and writes ButtonType directly, with no ControlWidgetType intermediary).
/// horn/alarmIndicator are never reachable here — they're absent from
/// _typeEntries (the 8 legacy motion/safety roles never offer them, since a
/// hoist/traverse/travel axis becoming a horn or alarm makes no semantic
/// sense) and only ever created via the free-standing custom-button picker,
/// which uses AxisTypePreview's replacement, not this function.
ControlWidgetType _previewWidgetType(ButtonType type) => switch (type) {
  ButtonType.pushButton || ButtonType.horn => ControlWidgetType.pushButton,
  ButtonType.toggle => ControlWidgetType.toggle,
  ButtonType.sliderButton ||
  ButtonType.bidirectionalSlider5Step ||
  ButtonType.bidirectionalSlider3Step => ControlWidgetType.sliderButton,
  ButtonType.joystick => ControlWidgetType.joystick,
  ButtonType.potentiometer ||
  ButtonType.alarmIndicator => ControlWidgetType.rotary,
};

bool _spanAwareTypeChangesEnabled() => true;

// ─────────────────────────────────────────────────────────────────────────────
// TYPE tab
// ─────────────────────────────────────────────────────────────────────────────

class _TypeEntry {
  const _TypeEntry(
    this.type,
    this.label,
    this.icon,
    this.available,
    this.note, {
    this.isNone = false,
  });
  final ButtonType? type;
  final String label;
  final IconData icon;
  final bool available;
  final String note;
  final bool isNone;
}

const _noneTypeEntry = _TypeEntry(
  null,
  'None',
  Icons.block_rounded,
  true,
  'Leave this slot vacant. No PLC output is mapped or sent.',
  isNone: true,
);

const _typeEntries = [
  _TypeEntry(
    ButtonType.sliderButton,
    'Slider',
    Icons.linear_scale_rounded,
    true,
    'Drag for slow, drag further for fast.',
  ),
  _TypeEntry(
    ButtonType.pushButton,
    'Push Button',
    Icons.touch_app_rounded,
    true,
    'Spring-return or latched, per Behavior tab.',
  ),
  _TypeEntry(
    ButtonType.toggle,
    'Toggle Switch',
    Icons.toggle_on_rounded,
    true,
    'Rocker-style switch. Slow speed only.',
  ),
  _TypeEntry(
    ButtonType.joystick,
    'Joystick',
    Icons.gamepad_rounded,
    true,
    'Analog or digital joystick. Configure behavior in the Behavior tab.',
  ),
  _TypeEntry(
    ButtonType.potentiometer,
    'Potentiometer',
    Icons.tune_rounded,
    true,
    'Rotary analog value control. Output transport is pending.',
  ),
];

const _crossTravelEntry = _TypeEntry(
  ButtonType.bidirectionalSlider5Step,
  'Bidirectional Slider 5-Step',
  Icons.compare_arrows_rounded,
  true,
  'Paired LEFT/RIGHT slider with slow and fast zones. Requires both '
      'directions to select this type — otherwise falls back to independent '
      'rendering.',
);

const _crossTravelSlowOnlyEntry = _TypeEntry(
  ButtonType.bidirectionalSlider3Step,
  'Bidirectional Slider 3-Step',
  Icons.swap_horiz_rounded,
  true,
  'Single-box LEFT/RIGHT slider. Slow speed only.',
);

class _TypeTab extends StatelessWidget {
  const _TypeTab({
    required this.axis,
    required this.scrollController,
    this.editRole,
  });
  final AxisKind axis;
  final ControlRole? editRole;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final draft = context.watch<CustomizationModeController>().draft;
    final primaryRole = axis.primaryRole;
    final secondaryRole = axis.secondaryRole;
    final (primaryColor, primaryColorLight) = colorsForRole(primaryRole);
    final (secondaryColor, secondaryColorLight) = colorsForRole(secondaryRole);
    final primaryConfig = draft.buttonFor(primaryRole);
    final secondaryConfig = draft.buttonFor(secondaryRole);
    final editConfig = editRole == null ? null : draft.buttonFor(editRole!);

    if (editRole != null && editConfig == null) {
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        children: const [
          _TabCard(
            title: 'CONTROL TYPE',
            child: _InfoNote(message: 'This control has been removed.'),
          ),
        ],
      );
    }
    if (editRole == null &&
        (primaryConfig == null || secondaryConfig == null)) {
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        children: const [
          _TabCard(
            title: 'CONTROL TYPE',
            child: _InfoNote(
              message:
                  'Both axis directions must exist before editing the paired control type.',
            ),
          ),
        ],
      );
    }

    // Per-button edit (editRole != null): this button's own type. Axis-level
    // edit (traverse cross-travel pair, editRole == null): show "mixed" if
    // the two directions currently disagree, else the shared type.
    final primaryType = primaryConfig?.type ?? editConfig!.type;
    final secondaryType = secondaryConfig?.type ?? editConfig!.type;
    final previewType = editRole != null
        ? editConfig!.type
        : (primaryType == secondaryType ? primaryType : null);

    final entries = [
      if (editRole != null && !editRole!.isSafetyControl) _noneTypeEntry,
      ..._typeEntries,
      if (axis == AxisKind.traverse) ...[
        _crossTravelEntry,
        _crossTravelSlowOnlyEntry,
      ],
    ];

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        _TabCard(
          title: 'CONTROL TYPE',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoNote(
                message: editRole != null
                    ? 'Applies to ${editConfig!.label} only.'
                    : 'Applies to both ${primaryConfig!.label} and '
                          '${secondaryConfig!.label} on '
                          '${axis.displayName}.',
              ),
              if (previewType == null) ...[
                const SizedBox(height: 6),
                const _InfoNote(
                  message: 'LEFT and RIGHT currently have different types.',
                  color: AppColors.fastColor,
                ),
              ],
              const SizedBox(height: 10),
              for (final entry in entries)
                _TypeTile(
                  entry: entry,
                  isSelected: entry.isNone
                      ? editRole != null && editConfig?.visible == false
                      : previewType != null && previewType == entry.type,
                  onTap: entry.available
                      ? () {
                          final ctrl = context
                              .read<CustomizationModeController>();
                          if (entry.isNone) {
                            final role = editRole;
                            if (role == null) return;
                            final config = ctrl.draft.buttonFor(role);
                            if (config == null) return;
                            ctrl.applyDraftChangeAndCompact(
                              ctrl.draft.withButton(
                                role.name,
                                config.copyWith(visible: false, enabled: false),
                              ),
                            );
                            Navigator.of(context).pop();
                            return;
                          }
                          final selectedType = entry.type;
                          if (selectedType == null) return;
                          if (_spanAwareTypeChangesEnabled()) {
                            var updated = ctrl.draft;
                            final isCombinedCrossTravelToThreeZone =
                                editRole == null &&
                                selectedType ==
                                    ButtonType.bidirectionalSlider3Step &&
                                primaryType ==
                                    ButtonType.bidirectionalSlider5Step &&
                                secondaryType ==
                                    ButtonType.bidirectionalSlider5Step;
                            final combinedCrossTravelRole =
                                primaryConfig?.visible == true
                                ? primaryRole
                                : secondaryRole;
                            final rolesToUpdate =
                                editRole != null ||
                                    selectedType ==
                                        ButtonType.bidirectionalSlider5Step ||
                                    isCombinedCrossTravelToThreeZone
                                ? [
                                    editRole ??
                                        (isCombinedCrossTravelToThreeZone
                                            ? combinedCrossTravelRole
                                            : primaryRole),
                                  ]
                                : [primaryRole, secondaryRole];

                            for (final role in rolesToUpdate) {
                              final result = buildButtonTypeChange(
                                draft: updated,
                                role: role,
                                type: selectedType,
                              );
                              if (!result.isValid) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      result.message ?? kCrossTravelSpanMessage,
                                    ),
                                  ),
                                );
                                return;
                              }
                              updated = result.layout!;
                            }
                            ctrl.applyDraftChange(updated);
                            return;
                          }
                          if (editRole != null) {
                            // Per-button: update only this button's type —
                            // never force-pairs the other side, preserving
                            // "editing one button never affects another."
                          } else {
                            // Traverse cross-travel pair entry point: applies
                            // to both directions (this is the one axis-level
                            // edit surface, opened via .forAxis).
                          }
                        }
                      : null,
                ),
            ],
          ),
        ),
        _TabCard(
          title: 'LIVE PREVIEW',
          child: AxisTypePreview(
            widgetType: _previewWidgetType(previewType ?? primaryType),
            wiringConfig: (primaryConfig ?? editConfig!).behavior.wiring,
            primaryLabel: primaryConfig?.label ?? primaryRole.defaultLabel,
            secondaryLabel:
                secondaryConfig?.label ?? secondaryRole.defaultLabel,
            primaryIcon: iconForRole(primaryRole),
            secondaryIcon: iconForRole(secondaryRole),
            primaryColor: primaryColor,
            primaryColorLight: primaryColorLight,
            secondaryColor: secondaryColor,
            secondaryColorLight: secondaryColorLight,
          ),
        ),
      ],
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({
    required this.entry,
    required this.isSelected,
    required this.onTap,
  });
  final _TypeEntry entry;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppColors.accent : AppColors.darkTextSub;
    return Opacity(
      opacity: entry.available ? 1.0 : 0.5,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: isSelected ? AppColors.accent.withAlpha(24) : AppColors.darkBg,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? AppColors.accent.withAlpha(100)
                      : AppColors.darkBorder,
                ),
              ),
              child: Row(
                children: [
                  Icon(entry.icon, color: color, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              entry.label,
                              style: TextStyle(
                                color: isSelected
                                    ? AppColors.accent
                                    : AppColors.darkText,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (!entry.available) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.fastColor.withAlpha(35),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Coming Soon',
                                  style: TextStyle(
                                    color: AppColors.fastColorLight,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          entry.note,
                          style: const TextStyle(
                            color: AppColors.darkTextMuted,
                            fontSize: 10,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.accent,
                      size: 18,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LABEL tab
// ─────────────────────────────────────────────────────────────────────────────

class _LabelTab extends StatelessWidget {
  const _LabelTab({
    required this.role,
    required this.axis,
    required this.scrollController,
  });
  final ControlRole? role;
  final AxisKind axis;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final roles = role != null
        ? [role!]
        : [axis.primaryRole, axis.secondaryRole];

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        for (final r in roles)
          _TabCard(
            title: '${r.defaultLabel} LABEL',
            child: _LabelField(role: r),
          ),
      ],
    );
  }
}

class _LabelField extends StatefulWidget {
  const _LabelField({required this.role});
  final ControlRole role;

  @override
  State<_LabelField> createState() => _LabelFieldState();
}

class _LabelFieldState extends State<_LabelField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String _lastCommitted = '';

  @override
  void initState() {
    super.initState();
    final draft = context.read<CustomizationModeController>().draft;
    _lastCommitted = draft.buttonFor(widget.role)!.label;
    _controller = TextEditingController(text: _lastCommitted);
    _focusNode = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _commit();
  }

  void _commit() {
    final value = _controller.text.trim();
    if (value.isEmpty || value == _lastCommitted) return;
    final customCtrl = context.read<CustomizationModeController>();
    final draft = customCtrl.draft;
    final config = draft.buttonFor(widget.role)!;
    customCtrl.applyDraftChange(
      draft.withButton(widget.role.name, config.copyWith(label: value)),
    );
    _lastCommitted = value;
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      maxLength: ControlLabelConfig.maxLabelLength,
      style: const TextStyle(color: AppColors.darkText, fontSize: 14),
      onSubmitted: (_) => _commit(),
      decoration: const InputDecoration(
        filled: true,
        fillColor: AppColors.darkBg,
        border: OutlineInputBorder(borderSide: BorderSide.none),
        counterStyle: TextStyle(color: AppColors.darkTextMuted, fontSize: 10),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APPEARANCE tab
//
// The legacy push-button primitive (IndustrialSpringButton) and slider
// (CraneSliderButton) are fixed custom-painted widgets that only expose
// color overrides — deliberately not touched here to avoid destabilizing
// safety-adjacent code. Corner radius / icon size / typography only take
// visible effect on the new ToggleSwitchButton, so those controls are shown
// only when the axis's Control Type is Toggle Switch, keeping the UI honest
// (no slider that silently does nothing).
// ─────────────────────────────────────────────────────────────────────────────

const _swatches = [
  AppColors.upColor,
  AppColors.downColor,
  AppColors.traverseColor,
  AppColors.travelColor,
  AppColors.fastColor,
  AppColors.accent,
  AppColors.darkInfo,
  AppColors.darkSuccess,
];

class _AppearanceTab extends StatelessWidget {
  const _AppearanceTab({
    required this.role,
    required this.axis,
    required this.scrollController,
  });
  final ControlRole? role;
  final AxisKind axis;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final roles = role != null
        ? [role!]
        : [axis.primaryRole, axis.secondaryRole];
    final draft = context.watch<CustomizationModeController>().draft;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        const _InfoNote(
          message:
              'Corner radius, icon size, and label typography are only '
              'configurable for Toggle Switch controls today. Colors and '
              'icon apply to every control type.',
        ),
        const SizedBox(height: 10),
        for (final r in roles)
          _TabCard(
            title: '${r.defaultLabel} APPEARANCE',
            // Each direction's extended controls are gated on its OWN
            // resolved type, not a shared axis-wide flag — fixes the
            // previous bug where both directions showed/hid the extra
            // controls together based on the legacy axis-level type.
            child: _RoleStyleEditor(
              role: r,
              showFullControls: draft.buttonFor(r)!.type == ButtonType.toggle,
            ),
          ),
      ],
    );
  }
}

class _RoleStyleEditor extends StatefulWidget {
  const _RoleStyleEditor({required this.role, required this.showFullControls});
  final ControlRole role;
  final bool showFullControls;

  @override
  State<_RoleStyleEditor> createState() => _RoleStyleEditorState();
}

const _iconPalette = [
  Icons.arrow_upward_rounded,
  Icons.arrow_downward_rounded,
  Icons.arrow_back_rounded,
  Icons.arrow_forward_rounded,
  Icons.north_rounded,
  Icons.south_rounded,
  Icons.east_rounded,
  Icons.west_rounded,
  Icons.touch_app_rounded,
  Icons.toggle_on_rounded,
  Icons.linear_scale_rounded,
  Icons.warning_amber_rounded,
  Icons.power_settings_new_rounded,
  Icons.restart_alt_rounded,
  Icons.compare_arrows_rounded,
  Icons.swap_vert_rounded,
  Icons.tune_rounded,
  Icons.rotate_right_rounded,
];

class _RoleStyleEditorState extends State<_RoleStyleEditor> {
  double? _localCornerRadius;
  double? _localIconSize;
  double? _localLabelFontSize;

  void _update(ButtonStyleConfig Function(ButtonStyleConfig) transform) {
    final customCtrl = context.read<CustomizationModeController>();
    final draft = customCtrl.draft;
    final config = draft.buttonFor(widget.role)!;
    customCtrl.applyDraftChange(
      draft.withButton(
        widget.role.name,
        config.copyWith(style: transform(config.style)),
      ),
    );
  }

  void _updateIcon(IconData? icon) {
    final customCtrl = context.read<CustomizationModeController>();
    final draft = customCtrl.draft;
    final config = draft.buttonFor(widget.role)!;
    customCtrl.applyDraftChange(
      draft.withButton(
        widget.role.name,
        config.copyWith(icon: icon, clearIcon: icon == null),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = context.watch<CustomizationModeController>().draft;
    final config = draft.buttonFor(widget.role)!;
    final style = config.style;
    final (defaultPrimary, defaultActive) = colorsForRole(widget.role);
    final defaultIcon = iconForRole(widget.role);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PRIMARY COLOR',
          style: TextStyle(
            color: AppColors.darkTextSub,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        _SwatchRow(
          selected: style.primaryColor,
          defaultColor: defaultPrimary,
          onSelect: (c) => _update((s) => s.copyWith(primaryColor: c)),
          onClear: () => _update((s) => s.copyWith(clearPrimaryColor: true)),
        ),
        const SizedBox(height: 12),
        const Text(
          'ACTIVE COLOR',
          style: TextStyle(
            color: AppColors.darkTextSub,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        _SwatchRow(
          selected: style.activeColor,
          defaultColor: defaultActive,
          onSelect: (c) => _update((s) => s.copyWith(activeColor: c)),
          onClear: () => _update((s) => s.copyWith(clearActiveColor: true)),
        ),
        const SizedBox(height: 12),
        const Text(
          'ICON',
          style: TextStyle(
            color: AppColors.darkTextSub,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _IconDot(
              icon: defaultIcon,
              isSelected: config.icon == null,
              isDefault: true,
              onTap: () => _updateIcon(null),
            ),
            for (final icon in _iconPalette)
              _IconDot(
                icon: icon,
                isSelected: config.icon == icon,
                onTap: () => _updateIcon(icon),
              ),
          ],
        ),
        if (widget.showFullControls) ...[
          const SizedBox(height: 14),
          _LabeledSlider(
            label: 'Corner radius',
            value: _localCornerRadius ?? (style.cornerRadius ?? 16),
            min: ButtonStyleConfig.minCornerRadius,
            max: ButtonStyleConfig.maxCornerRadius,
            onChanged: (v) => setState(() => _localCornerRadius = v),
            onChangeEnd: (v) {
              setState(() => _localCornerRadius = null);
              _update((s) => s.copyWith(cornerRadius: v));
            },
          ),
          _LabeledSlider(
            label: 'Icon size',
            value: _localIconSize ?? (style.iconSize ?? 26),
            min: ButtonStyleConfig.minIconSize,
            max: ButtonStyleConfig.maxIconSize,
            onChanged: (v) => setState(() => _localIconSize = v),
            onChangeEnd: (v) {
              setState(() => _localIconSize = null);
              _update((s) => s.copyWith(iconSize: v));
            },
          ),
          _LabeledSlider(
            label: 'Label font size',
            value: _localLabelFontSize ?? (style.labelFontSize ?? 13),
            min: ButtonStyleConfig.minLabelFontSize,
            max: ButtonStyleConfig.maxLabelFontSize,
            onChanged: (v) => setState(() => _localLabelFontSize = v),
            onChangeEnd: (v) {
              setState(() => _localLabelFontSize = null);
              _update((s) => s.copyWith(labelFontSize: v));
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Show label',
                style: TextStyle(color: AppColors.darkText, fontSize: 12),
              ),
              Switch(
                value: style.showLabel,
                activeThumbColor: AppColors.accent,
                onChanged: (v) => _update((s) => s.copyWith(showLabel: v)),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Bold label',
                style: TextStyle(color: AppColors.darkText, fontSize: 12),
              ),
              Switch(
                value: style.labelFontWeight == FontWeight.w900,
                activeThumbColor: AppColors.accent,
                onChanged: (v) => _update(
                  (s) => s.copyWith(
                    labelFontWeight: v ? FontWeight.w900 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onChangeEnd,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: AppColors.darkText, fontSize: 12),
            ),
            Text(
              value.toStringAsFixed(0),
              style: const TextStyle(
                color: AppColors.darkTextMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.accent,
            thumbColor: AppColors.accent,
            inactiveTrackColor: AppColors.darkBorder,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    );
  }
}

class _SwatchRow extends StatelessWidget {
  const _SwatchRow({
    required this.selected,
    required this.defaultColor,
    required this.onSelect,
    required this.onClear,
  });
  final Color? selected;
  final Color defaultColor;
  final ValueChanged<Color> onSelect;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SwatchDot(
          color: defaultColor,
          isSelected: selected == null,
          isDefault: true,
          onTap: onClear,
        ),
        for (final c in _swatches)
          _SwatchDot(
            color: c,
            isSelected: selected == c,
            onTap: () => onSelect(c),
          ),
      ],
    );
  }
}

class _SwatchDot extends StatelessWidget {
  const _SwatchDot({
    required this.color,
    required this.isSelected,
    required this.onTap,
    this.isDefault = false,
  });
  final Color color;
  final bool isSelected;
  final bool isDefault;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? AppColors.darkText : Colors.transparent,
            width: 2,
          ),
        ),
        child: isDefault
            ? const Icon(Icons.refresh_rounded, size: 14, color: Colors.white)
            : (isSelected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.white,
                    )
                  : null),
      ),
    );
  }
}

class _IconDot extends StatelessWidget {
  const _IconDot({
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.isDefault = false,
  });
  final IconData icon;
  final bool isSelected;
  final bool isDefault;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.darkBg,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.darkBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Icon(
          icon,
          size: 16,
          color: isSelected ? AppColors.accent : AppColors.darkTextSub,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BEHAVIOR tab
// ─────────────────────────────────────────────────────────────────────────────

class _BehaviorTab extends StatelessWidget {
  const _BehaviorTab({
    required this.axis,
    required this.scrollController,
    this.editRole,
  });
  final AxisKind axis;
  final ControlRole? editRole;
  final ScrollController scrollController;

  List<ControlRole> get _roles =>
      editRole != null ? [editRole!] : [axis.primaryRole, axis.secondaryRole];

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [for (final role in _roles) _BehaviorCard(role: role)],
    );
  }
}

class _BehaviorCard extends StatelessWidget {
  const _BehaviorCard({required this.role});
  final ControlRole role;

  @override
  Widget build(BuildContext context) {
    final customCtrl = context.watch<CustomizationModeController>();
    final draft = customCtrl.draft;
    final config = draft.buttonFor(role)!;
    final isSafety = role.isSafetyControl;
    final wiringApplicable =
        config.type == ButtonType.pushButton ||
        config.type == ButtonType.toggle;
    final validation = const LayoutValidationService().validateButtonConfig(
      config,
      draft.buttons,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isSafety)
          _TabCard(
            title: '${role.defaultLabel} · VISIBILITY & AVAILABILITY',
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Visible',
                      style: TextStyle(color: AppColors.darkText, fontSize: 12),
                    ),
                    Switch(
                      value: config.visible,
                      activeThumbColor: AppColors.accent,
                      onChanged: (v) => customCtrl.applyDraftChange(
                        draft.withButton(
                          role.name,
                          config.copyWith(visible: v),
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Enabled',
                      style: TextStyle(color: AppColors.darkText, fontSize: 12),
                    ),
                    Switch(
                      value: config.enabled,
                      activeThumbColor: AppColors.accent,
                      onChanged: (v) => customCtrl.applyDraftChange(
                        draft.withButton(
                          role.name,
                          config.copyWith(enabled: v),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (!isSafety)
          _TabCard(
            title: '${role.defaultLabel} · MODE',
            child: wiringApplicable
                ? _SwitchWiringPicker(
                    config: config,
                    onChanged: (wiring) => customCtrl.applyDraftChange(
                      draft.withButton(
                        role.name,
                        config.copyWith(
                          behavior: config.behavior.copyWith(wiring: wiring),
                        ),
                      ),
                    ),
                  )
                : const _InfoNote(
                    message:
                        'This control type does not use push-button latching or spring-return wiring.',
                  ),
          ),
        // _TabCard(
        //   title: '${role.defaultLabel} · REPEAT WHILE HELD',
        //   child: Column(
        //     crossAxisAlignment: CrossAxisAlignment.start,
        //     children: [
        //       Row(
        //         mainAxisAlignment: MainAxisAlignment.spaceBetween,
        //         children: [
        //           const Text(
        //             'Repeat while held',
        //             style: TextStyle(color: AppColors.darkText, fontSize: 12),
        //           ),
        //           Switch(
        //             value: config.behavior.repeatWhileHeld,
        //             activeThumbColor: AppColors.accent,
        //             onChanged: (v) => customCtrl.applyDraftChange(
        //               draft.withButton(
        //                 role.name,
        //                 config.copyWith(
        //                   behavior: config.behavior.copyWith(
        //                     repeatWhileHeld: v,
        //                   ),
        //                 ),
        //               ),
        //             ),
        //           ),
        //         ],
        //       ),
        //       if (config.behavior.repeatWhileHeld)
        //         _LabeledSlider(
        //           label: 'Repeat interval (ms)',
        //           value: config.behavior.repeatIntervalMs.toDouble(),
        //           min: ButtonBehaviorConfig.minRepeatIntervalMs.toDouble(),
        //           max: ButtonBehaviorConfig.maxRepeatIntervalMs.toDouble(),
        //           onChanged: (_) {},
        //           onChangeEnd: (v) => customCtrl.applyDraftChange(
        //             draft.withButton(
        //               role.name,
        //               config.copyWith(
        //                 behavior: config.behavior.copyWith(
        //                   repeatIntervalMs: v.round(),
        //                 ),
        //               ),
        //             ),
        //           ),
        //         )
        //       else
        //         const _InfoNote(
        //           message:
        //               'No current button type fires a repeat timer while '
        //               'held — this setting is stored for future control '
        //               'types (e.g. a jog-increment button).',
        //         ),
        //     ],
        //   ),
        // ),
        if (!isSafety)
          _TabCard(
            title: '${role.defaultLabel} · MUTUAL EXCLUSION',
            child: _MutualExclusionEditor(role: role),
          ),
        _TabCard(
          title: '${role.defaultLabel} · OUTPUT MAPPING',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isSafety)
                const _InfoNote(
                  message:
                      'E-Stop / Reset E-Stop are fixed safety controls — '
                      'their output is never user-configurable.',
                )
              else
                _OutputMappingEditor(
                  config: config,
                  bucket: customCtrl.activeBucket,
                  onChanged: (next) => customCtrl.applyDraftChange(
                    draft.withButton(role.name, next),
                  ),
                ),
              if (!validation.isValid) ...[
                const SizedBox(height: 8),
                for (final error in validation.errors)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _InfoNote(
                      message: error,
                      color: AppColors.eStopColor,
                    ),
                  ),
              ],
            ],
          ),
        ),
        // if (!isSafety)
        //   _TabCard(
        //     title: '${role.defaultLabel} · GROUP',
        //     child: _GroupField(role: role),
        //   ),
        if (config.type == ButtonType.joystick)
          _TabCard(
            title: '${role.defaultLabel} · JOYSTICK',
            child: _JoystickConfigEditor(role: role),
          ),
        if (config.type == ButtonType.potentiometer)
          _TabCard(
            title: '${role.defaultLabel} - POTENTIOMETER',
            child: _PotentiometerConfigEditor(
              config: config,
              onChanged: (next) => customCtrl.applyDraftChange(
                draft.withButton(role.name, next!),
              ),
            ),
          ),
        if (config.type != ButtonType.joystick &&
            config.type != ButtonType.potentiometer)
          _TabCard(
            title: '${role.defaultLabel} · CUSTOM PROPERTIES',
            child: const _InfoNote(
              message:
                  'Advanced per-type custom fields — none defined for this '
                  'button type yet. Reserved for future control types (e.g. a '
                  'joystick\'s dead-zone radius).',
            ),
          ),
      ],
    );
  }
}

class _JoystickConfigEditor extends StatelessWidget {
  const _JoystickConfigEditor({required this.role});

  final ControlRole role;

  @override
  Widget build(BuildContext context) {
    final customCtrl = context.watch<CustomizationModeController>();
    final draft = customCtrl.draft;
    final config = draft.buttonFor(role)!;
    final joystick = JoystickConfig.fromCustomProperties(
      config.customProperties,
    ).normalizedForMode();

    void save(JoystickConfig next) {
      customCtrl.applyDraftChange(
        draft.withButton(
          role.name,
          config.copyWith(
            customProperties: next.normalizedForMode().applyToCustomProperties(
              config.customProperties,
            ),
          ),
        ),
      );
    }

    Widget segmented<T>({
      required String label,
      required T value,
      required List<T> values,
      required String Function(T) text,
      required ValueChanged<T> onChanged,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.darkTextMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final item in values)
                  ChoiceChip(
                    label: Text(text(item)),
                    selected: item == value,
                    selectedColor: AppColors.accent.withAlpha(50),
                    labelStyle: TextStyle(
                      color: item == value
                          ? AppColors.accent
                          : AppColors.darkTextSub,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                    onSelected: (_) => onChanged(item),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    Widget slider({
      required String label,
      required double value,
      required double min,
      required double max,
      required ValueChanged<double> onChanged,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label ${value.toStringAsFixed(2)}',
            style: const TextStyle(
              color: AppColors.darkTextMuted,
              fontSize: 11,
            ),
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: 20,
            activeColor: AppColors.accent,
            inactiveColor: AppColors.darkBorder,
            onChanged: onChanged,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        segmented<JoystickMode>(
          label: 'Mode',
          value: joystick.mode,
          values: JoystickMode.values,
          text: (mode) => mode.label,
          onChanged: (mode) => save(
            joystick.copyWith(
              mode: mode,
              boundary: switch (mode) {
                JoystickMode.dualAxisAnalog => JoystickBoundary.circular,
                JoystickMode.singleAxisAnalog ||
                JoystickMode.singleAxisDigital5 ||
                JoystickMode.dualAxisDigital4 => joystick.boundary,
              },
              springReturn: switch (mode) {
                JoystickMode.singleAxisDigital5 ||
                JoystickMode.dualAxisAnalog => true,
                JoystickMode.dualAxisDigital4 => false,
                JoystickMode.singleAxisAnalog => joystick.springReturn,
              },
              allowDiagonal: switch (mode) {
                JoystickMode.dualAxisAnalog => true,
                JoystickMode.singleAxisAnalog ||
                JoystickMode.singleAxisDigital5 ||
                JoystickMode.dualAxisDigital4 => joystick.allowDiagonal,
              },
            ),
          ),
        ),
        segmented<JoystickAxis>(
          label: 'Single-axis orientation',
          value: joystick.axis,
          values: JoystickAxis.values,
          text: (axis) =>
              axis == JoystickAxis.vertical ? 'Vertical' : 'Horizontal',
          onChanged: (axis) => save(joystick.copyWith(axis: axis)),
        ),
        if (joystick.mode != JoystickMode.dualAxisAnalog)
          segmented<JoystickBoundary>(
            label: 'Movement bound',
            value: joystick.boundary,
            values: JoystickBoundary.values,
            text: (bound) =>
                bound == JoystickBoundary.circular ? 'Circular' : 'Square',
            onChanged: (bound) => save(joystick.copyWith(boundary: bound)),
          ),
        if (joystick.mode != JoystickMode.singleAxisDigital5 &&
            joystick.mode != JoystickMode.dualAxisAnalog)
          SwitchListTile(
            value: joystick.springReturn,
            activeThumbColor: AppColors.accent,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Spring return',
              style: TextStyle(color: AppColors.darkText, fontSize: 12),
            ),
            subtitle: const Text(
              'Off gives the joystick a maintained friction feel.',
              style: TextStyle(color: AppColors.darkTextMuted, fontSize: 10),
            ),
            onChanged: (value) => save(joystick.copyWith(springReturn: value)),
          ),
        if (joystick.isDualAxis && joystick.mode != JoystickMode.dualAxisAnalog)
          SwitchListTile(
            value: joystick.allowDiagonal,
            activeThumbColor: AppColors.accent,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Allow diagonals',
              style: TextStyle(color: AppColors.darkText, fontSize: 12),
            ),
            subtitle: const Text(
              'Off selects the stronger axis to avoid ambiguous directions.',
              style: TextStyle(color: AppColors.darkTextMuted, fontSize: 10),
            ),
            onChanged: (value) => save(joystick.copyWith(allowDiagonal: value)),
          ),
        slider(
          label: 'Dead zone',
          value: joystick.deadZone,
          min: 0.0,
          max: 0.45,
          onChanged: (value) => save(joystick.copyWith(deadZone: value)),
        ),
        slider(
          label: 'Slow threshold',
          value: joystick.slowThreshold,
          min: 0.05,
          max: 0.75,
          onChanged: (value) => save(joystick.copyWith(slowThreshold: value)),
        ),
        slider(
          label: 'Fast threshold',
          value: joystick.fastThreshold,
          min: 0.30,
          max: 1.0,
          onChanged: (value) => save(joystick.copyWith(fastThreshold: value)),
        ),
        const _InfoNote(
          message:
              'Analog modes emit normalized joystick values inside the UI. '
              'Until the PLC firmware exposes analog output fields, the '
              'strategy maps movement through the existing digital command '
              'composer.',
        ),
      ],
    );
  }
}

class _MutualExclusionEditor extends StatelessWidget {
  const _MutualExclusionEditor({required this.role});
  final ControlRole role;

  @override
  Widget build(BuildContext context) {
    final customCtrl = context.watch<CustomizationModeController>();
    final draft = customCtrl.draft;
    final config = draft.buttonFor(role)!;
    final others =
        draft.buttons.values
            .where((b) => b.id != config.id && b.role?.isSafetyControl != true)
            .toList()
          ..sort((a, b) => a.label.compareTo(b.label));

    Future<void> toggleExclusion(ButtonConfig target, bool exclude) async {
      final isSameAxisPair = role.pairedRole?.name == target.id;
      if (!exclude && isSameAxisPair) {
        final confirmed = await confirmDialog(
          context,
          title: 'Remove safety interlock?',
          body:
              '${config.label} and ${target.label} can currently never run '
              'at the same time. Removing this prevents that protection — '
              'both could become active simultaneously. This is not '
              'blocked, but confirm you intend it.',
          confirmLabel: 'Remove interlock',
        );
        if (!confirmed) return;
      }

      final newSelfExcluded = Set<String>.from(
        config.mutualExclusion.excludedButtonIds,
      );
      final newTargetExcluded = Set<String>.from(
        target.mutualExclusion.excludedButtonIds,
      );
      if (exclude) {
        newSelfExcluded.add(target.id);
        newTargetExcluded.add(config.id);
      } else {
        newSelfExcluded.remove(target.id);
        newTargetExcluded.remove(config.id);
      }

      final updated = draft
          .withButton(
            config.id,
            config.copyWith(
              mutualExclusion: config.mutualExclusion.copyWith(
                excludedButtonIds: newSelfExcluded,
              ),
            ),
          )
          .withButton(
            target.id,
            target.copyWith(
              mutualExclusion: target.mutualExclusion.copyWith(
                excludedButtonIds: newTargetExcluded,
              ),
            ),
          );
      customCtrl.applyDraftChange(updated);
    }

    void toggleInclusion(ButtonConfig target, bool include) {
      final newSelfIncluded = Set<String>.from(
        config.mutualExclusion.inclusiveButtonIds,
      );
      if (include) {
        newSelfIncluded.add(target.id);
      } else {
        newSelfIncluded.remove(target.id);
      }
      customCtrl.applyDraftChange(
        draft.withButton(
          config.id,
          config.copyWith(
            mutualExclusion: config.mutualExclusion.copyWith(
              inclusiveButtonIds: newSelfIncluded,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _InfoNote(
          message:
              'Excluded buttons are forced idle while this one is active. '
              'Exclusion is always symmetric — checking a box updates both '
              'buttons.',
        ),
        const SizedBox(height: 8),
        for (final target in others)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppColors.accent,
            title: Text(
              target.label.isEmpty ? target.id : target.label,
              style: const TextStyle(color: AppColors.darkText, fontSize: 12),
            ),
            value: config.mutualExclusion.excludedButtonIds.contains(target.id),
            onChanged: (v) => toggleExclusion(target, v ?? false),
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text(
            'INCLUSIVE (may run together)',
            style: TextStyle(
              color: AppColors.darkTextSub,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          children: [
            for (final target in others)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppColors.accent,
                title: Text(
                  target.label.isEmpty ? target.id : target.label,
                  style: const TextStyle(
                    color: AppColors.darkText,
                    fontSize: 12,
                  ),
                ),
                value: config.mutualExclusion.inclusiveButtonIds.contains(
                  target.id,
                ),
                onChanged: (v) => toggleInclusion(target, v ?? false),
              ),
          ],
        ),
      ],
    );
  }
}

class _GroupField extends StatefulWidget {
  const _GroupField({required this.role});
  final ControlRole role;

  @override
  State<_GroupField> createState() => _GroupFieldState();
}

class _GroupFieldState extends State<_GroupField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String _lastCommitted = '';

  @override
  void initState() {
    super.initState();
    final draft = context.read<CustomizationModeController>().draft;
    _lastCommitted = draft.buttonFor(widget.role)!.group ?? '';
    _controller = TextEditingController(text: _lastCommitted);
    _focusNode = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _commit();
  }

  void _commit() {
    final value = _controller.text.trim();
    if (value == _lastCommitted) return;
    final customCtrl = context.read<CustomizationModeController>();
    final draft = customCtrl.draft;
    final config = draft.buttonFor(widget.role)!;
    customCtrl.applyDraftChange(
      draft.withButton(
        widget.role.name,
        config.copyWith(group: value, clearGroup: value.isEmpty),
      ),
    );
    _lastCommitted = value;
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      style: const TextStyle(color: AppColors.darkText, fontSize: 14),
      onSubmitted: (_) => _commit(),
      decoration: const InputDecoration(
        filled: true,
        fillColor: AppColors.darkBg,
        border: OutlineInputBorder(borderSide: BorderSide.none),
        hintText: 'Optional tag, e.g. "hoist controls"',
        hintStyle: TextStyle(color: AppColors.darkTextMuted, fontSize: 12),
      ),
    );
  }
}
