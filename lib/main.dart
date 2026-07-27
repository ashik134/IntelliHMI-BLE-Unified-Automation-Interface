import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/app_theme.dart';
import 'package:rev_crane_control_ops/utils/device_type.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';

import 'package:rev_crane_control_ops/screens/home_screen.dart';
import 'package:rev_crane_control_ops/screens/login_screen.dart';
import 'package:rev_crane_control_ops/screens/splash_screen.dart';
import 'package:rev_crane_control_ops/screens/plc14_control_screen.dart';
import 'package:rev_crane_control_ops/screens/scan_page.dart';
import 'package:rev_crane_control_ops/screens/plc38_control_screen.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/customization_mode_controller.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev_crane_control_ops/controllers/navigation_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _applyOrientationPolicy();
  runApp(const IntelliHMIApp());
}

/// Locks phones to portrait; tablets are left free to follow the sensor.
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

class IntelliHMIApp extends StatelessWidget {
  const IntelliHMIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CraneController()),
        ChangeNotifierProvider(create: (_) => LayoutSettingsController()),
        ChangeNotifierProvider(create: (_) => NavigationController()),
        ChangeNotifierProxyProvider2<
          CraneController,
          LayoutSettingsController,
          CustomizationModeController
        >(
          create: (ctx) => CustomizationModeController(
            layoutSettings: ctx.read<LayoutSettingsController>(),
            craneController: ctx.read<CraneController>(),
          ),
          // The controller holds direct references it was constructed with
          // rather than derived state, so no recomputation is needed when
          // its dependencies rebuild.
          update: (ctx, crane, layout, previous) => previous!,
        ),
      ],
      child: MaterialApp(
        title: AppConstants.appTitle,
        theme: AppTheme.theme,
        debugShowCheckedModeBanner: false,
        home: StartupSplashScreen(destinationBuilder: (_) => const MainShell()),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// MainShell — persistent scaffold with Bottom Navigation Bar
// ═══════════════════════════════════════════════════════════════
class MainShell extends StatelessWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context) {
    final navController = context.watch<NavigationController>();
    final currentIndex = navController.currentIndex;

    return Scaffold(
      backgroundColor: AppColors.homeBg,
      bottomNavigationBar: _IndustrialBottomNav(
        currentIndex: currentIndex,
        onTap: (i) {
          HapticFeedback.selectionClick();
          navController.navigateTo(i);
        },
      ),

      body: IndexedStack(
        index: currentIndex,
        children: const [
          HomeScreen(),
          _ControlTab(),
          _PlaceholderTab(
            icon: Icons.monitor_heart_outlined,
            title: 'Diagnostics',
            subtitle: 'System health monitoring — coming soon',
          ),
          _PlaceholderTab(
            icon: Icons.receipt_long_outlined,
            title: 'Event Logs',
            subtitle: 'Activity history — coming soon',
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// _ControlTab — Control workflow navigator
// ═══════════════════════════════════════════════════════════════

class _ControlTab extends StatefulWidget {
  const _ControlTab();

  @override
  State<_ControlTab> createState() => _ControlTabState();
}

class _ControlTabState extends State<_ControlTab> {
  CraneController? _controllerRef;

  bool _subShellPushed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<CraneController>();
    if (_controllerRef != controller) {
      _controllerRef?.removeListener(_onControllerChanged);
      _controllerRef = controller;
      controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _controllerRef?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    // This fires synchronously from CraneController.notifyListeners(), which
    // can happen at any point in a BLE callback chain — including mid-frame,
    // while this element's ancestor chain (Provider/Navigator) is itself
    // transitioning. `mounted` only means "not yet disposed"; it does not
    // guarantee the element is safe to use for ancestor lookups right now.
    // So every context-dependent call below is deferred to a post-frame
    // callback, each re-checking `mounted` immediately before use, rather
    // than trusting a `mounted` check taken earlier in the same tick.
    if (!mounted) return;
    final screen = _controllerRef!.currentScreen;

    if (screen != AppScreen.connection && !_subShellPushed) {
      _subShellPushed = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_controllerRef!.currentScreen == AppScreen.connection) {
          _subShellPushed = false;
          return;
        }
        context.read<NavigationController>().navigateToControl();
        Navigator.of(
          context,
          rootNavigator: true,
        ).push<void>(_buildSubShellRoute()).then((_) {
          if (mounted) _subShellPushed = false;
        });
      });
    } else if (screen == AppScreen.connection && _subShellPushed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_subShellPushed) return;
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) nav.pop();
      });
    }
  }

  PageRouteBuilder<void> _buildSubShellRoute() {
    return PageRouteBuilder<void>(
      opaque: true,
      pageBuilder: (context, animation, secondaryAnimation) =>
          const _ControlSubShell(),
      transitionsBuilder: (context, animation, _, child) {
        final offset =
            Tween<Offset>(
              begin: const Offset(0.025, 0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => const ScanScreen();
}

// ═══════════════════════════════════════════════════════════════
// _ControlSubShell — auth / control screen host (no bottom nav)
// ═══════════════════════════════════════════════════════════════

class _ControlSubShell extends StatelessWidget {
  const _ControlSubShell();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Consumer<CraneController>(
        builder: (context, controller, _) {
          final screen = controller.currentScreen;
          final destination = switch (screen) {
            AppScreen.authentication => const LoginScreen(),
            AppScreen.control => const ControlScreen(),
            AppScreen.plc38Control => const Plc38ControlScreen(),
            AppScreen.connection => const SizedBox.shrink(),
          };
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            reverseDuration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final offset =
                  Tween<Offset>(
                    begin: const Offset(0.025, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  );
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: offset, child: child),
              );
            },
            child: KeyedSubtree(key: ValueKey(screen), child: destination),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// _IndustrialBottomNav — 4-tab bottom navigation bar
// ═══════════════════════════════════════════════════════════════

class _IndustrialBottomNav extends StatelessWidget {
  const _IndustrialBottomNav({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final void Function(int) onTap;

  static const _tabs = [
    (icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home'),
    (
      icon: Icons.tune_outlined,
      activeIcon: Icons.tune_rounded,
      label: 'Control',
    ),
    (
      icon: Icons.monitor_heart_outlined,
      activeIcon: Icons.monitor_heart_rounded,
      label: 'Diagnostics',
    ),
    (
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long_rounded,
      label: 'Logs',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.navBarBg,
        border: Border(
          top: BorderSide(color: AppColors.navBarBorder, width: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowMedium,
            blurRadius: 12,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_tabs.length, (i) {
              final isActive = i == currentIndex;
              return _NavTabItem(
                icon: isActive ? _tabs[i].activeIcon : _tabs[i].icon,
                label: _tabs[i].label,
                isActive: isActive,
                onTap: () => onTap(i),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavTabItem extends StatelessWidget {
  const _NavTabItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.navBarActive.withAlpha(20)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive
                  ? AppColors.navBarActive
                  : AppColors.navBarInactive,
              size: 22,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? AppColors.navBarActive
                    : AppColors.navBarInactive,
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// _PlaceholderTab — coming-soon placeholder for unbuilt tabs
// ═══════════════════════════════════════════════════════════════

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.homeBg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.lightTextMuted.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.lightTextMuted, size: 44),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.lightText,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.lightTextMuted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
