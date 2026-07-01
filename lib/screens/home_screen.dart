import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:battery_plus/battery_plus.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev_crane_control_ops/controllers/navigation_controller.dart';
import 'package:rev_crane_control_ops/screens/settings/settings_screen.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';

// ─── Data Models ─────────────────────────────────────────────────────────────

class _RecentEvent {
  const _RecentEvent({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.time,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final String time;
}

enum _MetricStatus { ok, warning, error, neutral }

// ═══════════════════════════════════════════════════════════════
// HomeScreen
// ═══════════════════════════════════════════════════════════════

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  bool _commStatsExpanded = false;

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  static const List<_RecentEvent> _recentEvents = [
    _RecentEvent(
      icon: Icons.check_circle_outline_rounded,
      color: AppColors.homeSuccess,
      title: 'System Initialized',
      detail: 'Application started successfully',
      time: 'Just now',
    ),
    _RecentEvent(
      icon: Icons.bluetooth_rounded,
      color: AppColors.homePrimary,
      title: 'BLE Adapter Checked',
      detail: 'Bluetooth adapter scanned',
      time: 'Just now',
    ),
    _RecentEvent(
      icon: Icons.shield_outlined,
      color: AppColors.homeInfo,
      title: 'Permissions Verified',
      detail: 'Runtime permissions checked',
      time: 'Just now',
    ),
    _RecentEvent(
      icon: Icons.info_outline_rounded,
      color: AppColors.lightTextMuted,
      title: 'No Previous Session',
      detail: 'Connect to start a new session',
      time: '\u2014',
    ),
  ];

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..forward();

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );

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

  void _navigateToConnect() {
    HapticFeedback.mediumImpact();
    context.read<NavigationController>().navigateToControl();
  }

  void _navigateToSettings() {
    HapticFeedback.lightImpact();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CraneController>();

    return Scaffold(
      backgroundColor: AppColors.homeBg,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _ProfessionalHeader(
                  onSettingsTap: _navigateToSettings,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _ConnectPlcCard(onConnect: _navigateToConnect),
                    const SizedBox(height: 22),
                    const _SectionLabel(label: 'QUICK ACTIONS'),
                    const SizedBox(height: 10),
                    _QuickActionsGrid(
                      onControlPanel: _navigateToConnect,
                      onDiagnostics: () => context
                          .read<NavigationController>()
                          .navigateToDiagnostics(),
                      onLogs: () =>
                          context.read<NavigationController>().navigateToLogs(),
                      onSettings: _navigateToSettings,
                    ),
                    const SizedBox(height: 22),
                    const _SectionLabel(label: 'SYSTEM HEALTH'),
                    const SizedBox(height: 10),
                    _SystemHealthCard(controller: controller),
                    const SizedBox(height: 16),
                    _CommStatsPanel(
                      expanded: _commStatsExpanded,
                      onToggle: () => setState(
                        () => _commStatsExpanded = !_commStatsExpanded,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const _SectionLabel(label: 'RECENT EVENTS'),
                    const SizedBox(height: 10),
                    const _RecentEventsCard(events: _recentEvents),
                    const SizedBox(height: 8),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Section Label
// ═══════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.lightTextMuted,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Professional Header
// ═══════════════════════════════════════════════════════════════

class _ProfessionalHeader extends StatelessWidget {
  const _ProfessionalHeader({required this.onSettingsTap});

  final VoidCallback onSettingsTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 10, 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.homeBorder, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 46,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.homePrimaryLight,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: AppColors.homePrimary.withAlpha(40)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset(
                'assets/images/intellicontrol-icon-1024x1024 (6).png',
                fit: BoxFit.fill,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'IntelliHMI',
                  style: GoogleFonts.exo2(
                    color: AppColors.lightText,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'PLC Control System',
                  style: TextStyle(
                    color: AppColors.lightTextSub,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.homePrimaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'v${AppConstants.appVersion}',
              style: TextStyle(
                color: AppColors.homePrimary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 2),
          _HeaderIconButton(
            icon: Icons.person_outline_rounded,
            tooltip: 'Profile',
            onTap: () {},
          ),
          _HeaderIconButton(
            icon: Icons.settings_outlined,
            tooltip: 'Settings',
            onTap: onSettingsTap,
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: AppColors.lightTextSub, size: 22),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Connect PLC — Primary CTA Card
// ═══════════════════════════════════════════════════════════════

class _ConnectPlcCard extends StatefulWidget {
  const _ConnectPlcCard({required this.onConnect});
  final VoidCallback onConnect;

  @override
  State<_ConnectPlcCard> createState() => _ConnectPlcCardState();
}

class _ConnectPlcCardState extends State<_ConnectPlcCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _pressAnim;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _pressAnim = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        widget.onConnect();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      child: AnimatedBuilder(
        animation: _pressAnim,
        builder: (_, child) =>
            Transform.scale(scale: _pressAnim.value, child: child),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.homePrimary, AppColors.homePrimaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.homePrimary.withAlpha(90),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(38),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.bluetooth_searching_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 18),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CONNECT PLC',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Scan & pair your PLC device via Bluetooth LE',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(38),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Quick Actions Grid (2 x 2)
// ═══════════════════════════════════════════════════════════════

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid({
    required this.onControlPanel,
    required this.onDiagnostics,
    required this.onLogs,
    required this.onSettings,
  });

  final VoidCallback onControlPanel;
  final VoidCallback onDiagnostics;
  final VoidCallback onLogs;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = constraints.maxWidth > 560;
        return GridView.count(
          crossAxisCount: isTablet ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: isTablet ? 1.1 : 1.55,
          children: [
            _QuickActionCard(
              icon: Icons.dashboard_customize_rounded,
              label: 'Control Panel',
              subtitle: 'Machine controls',
              color: AppColors.homePrimary,
              onTap: onControlPanel,
            ),
            _QuickActionCard(
              icon: Icons.monitor_heart_rounded,
              label: 'Diagnostics',
              subtitle: 'System health check',
              color: AppColors.homeInfo,
              onTap: onDiagnostics,
            ),
            _QuickActionCard(
              icon: Icons.receipt_long_rounded,
              label: 'Event Logs',
              subtitle: 'Activity history',
              color: AppColors.homeWarning,
              onTap: onLogs,
            ),
            _QuickActionCard(
              icon: Icons.tune_rounded,
              label: 'Settings',
              subtitle: 'App configuration',
              color: AppColors.lightTextSub,
              onTap: onSettings,
            ),
          ],
        );
      },
    );
  }
}

class _QuickActionCard extends StatefulWidget {
  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_QuickActionCard> createState() => _QuickActionCardState();
}

class _QuickActionCardState extends State<_QuickActionCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double> _pressAnim;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _pressAnim = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _pressCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressCtrl.forward(),
      onTapUp: (_) {
        _pressCtrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _pressCtrl.reverse(),
      child: AnimatedBuilder(
        animation: _pressAnim,
        builder: (_, child) =>
            Transform.scale(scale: _pressAnim.value, child: child),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.homeBorder),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadowLight,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: widget.color.withAlpha(24),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.icon, color: widget.color, size: 18),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: const TextStyle(
                      color: AppColors.lightText,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle,
                    style: const TextStyle(
                      color: AppColors.lightTextMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// System Health Card (with live battery)
// ═══════════════════════════════════════════════════════════════

class _SystemHealthCard extends StatefulWidget {
  const _SystemHealthCard({required this.controller});
  final CraneController controller;

  @override
  State<_SystemHealthCard> createState() => _SystemHealthCardState();
}

class _SystemHealthCardState extends State<_SystemHealthCard> {
  final Battery _battery = Battery();
  int? _batteryLevel;
  BatteryState _batteryState = BatteryState.unknown;

  @override
  void initState() {
    super.initState();
    _fetchBattery();
  }

  Future<void> _fetchBattery() async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      if (mounted) {
        setState(() {
          _batteryLevel = level;
          _batteryState = state;
        });
      }
    } catch (_) {
      // Battery not available on this platform
    }
  }

  String get _batteryValue {
    if (_batteryLevel == null) return '\u2014';
    return '$_batteryLevel%';
  }

  IconData get _batteryIcon {
    if (_batteryState == BatteryState.charging ||
        _batteryState == BatteryState.full) {
      return Icons.battery_charging_full_rounded;
    }
    final level = _batteryLevel ?? 100;
    if (level <= 10) return Icons.battery_0_bar_rounded;
    if (level <= 30) return Icons.battery_2_bar_rounded;
    if (level <= 50) return Icons.battery_3_bar_rounded;
    if (level <= 70) return Icons.battery_4_bar_rounded;
    if (level <= 90) return Icons.battery_5_bar_rounded;
    return Icons.battery_full_rounded;
  }

  _MetricStatus get _batteryStatus {
    if (_batteryLevel == null) return _MetricStatus.neutral;
    if (_batteryLevel! <= 10) return _MetricStatus.error;
    if (_batteryLevel! <= 25) return _MetricStatus.warning;
    return _MetricStatus.ok;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.homeBorder),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          const _HealthMetricRow(
            icon: Icons.check_circle_rounded,
            label: 'App Status',
            value: 'Operational',
            status: _MetricStatus.ok,
            isFirst: true,
          ),
          _HealthMetricRow(
            icon: Icons.bluetooth_rounded,
            label: 'BLE Adapter',
            value: widget.controller.bluetoothReady ? 'Ready' : 'Offline',
            status: widget.controller.bluetoothReady
                ? _MetricStatus.ok
                : _MetricStatus.error,
          ),
          _HealthMetricRow(
            icon: Icons.security_rounded,
            label: 'Permissions',
            value: widget.controller.permissionsGranted ? 'Granted' : 'Missing',
            status: widget.controller.permissionsGranted
                ? _MetricStatus.ok
                : _MetricStatus.warning,
          ),
          const _HealthMetricRow(
            icon: Icons.memory_rounded,
            label: 'Memory',
            value: 'Normal',
            status: _MetricStatus.ok,
          ),
          _HealthMetricRow(
            icon: _batteryIcon,
            label: _batteryState == BatteryState.charging
                ? 'Battery (Charging)'
                : 'Battery',
            value: _batteryValue,
            status: _batteryStatus,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _HealthMetricRow extends StatelessWidget {
  const _HealthMetricRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.status,
    this.isFirst = false,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final _MetricStatus status;
  final bool isFirst;
  final bool isLast;

  Color get _color => switch (status) {
        _MetricStatus.ok => AppColors.homeSuccess,
        _MetricStatus.warning => AppColors.homeWarning,
        _MetricStatus.error => AppColors.homeDanger,
        _MetricStatus.neutral => AppColors.lightTextMuted,
      };

  Color get _bgColor => switch (status) {
        _MetricStatus.ok => AppColors.homeSuccessLight,
        _MetricStatus.warning => AppColors.homeWarningLight,
        _MetricStatus.error => AppColors.homeDangerLight,
        _MetricStatus.neutral => AppColors.homeSurfaceAlt,
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (!isFirst)
          const Divider(height: 1, thickness: 0.5, color: AppColors.homeBorder),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _bgColor,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: _color, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.lightText,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _bgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  value,
                  style: TextStyle(
                    color: _color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Communication Statistics Panel (Expandable)
// ═══════════════════════════════════════════════════════════════

class _CommStatsPanel extends StatelessWidget {
  const _CommStatsPanel({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.homeBorder),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.homePrimaryLight,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.bar_chart_rounded,
                      color: AppColors.homePrimary,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'COMMUNICATION STATISTICS',
                      style: TextStyle(
                        color: AppColors.lightText,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 220),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.lightTextMuted,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 230),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: const Column(
              children: [
                Divider(
                    height: 1, thickness: 0.5, color: AppColors.homeBorder),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    children: [
                      _StatRowItem(
                        icon: Icons.link_rounded,
                        label: 'Total Sessions',
                        value: '0',
                      ),
                      _StatRowItem(
                        icon: Icons.refresh_rounded,
                        label: 'Connection Attempts',
                        value: '0',
                      ),
                      _StatRowItem(
                        icon: Icons.error_outline_rounded,
                        label: 'Communication Errors',
                        value: '0',
                        isWarning: true,
                      ),
                      _StatRowItem(
                        icon: Icons.schedule_rounded,
                        label: 'Last Successful Conn.',
                        value: 'Never',
                      ),
                      _StatRowItem(
                        icon: Icons.swap_horiz_rounded,
                        label: 'Packets Exchanged',
                        value: '0',
                        isLast: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRowItem extends StatelessWidget {
  const _StatRowItem({
    required this.icon,
    required this.label,
    required this.value,
    this.isWarning = false,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isWarning;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Icon(
                icon,
                size: 15,
                color: isWarning
                    ? AppColors.homeWarning
                    : AppColors.lightTextMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.lightTextSub,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: isWarning ? AppColors.homeWarning : AppColors.lightText,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          const Divider(
            height: 1,
            thickness: 0.5,
            color: AppColors.homeBorder,
            indent: 25,
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Recent Events Card (Timeline Feed)
// ═══════════════════════════════════════════════════════════════

class _RecentEventsCard extends StatelessWidget {
  const _RecentEventsCard({required this.events});
  final List<_RecentEvent> events;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.homeBorder),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowLight,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: List.generate(events.length, (i) {
          return _EventTimelineItem(
            event: events[i],
            isLast: i == events.length - 1,
          );
        }),
      ),
    );
  }
}

class _EventTimelineItem extends StatelessWidget {
  const _EventTimelineItem({required this.event, required this.isLast});
  final _RecentEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 30,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: event.color.withAlpha(24),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(event.icon, size: 12, color: event.color),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: AppColors.homeBorder,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.title,
                          style: const TextStyle(
                            color: AppColors.lightText,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        event.time,
                        style: const TextStyle(
                          color: AppColors.lightTextMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    event.detail,
                    style: const TextStyle(
                      color: AppColors.lightTextSub,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}