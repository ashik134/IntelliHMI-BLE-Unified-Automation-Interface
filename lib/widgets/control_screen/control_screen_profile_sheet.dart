import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';

/// Opens the "Configure Screen" bottom sheet: lets the operator switch this
/// (operator, PLC) pair between Standard Control and Safety Control.
/// Reachable from the Standard Control Screens' AppBar and "More" menu, and
/// from the Safety Control Screen's own AppBar — one shared sheet, no
/// duplicated selection logic.
Future<void> showControlScreenProfileSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ControlScreenProfileSheet(),
  );
}

class _ControlScreenProfileSheet extends StatelessWidget {
  const _ControlScreenProfileSheet();

  static const Map<ControlScreenProfile, (IconData, String)> _options = {
    ControlScreenProfile.standard: (
      Icons.dashboard_customize_rounded,
      'Full dynamic control grid with all of this PLC\'s configured widgets.',
    ),
    ControlScreenProfile.safetyOnly: (
      Icons.power_settings_new_rounded,
      'Circular Emergency Stop only — no control grid.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final current = context.watch<CraneController>().controlScreenProfile;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.darkBorder),
            boxShadow: AppMetrics.shadowMd,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.panelStroke,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Configure Screen',
                  style: TextStyle(
                    color: AppColors.darkText,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Switch between Standard Control and Safety Control for '
                  'this operator and PLC.',
                  style: TextStyle(
                    color: AppColors.darkTextMuted,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 14),
                for (final profile in ControlScreenProfile.values)
                  _ProfileRow(
                    profile: profile,
                    icon: _options[profile]!.$1,
                    subtitle: _options[profile]!.$2,
                    selected: profile == current,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.profile,
    required this.icon,
    required this.subtitle,
    required this.selected,
  });

  final ControlScreenProfile profile;
  final IconData icon;
  final String subtitle;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).pop();
          context.read<CraneController>().setControlScreenProfile(profile);
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.selectionViolet.withAlpha(22)
                : AppColors.darkBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? AppColors.selectionViolet.withAlpha(110)
                  : AppColors.darkBorder,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.selectionViolet),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      profile.displayName,
                      style: const TextStyle(
                        color: AppColors.darkText,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.darkTextMuted,
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                color: selected
                    ? AppColors.selectionViolet
                    : AppColors.darkTextMuted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
