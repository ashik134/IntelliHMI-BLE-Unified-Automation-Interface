import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rev6_crane_control_ops/controllers/hmi_layout_controller.dart';
import 'package:rev6_crane_control_ops/models/hmi_layout_models.dart';
import 'package:rev6_crane_control_ops/utils/constants.dart';

class HmiConfigurationScreen extends StatelessWidget {
  const HmiConfigurationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<HmiLayoutController>(
      builder: (context, controller, _) {
        if (controller.loading) {
          return Scaffold(
            appBar: AppBar(title: const Text('HMI Configuration')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final profile = controller.activeProfile;
        if (profile == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('HMI Configuration')),
            body: const Center(
              child: Text(
                'No configuration profiles available.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('HMI Configuration'),
            actions: [
              IconButton(
                tooltip: controller.editMode
                    ? 'Exit drag/resize mode'
                    : 'Enable drag/resize mode',
                onPressed: () => controller.setEditMode(!controller.editMode),
                icon: Icon(
                  controller.editMode
                      ? Icons.edit_location_alt_rounded
                      : Icons.edit_location_alt_outlined,
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 980;
                if (!wide) {
                  return Column(
                    children: [
                      _ProfileToolbar(profile: profile),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          children: const [
                            _WidgetPalette(),
                            SizedBox(height: 10),
                            _LayoutValidationCard(),
                            SizedBox(height: 10),
                            _WidgetListCard(),
                            SizedBox(height: 10),
                            _WidgetEditorCard(),
                          ],
                        ),
                      ),
                    ],
                  );
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Column(
                    children: [
                      _ProfileToolbar(profile: profile),
                      const SizedBox(height: 10),
                      const _WidgetPalette(),
                      const SizedBox(height: 10),
                      const _LayoutValidationCard(),
                      const SizedBox(height: 10),
                      const Expanded(
                        child: Row(
                          children: [
                            Expanded(flex: 4, child: _WidgetListCard()),
                            SizedBox(width: 10),
                            Expanded(flex: 5, child: _WidgetEditorCard()),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _ProfileToolbar extends StatelessWidget {
  const _ProfileToolbar({required this.profile});

  final HmiLayoutProfile profile;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HmiLayoutController>();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: controller.activeProfileId,
                  decoration: _compactDecoration('Layout Profile'),
                  dropdownColor: AppColors.panelAlt,
                  items: [
                    for (final item in controller.profiles)
                      DropdownMenuItem(
                        value: item.id,
                        child: Text(
                          item.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      controller.setActiveProfile(value);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Duplicate profile',
                onPressed: controller.createProfileFromActive,
                icon: const Icon(Icons.copy_all_rounded, size: 20),
              ),
              IconButton(
                tooltip: 'Delete profile',
                onPressed: controller.profiles.length <= 1
                    ? null
                    : () => controller.deleteProfile(profile.id),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: profile.name,
                  decoration: _compactDecoration('Profile Name'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                  ),
                  onFieldSubmitted: controller.renameActiveProfile,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  initialValue: profile.template,
                  decoration: _compactDecoration('Template'),
                  dropdownColor: AppColors.panelAlt,
                  items: const [
                    DropdownMenuItem(value: 'free', child: Text('Free')),
                    DropdownMenuItem(value: 'compact', child: Text('Compact')),
                    DropdownMenuItem(value: 'split', child: Text('Split')),
                    DropdownMenuItem(
                      value: 'monitoring',
                      child: Text('Monitoring'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      controller.setTemplate(value);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Device: ${profile.deviceType}   Updated: ${profile.updatedAt.toLocal()}',
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _compactDecoration(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      labelStyle: const TextStyle(fontSize: 11),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }
}

class _WidgetPalette extends StatelessWidget {
  const _WidgetPalette();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HmiLayoutController>();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final type in HmiWidgetType.values)
            OutlinedButton.icon(
              onPressed: () => controller.addWidget(type),
              icon: const Icon(Icons.add_circle_outline_rounded, size: 15),
              label: Text(
                type.displayName,
                style: const TextStyle(fontSize: 11),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: BorderSide(
                  color: AppColors.border.withValues(alpha: 0.9),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LayoutValidationCard extends StatelessWidget {
  const _LayoutValidationCard();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HmiLayoutController>();
    final issues = controller.layoutIssues;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Layout Validation',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          if (issues.isEmpty)
            const Text(
              'No overlap or boundary issues found.',
              style: TextStyle(fontSize: 11, color: AppColors.upColorLight),
            )
          else
            for (final issue in issues.take(8))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 14,
                      color: AppColors.fastColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        issue.message,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _WidgetListCard extends StatelessWidget {
  const _WidgetListCard();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HmiLayoutController>();
    final profile = controller.activeProfile;
    if (profile == null) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Row(
              children: [
                Text(
                  'Widgets',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: ListView.separated(
              itemCount: profile.widgets.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: AppColors.border),
              itemBuilder: (context, index) {
                final widget = profile.widgets[index];
                final selected = widget.id == controller.selectedWidgetId;
                return ListTile(
                  dense: true,
                  selected: selected,
                  selectedTileColor: widget.color.withValues(alpha: 0.13),
                  leading: Icon(
                    widget.visible
                        ? Icons.widgets_rounded
                        : Icons.visibility_off_rounded,
                    size: 18,
                    color: widget.visible
                        ? widget.color
                        : AppColors.textSecondary,
                  ),
                  title: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    '${widget.type.displayName} | ${widget.binding.primaryTag}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(
                      Icons.remove_circle_outline_rounded,
                      size: 18,
                    ),
                    onPressed: () => controller.removeWidget(widget.id),
                  ),
                  onTap: () => controller.selectWidget(widget.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WidgetEditorCard extends StatelessWidget {
  const _WidgetEditorCard();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HmiLayoutController>();
    final widget = controller.selectedWidget;
    if (widget == null) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(
          child: Text(
            'Select a widget to edit properties.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
      );
    }

    final behavior = widget.behavior;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: ListView(
        padding: const EdgeInsets.all(10),
        children: [
          Text(
            widget.label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey('label-${widget.id}'),
            initialValue: widget.label,
            decoration: _inputDecoration('Label'),
            style: const TextStyle(fontSize: 12),
            onFieldSubmitted: (value) {
              controller.updateWidgetLabel(widget.id, value);
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<HmiWidgetType>(
            initialValue: widget.type,
            decoration: _inputDecoration('Control Type'),
            dropdownColor: AppColors.panelAlt,
            items: [
              for (final type in HmiWidgetType.values)
                DropdownMenuItem(
                  value: type,
                  child: Text(
                    type.displayName,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                controller.updateWidgetType(widget.id, value);
              }
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('primary-${widget.id}'),
                  initialValue: widget.binding.primaryTag,
                  decoration: _inputDecoration('Primary PLC Tag'),
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  onFieldSubmitted: (value) {
                    controller.updateWidgetBinding(
                      widget.id,
                      primaryTag: value,
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  key: ValueKey('secondary-${widget.id}'),
                  initialValue: widget.binding.secondaryTag ?? '',
                  decoration: _inputDecoration('Secondary Tag'),
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  onFieldSubmitted: (value) {
                    controller.updateWidgetBinding(
                      widget.id,
                      secondaryTag: value,
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('tertiary-${widget.id}'),
                  initialValue: widget.binding.tertiaryTag ?? '',
                  decoration: _inputDecoration('Tertiary Tag'),
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  onFieldSubmitted: (value) {
                    controller.updateWidgetBinding(
                      widget.id,
                      tertiaryTag: value,
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  key: ValueKey('quaternary-${widget.id}'),
                  initialValue: widget.binding.quaternaryTag ?? '',
                  decoration: _inputDecoration('Quaternary Tag'),
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  onFieldSubmitted: (value) {
                    controller.updateWidgetBinding(
                      widget.id,
                      quaternaryTag: value,
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<ControlHoldMode>(
            initialValue: behavior.holdMode,
            decoration: _inputDecoration('Hold Mode'),
            dropdownColor: AppColors.panelAlt,
            items: [
              for (final mode in ControlHoldMode.values)
                DropdownMenuItem(
                  value: mode,
                  child: Text(
                    mode.displayName,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                controller.updateWidgetHoldMode(widget.id, value);
              }
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<TogglePattern>(
            initialValue: behavior.togglePattern,
            decoration: _inputDecoration('Toggle Pattern'),
            dropdownColor: AppColors.panelAlt,
            items: [
              for (final pattern in TogglePattern.values)
                DropdownMenuItem(
                  value: pattern,
                  child: Text(
                    pattern.key,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                controller.updateWidgetTogglePattern(widget.id, value);
              }
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('min-${widget.id}'),
                  initialValue: behavior.minValue.toStringAsFixed(0),
                  decoration: _inputDecoration('Min Value'),
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                  ),
                  style: const TextStyle(fontSize: 12),
                  onFieldSubmitted: (value) {
                    final parsed = double.tryParse(value);
                    if (parsed == null) return;
                    controller.updateWidgetBehavior(
                      widget.id,
                      behavior.copyWith(minValue: parsed),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  key: ValueKey('max-${widget.id}'),
                  initialValue: behavior.maxValue.toStringAsFixed(0),
                  decoration: _inputDecoration('Max Value'),
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                  ),
                  style: const TextStyle(fontSize: 12),
                  onFieldSubmitted: (value) {
                    final parsed = double.tryParse(value);
                    if (parsed == null) return;
                    controller.updateWidgetBehavior(
                      widget.id,
                      behavior.copyWith(maxValue: parsed),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  key: ValueKey('unit-${widget.id}'),
                  initialValue: behavior.unit,
                  decoration: _inputDecoration('Unit'),
                  style: const TextStyle(fontSize: 12),
                  onFieldSubmitted: (value) {
                    controller.updateWidgetBehavior(
                      widget.id,
                      behavior.copyWith(unit: value.trim()),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _switchTile(
                  label: 'Enabled',
                  value: widget.enabled,
                  onChanged: (value) =>
                      controller.updateWidgetEnabled(widget.id, value),
                ),
              ),
              Expanded(
                child: _switchTile(
                  label: 'Visible',
                  value: widget.visible,
                  onChanged: (value) =>
                      controller.updateWidgetVisibility(widget.id, value),
                ),
              ),
              Expanded(
                child: _switchTile(
                  label: 'Trend',
                  value: behavior.trendEnabled,
                  onChanged: (value) => controller.updateWidgetBehavior(
                    widget.id,
                    behavior.copyWith(trendEnabled: value),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ColorSwatchRow(widgetId: widget.id, selectedColor: widget.color),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 11),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Widget _switchTile({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: AppColors.panelAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

class _ColorSwatchRow extends StatelessWidget {
  const _ColorSwatchRow({required this.widgetId, required this.selectedColor});

  final String widgetId;
  final Color selectedColor;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HmiLayoutController>();
    const palette = [
      AppColors.upColor,
      AppColors.downColor,
      AppColors.fastColor,
      AppColors.eStopColor,
      AppColors.info,
      AppColors.accent,
    ];
    return Row(
      children: [
        const Text(
          'Color',
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(width: 10),
        for (final color in palette)
          GestureDetector(
            onTap: () => controller.updateWidgetColor(widgetId, color),
            child: Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: selectedColor == color
                      ? Colors.white
                      : AppColors.border,
                  width: selectedColor == color ? 2 : 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
