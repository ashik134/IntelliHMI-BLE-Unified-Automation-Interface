import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/customization_mode_controller.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/plc_mapping.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';

class FreeButtonEditSheet extends StatelessWidget {
  const FreeButtonEditSheet({super.key, required this.buttonId});

  final String buttonId;

  static Future<void> show(BuildContext context, String buttonId) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FreeButtonEditSheet(buttonId: buttonId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.42,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Consumer<CustomizationModeController>(
            builder: (context, customCtrl, _) {
              final config = customCtrl.draft.resolvedButtons[buttonId];
              if (config == null) {
                return const Center(
                  child: Text(
                    'Button not found',
                    style: TextStyle(color: AppColors.darkText),
                  ),
                );
              }
              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.add_circle_outline_rounded,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          config.label.isEmpty ? 'New Button' : config.label,
                          style: const TextStyle(
                            color: AppColors.darkText,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.darkTextSub,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _EditorCard(
                    title: 'Identity',
                    child: _LabelField(config: config),
                  ),
                  const SizedBox(height: 10),
                  _EditorCard(
                    title: 'Button Type',
                    child: _TypePicker(config: config),
                  ),
                  const SizedBox(height: 10),
                  _EditorCard(
                    title: 'PLC Function',
                    child: _MappingPicker(config: config),
                  ),
                  const SizedBox(height: 10),
                  _EditorCard(
                    title: 'Behavior',
                    child: _BehaviorPicker(config: config),
                  ),
                  const SizedBox(height: 10),
                  _EditorCard(
                    title: 'Appearance',
                    child: _AppearancePicker(config: config),
                  ),
                  const SizedBox(height: 10),
                  _EditorCard(
                    title: 'Size',
                    child: _SizePicker(config: config),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _EditorCard extends StatelessWidget {
  const _EditorCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.darkBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: AppColors.darkTextSub,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _LabelField extends StatefulWidget {
  const _LabelField({required this.config});

  final ButtonConfig config;

  @override
  State<_LabelField> createState() => _LabelFieldState();
}

class _LabelFieldState extends State<_LabelField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.config.label);
  }

  @override
  void didUpdateWidget(covariant _LabelField oldWidget) {
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
        fillColor: AppColors.panel,
        border: OutlineInputBorder(borderSide: BorderSide.none),
        counterStyle: TextStyle(color: AppColors.darkTextMuted, fontSize: 10),
      ),
      onSubmitted: (_) => _save(context),
      onEditingComplete: () => _save(context),
    );
  }

  void _save(BuildContext context) {
    final value = _controller.text.trim();
    if (value.isEmpty || value == widget.config.label) return;
    _update(context, widget.config.copyWith(label: value));
  }
}

class _TypePicker extends StatelessWidget {
  const _TypePicker({required this.config});

  final ButtonConfig config;

  @override
  Widget build(BuildContext context) {
    const supportedTypes = [
      ButtonType.pushButton,
      ButtonType.toggle,
      ButtonType.sliderButton,
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final type in supportedTypes)
          ChoiceChip(
            label: Text(_typeLabel(type)),
            selected: config.type == type,
            selectedColor: AppColors.accent.withAlpha(55),
            labelStyle: TextStyle(
              color: config.type == type
                  ? AppColors.accent
                  : AppColors.darkTextSub,
              fontWeight: FontWeight.w700,
            ),
            onSelected: (_) {
              final (columns, rows) = ButtonConfig.defaultGridSizeFor(type);
              _update(
                context,
                config.copyWith(
                  type: type,
                  gridColumns: columns,
                  gridRows: rows,
                ),
              );
            },
          ),
      ],
    );
  }
}

class _MappingPicker extends StatelessWidget {
  const _MappingPicker({required this.config});

  final ButtonConfig config;

  @override
  Widget build(BuildContext context) {
    final value = config.plcMappingEnabled ? config.plcMapping : null;
    return DropdownButtonFormField<PlcMapping?>(
      initialValue: value,
      dropdownColor: AppColors.panel,
      decoration: const InputDecoration(
        filled: true,
        fillColor: AppColors.panel,
        border: OutlineInputBorder(borderSide: BorderSide.none),
      ),
      style: const TextStyle(color: AppColors.darkText),
      items: [
        const DropdownMenuItem<PlcMapping?>(
          value: null,
          child: Text('Unassigned'),
        ),
        for (final mapping in PlcMapping.values)
          if (mapping != PlcMapping.estop)
            DropdownMenuItem<PlcMapping?>(
              value: mapping,
              child: Text(_mappingLabel(mapping)),
            ),
      ],
      onChanged: (mapping) {
        _update(
          context,
          config.copyWith(
            plcMapping: mapping ?? config.plcMapping,
            plcMappingEnabled: mapping != null,
            enabled: mapping != null,
          ),
        );
      },
    );
  }
}

class _BehaviorPicker extends StatelessWidget {
  const _BehaviorPicker({required this.config});

  final ButtonConfig config;

  @override
  Widget build(BuildContext context) {
    return Column(
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
              ? (value) => _update(context, config.copyWith(enabled: value))
              : null,
        ),
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
                  onSelected: (_) => _update(
                    context,
                    config.copyWith(
                      behavior: config.behavior.copyWith(wiring: wiring),
                    ),
                  ),
                ),
          ],
        ),
      ],
    );
  }
}

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

class _AppearancePicker extends StatelessWidget {
  const _AppearancePicker({required this.config});

  final ButtonConfig config;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final color in _swatches)
          InkWell(
            onTap: () => _update(
              context,
              config.copyWith(
                style: config.style.copyWith(primaryColor: color),
              ),
            ),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: config.style.primaryColor == color
                      ? AppColors.darkText
                      : AppColors.darkBorder,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SizePicker extends StatelessWidget {
  const _SizePicker({required this.config});

  final ButtonConfig config;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StepperButton(
            label: 'Columns',
            value: config.gridColumnSpan,
            onMinus: () => _resize(context, -1, 0),
            onPlus: () => _resize(context, 1, 0),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StepperButton(
            label: 'Rows',
            value: config.gridRowSpan,
            onMinus: () => _resize(context, 0, -1),
            onPlus: () => _resize(context, 0, 1),
          ),
        ),
      ],
    );
  }

  void _resize(BuildContext context, int dx, int dy) {
    final minSize = ButtonConfig.defaultGridSizeFor(
      config.type,
      customProperties: config.customProperties,
    );
    final customCtrl = context.read<CustomizationModeController>();
    final result = buildButtonResize(
      buttons: customCtrl.draft.resolvedButtons,
      selected: config,
      gridColumns: (config.gridColumnSpan + dx).clamp(
        minSize.$1,
        ButtonConfig.controlGridColumns,
      ),
      gridRows: (config.gridRowSpan + dy).clamp(
        minSize.$2,
        ButtonConfig.controlGridRows,
      ),
    );
    if (!result.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? kWidgetPlacementMessage)),
      );
      return;
    }
    customCtrl.applyDraftChange(
      customCtrl.draft.copyWith(buttons: result.buttons),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final int value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.remove_rounded),
          color: AppColors.darkTextSub,
          onPressed: onMinus,
        ),
        Expanded(
          child: Text(
            '$label: $value',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.darkText, fontSize: 12),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_rounded),
          color: AppColors.darkTextSub,
          onPressed: onPlus,
        ),
      ],
    );
  }
}

void _update(BuildContext context, ButtonConfig next) {
  final customCtrl = context.read<CustomizationModeController>();
  customCtrl.applyDraftChange(customCtrl.draft.withButton(next.id, next));
}

String _typeLabel(ButtonType type) => switch (type) {
  ButtonType.pushButton => 'Push',
  ButtonType.toggle => 'Toggle',
  ButtonType.sliderButton => 'Slider',
  ButtonType.crossTravel => 'Cross Travel',
  ButtonType.crossTravelSlowOnly => '3-Zone Slider',
  ButtonType.joystick => 'Joystick',
};

String _mappingLabel(PlcMapping mapping) => switch (mapping) {
  PlcMapping.up => 'Hoist Up',
  PlcMapping.down => 'Hoist Down',
  PlcMapping.fastUd => 'Hoist Fast',
  PlcMapping.left => 'Traverse Left',
  PlcMapping.right => 'Traverse Right',
  PlcMapping.fastLr => 'Traverse Fast',
  PlcMapping.forward => 'Travel Forward',
  PlcMapping.reverse => 'Travel Reverse',
  PlcMapping.fastFb => 'Travel Fast',
  PlcMapping.estop => 'E-Stop',
};
