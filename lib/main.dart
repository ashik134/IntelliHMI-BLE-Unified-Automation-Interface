import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/app_theme.dart';

import 'package:rev_crane_control_ops/screens/home_screen.dart';
import 'package:rev_crane_control_ops/screens/login_screen.dart';
import 'package:rev_crane_control_ops/screens/splash_screen.dart';
import 'package:rev_crane_control_ops/screens/control_screen.dart';
import 'package:rev_crane_control_ops/screens/connection_screen.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CraneControlApp());
}

class CraneControlApp extends StatelessWidget {
  const CraneControlApp({super.key});

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
          '/crane': (_) => const CraneAppShell(),
        },
      ),
    );
  }
}

class CraneAppShell extends StatelessWidget {
  const CraneAppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CraneController>(
      builder: (context, controller, _) {
        final currentScreen = controller.currentScreen;
        final destination = switch (currentScreen) {
          AppScreen.connection => const ConnectionScreen(),
          AppScreen.authentication => const LoginScreen(),
          AppScreen.control => const ControlScreen(),
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
