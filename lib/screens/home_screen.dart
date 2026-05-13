import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:rev6_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev6_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev6_crane_control_ops/screens/settings/settings_screen.dart';
import 'package:rev6_crane_control_ops/utils/constants.dart';

// ═══════════════════════════════════════════════════════════════
// HomeScreen
// ═══════════════════════════════════════════════════════════════

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _currentNavIndex = 0;

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  // Subtle pulse for status indicator
  late final AnimationController _pulseController;
  // late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    // _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
    //   CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    // );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<LayoutSettingsController>().load();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ─── Navigation Handlers ──────────────────────────────

  void _navigateToConnect() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pushNamed('/crane');
  }

  void _navigateToSettings() {
    HapticFeedback.lightImpact();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  void _onNavTap(int index) {
    HapticFeedback.selectionClick();
    setState(() => _currentNavIndex = index);

    switch (index) {
      case 0: // Home — already here
        break;
      case 1: // Connect
        _navigateToConnect();
        break;
      case 2: // Settings
        _navigateToSettings();
        break;
    }
  }

  // ─── Build ────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CraneController>();

    return Scaffold(
      backgroundColor: AppColors.homeBg,

      // ── Bottom Navigation Bar ──────────────────────
      bottomNavigationBar: _AnimatedBottomNav(
        currentIndex: _currentNavIndex,
        onTap: _onNavTap,
        isConnected: controller.isConnected,
      ),

      // ── Body ────────────────────────────────────────
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: _ProfessionalHeader(controller: controller),
              ),

              // Content
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Quick Status Banner
                    _QuickStatusBanner(controller: controller),
                    const SizedBox(height: 16),

                    // Quick Actions Row
                    _QuickActionsRow(
                      onConnect: _navigateToConnect,
                      onSettings: _navigateToSettings,
                    ),
                    const SizedBox(height: 20),

                    // Connection Status Card
                    // _EnhancedConnectionCard(
                    //   controller: controller,
                    //   pulseAnimation: _pulseAnimation,
                    // ),
                    const SizedBox(height: 16),

                    // System Health Cards
                    _SystemHealthGrid(controller: controller),
                    const SizedBox(height: 16),

                    // Recent Activity
                    _RecentActivityCard(controller: controller),
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
// Animated Bottom Navigation Bar
// ═══════════════════════════════════════════════════════════════

class _AnimatedBottomNav extends StatelessWidget {
  const _AnimatedBottomNav({
    required this.currentIndex,
    required this.onTap,
    required this.isConnected,
  });

  final int currentIndex;
  final Function(int) onTap;
  final bool isConnected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.navBarBg,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowMedium,
            blurRadius: 12,
            offset: Offset(0, -2),
          ),
        ],
        border: Border(
          top: BorderSide(color: AppColors.navBarBorder, width: 0.5),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                index: 0,
                currentIndex: currentIndex,
                icon: Icons.dashboard_rounded,
                activeIcon: Icons.dashboard_rounded,
                label: 'Dashboard',
                onTap: () => onTap(0),
              ),
              _NavItem(
                index: 1,
                currentIndex: currentIndex,
                icon: Icons.bluetooth_rounded,
                activeIcon: Icons.bluetooth_connected_rounded,
                label: 'Connect',
                badge: isConnected ? _NavBadge.pulse : null,
                onTap: () => onTap(1),
              ),
              _NavItem(
                index: 2,
                currentIndex: currentIndex,
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings_rounded,
                label: 'Settings',
                onTap: () => onTap(2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ignore: unused_field
enum _NavBadge { pulse, count }

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.index,
    required this.currentIndex,
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badge,
    required this.onTap,
  });

  final int index;
  final int currentIndex;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final _NavBadge? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = index == currentIndex;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: isActive ? 20 : 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isActive ? AppColors.homePrimaryLight : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon with animation
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: isActive ? 1.0 : 0.8),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: scale,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        isActive ? activeIcon : icon,
                        color: isActive
                            ? AppColors.navBarActive
                            : AppColors.navBarInactive,
                        size: 24,
                      ),
                      // Pulse badge for connected state
                      if (badge == _NavBadge.pulse)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: AppColors.homeSuccess,
                              shape: BoxShape.circle,
                            ),
                            child: const _PulseDot(),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            // Label (only when active)
            if (isActive) ...[
              const SizedBox(width: 8),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 200),
                builder: (context, opacity, child) {
                  return Opacity(
                    opacity: opacity,
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.navBarActive,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Pulse Dot (for connection indicator)
// ═══════════════════════════════════════════════════════════════

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.6, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.homeSuccess.withAlpha(
              (_animation.value * 255).toInt(),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Professional Header
// ═══════════════════════════════════════════════════════════════

class _ProfessionalHeader extends StatelessWidget {
  const _ProfessionalHeader({required this.controller});

  final CraneController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.homeBorder, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Logo
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.homePrimary, AppColors.homePrimaryDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.homePrimary.withAlpha(64),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.precision_manufacturing_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      AppConstants.appTitle,
                      style: TextStyle(
                        color: AppColors.lightText,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'PLC14 Industrial Control System',
                      style: TextStyle(
                        color: AppColors.lightTextSub.withAlpha(204),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              // Version badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
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
            ],
          ),
          const SizedBox(height: 14),
          // Status strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.homeSurfaceAlt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _MiniStatusDot(
                  active: controller.bluetoothReady,
                  color: AppColors.homeSuccess,
                  label: 'BT',
                ),
                const SizedBox(width: 12),
                _MiniStatusDot(
                  active: controller.isConnected,
                  color: AppColors.homePrimary,
                  label: 'PLC',
                ),
                const SizedBox(width: 12),
                _MiniStatusDot(
                  active: controller.isAuthenticated,
                  color: AppColors.homeInfo,
                  label: 'Auth',
                ),
                const Spacer(),
                Text(
                  controller.isConnected ? 'Online' : 'Standby',
                  style: TextStyle(
                    color: controller.isConnected
                        ? AppColors.homeSuccess
                        : AppColors.lightTextMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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

class _MiniStatusDot extends StatelessWidget {
  const _MiniStatusDot({
    required this.active,
    required this.color,
    required this.label,
  });

  final bool active;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? color : AppColors.borderStrong,
            shape: BoxShape.circle,
            boxShadow: active
                ? [BoxShadow(color: color.withAlpha(102), blurRadius: 4)]
                : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            color: active ? AppColors.lightText : AppColors.lightTextMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Quick Status Banner
// ═══════════════════════════════════════════════════════════════

class _QuickStatusBanner extends StatelessWidget {
  const _QuickStatusBanner({required this.controller});

  final CraneController controller;

  @override
  Widget build(BuildContext context) {
    final isConnected = controller.isConnected;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isConnected
              ? [AppColors.homeSuccessLight, AppColors.homeSuccessLight]
              : [AppColors.homeWarningLight, AppColors.homeWarningLight],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isConnected
              ? AppColors.homeSuccess.withAlpha(51)
              : AppColors.homeWarning.withAlpha(51),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isConnected ? Icons.check_circle_rounded : Icons.info_rounded,
            color: isConnected ? AppColors.homeSuccess : AppColors.homeWarning,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isConnected
                  ? 'System ready — Connected to ${controller.connectedDeviceName ?? "PLC14"}'
                  : 'Device not connected — Tap Connect to begin',
              style: TextStyle(
                color: isConnected ? AppColors.homeSuccess : AppColors.homeWarning,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (isConnected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.homeSuccess.withAlpha(38),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'LIVE',
                style: TextStyle(
                  color: AppColors.homeSuccess,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Quick Actions Row
// ═══════════════════════════════════════════════════════════════

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({required this.onConnect, required this.onSettings});

  final VoidCallback onConnect;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _QuickActionCard(
            icon: Icons.bluetooth_searching_rounded,
            label: 'Connect Device',
            subtitle: 'Scan & pair',
            color: AppColors.homePrimary,
            onTap: onConnect,
            primary: true,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: _QuickActionCard(
            icon: Icons.tune_rounded,
            label: 'Settings',
            subtitle: 'Configure',
            color: AppColors.homeInfo,
            onTap: onSettings,
          ),
        ),
      ],
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
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool primary;

  @override
  State<_QuickActionCard> createState() => _QuickActionCardState();
}

class _QuickActionCardState extends State<_QuickActionCard>
    with SingleTickerProviderStateMixin {
  // ignore: unused_field
  bool _isPressed = false;
  late AnimationController _pressController;
  late Animation<double> _pressAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _pressAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
        _pressController.forward();
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        _pressController.reverse();
        widget.onTap();
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
        _pressController.reverse();
      },
      child: AnimatedBuilder(
        animation: _pressAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _pressAnimation.value,
            child: Container(
              padding: EdgeInsets.all(widget.primary ? 16 : 14),
              decoration: BoxDecoration(
                color: widget.primary
                    ? widget.color.withAlpha(242)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: widget.primary
                    ? null
                    : Border.all(color: AppColors.homeBorder),
                boxShadow: [
                  BoxShadow(
                    color: widget.primary
                        ? widget.color.withAlpha(77)
                        : AppColors.shadowLight,
                    blurRadius: widget.primary ? 12 : 6,
                    offset: Offset(0, widget.primary ? 6 : 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: widget.primary ? 44 : 36,
                    height: widget.primary ? 44 : 36,
                    decoration: BoxDecoration(
                      color: widget.primary
                          ? Colors.white.withAlpha(51)
                          : widget.color.withAlpha(26),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      widget.icon,
                      color: widget.primary ? Colors.white : widget.color,
                      size: widget.primary ? 24 : 20,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.primary
                          ? Colors.white
                          : AppColors.lightText,
                      fontSize: widget.primary ? 14 : 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle,
                    style: TextStyle(
                      color: widget.primary
                          ? Colors.white.withAlpha(204)
                          : AppColors.lightTextMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Enhanced Connection Card
// ═══════════════════════════════════════════════════════════════

// class _EnhancedConnectionCard extends StatelessWidget {
//   const _EnhancedConnectionCard({
//     required this.controller,
//     required this.pulseAnimation,
//   });

//   final CraneController controller;
//   final Animation<double> pulseAnimation;

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: AppColors.surface,
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: AppColors.homeBorder),
//         boxShadow: [
//           const BoxShadow(
//             color: AppColors.shadowLight,
//             blurRadius: 8,
//             offset: Offset(0, 2),
//           ),
//         ],
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           // Title row
//           Row(
//             children: [
//               const Icon(
//                 Icons.bluetooth_rounded,
//                 color: AppColors.homePrimary,
//                 size: 18,
//               ),
//               const SizedBox(width: 8),
//               const Text(
//                 'Connection Status',
//                 style: TextStyle(
//                   color: AppColors.lightText,
//                   fontSize: 14,
//                   fontWeight: FontWeight.w700,
//                 ),
//               ),
//               const Spacer(),
//               if (controller.isConnected)
//                 AnimatedBuilder(
//                   animation: pulseAnimation,
//                   builder: (context, child) {
//                     return Container(
//                       width: 10,
//                       height: 10,
//                       decoration: BoxDecoration(
//                         color: AppColors.homeSuccess.withAlpha(
//                           (pulseAnimation.value * 255).toInt(),
//                         ),
//                         shape: BoxShape.circle,
//                       ),
//                     );
//                   },
//                 ),
//             ],
//           ),
//           const SizedBox(height: 14),
//           // Device info
//           Row(
//             children: [
//               Container(
//                 width: 52,
//                 height: 52,
//                 decoration: BoxDecoration(
//                   color: controller.isConnected
//                       ? AppColors.homeSuccessLight
//                       : AppColors.homeSurfaceAlt,
//                   borderRadius: BorderRadius.circular(14),
//                 ),
//                 child: Icon(
//                   controller.isConnected
//                       ? Icons.bluetooth_connected_rounded
//                       : Icons.bluetooth_rounded,
//                   color: controller.isConnected
//                       ? AppColors.homeSuccess
//                       : AppColors.lightTextMuted,
//                   size: 28,
//                 ),
//               ),
//               const SizedBox(width: 14),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       controller.isConnected
//                           ? controller.connectedDeviceName ?? 'PLC14_BLE'
//                           : 'No Device Connected',
//                       style: const TextStyle(
//                         color: AppColors.lightText,
//                         fontSize: 15,
//                         fontWeight: FontWeight.w700,
//                       ),
//                     ),
//                     const SizedBox(height: 3),
//                     Text(
//                       controller.isConnected
//                           ? 'BLE · Authenticated · ${BLEConstants.serviceUuid.substring(0, 8)}...'
//                           : 'Tap Connect to scan for PLC14',
//                       style: const TextStyle(
//                         color: AppColors.lightTextSub,
//                         fontSize: 11,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 14),
//           // Progress bar for connection state
//           if (controller.isConnecting || controller.isScanning)
//             Padding(
//               padding: const EdgeInsets.only(bottom: 12),
//               child: ClipRRect(
//                 borderRadius: BorderRadius.circular(3),
//                 child: const LinearProgressIndicator(
//                   minHeight: 3,
//                   backgroundColor: AppColors.homeSurfaceAlt,
//                   valueColor: AlwaysStoppedAnimation<Color>(
//                     AppColors.homePrimary,
//                   ),
//                 ),
//               ),
//             ),
//           // Action button
//           SizedBox(
//             width: double.infinity,
//             child: ElevatedButton.icon(
//               onPressed: controller.isConnected
//                   ? null
//                   : () {
//                       HapticFeedback.mediumImpact();
//                       Navigator.of(context).pushNamed('/crane');
//                     },
//               icon: Icon(
//                 controller.isConnected
//                     ? Icons.check_rounded
//                     : Icons.bluetooth_rounded,
//                 size: 18,
//               ),
//               label: Text(
//                 controller.isConnected ? 'Connected' : 'Connect to Device',
//                 style: const TextStyle(fontWeight: FontWeight.w600),
//               ),
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: controller.isConnected
//                     ? AppColors.homeSuccess
//                     : AppColors.homePrimary,
//                 foregroundColor: Colors.white,
//                 disabledBackgroundColor: AppColors.homeSuccess.withAlpha(204),
//                 disabledForegroundColor: Colors.white,
//                 padding: const EdgeInsets.symmetric(vertical: 14),
//                 shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 elevation: 0,
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// ═══════════════════════════════════════════════════════════════
// System Health Grid
// ═══════════════════════════════════════════════════════════════

class _SystemHealthGrid extends StatelessWidget {
  const _SystemHealthGrid({required this.controller});

  final CraneController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(
            'SYSTEM HEALTH',
            style: TextStyle(
              color: AppColors.lightTextMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _HealthCard(
                icon: Icons.bluetooth_rounded,
                label: 'Bluetooth',
                value: controller.bluetoothReady ? 'Ready' : 'Disabled',
                status: controller.bluetoothReady ? 'good' : 'error',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _HealthCard(
                icon: Icons.security_rounded,
                label: 'Permissions',
                value: controller.permissionsGranted ? 'Granted' : 'Missing',
                status: controller.permissionsGranted ? 'good' : 'warning',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _HealthCard(
                icon: Icons.verified_user_rounded,
                label: 'Auth',
                value: controller.isAuthenticated ? 'Active' : 'Idle',
                status: controller.isAuthenticated ? 'good' : 'neutral',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.status,
  });

  final IconData icon;
  final String label;
  final String value;
  final String status; // 'good', 'warning', 'error', 'neutral'

  Color get _statusColor {
    switch (status) {
      case 'good':
        return AppColors.homeSuccess;
      case 'warning':
        return AppColors.homeWarning;
      case 'error':
        return AppColors.homeDanger;
      default:
        return AppColors.lightTextMuted;
    }
  }

  Color get _statusBg {
    switch (status) {
      case 'good':
        return AppColors.homeSuccessLight;
      case 'warning':
        return AppColors.homeWarningLight;
      case 'error':
        return AppColors.homeDangerLight;
      default:
        return AppColors.homeSurfaceAlt;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.homeBorder),
      ),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _statusBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _statusColor, size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.lightTextSub,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _statusBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: _statusColor,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Recent Activity Card
// ═══════════════════════════════════════════════════════════════

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard({required this.controller});

  final CraneController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.homeBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.history_rounded,
                size: 16,
                color: AppColors.lightTextMuted,
              ),
              SizedBox(width: 6),
              Text(
                'DEVICE INFORMATION',
                style: TextStyle(
                  color: AppColors.lightTextMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.homePrimaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.developer_board_rounded,
                  color: AppColors.homePrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.connectedDeviceName ?? BLEConstants.deviceName,
                      style: const TextStyle(
                        color: AppColors.lightText,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Service: ${BLEConstants.serviceUuid}',
                      style: TextStyle(
                        color: AppColors.lightTextMuted,
                        fontSize: 9,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.lightTextMuted,
                size: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
