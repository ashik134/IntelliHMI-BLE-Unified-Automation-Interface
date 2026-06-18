import 'package:flutter/material.dart';
import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';

class QuickStatusRow extends StatelessWidget {
  const QuickStatusRow({super.key, required this.controller});

  final CraneController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MiniStatCard(
            label: 'Devices',
            value: controller.isConnected
                ? '1'
                : controller.isConnectionActive
                ? '...'
                : '${controller.devices.length}',
            icon: Icons.memory_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MiniStatCard(
            label: 'Bluetooth',
            value: controller.bluetoothReady ? 'ON' : 'OFF',
            icon: controller.bluetoothReady
                ? Icons.bluetooth_connected_rounded
                : Icons.bluetooth_disabled_rounded,
            valueColor: controller.bluetoothReady
                ? AppColors.connected
                : AppColors.error,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MiniStatCard(
            label: 'Permission',
            value: controller.permissionsGranted ? 'OK' : 'WAIT',
            icon: controller.permissionsGranted
                ? Icons.verified_rounded
                : Icons.key_off_rounded,
            valueColor: controller.permissionsGranted
                ? AppColors.connected
                : AppColors.connWarning,
          ),
        ),
      ],
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor = AppColors.connPrimary,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final double cardWidth = screenWidth < 600 ? 110 : 140;
    final double cardHeight = screenWidth < 600 ? 65 : 75;

    return Container(
      width: cardWidth,
      height: cardHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.connBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.connTextMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.connTextMuted,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    color: valueColor,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
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

