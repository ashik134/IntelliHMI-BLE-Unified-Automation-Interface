import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev6_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev6_crane_control_ops/screens/settings/control_customization_screen.dart';
import 'package:rev6_crane_control_ops/utils/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SettingsScreen
//
// Top-level settings list.  Uses the light industrial palette (ConnectionColors)
// to be visually consistent with the connection / authentication screens.
// ─────────────────────────────────────────────────────────────────────────────

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
          'Settings',
          style: TextStyle(
            fontSize: 17,
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
        children: [
          // ── Control Screen section ──────────────────────────────────────
          const _SectionHeader(label: 'CONTROL SCREEN'),
          _SettingsTile(
            icon: Icons.tune_rounded,
            iconColor: AppColors.connPrimary,
            title: 'Control Screen Customisation',
            subtitle:
                'Resize buttons, rename labels, configure layout sections',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ControlCustomizationScreen(),
              ),
            ),
          ),

          // ── App section ─────────────────────────────────────────────────
          const _SectionHeader(label: 'APPLICATION'),
          _SettingsTile(
            icon: Icons.info_outline_rounded,
            iconColor: AppColors.neutral,
            title: 'About',
            subtitle:
                '${AppConstants.appTitle}  ·  v${AppConstants.appVersion}',
            onTap: () => _showAboutDialog(context),
          ),
          _SettingsTile(
            icon: Icons.restore_rounded,
            iconColor: AppColors.connWarning,
            title: 'Reset All Settings',
            subtitle: 'Restore all customisations to factory defaults',
            onTap: () => _confirmReset(context),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset all settings?'),
        content: const Text(
          'This will restore all control screen customisations to their '
          'factory defaults.  This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
            ),
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

  void _showAboutDialog(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: AppConstants.appTitle,
      applicationVersion: AppConstants.appVersion,
      applicationLegalese:
          '© ${DateTime.now().year}  Industrial crane remote control system.',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private helpers
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 6),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.connTextMuted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.divider),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(22),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
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
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.connTextMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.connTextMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}