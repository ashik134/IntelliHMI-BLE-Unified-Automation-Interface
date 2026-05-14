import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev6_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev6_crane_control_ops/models/control_layout_config.dart';
import 'package:rev6_crane_control_ops/utils/constants.dart';
import 'package:rev6_crane_control_ops/widgets/toggle_control_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ControlTypePage
// ─────────────────────────────────────────────────────────────────────────────

class ControlTypePage extends StatelessWidget {
  const ControlTypePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.connBg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.connText,
        elevation: 0,
        titleSpacing: 0,
        title: const Text(
          'Control Type',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.divider),
        ),
      ),
      body: const _ControlTypeBody(),
    );
  }
}

class _ControlTypeBody extends StatelessWidget {
  const _ControlTypeBody();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<LayoutSettingsController>();
    final isToggle = ctrl.config.widgetType == ControlWidgetType.toggle;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // ── Widget type selector
        _PageCard(
          title: 'WIDGET TYPE',
          icon: Icons.widgets_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _InfoBanner(
                message:
                    'Slider and Toggle controls are active. '
                    'Joystick and Press-and-Hold are reserved for a future release.',
              ),
              const SizedBox(height: 12),
              for (final entry in _widgetTypeEntries)
                _TypeOptionTile(entry: entry),
            ],
          ),
        ),

        // ── Toggle configuration (only shown when toggle is selected)
        if (isToggle) ...[
          _PageCard(
            title: 'TOGGLE WIRING CONFIGURATION',
            icon: Icons.cable_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _InfoBanner(
                  message:
                      'Select the switch schema that matches your operating '
                      'procedure. The wiring configuration controls whether '
                      'buttons are spring-return (hold) or latched (tap).',
                ),
                const SizedBox(height: 12),
                for (final cfg in ToggleWiringConfig.values)
                  _WiringConfigTile(config: cfg),
              ],
            ),
          ),
          const _PageCard(
            title: 'CONTROL BEHAVIOR REFERENCE',
            icon: Icons.info_outline_rounded,
            child: Column(
              children: [
                _BehaviorRefTile(
                  label: 'Spring Return  (T)',
                  description:
                      'Button activates while held; returns to OFF on release. '
                      'Safest option — stops automatically when operator releases.',
                  icon: Icons.touch_app_rounded,
                  color: AppColors.homeWarning,
                ),
                Divider(height: 20, color: AppColors.divider),
                _BehaviorRefTile(
                  label: 'Maintained  (R)',
                  description:
                      'Button latches ON after tap; stays active until tapped again. '
                      'Operator must explicitly cancel the command.',
                  icon: Icons.lock_outline_rounded,
                  color: AppColors.connPrimary,
                ),
                Divider(height: 20, color: AppColors.divider),
                _BehaviorRefTile(
                  label: 'Mutual Exclusion  (R-0-R)',
                  description:
                      'Only one direction can be active at a time. '
                      'Activating UP automatically cancels DOWN, and vice versa.',
                  icon: Icons.swap_vert_rounded,
                  color: AppColors.homeSuccess,
                ),
              ],
            ),
          ),
        ],

        // ── Live preview
        _PageCard(
          title: 'PREVIEW',
          icon: Icons.preview_rounded,
          child: _ControlTypePreview(
            widgetType: ctrl.config.widgetType,
            toggleConfig: ctrl.config.toggleConfig,
            upLabel: ctrl.config.labelConfig.upLabel,
            downLabel: ctrl.config.labelConfig.downLabel,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget type option definitions
// ─────────────────────────────────────────────────────────────────────────────

const _widgetTypeEntries = [
  _WidgetTypeEntry(
    type: ControlWidgetType.sliderButton,
    label: 'Slider Button',
    icon: Icons.linear_scale_rounded,
    available: true,
    description: 'Drag up for slow lift, drag further for fast. Full speed ramp.',
  ),
  _WidgetTypeEntry(
    type: ControlWidgetType.toggle,
    label: 'Toggle Control',
    icon: Icons.toggle_on_rounded,
    available: true,
    description: 'Configurable spring-return or latched buttons. Slow speed only.',
  ),
  _WidgetTypeEntry(
    type: ControlWidgetType.pressAndHold,
    label: 'Press and Hold',
    icon: Icons.touch_app_rounded,
    available: false,
    description: 'Hold to activate; release to stop. Coming soon.',
  ),
  _WidgetTypeEntry(
    type: ControlWidgetType.joystick,
    label: 'Joystick',
    icon: Icons.gamepad_rounded,
    available: false,
    description: 'Virtual joystick with directional input. Coming soon.',
  ),
];

class _WidgetTypeEntry {
  const _WidgetTypeEntry({
    required this.type,
    required this.label,
    required this.icon,
    required this.available,
    required this.description,
  });
  final ControlWidgetType type;
  final String label;
  final IconData icon;
  final bool available;
  final String description;
}

// ─────────────────────────────────────────────────────────────────────────────
// _TypeOptionTile
// ─────────────────────────────────────────────────────────────────────────────

class _TypeOptionTile extends StatelessWidget {
  const _TypeOptionTile({required this.entry});
  final _WidgetTypeEntry entry;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<LayoutSettingsController>();
    final isSelected = ctrl.config.widgetType == entry.type;
    final color = isSelected ? AppColors.connPrimary : AppColors.neutral;

    return Opacity(
      opacity: entry.available ? 1.0 : 0.45,
      child: Material(
        color: isSelected ? AppColors.connPrimary.withAlpha(18) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: entry.available
              ? () => ctrl.updateWidgetType(entry.type)
              : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? AppColors.connPrimary.withAlpha(80)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(entry.icon, color: color, size: 22),
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
                                  ? AppColors.connPrimary
                                  : AppColors.connText,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
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
                                color: AppColors.connWarning.withAlpha(30),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Coming Soon',
                                style: TextStyle(
                                  color: AppColors.connWarning,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        entry.description,
                        style: const TextStyle(
                          color: AppColors.connTextMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.connPrimary,
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
// _WiringConfigTile
// ─────────────────────────────────────────────────────────────────────────────

class _WiringConfigTile extends StatelessWidget {
  const _WiringConfigTile({required this.config});
  final ToggleWiringConfig config;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<LayoutSettingsController>();
    final isSelected = ctrl.config.toggleConfig.wiringConfig == config;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isSelected ? AppColors.connPrimary.withAlpha(18) : AppColors.connBg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => ctrl.updateToggleConfig(
            ctrl.config.toggleConfig.copyWith(wiringConfig: config),
          ),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? AppColors.connPrimary.withAlpha(80)
                    : AppColors.connBorder,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 1),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? AppColors.connPrimary
                          : AppColors.neutral,
                      width: isSelected ? 5 : 1.5,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        config.label,
                        style: TextStyle(
                          color: isSelected
                              ? AppColors.connPrimary
                              : AppColors.connText,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        config.description,
                        style: const TextStyle(
                          color: AppColors.connTextMuted,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _BehaviorChip(
                            label: 'UP: ${config.upIsSpringReturn ? "HOLD" : "TAP"}',
                            color: AppColors.upColor,
                          ),
                          const SizedBox(width: 6),
                          _BehaviorChip(
                            label: 'DOWN: ${config.downIsSpringReturn ? "HOLD" : "TAP"}',
                            color: AppColors.downColor,
                          ),
                          if (config.isMutuallyExclusive) ...[
                            const SizedBox(width: 6),
                            const _BehaviorChip(
                              label: 'EXCLUSIVE',
                              color: AppColors.homeSuccess,
                            ),
                          ],
                        ],
                      ),
                    ],
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

class _BehaviorChip extends StatelessWidget {
  const _BehaviorChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _BehaviorRefTile extends StatelessWidget {
  const _BehaviorRefTile({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });
  final String label;
  final String description;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(
                  color: AppColors.connTextMuted,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ControlTypePreview
// ─────────────────────────────────────────────────────────────────────────────

class _ControlTypePreview extends StatefulWidget {
  const _ControlTypePreview({
    required this.widgetType,
    required this.toggleConfig,
    required this.upLabel,
    required this.downLabel,
  });
  final ControlWidgetType widgetType;
  final ToggleControlConfig toggleConfig;
  final String upLabel;
  final String downLabel;

  @override
  State<_ControlTypePreview> createState() => _ControlTypePreviewState();
}

class _ControlTypePreviewState extends State<_ControlTypePreview> {
  final bool _upDemo = false;
  final bool _downDemo = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tap the buttons below to see how they will behave on the control screen.',
          style: TextStyle(
            color: AppColors.connTextMuted,
            fontSize: 11,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        // Dark device frame
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.darkBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Column(
            children: [
              // Mock E-Stop bar
              Container(
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.eStopColor.withAlpha(38),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.eStopColor.withAlpha(80)),
                ),
                child: const Center(
                  child: Text(
                    '▶▶  SWIPE TO EMERGENCY STOP',
                    style: TextStyle(
                      color: AppColors.eStopColorLight,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Hoist controls preview
              SizedBox(
                height: 140,
                child: widget.widgetType == ControlWidgetType.toggle
                    ? ToggleButtonPreview(
                        wiringConfig: widget.toggleConfig.wiringConfig,
                        upLabel: widget.upLabel,
                        downLabel: widget.downLabel,
                      )
                    : _SliderPreview(
                        upLabel: widget.upLabel,
                        downLabel: widget.downLabel,
                        upActive: _upDemo,
                        downActive: _downDemo,
                      ),
              ),
            ],
          ),
        ),
        if (widget.widgetType == ControlWidgetType.toggle) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.connWarning.withAlpha(15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.connWarning.withAlpha(50)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 13, color: AppColors.connWarning),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Toggle mode sends slow speed only. '
                    'Use Slider mode to access fast speed.',
                    style: TextStyle(
                      color: AppColors.connWarning,
                      fontSize: 10,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SliderPreview extends StatelessWidget {
  const _SliderPreview({
    required this.upLabel,
    required this.downLabel,
    required this.upActive,
    required this.downActive,
  });
  final String upLabel;
  final String downLabel;
  final bool upActive;
  final bool downActive;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _SliderMock(label: upLabel, isUp: true, isActive: upActive)),
        const SizedBox(width: 8),
        Expanded(child: _SliderMock(label: downLabel, isUp: false, isActive: downActive)),
      ],
    );
  }
}

class _SliderMock extends StatelessWidget {
  const _SliderMock({
    required this.label,
    required this.isUp,
    required this.isActive,
  });
  final String label;
  final bool isUp;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isUp ? AppColors.upColor : AppColors.downColor;
    final colorLight = isUp ? AppColors.upColorLight : AppColors.downColorLight;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panelAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isActive ? color : AppColors.darkBorder),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            color: colorLight,
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.darkText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 32,
            height: 3,
            decoration: BoxDecoration(
              color: color.withAlpha(80),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'SLIDE',
            style: TextStyle(
              color: AppColors.darkTextMuted,
              fontSize: 8,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared atoms (local to this file)
// ─────────────────────────────────────────────────────────────────────────────

class _PageCard extends StatelessWidget {
  const _PageCard({
    required this.title,
    required this.icon,
    required this.child,
  });
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.connBorder),
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
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              color: AppColors.connSurfaceAlt,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 15, color: AppColors.connTextMuted),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.connTextMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(16), child: child),
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
        color: AppColors.scanning.withAlpha(14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.scanningBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 14, color: AppColors.scanning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.connTextSub,
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
