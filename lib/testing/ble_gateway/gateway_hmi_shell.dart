import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/customization_mode_controller.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev_crane_control_ops/controllers/navigation_controller.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/screens/connection_screen.dart';
import 'package:rev_crane_control_ops/screens/home_screen.dart';
import 'package:rev_crane_control_ops/screens/login_screen.dart';
import 'package:rev_crane_control_ops/screens/plc14_control_screen.dart';
import 'package:rev_crane_control_ops/screens/plc38_control_screen.dart';
import 'package:rev_crane_control_ops/startup/app_startup_initializer.dart';
import 'package:rev_crane_control_ops/testing/ble_gateway/remote_ble_transport.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';

class GatewayRemoteHmiApp extends StatelessWidget {
  const GatewayRemoteHmiApp({required this.transport, super.key});

  final RemoteBleTransport transport;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => CraneController(bleTransport: transport),
        ),
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
          update: (ctx, crane, layout, previous) => previous!,
        ),
      ],
      child: Navigator(
        onGenerateRoute: (settings) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const _GatewayStartupGate(),
          );
        },
      ),
    );
  }
}

class _GatewayStartupGate extends StatefulWidget {
  const _GatewayStartupGate();

  @override
  State<_GatewayStartupGate> createState() => _GatewayStartupGateState();
}

class _GatewayStartupGateState extends State<_GatewayStartupGate> {
  bool _ready = false;
  bool _starting = false;
  Object? _error;
  String _message = 'Preparing remote BLE HMI';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _start();
      }
    });
  }

  Future<void> _start() async {
    if (_starting) {
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
    });

    try {
      await AppStartupInitializer(
        controller: context.read<CraneController>(),
      ).initialize(onProgress: (message) {
        if (mounted) {
          setState(() => _message = message);
        }
      });
      if (mounted) {
        setState(() => _ready = true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted) {
        setState(() => _starting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return const GatewayHmiShell();
    }

    return Scaffold(
      backgroundColor: AppColors.brandBg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/Intellicontrol Final Logo300PPI.png',
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 18),
                Text(
                  _error == null ? _message : 'Remote startup failed',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.brandText,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                if (_error == null)
                  const CircularProgressIndicator(
                    color: AppColors.brandViolet,
                    strokeWidth: 2.5,
                  )
                else
                  FilledButton.icon(
                    onPressed: _starting ? null : _start,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Retry'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GatewayHmiShell extends StatelessWidget {
  const GatewayHmiShell({super.key});

  @override
  Widget build(BuildContext context) {
    final navController = context.watch<NavigationController>();
    final currentIndex = navController.currentIndex;

    return Scaffold(
      backgroundColor: AppColors.homeBg,
      bottomNavigationBar: _GatewayBottomNav(
        currentIndex: currentIndex,
        onTap: (index) {
          HapticFeedback.selectionClick();
          navController.navigateTo(index);
        },
      ),
      body: IndexedStack(
        index: currentIndex,
        children: const [
          HomeScreen(),
          _GatewayControlTab(),
          _GatewayPlaceholderTab(
            icon: Icons.monitor_heart_outlined,
            title: 'Diagnostics',
            subtitle: 'System health monitoring - coming soon',
          ),
          _GatewayPlaceholderTab(
            icon: Icons.receipt_long_outlined,
            title: 'Event Logs',
            subtitle: 'Activity history - coming soon',
          ),
        ],
      ),
    );
  }
}

class _GatewayControlTab extends StatefulWidget {
  const _GatewayControlTab();

  @override
  State<_GatewayControlTab> createState() => _GatewayControlTabState();
}

class _GatewayControlTabState extends State<_GatewayControlTab> {
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
    if (!mounted) {
      return;
    }

    final screen = _controllerRef!.currentScreen;
    if (screen != AppScreen.connection && !_subShellPushed) {
      _subShellPushed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        if (_controllerRef!.currentScreen == AppScreen.connection) {
          _subShellPushed = false;
          return;
        }
        context.read<NavigationController>().navigateToControl();
        Navigator.of(
          context,
        ).push<void>(_buildSubShellRoute(context)).then((_) {
          if (mounted) {
            _subShellPushed = false;
          }
        });
      });
    } else if (screen == AppScreen.connection && _subShellPushed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_subShellPushed) {
          return;
        }
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.pop();
        }
      });
    }
  }

  PageRouteBuilder<void> _buildSubShellRoute(BuildContext providerContext) {
    final craneController = providerContext.read<CraneController>();
    final layoutSettings = providerContext.read<LayoutSettingsController>();
    final navigationController = providerContext.read<NavigationController>();
    final customizationMode = providerContext
        .read<CustomizationModeController>();

    return PageRouteBuilder<void>(
      opaque: true,
      pageBuilder: (context, animation, secondaryAnimation) => MultiProvider(
        providers: [
          ChangeNotifierProvider<CraneController>.value(
            value: craneController,
          ),
          ChangeNotifierProvider<LayoutSettingsController>.value(
            value: layoutSettings,
          ),
          ChangeNotifierProvider<NavigationController>.value(
            value: navigationController,
          ),
          ChangeNotifierProvider<CustomizationModeController>.value(
            value: customizationMode,
          ),
        ],
        child: const _GatewayControlSubShell(),
      ),
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
  Widget build(BuildContext context) => const ConnectionScreen();
}

class _GatewayControlSubShell extends StatelessWidget {
  const _GatewayControlSubShell();

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

class _GatewayBottomNav extends StatelessWidget {
  const _GatewayBottomNav({
    required this.currentIndex,
    required this.onTap,
  });

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
            children: List.generate(_tabs.length, (index) {
              final isActive = index == currentIndex;
              return _GatewayNavTabItem(
                icon: isActive
                    ? _tabs[index].activeIcon
                    : _tabs[index].icon,
                label: _tabs[index].label,
                isActive: isActive,
                onTap: () => onTap(index),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _GatewayNavTabItem extends StatelessWidget {
  const _GatewayNavTabItem({
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
          borderRadius: BorderRadius.circular(8),
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

class _GatewayPlaceholderTab extends StatelessWidget {
  const _GatewayPlaceholderTab({
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
