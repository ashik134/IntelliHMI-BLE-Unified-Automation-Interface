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
import 'package:rev_crane_control_ops/screens/connection_screen.dart';
import 'package:rev_crane_control_ops/screens/plc38_control_screen.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _applyOrientationPolicy();
  runApp(const IntelliHMIApp());
}

/// Locks phones to portrait; tablets are left free to follow the sensor.
Future<void> _applyOrientationPolicy() async {
  final orientations =
      DeviceType.isTablet
          ? [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]
          : [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ];

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
      ],
      child: MaterialApp(
        title: AppConstants.appTitle,
        theme: AppTheme.theme,
        debugShowCheckedModeBanner: false,
        home: StartupSplashScreen(
          destinationBuilder: (_) => const HomeScreen(),
        ),
        routes: {
          '/home': (_) => const HomeScreen(),
          '/crane': (_) => const HMIAppShell(),
        },
      ),
    );
  }
}

class HMIAppShell extends StatelessWidget {
  const HMIAppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CraneController>(
      builder: (context, controller, _) {
        final currentScreen = controller.currentScreen;
        final destination = switch (currentScreen) {
          AppScreen.connection => const ConnectionScreen(),
          AppScreen.authentication => const LoginScreen(),
          AppScreen.control => const ControlScreen(),
          AppScreen.plc38Control => const Plc38ControlScreen(),
        };

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          reverseDuration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final offsetAnimation =
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
              child: SlideTransition(position: offsetAnimation, child: child),
            );
          },
          child: KeyedSubtree(key: ValueKey(currentScreen), child: destination),
        );
      },
    );
  }
}
