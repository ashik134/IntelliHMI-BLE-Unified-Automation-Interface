import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/customization_mode_controller.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/widgets/customization/axis_type_preview.dart';

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

  String get _title =>
      widget.role != null
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
                      scrollController: scrollController,
                    ),
                    _SizeTab(
                      axis: widget.resolvedAxis,
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
// Icon lookup — kept local to the UI layer so control_role.dart stays free
// of Flutter/Material imports.
// ─────────────────────────────────────────────────────────────────────────────

IconData _iconForRole(ControlRole role) => switch (role) {
  ControlRole.hoistUp => Icons.arrow_upward_rounded,
  ControlRole.hoistDown => Icons.arrow_downward_rounded,
  ControlRole.traverseLeft => Icons.arrow_back_rounded,
  ControlRole.traverseRight => Icons.arrow_forward_rounded,
  ControlRole.travelForward => Icons.north_rounded,
  ControlRole.travelReverse => Icons.south_rounded,
  ControlRole.estop => Icons.power_settings_new_rounded,
  ControlRole.resetEstop => Icons.restart_alt_rounded,
};

(Color, Color) _colorsForRole(ControlRole role) => switch (role) {
  ControlRole.hoistUp => (AppColors.upColor, AppColors.upColorLight),
  ControlRole.hoistDown => (AppColors.downColor, AppColors.downColorLight),
  ControlRole.traverseLeft ||
  ControlRole.traverseRight => (
    AppColors.traverseColor,
    AppColors.traverseColorLight,
  ),
  ControlRole.travelForward ||
  ControlRole.travelReverse => (AppColors.travelColor, AppColors.travelColorLight),
  ControlRole.estop => (AppColors.eStopColor, AppColors.eStopColorLight),
  ControlRole.resetEstop => (AppColors.eStopColor, AppColors.eStopColorLight),
};

String _labelForRole(ControlLabelConfig lc, ControlRole role) => switch (role) {
  ControlRole.hoistUp => lc.upLabel,
  ControlRole.hoistDown => lc.downLabel,
  ControlRole.traverseLeft => lc.leftLabel,
  ControlRole.traverseRight => lc.rightLabel,
  ControlRole.travelForward => lc.forwardLabel,
  ControlRole.travelReverse => lc.reverseLabel,
  ControlRole.estop => 'STOP',
  ControlRole.resetEstop => lc.resetEstopLabel,
};

ControlLabelConfig _withLabelForRole(
  ControlLabelConfig lc,
  ControlRole role,
  String value,
) => switch (role) {
  ControlRole.hoistUp => lc.copyWith(upLabel: value),
  ControlRole.hoistDown => lc.copyWith(downLabel: value),
  ControlRole.traverseLeft => lc.copyWith(leftLabel: value),
  ControlRole.traverseRight => lc.copyWith(rightLabel: value),
  ControlRole.travelForward => lc.copyWith(forwardLabel: value),
  ControlRole.travelReverse => lc.copyWith(reverseLabel: value),
  ControlRole.estop => lc,
  ControlRole.resetEstop => lc.copyWith(resetEstopLabel: value),
};

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
          child,
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
// TYPE tab
// ─────────────────────────────────────────────────────────────────────────────

class _TypeEntry {
  const _TypeEntry(this.type, this.label, this.icon, this.available, this.note);
  final ControlWidgetType type;
  final String label;
  final IconData icon;
  final bool available;
  final String note;
}

const _typeEntries = [
  _TypeEntry(
    ControlWidgetType.sliderButton,
    'Slider',
    Icons.linear_scale_rounded,
    true,
    'Drag for slow, drag further for fast.',
  ),
  _TypeEntry(
    ControlWidgetType.pushButton,
    'Push Button',
    Icons.touch_app_rounded,
    true,
    'Spring-return or latched, per Behavior tab.',
  ),
  _TypeEntry(
    ControlWidgetType.toggle,
    'Toggle Switch',
    Icons.toggle_on_rounded,
    true,
    'Rocker-style switch. Slow speed only.',
  ),
  _TypeEntry(
    ControlWidgetType.joystick,
    'Joystick',
    Icons.gamepad_rounded,
    false,
    'Blocked — the PLC output protocol is boolean-only; no analog wire format exists yet.',
  ),
  _TypeEntry(
    ControlWidgetType.rotary,
    'Rotary Encoder',
    Icons.rotate_right_rounded,
    false,
    'Blocked — the PLC output protocol is boolean-only; no analog wire format exists yet.',
  ),
];

class _TypeTab extends StatelessWidget {
  const _TypeTab({required this.axis, required this.scrollController});
  final AxisKind axis;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final customCtrl = context.watch<CustomizationModeController>();
    final draft = customCtrl.draft;
    final axisCfg = draft.axisConfigs.forAxis(axis);
    final labels = draft.labelConfig;
    final primaryRole = axis.primaryRole;
    final secondaryRole = axis.secondaryRole;
    final (primaryColor, primaryColorLight) = _colorsForRole(primaryRole);
    final (secondaryColor, secondaryColorLight) = _colorsForRole(secondaryRole);

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
                message:
                    'Applies to both ${_labelForRole(labels, primaryRole)} and '
                    '${_labelForRole(labels, secondaryRole)} on ${axis.displayName}.',
              ),
              const SizedBox(height: 10),
              for (final entry in _typeEntries)
                _TypeTile(
                  entry: entry,
                  isSelected: axisCfg.widgetType == entry.type,
                  onTap: entry.available
                      ? () => context.read<CustomizationModeController>().applyDraftChange(
                          draft.copyWith(
                            axisConfigs: draft.axisConfigs.withAxis(
                              axis,
                              axisCfg.copyWith(widgetType: entry.type),
                            ),
                          ),
                        )
                      : null,
                ),
            ],
          ),
        ),
        _TabCard(
          title: 'LIVE PREVIEW',
          child: AxisTypePreview(
            widgetType: axisCfg.widgetType,
            wiringConfig: axisCfg.wiringConfig,
            primaryLabel: _labelForRole(labels, primaryRole),
            secondaryLabel: _labelForRole(labels, secondaryRole),
            primaryIcon: _iconForRole(primaryRole),
            secondaryIcon: _iconForRole(secondaryRole),
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
  const _SizeTab({required this.axis, required this.scrollController});
  final AxisKind axis;
  final ScrollController scrollController;

  @override
  State<_SizeTab> createState() => _SizeTabState();
}

class _SizeTabState extends State<_SizeTab> {
  double? _localScale;

  @override
  Widget build(BuildContext context) {
    final customCtrl = context.watch<CustomizationModeController>();
    final draft = customCtrl.draft;
    final axisCfg = draft.axisConfigs.forAxis(widget.axis);
    final scale = _localScale ?? axisCfg.heightScale;
    final resolvedPx = AxisControlConfig.baseHeight * scale;
    final belowMin = resolvedPx < AxisControlConfig.minTouchTargetPx;

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        _TabCard(
          title: '${widget.axis.displayName} BUTTON HEIGHT',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${resolvedPx.toStringAsFixed(0)} px',
                    style: TextStyle(
                      color: belowMin ? AppColors.eStopColor : AppColors.darkSuccess,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    '×${scale.toStringAsFixed(2)}',
                    style: const TextStyle(color: AppColors.darkTextMuted, fontSize: 11),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: belowMin ? AppColors.eStopColor : AppColors.accent,
                  thumbColor: belowMin ? AppColors.eStopColor : AppColors.accent,
                  inactiveTrackColor: AppColors.darkBorder,
                ),
                child: Slider(
                  value: scale,
                  min: AxisControlConfig.minHeightScale,
                  max: AxisControlConfig.maxHeightScale,
                  divisions: 16,
                  onChanged: (v) => setState(() => _localScale = v),
                  onChangeEnd: (v) {
                    setState(() => _localScale = null);
                    context.read<CustomizationModeController>().applyDraftChange(
                      draft.copyWith(
                        axisConfigs: draft.axisConfigs.withAxis(
                          widget.axis,
                          axisCfg.copyWith(heightScale: v),
                        ),
                      ),
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
            ],
          ),
        ),
      ],
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
          _TabCard(title: _roleShortTitle(r), child: _LabelField(role: r)),
      ],
    );
  }

  static String _roleShortTitle(ControlRole role) =>
      '${role.defaultLabel} LABEL';
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
    _lastCommitted = _labelForRole(draft.labelConfig, widget.role);
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
    customCtrl.applyDraftChange(
      draft.copyWith(
        labelConfig: _withLabelForRole(draft.labelConfig, widget.role, value),
      ),
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
    final isToggle =
        draft.axisConfigs.forAxis(axis).widgetType == ControlWidgetType.toggle;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        if (!isToggle)
          const _InfoNote(
            message:
                'Corner radius, icon size, and label typography are only '
                'configurable for Toggle Switch controls today. Colors apply '
                'to every control type.',
          ),
        if (!isToggle) const SizedBox(height: 10),
        for (final r in roles)
          _TabCard(
            title: '${r.defaultLabel} APPEARANCE',
            child: _RoleStyleEditor(role: r, showFullControls: isToggle),
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

class _RoleStyleEditorState extends State<_RoleStyleEditor> {
  double? _localCornerRadius;
  double? _localIconSize;
  double? _localLabelFontSize;

  void _update(ButtonStyleConfig Function(ButtonStyleConfig) transform) {
    final customCtrl = context.read<CustomizationModeController>();
    final draft = customCtrl.draft;
    final current = draft.roleStyles.forRole(widget.role);
    customCtrl.applyDraftChange(
      draft.copyWith(
        roleStyles: draft.roleStyles.withRole(widget.role, transform(current)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = context.watch<CustomizationModeController>().draft;
    final style = draft.roleStyles.forRole(widget.role);
    final (defaultPrimary, defaultActive) = _colorsForRole(widget.role);

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
            Text(label, style: const TextStyle(color: AppColors.darkText, fontSize: 12)),
            Text(
              value.toStringAsFixed(0),
              style: const TextStyle(color: AppColors.darkTextMuted, fontSize: 11),
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
          _SwatchDot(color: c, isSelected: selected == c, onTap: () => onSelect(c)),
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
                  ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                  : null),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BEHAVIOR tab
// ─────────────────────────────────────────────────────────────────────────────

class _BehaviorTab extends StatelessWidget {
  const _BehaviorTab({required this.axis, required this.scrollController});
  final AxisKind axis;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final customCtrl = context.watch<CustomizationModeController>();
    final draft = customCtrl.draft;
    final axisCfg = draft.axisConfigs.forAxis(axis);
    final wiringApplicable = axisCfg.widgetType != ControlWidgetType.sliderButton;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        _TabCard(
          title: 'SWITCH WIRING',
          child: wiringApplicable
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final cfg in PushButtonWiringConfig.values)
                      _WiringTile(
                        cfg: cfg,
                        isSelected: axisCfg.wiringConfig == cfg,
                        onTap: () => customCtrl.applyDraftChange(
                          draft.copyWith(
                            axisConfigs: draft.axisConfigs.withAxis(
                              axis,
                              axisCfg.copyWith(wiringConfig: cfg),
                            ),
                          ),
                        ),
                      ),
                  ],
                )
              : const _InfoNote(
                  message:
                      'Not applicable — Slider controls use continuous drag '
                      'speed, not switch wiring.',
                ),
        ),
        const _TabCard(
          title: 'MUTUAL EXCLUSION',
          child: _InfoNote(
            message:
                'The two directions on an axis can never be active at the same '
                'time — this is enforced by the PLC command model and is not '
                'user-editable.',
            color: AppColors.darkSuccess,
          ),
        ),
        const _TabCard(
          title: 'REPEAT WHILE HELD',
          child: _InfoNote(
            message:
                'Intentionally not offered. Continuous motion outputs already '
                'drive continuously for as long as a spring-return button is '
                'held — a typematic repeat pattern doesn\'t apply and would be '
                'confusing on a motion control.',
          ),
        ),
      ],
    );
  }
}

class _WiringTile extends StatelessWidget {
  const _WiringTile({required this.cfg, required this.isSelected, required this.onTap});
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
                  style: const TextStyle(color: AppColors.darkTextMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
