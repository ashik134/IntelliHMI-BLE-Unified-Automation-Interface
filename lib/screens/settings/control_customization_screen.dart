import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';
// import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/screens/settings/pages/control_type_page.dart';
import 'package:rev_crane_control_ops/screens/settings/pages/button_sizing_page.dart';
import 'package:rev_crane_control_ops/screens/settings/pages/label_customization_page.dart';
import 'package:rev_crane_control_ops/screens/settings/pages/layout_configuration_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ControlCustomizationScreen
//
// Navigation menu with 4 tiles, each pushing to a dedicated sub-page:
//
//   1. Control Type         — widget type + toggle wiring configuration
//   2. Button Sizing        — scale sliders with live safety validation
//   3. Label Customisation  — text fields for all named UI strings
//   4. Layout Configuration — optional row visibility toggles
// ─────────────────────────────────────────────────────────────────────────────

class ControlCustomizationScreen extends StatelessWidget {
  const ControlCustomizationScreen({super.key});

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
          'Control Screen Customisation',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.connText,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.divider),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: const [
          _MenuCard(),
          SizedBox(height: 28),
          _AppSection(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MenuCard  — single card holding the 4 nav tiles
// ─────────────────────────────────────────────────────────────────────────────

class _MenuCard extends StatelessWidget {
  const _MenuCard();

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: const Column(
        children: [
          _NavTile(
            icon: Icons.widgets_outlined,
            title: 'Control Type',
            subtitle: 'Slider, toggle wiring and more',
            destination: ControlTypePage(),
            isFirst: true,
          ),
          Divider(height: 1, indent: 56, color: AppColors.divider),
          _NavTile(
            icon: Icons.open_in_full_rounded,
            title: 'Button Sizing',
            subtitle: 'Hoist and E-Stop button height scales',
            destination: ButtonSizingPage(),
          ),
          Divider(height: 1, indent: 56, color: AppColors.divider),
          _NavTile(
            icon: Icons.label_outline_rounded,
            title: 'Label Customisation',
            subtitle: 'Button, E-Stop and screen title text',
            destination: LabelCustomizationPage(),
          ),
          Divider(height: 1, indent: 56, color: AppColors.divider),
          _NavTile(
            icon: Icons.dashboard_customize_rounded,
            title: 'Layout Configuration',
            subtitle: 'Show or hide optional screen rows',
            destination: LayoutConfigurationPage(),
            isLast: true,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _NavTile
// ─────────────────────────────────────────────────────────────────────────────

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.destination,
    this.isFirst = false,
    this.isLast = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget destination;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.vertical(
      top: isFirst ? const Radius.circular(16) : Radius.zero,
      bottom: isLast ? const Radius.circular(16) : Radius.zero,
    );

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => destination),
        ),
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.connPrimary.withAlpha(18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: AppColors.connPrimary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.connText,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.connTextMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.neutral,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ActionTile  — tappable tile for in-place actions (no navigation chevron)
// ─────────────────────────────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor = AppColors.connPrimary,
    this.isFirst = false,
    this.isLast = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color iconColor;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.vertical(
      top: isFirst ? const Radius.circular(16) : Radius.zero,
      bottom: isLast ? const Radius.circular(16) : Radius.zero,
    );

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.connText,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.connTextMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AppSection  — About and Reset tiles, moved from SettingsScreen
// ─────────────────────────────────────────────────────────────────────────────

class _AppSection extends StatelessWidget {
  const _AppSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'APPLICATION',
            style: TextStyle(
              color: AppColors.connTextMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ),
        Container(
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
            children: [
              _ActionTile(
                icon: Icons.info_outline_rounded,
                title: 'About',
                subtitle:
                    '${AppConstants.appTitle}  ·  v${AppConstants.appVersion}',
                isFirst: true,
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: AppConstants.appTitle,
                  applicationVersion: AppConstants.appVersion,
                  applicationLegalese:
                      '© ${DateTime.now().year}  Industrial crane remote control system.',
                ),
              ),
              const Divider(height: 1, indent: 56, color: AppColors.divider),
              _ActionTile(
                icon: Icons.restore_rounded,
                iconColor: AppColors.connWarning,
                title: 'Reset All Settings',
                subtitle: 'Restore all customisations to factory defaults',
                isLast: true,
                onTap: () => _confirmReset(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset all settings?'),
        content: const Text(
          'This will restore all control screen customisations to their '
          'factory defaults. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<LayoutSettingsController>().resetToDefaults();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings reset to defaults.')),
        );
      }
    }
  }
}
