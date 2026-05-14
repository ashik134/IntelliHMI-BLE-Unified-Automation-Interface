import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev6_crane_control_ops/controllers/layout_settings_controller.dart';
// import 'package:rev6_crane_control_ops/models/control_layout_config.dart';
import 'package:rev6_crane_control_ops/utils/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LayoutConfigurationPage
// ─────────────────────────────────────────────────────────────────────────────

class LayoutConfigurationPage extends StatelessWidget {
  const LayoutConfigurationPage({super.key});

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
          'Layout Configuration',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.divider),
        ),
      ),
      body: const _LayoutConfigurationBody(),
    );
  }
}

class _LayoutConfigurationBody extends StatelessWidget {
  const _LayoutConfigurationBody();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<LayoutSettingsController>();
    final cfg = ctrl.config.arrangementConfig;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // ── Toggles
        _PageCard(
          title: 'OPTIONAL ROWS',
          icon: Icons.view_list_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _InfoBanner(
                message:
                    'Show or hide optional rows on the control screen. '
                    'Hiding rows gives more screen space to the hoist buttons.',
              ),
              const SizedBox(height: 12),
              _ToggleTile(
                title: 'Sensor Row',
                subtitle:
                    'Displays load cell / proximity sensor readings at '
                    'the top of the control screen.',
                icon: Icons.sensors_rounded,
                value: cfg.showSensorRow,
                onChanged: (v) => ctrl.updateArrangementConfig(
                  cfg.copyWith(showSensorRow: v),
                ),
              ),
              const Divider(height: 20, color: AppColors.divider),
              _ToggleTile(
                title: 'Live LEDs',
                subtitle:
                    'Shows real-time I/O indicator LEDs for PLC input / '
                    'output states.',
                icon: Icons.circle_outlined,
                value: cfg.showLiveLEDs,
                onChanged: (v) => ctrl.updateArrangementConfig(
                  cfg.copyWith(showLiveLEDs: v),
                ),
              ),
            ],
          ),
        ),

        // ── Preview
        _PageCard(
          title: 'PREVIEW',
          icon: Icons.preview_rounded,
          child: _LayoutPreview(
            showSensorRow: cfg.showSensorRow,
            showLiveLEDs: cfg.showLiveLEDs,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ToggleTile
// ─────────────────────────────────────────────────────────────────────────────

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: value
                ? AppColors.connPrimary.withAlpha(18)
                : AppColors.connBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: value
                  ? AppColors.connPrimary.withAlpha(60)
                  : AppColors.connBorder,
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: value ? AppColors.connPrimary : AppColors.neutral,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: value ? AppColors.connText : AppColors.connTextMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.connTextMuted,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.connPrimary,
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.connPrimary.withAlpha(50)
                : AppColors.neutralBg,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LayoutPreview
// ─────────────────────────────────────────────────────────────────────────────

class _LayoutPreview extends StatelessWidget {
  const _LayoutPreview({
    required this.showSensorRow,
    required this.showLiveLEDs,
  });

  final bool showSensorRow;
  final bool showLiveLEDs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Schematic of the control screen layout with current settings.',
          style: TextStyle(
              color: AppColors.connTextMuted, fontSize: 11, height: 1.4),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.darkBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Screen title
              Center(
                child: Container(
                  height: 16,
                  width: 120,
                  decoration: BoxDecoration(
                    color: AppColors.darkText.withAlpha(18),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Center(
                    child: Text(
                      'CRANE CONTROL',
                      style: TextStyle(
                        color: AppColors.darkTextMuted,
                        fontSize: 7,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Sensor row (conditional)
              _AnimatedLayoutRow(
                visible: showSensorRow,
                label: 'SENSOR ROW',
                icon: Icons.sensors_rounded,
                color: AppColors.fastColor,
                height: 28,
              ),
              if (showSensorRow) const SizedBox(height: 6),

              // E-Stop
              const _LayoutRowBlock(
                label: 'E-STOP',
                color: AppColors.eStopColor,
                height: 28,
                icon: Icons.warning_amber_rounded,
                always: true,
              ),
              const SizedBox(height: 6),

              // Hoist buttons
              const Row(
                children: [
                  Expanded(
                    child: _LayoutRowBlock(
                      label: 'UP',
                      color: AppColors.upColor,
                      height: 56,
                      icon: Icons.arrow_upward_rounded,
                      always: true,
                    ),
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: _LayoutRowBlock(
                      label: 'DOWN',
                      color: AppColors.downColor,
                      height: 56,
                      icon: Icons.arrow_downward_rounded,
                      always: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // LEDs row (conditional)
              _AnimatedLayoutRow(
                visible: showLiveLEDs,
                label: 'LIVE LEDs',
                icon: Icons.circle_outlined,
                color: AppColors.idleColor,
                height: 24,
              ),

              // Legend
              const SizedBox(height: 10),
              const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _LegendDot(
                    color: AppColors.connPrimary,
                    label: 'Optional',
                  ),
                  SizedBox(width: 10),
                  _LegendDot(
                    color: AppColors.darkTextSub,
                    label: 'Always shown',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnimatedLayoutRow extends StatelessWidget {
  const _AnimatedLayoutRow({
    required this.visible,
    required this.label,
    required this.icon,
    required this.color,
    required this.height,
  });

  final bool visible;
  final String label;
  final IconData icon;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      firstChild: _LayoutRowBlock(
        label: label,
        color: AppColors.connPrimary,
        height: height,
        icon: icon,
        always: false,
      ),
      secondChild: const SizedBox(height: 0),
      crossFadeState:
          visible ? CrossFadeState.showFirst : CrossFadeState.showSecond,
      duration: const Duration(milliseconds: 250),
      sizeCurve: Curves.easeInOut,
    );
  }
}

class _LayoutRowBlock extends StatelessWidget {
  const _LayoutRowBlock({
    required this.label,
    required this.color,
    required this.height,
    required this.icon,
    required this.always,
  });

  final String label;
  final Color color;
  final double height;
  final IconData icon;
  final bool always;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 12, color: color.withAlpha(200)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          if (!always) ...[
            const SizedBox(width: 4),
            const Icon(Icons.circle, size: 5, color: AppColors.connPrimary),
          ],
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color.withAlpha(60),
            shape: BoxShape.circle,
            border: Border.all(color: color.withAlpha(120)),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
              color: AppColors.darkTextMuted, fontSize: 9),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared atoms
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
              offset: const Offset(0, 2)),
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
                  color: AppColors.connTextSub, fontSize: 11, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
