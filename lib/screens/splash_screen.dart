import 'dart:async';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:rev6_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev6_crane_control_ops/startup/app_startup_initializer.dart';

class StartupSplashScreen extends StatefulWidget {
  const StartupSplashScreen({required this.destinationBuilder, super.key});

  final WidgetBuilder destinationBuilder;

  @override
  State<StartupSplashScreen> createState() => _StartupSplashScreenState();
}

class _StartupSplashScreenState extends State<StartupSplashScreen>
    with SingleTickerProviderStateMixin {
  static const Color _background = Colors.white;
  // static const Color _textPrimary = Color(0xFF2E3180);
  static const Color _textSecondary = Color(0xFF5C6470);
  static const Duration _minimumVisible = Duration(seconds: 3);

  late final AnimationController _introController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  late final Stopwatch _startupClock;

  bool _isStarting = false;
  Object? _startupError;
  String _statusMessage = 'Preparing secure runtime';

  @override
  void initState() {
    super.initState();
    _startupClock = Stopwatch()..start();

    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    )..forward();
    _fadeAnimation = CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOutCubic,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.96,
      end: 1.0,
    ).animate(_fadeAnimation);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      unawaited(_startInitialization());
    });
  }

  @override
  void dispose() {
    _introController.dispose();
    super.dispose();
  }

  Future<void> _startInitialization() async {
    if (_isStarting) return;

    setState(() {
      _isStarting = true;
      _startupError = null;
    });

    final controller = context.read<CraneController>();
    final initializer = AppStartupInitializer(controller: controller);

    try {
      await initializer.initialize(onProgress: _onProgressUpdate);

      final remaining = _minimumVisible - _startupClock.elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          settings: const RouteSettings(name: '/connection'),
          transitionDuration: const Duration(milliseconds: 560),
          reverseTransitionDuration: const Duration(milliseconds: 380),
          pageBuilder: (routeContext, _, _) {
            return widget.destinationBuilder(routeContext);
          },
          transitionsBuilder: (_, animation, _, child) {
            final curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOutCubic,
              reverseCurve: Curves.easeInOutCubic,
            );
            final offsetAnimation = Tween<Offset>(
              begin: const Offset(0, 0.012),
              end: Offset.zero,
            ).animate(curvedAnimation);
            return FadeTransition(
              opacity: curvedAnimation,
              child: SlideTransition(position: offsetAnimation, child: child),
            );
          },
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _startupError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  void _onProgressUpdate(String message) {
    if (!mounted) return;
    setState(() {
      _statusMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/images/Intellicontrol Final Logo300PPI.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                    // const SizedBox(height: 28),
                    // const Text(
                    //   'INTELLICONTROL',
                    //   textAlign: TextAlign.center,
                    //   style: TextStyle(
                    //     color: _textPrimary,
                    //     fontSize: 24,
                    //     fontWeight: FontWeight.w800,
                    //     letterSpacing: 2.4,
                    //   ),
                    // ),
                    const SizedBox(height: 8),
                    const Text(
                      'Industrial Crane Control System',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 28),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _startupError == null
                          ? _StartupStatus(message: _statusMessage)
                          : _StartupError(
                              message:
                                  'Startup checks could not complete. Retry initialization.',
                              onRetry: _isStarting
                                  ? null
                                  : () {
                                      unawaited(_startInitialization());
                                    },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupStatus extends StatelessWidget {
  const _StartupStatus({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('status'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD5DDE8)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: Color(0xFF2E3180),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF5C6470),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('error'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF1C6C6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 18,
                color: Color(0xFFB93D3D),
              ),
              SizedBox(width: 8),
              Text(
                'Initialization Attention',
                style: TextStyle(
                  color: Color(0xFFB93D3D),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFF5C6470),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2E3180),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Retry Startup',
              style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}
