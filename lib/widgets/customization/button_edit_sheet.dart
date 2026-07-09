import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/customization_mode_controller.dart';
import 'package:rev_crane_control_ops/models/button_behavior_config.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/models/joystick_config.dart';
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
  const ButtonEditSheet.forRole({super.key, required this.role}) : axis = null;

  const ButtonEditSheet.forAxis({super.key, required this.axis}) : role = null;

  final ControlRole? role;
  final AxisKind? axis;

  AxisKind get resolvedAxis => axis ?? role!.axis!;

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

  @override
  State<ButtonEditSheet> createState() => _ButtonEditSheetState();
}

class _ButtonEditSheetState extends State<ButtonEditSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _title => widget.role != null
      ? _roleTitle(widget.role!)
      : '${widget.resolvedAxis.displayName} AXIS';

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
                  Tab(text: 'SIZE'),
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
                    _SizeTab(
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

/// ButtonType -> ControlWidgetType, purely for feeding the existing
/// AxisTypePreview widget's API (presentation-only — the model itself reads
/// and writes ButtonType directly, with no ControlWidgetType intermediary).
ControlWidgetType _previewWidgetType(ButtonType type) => switch (type) {
  ButtonType.pushButton => ControlWidgetType.pushButton,
  ButtonType.toggle => ControlWidgetType.toggle,
  ButtonType.sliderButton ||
  ButtonType.crossTravel ||
  ButtonType.crossTravelSlowOnly => ControlWidgetType.sliderButton,
  ButtonType.joystick => ControlWidgetType.joystick,
};

bool _spanAwareTypeChangesEnabled() => true;

// ─────────────────────────────────────────────────────────────────────────────
// TYPE tab
// ─────────────────────────────────────────────────────────────────────────────

class _TypeEntry {
  const _TypeEntry(this.type, this.label, this.icon, this.available, this.note);
  final ButtonType? type; // null => informational-only "coming soon" tile
  final String label;
  final IconData icon;
  final bool available;
  final String note;
}

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
    null,
    'Rotary Encoder',
    Icons.rotate_right_rounded,
    false,
    'Blocked — the PLC output protocol is boolean-only; no analog wire format exists yet.',
  ),
];

const _crossTravelEntry = _TypeEntry(
  ButtonType.crossTravel,
  'Cross Travel 5-Zone',
  Icons.compare_arrows_rounded,
  true,
  'Paired LEFT/RIGHT slider with slow and fast zones. Requires both '
      'directions to select this type — otherwise falls back to independent '
      'rendering.',
);

const _crossTravelSlowOnlyEntry = _TypeEntry(
  ButtonType.crossTravelSlowOnly,
  'Cross Travel 3-Zone',
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

    // Per-button edit (editRole != null): this button's own type. Axis-level
    // edit (traverse cross-travel pair, editRole == null): show "mixed" if
    // the two directions currently disagree, else the shared type.
    final primaryType = draft.buttonFor(primaryRole)!.type;
    final secondaryType = draft.buttonFor(secondaryRole)!.type;
    final previewType = editRole != null
        ? draft.buttonFor(editRole!)!.type
        : (primaryType == secondaryType ? primaryType : null);

    final entries = [
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
                    ? 'Applies to ${draft.buttonFor(editRole!)!.label} only.'
                    : 'Applies to both ${draft.buttonFor(primaryRole)!.label} and '
                          '${draft.buttonFor(secondaryRole)!.label} on '
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
                  isSelected: previewType != null && previewType == entry.type,
                  onTap: entry.available && entry.type != null
                      ? () {
                          final ctrl = context
                              .read<CustomizationModeController>();
                          if (_spanAwareTypeChangesEnabled()) {
                            var updated = ctrl.draft;
                            final rolesToUpdate =
                                editRole != null ||
                                    entry.type == ButtonType.crossTravel
                                ? [editRole ?? primaryRole]
                                : [primaryRole, secondaryRole];

                            for (final role in rolesToUpdate) {
                              final result = buildButtonTypeChange(
                                draft: updated,
                                role: role,
                                type: entry.type!,
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
            wiringConfig: draft.buttonFor(primaryRole)!.behavior.wiring,
            primaryLabel: draft.buttonFor(primaryRole)!.label,
            secondaryLabel: draft.buttonFor(secondaryRole)!.label,
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
// SIZE tab
// ─────────────────────────────────────────────────────────────────────────────

class _SizeTab extends StatefulWidget {
  const _SizeTab({
    required this.axis,
    required this.scrollController,
    this.editRole,
  });
  final AxisKind axis;
  final ControlRole? editRole;
  final ScrollController scrollController;

  @override
  State<_SizeTab> createState() => _SizeTabState();
}

class _SizeTabState extends State<_SizeTab> {
  double? _localHeightScale;
  double? _localWidthScale;

  List<ControlRole> get _roles => widget.editRole != null
      ? [widget.editRole!]
      : [widget.axis.primaryRole, widget.axis.secondaryRole];

  Widget _sizeCard(BuildContext context, ControlRole role) {
    final customCtrl = context.watch<CustomizationModeController>();
    final draft = customCtrl.draft;
    final config = draft.buttonFor(role)!;
    final heightScale = _localHeightScale ?? config.heightScale;
    final widthScale = _localWidthScale ?? config.widthScale;
    final resolvedPx = AxisControlConfig.baseHeight * heightScale;
    final belowMin = resolvedPx < AxisControlConfig.minTouchTargetPx;
    final slotIndex =
        config.slotIndex ?? ButtonConfig.defaultSlotIndexFor(role) ?? 0;
    final defaultSlotIndex = ButtonConfig.defaultSlotIndexFor(role) ?? 0;

    return _TabCard(
      title: '${role.defaultLabel} SIZE & POSITION',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${resolvedPx.toStringAsFixed(0)} px',
                style: TextStyle(
                  color: belowMin
                      ? AppColors.eStopColor
                      : AppColors.darkSuccess,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              Text(
                'HEIGHT ×${heightScale.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: AppColors.darkTextMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: belowMin
                  ? AppColors.eStopColor
                  : AppColors.accent,
              thumbColor: belowMin ? AppColors.eStopColor : AppColors.accent,
              inactiveTrackColor: AppColors.darkBorder,
            ),
            child: Slider(
              value: heightScale,
              min: ButtonConfig.minHeightScale,
              max: ButtonConfig.maxHeightScale,
              divisions: 16,
              onChanged: (v) => setState(() => _localHeightScale = v),
              onChangeEnd: (v) {
                setState(() => _localHeightScale = null);
                customCtrl.applyDraftChange(
                  draft.withButton(role.name, config.copyWith(heightScale: v)),
                );
              },
            ),
          ),
          if (belowMin)
            const _InfoNote(
              message:
                  'Below the 48px minimum industrial touch target. Increase '
                  'the scale before applying.',
              color: AppColors.eStopColor,
            ),
          const SizedBox(height: 10),
          Text(
            'WIDTH ×${widthScale.toStringAsFixed(2)}',
            style: const TextStyle(
              color: AppColors.darkTextMuted,
              fontSize: 11,
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.accent,
              thumbColor: AppColors.accent,
              inactiveTrackColor: AppColors.darkBorder,
            ),
            child: Slider(
              value: widthScale,
              min: ButtonConfig.minWidthScale,
              max: ButtonConfig.maxWidthScale,
              divisions: 16,
              onChanged: (v) => setState(() => _localWidthScale = v),
              onChangeEnd: (v) {
                setState(() => _localWidthScale = null);
                customCtrl.applyDraftChange(
                  draft.withButton(role.name, config.copyWith(widthScale: v)),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Grid slot: ${slotIndex + 1}',
                style: const TextStyle(
                  color: AppColors.darkTextMuted,
                  fontSize: 11,
                ),
              ),
              TextButton(
                onPressed: () => customCtrl.applyDraftChange(
                  draft.withButton(
                    role.name,
                    config.copyWith(slotIndex: defaultSlotIndex),
                  ),
                ),
                child: const Text('Reset slot'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(16),
      children: [for (final role in _roles) _sizeCard(context, role)],
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
    final wiringApplicable =
        config.type != ButtonType.sliderButton &&
        config.type != ButtonType.crossTravel &&
        config.type != ButtonType.crossTravelSlowOnly &&
        config.type != ButtonType.joystick;
    final isSafety = role.isSafetyControl;
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
        _TabCard(
          title: '${role.defaultLabel} · SWITCH WIRING',
          child: wiringApplicable
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final cfg in PushButtonWiringConfig.values)
                      // Three-position modes only make sense for Toggle Switch.
                      if (!cfg.isToggleOnly || config.type == ButtonType.toggle)
                        _WiringTile(
                          cfg: cfg,
                          isSelected: config.behavior.wiring == cfg,
                          onTap: () => customCtrl.applyDraftChange(
                            draft.withButton(
                              role.name,
                              config.copyWith(
                                behavior: config.behavior.copyWith(wiring: cfg),
                              ),
                            ),
                          ),
                        ),
                  ],
                )
              : const _InfoNote(
                  message:
                      'Not applicable — Slider/Cross Travel controls use '
                      'continuous drag speed, not switch wiring.',
                ),
        ),
        _TabCard(
          title: '${role.defaultLabel} · REPEAT WHILE HELD',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Repeat while held',
                    style: TextStyle(color: AppColors.darkText, fontSize: 12),
                  ),
                  Switch(
                    value: config.behavior.repeatWhileHeld,
                    activeThumbColor: AppColors.accent,
                    onChanged: (v) => customCtrl.applyDraftChange(
                      draft.withButton(
                        role.name,
                        config.copyWith(
                          behavior: config.behavior.copyWith(
                            repeatWhileHeld: v,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (config.behavior.repeatWhileHeld)
                _LabeledSlider(
                  label: 'Repeat interval (ms)',
                  value: config.behavior.repeatIntervalMs.toDouble(),
                  min: ButtonBehaviorConfig.minRepeatIntervalMs.toDouble(),
                  max: ButtonBehaviorConfig.maxRepeatIntervalMs.toDouble(),
                  onChanged: (_) {},
                  onChangeEnd: (v) => customCtrl.applyDraftChange(
                    draft.withButton(
                      role.name,
                      config.copyWith(
                        behavior: config.behavior.copyWith(
                          repeatIntervalMs: v.round(),
                        ),
                      ),
                    ),
                  ),
                )
              else
                const _InfoNote(
                  message:
                      'No current button type fires a repeat timer while '
                      'held — this setting is stored for future control '
                      'types (e.g. a jog-increment button).',
                ),
            ],
          ),
        ),
        if (!isSafety)
          _TabCard(
            title: '${role.defaultLabel} · MUTUAL EXCLUSION',
            child: _MutualExclusionEditor(role: role),
          ),
        _TabCard(
          title: '${role.defaultLabel} · PLC MAPPING',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Drives PlcOutputCommand.${config.plcMapping.name}'
                '${config.role != null ? ' — ${config.role!.name}' : ''}',
                style: const TextStyle(
                  color: AppColors.darkTextSub,
                  fontSize: 12,
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
        if (!isSafety)
          _TabCard(
            title: '${role.defaultLabel} · GROUP',
            child: _GroupField(role: role),
          ),
        if (config.type == ButtonType.joystick)
          _TabCard(
            title: '${role.defaultLabel} · JOYSTICK',
            child: _JoystickConfigEditor(role: role),
          ),
        if (config.type != ButtonType.joystick)
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

class _WiringTile extends StatelessWidget {
  const _WiringTile({
    required this.cfg,
    required this.isSelected,
    required this.onTap,
  });
  final PushButtonWiringConfig cfg;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isSelected ? AppColors.accent.withAlpha(24) : AppColors.darkBg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? AppColors.accent.withAlpha(100)
                    : AppColors.darkBorder,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cfg.label,
                  style: TextStyle(
                    color: isSelected ? AppColors.accent : AppColors.darkText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  cfg.description,
                  style: const TextStyle(
                    color: AppColors.darkTextMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
