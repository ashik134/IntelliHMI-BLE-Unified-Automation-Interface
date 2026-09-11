import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/app_theme.dart';
import 'package:rev_crane_control_ops/utils/device_type.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';

import 'package:rev_crane_control_ops/screens/diagnostics_screen.dart';
import 'package:rev_crane_control_ops/screens/event_log_screen.dart';
import 'package:rev_crane_control_ops/screens/home_screen.dart';
import 'package:rev_crane_control_ops/screens/login_screen.dart';
import 'package:rev_crane_control_ops/screens/operator/face_verification_screen.dart';
import 'package:rev_crane_control_ops/screens/setup_mode_screen.dart';
import 'package:rev_crane_control_ops/screens/splash_screen.dart';
import 'package:rev_crane_control_ops/screens/plc14_control_screen.dart';
import 'package:rev_crane_control_ops/screens/scan_page.dart';
import 'package:rev_crane_control_ops/screens/plc38_control_screen.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/feedback_manager.dart';
import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev_crane_control_ops/controllers/navigation_controller.dart';
import 'package:rev_crane_control_ops/services/auth_audit_log_service.dart';
import 'package:rev_crane_control_ops/services/saved_template_service.dart';


final AuthAuditLogService _authAuditLogService = AuthAuditLogService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  assert(() {
    debugPaintBaselinesEnabled = false;
    return true;
  }());
  await DeviceType.restoreDefaultOrientations();
  runApp(const IntelliHMIApp());
}

class IntelliHMIApp extends StatelessWidget {
  const IntelliHMIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthAuditLogService>.value(value: _authAuditLogService),
        ChangeNotifierProvider(
          create: (_) => CraneController(auditLog: _authAuditLogService),
        ),
        ChangeNotifierProvider(create: (_) => LayoutSettingsController()),
        ChangeNotifierProvider(create: (_) => SavedTemplateService()),
        ChangeNotifierProxyProvider2<
          CraneController,
          LayoutSettingsController,
          LayoutEditController
        >(
          create: (ctx) => LayoutEditController(
            layoutSettings: ctx.read<LayoutSettingsController>(),
            craneController: ctx.read<CraneController>(),
          ),
          update: (ctx, crane, layout, previous) => previous!,
        ),
      
        ChangeNotifierProxyProvider<CraneController, FeedbackManager>(
          create: (ctx) =>
              FeedbackManager(source: ctx.read<CraneController>()),
          update: (ctx, crane, previous) => previous!,
        ),
        ChangeNotifierProvider(create: (_) => NavigationController()),
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
          DiagnosticsScreen(),
          EventLogScreen(),
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
            AppScreen.faceVerification => const FaceVerificationScreen(),
            AppScreen.authentication => const LoginScreen(),
            AppScreen.setupMode => const SetupModeScreen(),
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

