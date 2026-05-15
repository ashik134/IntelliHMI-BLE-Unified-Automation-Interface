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
    with TickerProviderStateMixin {
  static const Color _backgroundBase = Color(0xFF031A2D);
  static const Color _textSecondary = Color(0xFFAFC1D5);
  static const Duration _minimumVisible = Duration(seconds: 3);

  late final AnimationController _introController;
  late final AnimationController _ambientController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _ambientAnimation;
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
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();
    _ambientAnimation = CurvedAnimation(
      parent: _ambientController,
      curve: Curves.linear,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      unawaited(_startInitialization());
    });
  }

  @override
  void dispose() {
    _introController.dispose();
    _ambientController.dispose();
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
      backgroundColor: _backgroundBase,
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF092540),
                    Color(0xFF031A2D),
                    Color(0xFF020F1B),
                  ],
                  stops: [0.0, 0.54, 1.0],
                ),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _ambientAnimation,
            builder: (context, child) {
              final phase = _ambientAnimation.value;
              return Stack(
                children: [
                  Positioned(
                    top: -120 + (phase * 36),
                    right: -74 + (phase * 24),
                    child: child!,
                  ),
                  Positioned(
                    left: -106 + (phase * 30),
                    bottom: -152 + (phase * 38),
                    child: child,
                  ),
                ],
              );
            },
            child: Container(
              width: 330,
              height: 330,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x22DFA14B), Color(0x00DFA14B)],
                ),
              ),
            ),
          ),
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                      decoration: BoxDecoration(
                        color: const Color(0xC9182F46),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: const Color(0x3FFFFFFF)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x6E020A12),
                            blurRadius: 34,
                            offset: Offset(0, 20),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _BrandChip(),
                          const SizedBox(height: 18),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0x66FFFFFF),
                                ),
                              ),
                              child: Image.asset(
                                'assets/images/splash_tusker.jpeg',
                                height: 172,
                                width: 312,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          const Text(
                            'Crane Remote Control',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.35,
                            ),
                          ),
                          const SizedBox(height: 7),
                          const Text(
                            'Industrial Operations Console',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _textSecondary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 24),
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
          ),
        ],
      ),
    );
  }
}

class _BrandChip extends StatelessWidget {
  const _BrandChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x2ADFA14B),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x4DEDBA77)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.precision_manufacturing_rounded,
            size: 16,
            color: Color(0xFFFFD182),
          ),
          SizedBox(width: 8),
          Text(
            'Tusker Engineering FZC',
            style: TextStyle(
              color: Color(0xFFFFE8C6),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.35,
            ),
          ),
        ],
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
        color: const Color(0x33132234),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x4DFFFFFF)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: Color(0xFFFFCD79),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFD4DEEB),
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
        color: const Color(0x66FF5B5B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x80FFC0C0)),
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
                  color: Color(0xFFFFDFDF),
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
              color: Color(0xFFFFECEC),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFFD182),
              foregroundColor: const Color(0xFF1A2230),
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
