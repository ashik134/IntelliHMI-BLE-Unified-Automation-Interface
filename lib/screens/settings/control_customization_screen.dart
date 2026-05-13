import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev6_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev6_crane_control_ops/models/control_layout_config.dart';
import 'package:rev6_crane_control_ops/services/layout_validation_service.dart';
import 'package:rev6_crane_control_ops/utils/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ControlCustomizationScreen
//
// Four collapsible sections let the operator personalise the control screen:
//
//   1. Control Type        (placeholder — future feature, non-functional)
//   2. Button Sizing       (scale sliders with live safety validation)
//   3. Label Customisation (text fields for all named UI strings)
//   4. Layout Configuration(section visibility toggles)
//
// All mutations go through [LayoutSettingsController] which validates each
// change against [LayoutValidationService] before persisting.
// ─────────────────────────────────────────────────────────────────────────────

class ControlCustomizationScreen extends StatelessWidget {
  const ControlCustomizationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ConnectionColors.background,
      appBar: AppBar(
        backgroundColor: ConnectionColors.surface,
        foregroundColor: ConnectionColors.textPrimary,
        elevation: 0,
        titleSpacing: 0,
        title: const Text(
          'Control Screen Customisation',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: ConnectionColors.textPrimary,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: ConnectionColors.divider),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: const [
          _ControlTypeSection(),
          _SizingSection(),
          _LabelSection(),
          _LayoutSection(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section 1 — Control Type (placeholder)
// ─────────────────────────────────────────────────────────────────────────────

class _ControlTypeSection extends StatelessWidget {
  const _ControlTypeSection();

  static const _types = [
    (
      type: ControlWidgetType.sliderButton,
      label: 'Slider Button',
      icon: Icons.linear_scale_rounded,
      available: true,
      description: 'Slide up/down to ramp between slow and fast speed.',
    ),
    (
      type: ControlWidgetType.pressAndHold,
      label: 'Press and Hold',
      icon: Icons.touch_app_rounded,
      available: false,
      description: 'Hold to activate; release to stop. Coming soon.',
    ),
    (
      type: ControlWidgetType.toggle,
      label: 'Toggle',
      icon: Icons.toggle_on_rounded,
      available: false,
      description: 'Tap once to start; tap again to stop. Coming soon.',
    ),
    (
      type: ControlWidgetType.joystick,
      label: 'Joystick',
      icon: Icons.gamepad_rounded,
      available: false,
      description:
          'Virtual joystick with directional analogue input. Coming soon.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final layoutCtrl = context.watch<LayoutSettingsController>();
    final current = layoutCtrl.config.widgetType;

    return _SectionCard(
      title: 'CONTROL TYPE',
      icon: Icons.widgets_outlined,
      badge: 'Future Feature',
      badgeColor: ConnectionColors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _InfoBanner(
            message:
                'Control type switching is reserved for a future release. '
                'Only "Slider Button" is currently active. '
                'Your selection will be applied automatically when the feature ships.',
          ),
          const SizedBox(height: 12),
          for (final entry in _types)
            _ControlTypeOption(
              type: entry.type,
              label: entry.label,
              icon: entry.icon,
              description: entry.description,
              isAvailable: entry.available,
              isSelected: current == entry.type,
              onTap: entry.available
                  ? () => layoutCtrl.updateWidgetType(entry.type)
                  : null,
            ),
        ],
      ),
    );
  }
}

class _ControlTypeOption extends StatelessWidget {
  const _ControlTypeOption({
    required this.type,
    required this.label,
    required this.icon,
    required this.description,
    required this.isAvailable,
    required this.isSelected,
    required this.onTap,
  });

  final ControlWidgetType type;
  final String label;
  final IconData icon;
  final String description;
  final bool isAvailable;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected
        ? ConnectionColors.primary
        : ConnectionColors.neutral;
    final bgColor = isSelected
        ? ConnectionColors.primary.withAlpha(18)
        : Colors.transparent;

    return Opacity(
      opacity: isAvailable ? 1.0 : 0.45,
      child: Material(
        color: bgColor,
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
                    ? ConnectionColors.primary.withAlpha(80)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              color: isSelected
                                  ? ConnectionColors.primary
                                  : ConnectionColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (!isAvailable) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: ConnectionColors.warning.withAlpha(30),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Coming Soon',
                                style: TextStyle(
                                  color: ConnectionColors.warning,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        description,
                        style: const TextStyle(
                          color: ConnectionColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: ConnectionColors.primary,
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section 2 — Button Sizing
// ─────────────────────────────────────────────────────────────────────────────

class _SizingSection extends StatefulWidget {
  const _SizingSection();

  @override
  State<_SizingSection> createState() => _SizingSectionState();
}

class _SizingSectionState extends State<_SizingSection> {
  late double _hoistScale;
  late double _estopScale;
  String? _errorMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final config =
        context.read<LayoutSettingsController>().config.sizeConfig;
    _hoistScale = config.hoistButtonHeightScale;
    _estopScale = config.estopButtonHeightScale;
  }

  void _apply(BuildContext context) {
    final proposed = ControlWidgetSizeConfig(
      hoistButtonHeightScale: _hoistScale,
      estopButtonHeightScale: _estopScale,
    );
    final result =
        context.read<LayoutSettingsController>().updateSizeConfig(proposed);
    setState(() {
      _errorMessage = result.isValid ? null : result.errors.join('\n');
    });
    if (result.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Button sizes saved.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep sliders in sync if config changed externally (e.g. reset).
    final savedConfig =
        context.watch<LayoutSettingsController>().config.sizeConfig;

    return _SectionCard(
      title: 'BUTTON SIZING',
      icon: Icons.open_in_full_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _InfoBanner(
            message:
                'Scale factors are validated against minimum touch target '
                'requirements (≥ 48 px) before being applied.',
          ),
          const SizedBox(height: 16),
          _ScaleSlider(
            label: 'Hoist Buttons Height',
            description: 'UP / DOWN control button height',
            value: _hoistScale,
            savedValue: savedConfig.hoistButtonHeightScale,
            resolvedPx: ControlWidgetSizeConfig.baseHoistButtonHeight *
                _hoistScale,
            onChanged: (v) => setState(() => _hoistScale = v),
          ),
          const SizedBox(height: 16),
          _ScaleSlider(
            label: 'E-Stop Button Height',
            description: 'Emergency stop swipe button height',
            value: _estopScale,
            savedValue: savedConfig.estopButtonHeightScale,
            resolvedPx:
                ControlWidgetSizeConfig.baseEstopButtonHeight * _estopScale,
            onChanged: (v) => setState(() => _estopScale = v),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            _ErrorBanner(message: _errorMessage!),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton.icon(
              onPressed: () => _apply(context),
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Apply Sizes'),
              style: FilledButton.styleFrom(
                backgroundColor: ConnectionColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScaleSlider extends StatelessWidget {
  const _ScaleSlider({
    required this.label,
    required this.description,
    required this.value,
    required this.savedValue,
    required this.resolvedPx,
    required this.onChanged,
  });

  final String label;
  final String description;
  final double value;
  final double savedValue;
  final double resolvedPx;
  final ValueChanged<double> onChanged;

  bool get _isSaved => (value - savedValue).abs() < 0.005;
  bool get _belowMinTarget =>
      resolvedPx < ControlWidgetSizeConfig.minTouchTargetPx;

  @override
  Widget build(BuildContext context) {
    final indicatorColor = _belowMinTarget
        ? ConnectionColors.error
        : ConnectionColors.connected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: ConnectionColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!_isSaved) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: ConnectionColors.warning.withAlpha(30),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Unsaved',
                            style: TextStyle(
                              color: ConnectionColors.warning,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    description,
                    style: const TextStyle(
                      color: ConnectionColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            // Resolved-pixel readout
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${resolvedPx.toStringAsFixed(0)} px',
                  style: TextStyle(
                    color: indicatorColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  'scale  ×${value.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: ConnectionColors.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: _belowMinTarget
                ? ConnectionColors.error
                : ConnectionColors.primary,
            thumbColor: _belowMinTarget
                ? ConnectionColors.error
                : ConnectionColors.primary,
            inactiveTrackColor: ConnectionColors.neutralBg,
          ),
          child: Slider(
            value: value,
            min: ControlWidgetSizeConfig.minHeightScale,
            max: ControlWidgetSizeConfig.maxHeightScale,
            divisions: 16,
            onChanged: onChanged,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '×${ControlWidgetSizeConfig.minHeightScale.toStringAsFixed(1)}  (min)',
              style: const TextStyle(
                color: ConnectionColors.textMuted,
                fontSize: 9,
              ),
            ),
            Text(
              '×${ControlWidgetSizeConfig.maxHeightScale.toStringAsFixed(1)}  (max)',
              style: const TextStyle(
                color: ConnectionColors.textMuted,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section 3 — Label Customisation
// ─────────────────────────────────────────────────────────────────────────────

class _LabelSection extends StatefulWidget {
  const _LabelSection();

  @override
  State<_LabelSection> createState() => _LabelSectionState();
}

class _LabelSectionState extends State<_LabelSection> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _upCtrl;
  late final TextEditingController _downCtrl;
  late final TextEditingController _estopCtrl;
  late final TextEditingController _resetCtrl;
  late final TextEditingController _titleCtrl;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _upCtrl = TextEditingController();
    _downCtrl = TextEditingController();
    _estopCtrl = TextEditingController();
    _resetCtrl = TextEditingController();
    _titleCtrl = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final labels =
        context.read<LayoutSettingsController>().config.labelConfig;
    _upCtrl.text = labels.upLabel;
    _downCtrl.text = labels.downLabel;
    _estopCtrl.text = labels.estopSwipeInstruction;
    _resetCtrl.text = labels.resetEstopLabel;
    _titleCtrl.text = labels.screenTitle;
  }

  @override
  void dispose() {
    _upCtrl.dispose();
    _downCtrl.dispose();
    _estopCtrl.dispose();
    _resetCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  void _apply(BuildContext context) {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final proposed = ControlLabelConfig(
      upLabel: _upCtrl.text.trim(),
      downLabel: _downCtrl.text.trim(),
      estopSwipeInstruction: _estopCtrl.text.trim(),
      resetEstopLabel: _resetCtrl.text.trim(),
      screenTitle: _titleCtrl.text.trim(),
    );
    final result =
        context.read<LayoutSettingsController>().updateLabelConfig(proposed);
    setState(() {
      _errorMessage = result.isValid ? null : result.errors.join('\n');
    });
    if (result.isValid && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Labels saved.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  String? _validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) return 'Required';
    if (value.trim().length > ControlLabelConfig.maxLabelLength) {
      return 'Max ${ControlLabelConfig.maxLabelLength} chars';
    }
    return null;
  }

  String? _validateOptional(String? value) {
    if (value == null || value.trim().isEmpty) return null; // optional
    if (value.trim().length > ControlLabelConfig.maxLabelLength) {
      return 'Max ${ControlLabelConfig.maxLabelLength} chars';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'LABEL CUSTOMISATION',
      icon: Icons.label_outline_rounded,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _InfoBanner(
              message:
                  'Rename any control label to suit your site terminology. '
                  'Maximum ${ControlLabelConfig.maxLabelLength} characters per label.',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _LabelField(
                    controller: _upCtrl,
                    label: 'UP Button',
                    hint: 'e.g.  HOIST UP',
                    validator: _validateRequired,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _LabelField(
                    controller: _downCtrl,
                    label: 'DOWN Button',
                    hint: 'e.g.  LOWER',
                    validator: _validateRequired,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _LabelField(
              controller: _estopCtrl,
              label: 'E-Stop Instruction',
              hint: 'e.g.  SWIPE TO EMERGENCY STOP',
              validator: _validateRequired,
            ),
            const SizedBox(height: 12),
            _LabelField(
              controller: _resetCtrl,
              label: 'Reset E-Stop',
              hint: 'e.g.  RESET E-STOP',
              validator: _validateRequired,
            ),
            const SizedBox(height: 12),
            _LabelField(
              controller: _titleCtrl,
              label: 'Screen Title (optional)',
              hint: 'Leave empty to show device name',
              validator: _validateOptional,
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _ErrorBanner(message: _errorMessage!),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton.icon(
                onPressed: () => _apply(context),
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text('Apply Labels'),
                style: FilledButton.styleFrom(
                  backgroundColor: ConnectionColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabelField extends StatelessWidget {
  const _LabelField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      textCapitalization: TextCapitalization.characters,
      style: const TextStyle(
        color: ConnectionColors.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(
          color: ConnectionColors.textMuted,
          fontSize: 12,
        ),
        hintStyle: const TextStyle(
          color: ConnectionColors.neutral,
          fontSize: 12,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        filled: true,
        fillColor: ConnectionColors.surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: ConnectionColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: ConnectionColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: ConnectionColors.primary,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: ConnectionColors.error),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section 4 — Layout Configuration
// ─────────────────────────────────────────────────────────────────────────────

class _LayoutSection extends StatelessWidget {
  const _LayoutSection();

  @override
  Widget build(BuildContext context) {
    final layoutCtrl = context.watch<LayoutSettingsController>();
    final arrangement = layoutCtrl.config.arrangementConfig;

    return _SectionCard(
      title: 'LAYOUT CONFIGURATION',
      icon: Icons.dashboard_customize_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _InfoBanner(
            message:
                'Toggle optional diagnostic sections on or off. '
                'Safety-critical controls (E-Stop, hoist buttons) are always visible.',
          ),
          const SizedBox(height: 8),
          _ToggleTile(
            icon: Icons.sensors_rounded,
            title: 'Sensor Row',
            subtitle: 'A1 / A2 load sensor readouts',
            value: arrangement.showSensorRow,
            onChanged: (v) => layoutCtrl.updateArrangementConfig(
              arrangement.copyWith(showSensorRow: v),
            ),
          ),
          _ToggleTile(
            icon: Icons.developer_board_rounded,
            title: 'Live PLC Output LEDs',
            subtitle: 'Digital output state indicators (ESTOP, UP, DOWN, FAST)',
            value: arrangement.showLiveLEDs,
            onChanged: (v) => layoutCtrl.updateArrangementConfig(
              arrangement.copyWith(showLiveLEDs: v),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: ConnectionColors.neutral, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: ConnectionColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: ConnectionColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,

            activeThumbColor: ConnectionColors.primary,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared UI atoms
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.badge,
    this.badgeColor,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final String? badge;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      decoration: BoxDecoration(
        color: ConnectionColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ConnectionColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              color: ConnectionColors.surfaceAlt,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              border: Border(
                bottom: BorderSide(color: ConnectionColors.divider),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: ConnectionColors.textMuted),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: ConnectionColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: (badgeColor ?? ConnectionColors.primary)
                          .withAlpha(25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        color: badgeColor ?? ConnectionColors.primary,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ConnectionColors.scanning.withAlpha(14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ConnectionColors.scanningBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 14,
            color: ConnectionColors.scanning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: ConnectionColors.textSecondary,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ConnectionColors.error.withAlpha(14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ConnectionColors.errorBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 14,
            color: ConnectionColors.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: ConnectionColors.error,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
