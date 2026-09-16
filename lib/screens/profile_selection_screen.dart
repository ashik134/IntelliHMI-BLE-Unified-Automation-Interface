import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/widgets/shared/brand_widgets.dart';

/// One-time step shown right after an operator's PLC credentials are
/// accepted for the first time on a given (operator, PLC) pair — lets them
/// choose which Control Screen Profile this pairing uses from now on.
///
/// Never shown again for the same (operator, PLC) pair once a choice is
/// saved (see [CraneController.setControlScreenProfile] and
/// `ControlScreenProfileRegistry`) — future connections load the saved
/// profile automatically. The choice can be changed later via the
/// "Configure Screen" option on either Control Screen.
class ProfileSelectionScreen extends StatefulWidget {
  const ProfileSelectionScreen({super.key});

  @override
  State<ProfileSelectionScreen> createState() =>
      _ProfileSelectionScreenState();
}

class _ProfileSelectionScreenState extends State<ProfileSelectionScreen> {
  bool _selecting = false;

  Future<void> _choose(
    CraneController controller,
    ControlScreenProfile profile,
  ) async {
    if (_selecting) return;
    setState(() => _selecting = true);
    await controller.setControlScreenProfile(profile);
    if (!mounted) return;
    setState(() => _selecting = false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CraneController>();
    final deviceTitle = controller.connectedDeviceTitle;

    return Scaffold(
      backgroundColor: AppColors.brandBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: AppColors.brandVioletSoft,
                          borderRadius: BorderRadius.circular(
                            AppMetrics.radiusMd,
                          ),
                        ),
                        child: const Icon(
                          Icons.dashboard_customize_rounded,
                          color: AppColors.brandViolet,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Choose Your Control Screen',
                              style: TextStyle(
                                color: AppColors.brandText,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'One-time choice — saved for you on this PLC.',
                              style: TextStyle(
                                color: AppColors.brandTextSub,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  BrandCard(
                    child: Row(
                      children: [
                        const Icon(
                          Icons.bluetooth_connected_rounded,
                          color: AppColors.brandTextSub,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            deviceTitle,
                            style: const TextStyle(
                              color: AppColors.brandText,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const BrandBadge(
                          label: 'FIRST CONNECTION',
                          tone: BrandTone.violet,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'This decides what you see on the Control Screen for this '
                    'PLC from now on. You can change it later from Configure '
                    'Screen.',
                    style: TextStyle(
                      color: AppColors.brandTextSub,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ProfileOptionCard(
                    icon: Icons.dashboard_customize_rounded,
                    title: ControlScreenProfile.standard.displayName,
                    description:
                        'Full dynamic control grid with all of this PLC\'s '
                        'configured widgets.',
                    busy: _selecting,
                    onTap: () =>
                        _choose(controller, ControlScreenProfile.standard),
                  ),
                  const SizedBox(height: 12),
                  _ProfileOptionCard(
                    icon: Icons.power_settings_new_rounded,
                    title: ControlScreenProfile.safetyOnly.displayName,
                    description:
                        'Circular Emergency Stop only — no control grid.',
                    busy: _selecting,
                    onTap: () =>
                        _choose(controller, ControlScreenProfile.safetyOnly),
                  ),
                  const SizedBox(height: 22),
                  BrandSecondaryButton(
                    label: 'Cancel & Disconnect',
                    icon: Icons.arrow_back_rounded,
                    onPressed: _selecting ? null : controller.disconnect,
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

class _ProfileOptionCard extends StatelessWidget {
  const _ProfileOptionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: busy ? 0.6 : 1.0,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        onTap: busy ? null : onTap,
        child: BrandCard(
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.brandVioletSoft,
                  borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                ),
                child: Icon(icon, color: AppColors.brandViolet, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.brandText,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: const TextStyle(
                        color: AppColors.brandTextSub,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.brandTextMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
