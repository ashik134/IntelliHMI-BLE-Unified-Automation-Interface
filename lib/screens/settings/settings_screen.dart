import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SettingsScreen
//
// Top-level settings list. Uses the light industrial palette (ConnectionColors)
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
      body: Consumer<CraneController>(
        builder: (context, controller, _) {
          return ListView(
            children: [
              // ── Device Identity Section ──────────────────────────────────────
              const _SectionHeader(label: 'DEVICE IDENTITY'),
              _DeviceIdentityCard(controller: controller),

              // ── Security Section ─────────────────────────────────────────────
              const _SectionHeader(label: 'SECURITY'),
              const _BiometricCard(),

              // ── Security Information Section ────────────────────────────────
              const _SectionHeader(label: 'SECURITY INFORMATION'),
              const _SecurityInfoCard(),

              // ── Active Session Section ──────────────────────────────────────
              if (_isAuthenticated) ...[
                const _SectionHeader(label: 'ACTIVE SESSION'),
                const _ActiveSessionCard(),
              ],

              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  bool get _isAuthenticated {
    // Replace with your actual authentication check
    // Example: return context.read<AuthController>().isAuthenticated;
    return false; // Placeholder - implement based on your auth state
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

// ─────────────────────────────────────────────────────────────────────────────
// Device Identity Card
// ─────────────────────────────────────────────────────────────────────────────

class _DeviceIdentityCard extends StatefulWidget {
  const _DeviceIdentityCard({required this.controller});

  final CraneController controller;

  @override
  State<_DeviceIdentityCard> createState() => _DeviceIdentityCardState();
}

class _DeviceIdentityCardState extends State<_DeviceIdentityCard> {
  bool _copied = false;

  void _copyDeviceId() {
    final id = widget.controller.deviceId;
    if (id.isEmpty) return;
    Clipboard.setData(ClipboardData(text: id));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.controller.deviceId;
    final displayId = id.isEmpty ? 'Initializing…' : id;

    return _IndustrialCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.connPrimary.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.connPrimary.withAlpha(80),
                  ),
                ),
                child: const Text(
                  'PERMANENT IDENTITY',
                  style: TextStyle(
                    color: AppColors.connPrimary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.homeSuccess,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'ACTIVE',
                style: TextStyle(
                  color: AppColors.homeSuccess,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Device ID',
            style: TextStyle(
              color: AppColors.connTextMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.connBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider),
            ),
            child: Text(
              displayId,
              style: const TextStyle(
                color: AppColors.connPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Register this Device ID in the PLC web interface to authorize this '
            'device for control access.',
            style: TextStyle(
              color: AppColors.connTextMuted,
              fontSize: 11.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
                  label: _copied ? 'Copied' : 'Copy Device ID',
                  color: _copied
                      ? AppColors.homeSuccess
                      : AppColors.connPrimary,
                  onTap: id.isEmpty ? null : _copyDeviceId,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Biometric Card
// ─────────────────────────────────────────────────────────────────────────────

class _BiometricCard extends StatelessWidget {
  const _BiometricCard();

  @override
  Widget build(BuildContext context) {
    // Replace with your actual biometric state
    const isBiometricAvailable = false; // TODO: Get from controller
    const isBiometricEnrolled = false; // TODO: Get from controller

    return _IndustrialCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.face_unlock_rounded,
                color: AppColors.connTextMuted,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Biometric Quick-Auth',
                      style: TextStyle(
                        color: AppColors.connText,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isBiometricEnrolled
                          ? 'Credentials enrolled. Fingerprint/face login active.'
                          : isBiometricAvailable
                          ? 'Hardware available. Log in manually to enroll.'
                          : 'No biometric hardware detected on this device.',
                      style: const TextStyle(
                        color: AppColors.connTextMuted,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.divider.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isBiometricEnrolled! ? 'ON' : 'OFF',
                  style: TextStyle(
                    color: isBiometricEnrolled!
                        ? AppColors.connSuccess
                        : AppColors.connTextMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          if (isBiometricEnrolled!) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: AppColors.divider),
            const SizedBox(height: 14),
            _ActionButton(
              icon: Icons.delete_outline_rounded,
              label: 'Revoke Biometric Access',
              color: AppColors.error,
              outlined: true,
              onTap: () => _confirmRevoke(context),
            ),
          ],
        ],
      ),
    );
  }

  void _confirmRevoke(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.divider),
        ),
        title: const Text(
          'Revoke Biometric Access',
          style: TextStyle(
            color: AppColors.connText,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'Stored operator credentials will be permanently removed from this '
          'device keystore. You will need to log in manually to re-enroll.',
          style: TextStyle(color: AppColors.connTextMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.connTextMuted),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // TODO: Call controller.clearBiometricEnrollment();
            },
            child: const Text(
              'Revoke',
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Security Information Card
// ─────────────────────────────────────────────────────────────────────────────

class _SecurityInfoCard extends StatelessWidget {
  const _SecurityInfoCard();

  @override
  Widget build(BuildContext context) {
    return const _IndustrialCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SecurityFact(
            icon: Icons.lock_rounded,
            label: 'AES-128-GCM Encrypted Communication',
          ),
          SizedBox(height: 12),
          _SecurityFact(
            icon: Icons.verified_user_rounded,
            label: 'Triple Authorization Gate',
          ),
          SizedBox(height: 12),
          _SecurityFact(
            icon: Icons.phonelink_lock_rounded,
            label: 'Device Identity — Android Keystore',
          ),
          SizedBox(height: 12),
          _SecurityFact(icon: Icons.shield_rounded, label: 'Fail-Safe Default'),
        ],
      ),
    );
  }
}

class _SecurityFact extends StatelessWidget {
  const _SecurityFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.divider.withAlpha(50),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.connTextMuted, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.connText,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
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
// Active Session Card
// ─────────────────────────────────────────────────────────────────────────────

class _ActiveSessionCard extends StatelessWidget {
  const _ActiveSessionCard();

  @override
  Widget build(BuildContext context) {
    // Replace with your actual session data
    return _IndustrialCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoRow(
            label: 'Operator',
            value: 'admin@plc.com', // TODO: Get from controller
            valueColor: AppColors.connSuccess,
          ),
          const SizedBox(height: 8),
          const _InfoRow(
            label: 'PLC Device',
            value: 'RRC_PLC', // TODO: Get from controller
          ),
          const SizedBox(height: 8),
          const _InfoRow(
            label: 'Signal',
            value: '-62 dBm', // TODO: Get from controller
          ),
          const SizedBox(height: 8),
          const _InfoRow(label: 'Encryption', value: 'AES-128-GCM Active'),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.connTextMuted,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AppColors.connText,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared primitives
// ─────────────────────────────────────────────────────────────────────────────

class _IndustrialCard extends StatelessWidget {
  const _IndustrialCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.outlined = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool outlined;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : color.withAlpha(38),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: onTap != null
                ? color.withAlpha(outlined ? 153 : 90)
                : AppColors.divider,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: onTap != null ? color : AppColors.connTextMuted,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: onTap != null ? color : AppColors.connTextMuted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
