import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev6_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev6_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev6_crane_control_ops/screens/settings/settings_screen.dart';
import 'package:rev6_crane_control_ops/utils/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HomeScreen
//
// Entry point after the startup splash.  Provides the operator with an
// industrial dashboard: connection status, navigation to the BLE scan /
// control flow, and access to settings.
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    )..forward();
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );

    // Load layout settings lazily on first visit.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<LayoutSettingsController>().load();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _navigateToConnect(BuildContext context) {
    Navigator.of(context).pushNamed('/crane');
  }

  void _navigateToSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CraneController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _buildHeader(context, controller),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _ConnectionStatusCard(controller: controller),
                    const SizedBox(height: 16),
                    _NavigationGrid(
                      onConnect: () => _navigateToConnect(context),
                      onSettings: () => _navigateToSettings(context),
                    ),
                    const SizedBox(height: 16),
                    _SystemInfoRow(controller: controller),
                    const SizedBox(height: 16),
                    _RecentDeviceCard(controller: controller),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, CraneController controller) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(
          bottom: BorderSide(color: AppColors.panelStroke),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.precision_manufacturing_rounded,
              color: AppColors.accent,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppConstants.appTitle,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                Text(
                  'v${AppConstants.appVersion}  ·  ${AppConstants.plcName}',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Settings shortcut
          _IconActionButton(
            icon: Icons.settings_outlined,
            tooltip: 'Settings',
            onTap: () => _navigateToSettings(context),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ConnectionStatusCard extends StatelessWidget {
  const _ConnectionStatusCard({required this.controller});

  final CraneController controller;

  @override
  Widget build(BuildContext context) {
    final status = _resolveStatus(controller);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: status.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: status.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(60),
              borderRadius: BorderRadius.circular(12),
            ),
            child: status.loading
                ? Padding(
                    padding: const EdgeInsets.all(11),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: status.iconColor,
                    ),
                  )
                : Icon(status.icon, color: status.iconColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.title,
                  style: TextStyle(
                    color: status.titleColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status.subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (controller.isConnected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.upColor.withAlpha(40),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.upColor.withAlpha(100)),
              ),
              child: const Text(
                'LIVE',
                style: TextStyle(
                  color: AppColors.upColorLight,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
        ],
      ),
    );
  }

  _StatusData _resolveStatus(CraneController c) {
    if (!c.bluetoothReady) {
      return const _StatusData(
        cardBg: Color(0xFF1A0E0A),
        cardBorder: Color(0xFF4A2010),
        iconColor: AppColors.accent,
        icon: Icons.bluetooth_disabled_rounded,
        title: 'Bluetooth Unavailable',
        subtitle: 'Enable Bluetooth to connect to the PLC',
        titleColor: AppColors.accent,
        loading: false,
      );
    }
    if (c.isConnected) {
      return _StatusData(
        cardBg: AppColors.upColor.withAlpha(20),
        cardBorder: AppColors.upColor.withAlpha(80),
        iconColor: AppColors.upColorLight,
        icon: Icons.bluetooth_connected_rounded,
        title: c.connectedDeviceName != null
            ? 'Connected — ${c.connectedDeviceName}'
            : 'Connected',
        subtitle: c.isAuthenticated
            ? 'Authenticated  ·  Control session active'
            : 'Pending authentication',
        titleColor: AppColors.upColorLight,
        loading: false,
      );
    }
    if (c.isScanning || c.isConnecting) {
      return _StatusData(
        cardBg: AppColors.info.withAlpha(18),
        cardBorder: AppColors.info.withAlpha(70),
        iconColor: AppColors.info,
        icon: Icons.bluetooth_searching_rounded,
        title: c.isScanning ? 'Scanning…' : 'Connecting…',
        subtitle: 'Searching for ${BLEConstants.deviceName}',
        titleColor: AppColors.info,
        loading: true,
      );
    }
    return const _StatusData(
      cardBg: Color(0xFF111820),
      cardBorder: AppColors.panelStroke,
      iconColor: AppColors.textMuted,
      icon: Icons.bluetooth_rounded,
      title: 'Not Connected',
      subtitle: 'Tap "Connect to Device" to begin',
      titleColor: AppColors.textSecondary,
      loading: false,
    );
  }
}

class _StatusData {
  const _StatusData({
    required this.cardBg,
    required this.cardBorder,
    required this.iconColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.titleColor,
    required this.loading,
  });

  final Color cardBg;
  final Color cardBorder;
  final Color iconColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color titleColor;
  final bool loading;
}

// ─────────────────────────────────────────────────────────────────────────────

class _NavigationGrid extends StatelessWidget {
  const _NavigationGrid({
    required this.onConnect,
    required this.onSettings,
  });

  final VoidCallback onConnect;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Primary CTA — full width
        _NavTile(
          icon: Icons.cable_rounded,
          label: 'Connect to Device',
          subtitle: 'Scan & connect to PLC via Bluetooth',
          color: AppColors.accent,
          onTap: onConnect,
          primary: true,
        ),
        const SizedBox(height: 10),
        // Secondary row
        Row(
          children: [
            Expanded(
              child: _NavTile(
                icon: Icons.tune_rounded,
                label: 'Settings',
                subtitle: 'Customise UI & preferences',
                color: AppColors.info,
                onTap: onSettings,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.all(primary ? 18 : 14),
          decoration: BoxDecoration(
            color: primary
                ? color.withAlpha(28)
                : AppColors.panelAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: primary ? color.withAlpha(100) : AppColors.panelStroke,
              width: primary ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: primary ? 48 : 40,
                height: primary ? 48 : 40,
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: primary ? 26 : 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: primary ? color : AppColors.textPrimary,
                        fontSize: primary ? 15 : 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: primary ? color.withAlpha(180) : AppColors.textMuted,
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

class _SystemInfoRow extends StatelessWidget {
  const _SystemInfoRow({required this.controller});

  final CraneController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _InfoChip(
            icon: Icons.bluetooth_rounded,
            label: 'Bluetooth',
            value: controller.bluetoothReady ? 'Ready' : 'Off',
            valueColor: controller.bluetoothReady
                ? AppColors.upColorLight
                : AppColors.danger,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _InfoChip(
            icon: Icons.security_rounded,
            label: 'Permissions',
            value: controller.permissionsGranted ? 'Granted' : 'Missing',
            valueColor: controller.permissionsGranted
                ? AppColors.upColorLight
                : AppColors.accent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _InfoChip(
            icon: Icons.memory_rounded,
            label: 'Session',
            value: controller.isAuthenticated ? 'Active' : 'None',
            valueColor: controller.isAuthenticated
                ? AppColors.upColorLight
                : AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.panelAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.panelStroke),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.textMuted, size: 18),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _RecentDeviceCard extends StatelessWidget {
  const _RecentDeviceCard({required this.controller});

  final CraneController controller;

  @override
  Widget build(BuildContext context) {
    final deviceName =
        controller.connectedDeviceName ?? BLEConstants.deviceName;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.panelStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.history_rounded,
                size: 14,
                color: AppColors.textMuted,
              ),
              SizedBox(width: 6),
              Text(
                'DEVICE INFO',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.developer_board_rounded,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deviceName,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text(
                      BLEConstants.serviceUuid,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 9,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
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

class _IconActionButton extends StatelessWidget {
  const _IconActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.panelAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.panelStroke),
          ),
          child: Icon(icon, color: AppColors.textSecondary, size: 20),
        ),
      ),
    );
  }
}
