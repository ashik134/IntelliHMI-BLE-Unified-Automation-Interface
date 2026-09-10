import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/screens/operator/operator_management_screen.dart';
import 'package:rev_crane_control_ops/widgets/settings/admin_pin_gate_sheet.dart';
import 'package:rev_crane_control_ops/widgets/shared/brand_widgets.dart';

/// One-time configuration step shown right after a never-before-connected
/// PLC (identified by its BLE MAC ID) accepts valid credentials for the
/// first time. Lets whoever just authenticated — any operator role may
/// complete this — choose which identity-verification methods this
/// specific device will use on every future connection.
///
/// Biometric's enabled state is decided one screen earlier, on
/// [LoginScreen]'s existing "save biometric login" offer — this screen only
/// surfaces that as a read-only status and lets Face Verification be turned
/// on/off, then persists the choice via [CraneController.completeSetupMode].
class SetupModeScreen extends StatefulWidget {
  const SetupModeScreen({super.key});

  @override
  State<SetupModeScreen> createState() => _SetupModeScreenState();
}

class _SetupModeScreenState extends State<SetupModeScreen> {
  bool _faceVerificationEnabled = true;
  bool _finishing = false;

  Future<void> _manageOperators() async {
    final verified = await requireAdminPin(context);
    if (!verified || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const OperatorManagementScreen(),
      ),
    );
  }

  Future<void> _finishSetup(CraneController controller) async {
    setState(() => _finishing = true);
    await controller.completeSetupMode(
      faceVerificationEnabled: _faceVerificationEnabled,
    );
    if (!mounted) return;
    setState(() => _finishing = false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CraneController>();
    final deviceTitle = controller.connectedDeviceTitle;
    final biometricEnrolled = controller.isBiometricEnrolled;

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
                          Icons.verified_user_rounded,
                          color: AppColors.brandViolet,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Set Up This Device',
                              style: TextStyle(
                                color: AppColors.brandText,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'One-time setup — this only runs once per PLC.',
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
                    'Credentials were accepted. Choose which identity checks '
                    'this device should use for every connection from now on.',
                    style: TextStyle(
                      color: AppColors.brandTextSub,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  BrandCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.face_retouching_natural_rounded,
                              color: AppColors.brandViolet,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Face Verification',
                                style: TextStyle(
                                  color: AppColors.brandText,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Switch.adaptive(
                              value: _faceVerificationEnabled,
                              activeThumbColor: AppColors.brandViolet,
                              activeTrackColor: AppColors.brandViolet
                                  .withValues(alpha: 0.35),
                              onChanged: _finishing
                                  ? null
                                  : (value) => setState(
                                      () => _faceVerificationEnabled = value,
                                    ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'On future connections to this device, a recognized '
                          'face signs the operator in automatically. Stores '
                          'this login securely on this tablet so that '
                          'sign-in can happen without retyping a password.',
                          style: TextStyle(
                            color: AppColors.brandTextMuted,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        BrandSecondaryButton(
                          label: 'Manage Operators & Enroll a Face',
                          icon: Icons.badge_outlined,
                          onPressed: _finishing ? null : _manageOperators,
                          height: 44,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  BrandCard(
                    child: Row(
                      children: [
                        Icon(
                          Icons.fingerprint_rounded,
                          color: biometricEnrolled
                              ? AppColors.brandSuccess
                              : AppColors.brandTextMuted,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Biometric Authentication',
                            style: TextStyle(
                              color: AppColors.brandText,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        BrandBadge(
                          label: biometricEnrolled ? 'ENABLED' : 'NOT SET UP',
                          tone: biometricEnrolled
                              ? BrandTone.success
                              : BrandTone.neutral,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  BrandPrimaryButton(
                    label: _finishing ? 'FINISHING SETUP...' : 'FINISH SETUP',
                    icon: Icons.check_circle_outline_rounded,
                    busy: _finishing,
                    onPressed: () => _finishSetup(controller),
                  ),
                  const SizedBox(height: 10),
                  BrandSecondaryButton(
                    label: 'Cancel Setup & Disconnect',
                    icon: Icons.arrow_back_rounded,
                    onPressed: _finishing ? null : controller.disconnect,
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
