import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:rev_crane_control_ops/testing/ble_gateway/gateway_mode_screen.dart';
import 'package:rev_crane_control_ops/testing/ble_gateway/remote_ble_setup_screen.dart';
import 'package:rev_crane_control_ops/utils/app_theme.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/device_type.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _applyOrientationPolicy();
  runApp(const BleGatewayTestApp());
}

Future<void> _applyOrientationPolicy() async {
  final orientations = DeviceType.isTablet
      ? [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]
      : [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown];

  await SystemChrome.setPreferredOrientations(orientations);
}

class BleGatewayTestApp extends StatelessWidget {
  const BleGatewayTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Gateway Test',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const BleGatewayTestLauncher(),
    );
  }
}

class BleGatewayTestLauncher extends StatelessWidget {
  const BleGatewayTestLauncher({super.key});

  void _openGatewayMode(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const GatewayModeScreen()),
    );
  }

  void _openRemoteMode(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const RemoteBleSetupScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.brandBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(20),
              children: [
                Image.asset(
                  'assets/images/Intellicontrol Final Logo300PPI.png',
                  height: 110,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 18),
                const Text(
                  'BLE Gateway Test',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.brandText,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Temporary local-network bridge for tablet HMI testing.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.brandTextMuted,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 24),
                _LauncherCard(
                  icon: Icons.phone_android_rounded,
                  title: 'Phone Gateway Mode',
                  subtitle: 'Run this on the Android phone with reliable BLE.',
                  actionLabel: 'OPEN GATEWAY',
                  color: AppColors.connPrimary,
                  onTap: () => _openGatewayMode(context),
                ),
                const SizedBox(height: 12),
                _LauncherCard(
                  icon: Icons.tablet_android_rounded,
                  title: 'Tablet Remote BLE Mode',
                  subtitle: 'Run this on the tablet and enter the phone IP.',
                  actionLabel: 'OPEN TABLET HMI',
                  color: AppColors.brandViolet,
                  onTap: () => _openRemoteMode(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LauncherCard extends StatelessWidget {
  const _LauncherCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.brandSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.brandBorder),
        boxShadow: AppMetrics.shadowSm,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withAlpha(24),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
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
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.brandTextMuted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              actionLabel,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
