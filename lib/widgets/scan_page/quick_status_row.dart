import 'package:flutter/material.dart';
import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';

/// At-a-glance runtime status, rendered as chips on the dark console
/// header. Previously three light cards on the light sheet, where they
/// washed out against the page background and cost a full row of height —
/// on the dark surface the same three readings carry their own contrast.
class ScanStatusChips extends StatelessWidget {
  const ScanStatusChips({super.key, required this.controller});

  final CraneController controller;

  @override
  Widget build(BuildContext context) {
    final String deviceValue = controller.isConnected
        ? '1'
        : controller.isConnectionActive
        ? '···'
        : '${controller.devices.length}';

    return Row(
      children: [
        Expanded(
          child: _StatusChip(
            label: 'Devices',
            value: deviceValue,
            icon: Icons.memory_rounded,
            tone: AppColors.brandViolet,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatusChip(
            label: 'Bluetooth',
            value: controller.bluetoothReady ? 'ON' : 'OFF',
            icon: controller.bluetoothReady
                ? Icons.bluetooth_connected_rounded
                : Icons.bluetooth_disabled_rounded,
            tone: controller.bluetoothReady
                ? AppColors.brandSuccess
                : AppColors.brandDanger,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatusChip(
            label: 'Permission',
            value: controller.permissionsGranted ? 'OK' : 'WAIT',
            icon: controller.permissionsGranted
                ? Icons.verified_rounded
                : Icons.key_off_rounded,
            tone: controller.permissionsGranted
                ? AppColors.brandSuccess
                : AppColors.brandWarning,
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(13),
        borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
        border: Border.all(color: tone.withAlpha(70)),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: tone.withAlpha(38),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 13, color: tone),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 8,
                    color: AppColors.brandOnDarkSub,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    color: tone,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    height: 1.25,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
