import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/startup/app_startup_initializer.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/widgets/shared/brand_widgets.dart';

/// Full-screen startup surface.
///
/// This is deliberately the Home hero panel (see `home_screen.dart`) blown up
/// to fill the display — same ink gradient, same violet glow, same brand mark
/// — so the hand-off into the app reads as one continuous surface rather than
/// a separate "loading" screen.
///
/// The screen opens white to match the native launch screen configured in
/// `pubspec.yaml`, then powers down into the dark instrument surface while the
/// brand plate settles. That removes the white→dark flash at the native
/// hand-off and turns it into the intro itself.
class StartupSplashScreen extends StatefulWidget {
  const StartupSplashScreen({required this.destinationBuilder, super.key});

  final WidgetBuilder destinationBuilder;

  @override
  State<StartupSplashScreen> createState() => _StartupSplashScreenState();
}

class _StartupSplashScreenState extends State<StartupSplashScreen>
    with TickerProviderStateMixin {
  static const Duration _minimumVisible = Duration(seconds: 3);
  static const Duration _introDuration = Duration(milliseconds: 1400);
  static const Duration _ambientCycle = Duration(milliseconds: 5200);

  /// Deepest tone of the backdrop, below `brandInk` — used for the bottom of
  /// the gradient and for the plate's cast shadow.
  static const Color _inkDeep = Color(0xFF05080F);
  static const Color _inkTop = Color(0xFF161E36);

  /// Drives the one-shot entrance: the iris reveal of the dark surface plus
  /// the staggered arrival of plate → wordmark → tagline → status.
  late final AnimationController _intro;

  /// Free-running loop behind the scan ring and the status pulse.
  late final AnimationController _ambient;

  late final Animation<double> _surface;
  late final Animation<double> _plateIn;
  late final Animation<double> _wordmarkIn;
  late final Animation<double> _taglineIn;
  late final Animation<double> _statusIn;

  late final Stopwatch _startupClock;

  /// Null until the first dependency resolution, so the setting is applied
  /// once up front and again only if it actually changes.
  bool? _reduceMotion;
  bool _isStarting = false;
  Object? _startupError;
  String _statusMessage = 'Preparing secure runtime';
  int _completedSteps = 0;

  @override
  void initState() {
    super.initState();
    _startupClock = Stopwatch()..start();

    _intro = AnimationController(vsync: this, duration: _introDuration);
    _ambient = AnimationController(vsync: this, duration: _ambientCycle);

    _surface = _curve(0.0, 0.46, Curves.easeInOutCubic);
    _plateIn = _curve(0.04, 0.44, Curves.easeOutCubic);
    _wordmarkIn = _curve(0.30, 0.62, Curves.easeOutCubic);
    _taglineIn = _curve(0.40, 0.72, Curves.easeOutCubic);
    _statusIn = _curve(0.55, 0.90, Curves.easeOutCubic);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      unawaited(_startInitialization());
    });
  }

  Animation<double> _curve(double begin, double end, Curve curve) {
    return CurvedAnimation(
      parent: _intro,
      curve: Interval(begin, end, curve: curve),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // "Remove animations" is an OS-level accessibility setting; honour it by
    // showing the finished composition instead of playing the intro, and by
    // parking the ambient loop rather than letting it run forever.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion == _reduceMotion) return;
    _reduceMotion = reduceMotion;

    if (reduceMotion) {
      _intro.value = 1.0;
      _ambient
        ..stop()
        ..value = 0.0;
    } else {
      _intro.forward();
      _ambient.repeat();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _ambient.dispose();
    super.dispose();
  }

  Future<void> _startInitialization() async {
    if (_isStarting) return;

    setState(() {
      _isStarting = true;
      _startupError = null;
      _completedSteps = 0;
      _statusMessage = 'Preparing secure runtime';
    });

    final controller = context.read<CraneController>();
    final initializer = AppStartupInitializer(controller: controller);

    try {
      await initializer.initialize(onProgress: _onProgressUpdate);

      if (mounted) {
        setState(() {
          _completedSteps = AppStartupInitializer.totalSteps;
          _statusMessage = 'System ready';
        });
      }

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
      _completedSteps = math.min(
        _completedSteps + 1,
        AppStartupInitializer.totalSteps,
      );
    });
  }

  /// Fraction of startup completed, derived from the number of progress
  /// callbacks the initializer has emitted — never a synthetic timer.
  double get _progress =>
      (_completedSteps / AppStartupInitializer.totalSteps).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.brandInk,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.brandInk,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_inkTop, AppColors.brandInk, _inkDeep],
              stops: [0.0, 0.52, 1.0],
            ),
          ),
          child: Stack(
            children: [
              const Positioned.fill(child: _Atmosphere()),
              // Sits above the backdrop but below the brand block, so the
              // dark surface irises open from behind the mark.
              Positioned.fill(child: _IrisCurtain(progress: _surface)),
              Positioned.fill(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          final width = constraints.maxWidth;
          final compact = height < 640;
          final spacious = width >= 600 && height >= 620;
          final plateSize = math
              .min(width * 0.30, height * 0.17)
              .clamp(80.0, spacious ? 148.0 : 132.0);

          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppMetrics.space2xl,
              vertical: compact ? AppMetrics.spaceLg : AppMetrics.space2xl,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: spacious ? 520 : 460),
                child: Column(
                  children: [
                    Expanded(
                      // Biased just below the centre of the free space: the
                      // native launch screen centres the mark on the full
                      // display, so sitting lower shortens the jump at the
                      // hand-off.
                      child: Align(
                        alignment: const Alignment(0, 0.10),
                        child: _buildIdentity(
                          plateSize: plateSize,
                          compact: compact,
                          spacious: spacious,
                        ),
                      ),
                    ),
                    _buildStatusArea(compact: compact),
                    SizedBox(height: compact ? 16 : 22),
                    _buildFooter(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildIdentity({
    required double plateSize,
    required bool compact,
    required bool spacious,
  }) {
    final wordmarkSize = compact
        ? 22.0
        : spacious
        ? 31.0
        : 27.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Deliberately not faded in: the native launch screen has just shown
        // this mark, so it must already be on screen at the first frame and
        // only settle into place.
        AnimatedBuilder(
          animation: _plateIn,
          builder: (context, child) => Transform.scale(
            scale: 0.96 + 0.04 * _plateIn.value,
            child: child,
          ),
          child: _BrandPlate(
            size: plateSize,
            ring: _ambient,
            surface: _surface,
          ),
        ),
        SizedBox(height: compact ? 24 : 32),
        _StaggerIn(
          animation: _wordmarkIn,
          child: _Wordmark(fontSize: wordmarkSize),
        ),
        SizedBox(height: compact ? 12 : 16),
        _StaggerIn(
          animation: _taglineIn,
          offsetY: 10,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _AccentRule(),
              SizedBox(height: compact ? 10 : 14),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'INDUSTRIAL CRANE CONTROL SYSTEM',
                  style: TextStyle(
                    color: AppColors.brandOnDarkSub,
                    fontSize: compact ? 9.5 : 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.6,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusArea({required bool compact}) {
    return _StaggerIn(
      animation: _statusIn,
      offsetY: 12,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _startupError == null
            ? _StartupStatus(
                key: const ValueKey('status'),
                message: _statusMessage,
                progress: _progress,
                pulse: _ambient,
                compact: compact,
              )
            : _StartupError(
                key: const ValueKey('error'),
                message:
                    'Startup checks could not complete. Retry initialization '
                    'to bring the control runtime online.',
                busy: _isStarting,
                onRetry: _isStarting
                    ? null
                    : () {
                        unawaited(_startInitialization());
                      },
              ),
      ),
    );
  }

  Widget _buildFooter() {
    return _StaggerIn(
      animation: _statusIn,
      offsetY: 8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 1, color: Colors.white.withValues(alpha: 0.06)),
          const SizedBox(height: AppMetrics.spaceMd),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('BY INTELLICONTROL', style: _footerStyle),
              Text('v${AppConstants.appVersion}', style: _footerStyle),
            ],
          ),
        ],
      ),
    );
  }

  static final TextStyle _footerStyle = TextStyle(
    color: AppColors.brandOnDarkSub.withValues(alpha: 0.55),
    fontSize: 9.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.6,
  );
}

// ═══════════════════════════════════════════════════════════════════════
// Backdrop
// ═══════════════════════════════════════════════════════════════════════

/// Violet glow orbs plus the fine engineering grid. Static — the iris curtain
/// above it is what brings the atmosphere into view.
class _Atmosphere extends StatelessWidget {
  const _Atmosphere();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _BlueprintGridPainter())),
          Positioned(
            top: -120,
            right: -100,
            child: _GlowOrb(size: 320, color: Color(0x338B5CF6)),
          ),
          Positioned(
            bottom: -140,
            left: -90,
            child: _GlowOrb(size: 300, color: Color(0x218B5CF6)),
          ),
          Positioned(
            bottom: -70,
            right: -60,
            child: _GlowOrb(size: 220, color: Color(0x0FFFB000)),
          ),
        ],
      ),
    );
  }
}

/// The startup reveal: the screen opens white — matching the native launch
/// screen — and the dark instrument surface irises open from behind the brand
/// mark. Every pixel is either white or fully dark at any instant, so the
/// transition never washes through a flat grey the way a cross-fade would.
class _IrisCurtain extends StatelessWidget {
  const _IrisCurtain({required this.progress});

  final Animation<double> progress;

  /// Roughly where the brand plate sits, as a fraction of the usable height.
  static const Alignment origin = Alignment(0, -0.19);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: progress,
        builder: (context, _) {
          if (progress.value >= 1) return const SizedBox.shrink();
          return CustomPaint(painter: _IrisPainter(progress: progress.value));
        },
      ),
    );
  }
}

class _IrisPainter extends CustomPainter {
  const _IrisPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1) return;

    final origin = _IrisCurtain.origin.alongSize(size);
    var maxRadius = 0.0;
    for (final corner in [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ]) {
      maxRadius = math.max(maxRadius, (corner - origin).distance);
    }
    final radius = maxRadius * progress;

    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addOval(Rect.fromCircle(center: origin, radius: radius)),
      ),
      Paint()..color = Colors.white,
    );

    // Warm wavefront on the leading edge — the surface reads as energising
    // rather than simply uncovering.
    canvas.drawCircle(
      origin,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.accent.withValues(alpha: 0.30 * (1 - progress)),
    );
  }

  @override
  bool shouldRepaint(covariant _IrisPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
          stops: const [0.0, 1.0],
        ),
      ),
    );
  }
}

/// Fine instrument grid, faded top and bottom so it never competes with the
/// brand block sitting on top of it.
class _BlueprintGridPainter extends CustomPainter {
  const _BlueprintGridPainter();

  static const double _cell = 34;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x00FFFFFF),
          Color(0x0EFFFFFF),
          Color(0x05FFFFFF),
          Color(0x00FFFFFF),
        ],
        stops: [0.0, 0.34, 0.74, 1.0],
      ).createShader(Offset.zero & size);

    for (double x = 0; x <= size.width; x += _cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += _cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BlueprintGridPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════
// Brand identity block
// ═══════════════════════════════════════════════════════════════════════

/// The logo mark on a white nameplate, ringed by a slow amber scan arc.
///
/// The plate is pure white because the mark asset is itself drawn on white —
/// the two merge seamlessly, so the brand renders exactly as supplied instead
/// of being recoloured or knocked out.
class _BrandPlate extends StatelessWidget {
  const _BrandPlate({
    required this.size,
    required this.ring,
    required this.surface,
  });

  final double size;
  final Animation<double> ring;
  final Animation<double> surface;

  /// The mark occupies ~56% of the source asset; scaling it up crops the
  /// asset's own padding so it sits confidently inside the plate.
  static const double _markScale = 1.32;

  /// The mark's optical centre sits ~2% above the asset's centre.
  static const double _markOffsetY = 0.024;

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final box = size * 1.72;
    final radius = BorderRadius.circular(size * 0.27);

    return SizedBox(
      width: box,
      height: box,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: surface,
            builder: (context, _) => _GlowOrb(
              size: box,
              color: AppColors.brandViolet.withValues(
                alpha: 0.30 * surface.value,
              ),
            ),
          ),
          AnimatedBuilder(
            animation: Listenable.merge([ring, surface]),
            builder: (context, _) => CustomPaint(
              size: Size.square(box * 0.88),
              painter: _ScanRingPainter(
                rotation: ring.value,
                opacity: surface.value,
              ),
            ),
          ),
          AnimatedBuilder(
            animation: surface,
            builder: (context, child) {
              final t = surface.value;
              return Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: radius,
                  boxShadow: [
                    BoxShadow(
                      color: _StartupSplashScreenState._inkDeep.withValues(
                        alpha: 0.55 * t,
                      ),
                      blurRadius: 32,
                      offset: const Offset(0, 14),
                    ),
                    BoxShadow(
                      color: AppColors.brandViolet.withValues(alpha: 0.28 * t),
                      blurRadius: 44,
                      spreadRadius: -8,
                    ),
                  ],
                ),
                child: ClipRRect(borderRadius: radius, child: child),
              );
            },
            child: Transform.translate(
              offset: Offset(0, size * _markOffsetY),
              child: Transform.scale(
                scale: _markScale,
                child: Image.asset(
                  'assets/images/app_icon1.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  cacheWidth: (size * _markScale * devicePixelRatio).round(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Static bezel ring, four diagonal ticks echoing the diamond mark, and a
/// single amber arc sweeping the circle while startup runs.
class _ScanRingPainter extends CustomPainter {
  const _ScanRingPainter({required this.rotation, required this.opacity});

  /// 0..1 around the circle.
  final double rotation;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.01) return;

    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 1;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.10 * opacity),
    );

    final tick = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.22 * opacity);
    for (var i = 0; i < 4; i++) {
      final angle = math.pi / 4 + i * math.pi / 2;
      final direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + direction * (radius - 5),
        center + direction * (radius + 3),
        tick,
      );
    }

    final start = rotation * 2 * math.pi;
    const sweep = math.pi * 0.5;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: sweep,
          colors: [
            AppColors.accent.withValues(alpha: 0),
            AppColors.accent.withValues(alpha: 0.9 * opacity),
          ],
          transform: GradientRotation(start),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _ScanRingPainter oldDelegate) =>
      oldDelegate.rotation != rotation || oldDelegate.opacity != opacity;
}

/// "INTELLI" + "HMI" in the logo's own two-tone split, matching the Home
/// header wordmark.
class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.fontSize});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final tracking = fontSize * 0.15;

    return Semantics(
      label: 'IntelliHMI',
      child: Transform.translate(
        // Letter-spacing is appended after the final glyph; nudge back by half
        // of it so the wordmark stays optically centred.
        offset: Offset(tracking / 2, 0),
        child: Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text: 'INTELLI',
                style: TextStyle(color: AppColors.brandOnDark),
              ),
              TextSpan(
                text: 'HMI',
                style: TextStyle(
                  color: AppColors.brandOnDarkSub.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: tracking,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

/// Hairline rule broken by an amber diamond — the logo's centre stone used as
/// a divider glyph.
class _AccentRule extends StatelessWidget {
  const _AccentRule();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Row(
        children: [
          const Expanded(child: _Hairline(fadeLeft: true)),
          const SizedBox(width: 12),
          Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(1.4),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.55),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(child: _Hairline(fadeLeft: false)),
        ],
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline({required this.fadeLeft});

  final bool fadeLeft;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: fadeLeft ? Alignment.centerLeft : Alignment.centerRight,
          end: fadeLeft ? Alignment.centerRight : Alignment.centerLeft,
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.30),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Status / error
// ═══════════════════════════════════════════════════════════════════════

class _StartupStatus extends StatelessWidget {
  const _StartupStatus({
    required this.message,
    required this.progress,
    required this.pulse,
    required this.compact,
    super.key,
  });

  final String message;
  final double progress;
  final Animation<double> pulse;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _PulseDot(animation: pulse),
            const SizedBox(width: 10),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                // Default layout stacks children centred; the readout has to
                // stay pinned to the status dot.
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previousChildren, ?currentChild],
                ),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.35),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Text(
                  message,
                  key: ValueKey<String>(message),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.brandOnDark.withValues(alpha: 0.88),
                    fontSize: compact ? 11.5 : 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 38,
              child: Text(
                '${(progress * 100).round()}%',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: compact ? 11 : 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ProgressTrack(value: progress),
      ],
    );
  }
}

/// Slim amber progress rail. Advances only on real initializer milestones.
class _ProgressTrack extends StatelessWidget {
  const _ProgressTrack({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) {
        return SizedBox(
          height: 4,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: animated,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      gradient: LinearGradient(
                        colors: [
                          AppColors.accent.withValues(alpha: 0.45),
                          AppColors.accent,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.45),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PulseDot extends StatelessWidget {
  const _PulseDot({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        // Two breaths per ambient cycle.
        final pulse = (math.sin(animation.value * 4 * math.pi) + 1) / 2;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accent,
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.25 + 0.45 * pulse),
                blurRadius: 6 + 6 * pulse,
                spreadRadius: 0.5 + 1.5 * pulse,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({
    required this.message,
    required this.busy,
    required this.onRetry,
    super.key,
  });

  final String message;
  final bool busy;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppMetrics.spaceLg),
      decoration: BoxDecoration(
        color: AppColors.brandDanger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        border: Border.all(
          color: AppColors.brandDanger.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 18,
                color: AppColors.brandDanger,
              ),
              SizedBox(width: 8),
              Text(
                'INITIALIZATION HALTED',
                style: TextStyle(
                  color: AppColors.brandDanger,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppMetrics.spaceSm),
          Text(
            message,
            style: const TextStyle(
              color: AppColors.brandOnDarkSub,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppMetrics.spaceMd),
          BrandPrimaryButton(
            label: 'RETRY STARTUP',
            icon: Icons.refresh_rounded,
            busy: busy,
            height: 46,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Entrance helper
// ═══════════════════════════════════════════════════════════════════════

/// Fade + rise driven by an interval of the intro controller, so the screen
/// assembles itself in a deliberate order instead of appearing all at once.
class _StaggerIn extends StatelessWidget {
  const _StaggerIn({
    required this.animation,
    required this.child,
    this.offsetY = 14,
  });

  final Animation<double> animation;
  final Widget child;
  final double offsetY;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final value = animation.value;
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - value) * offsetY),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
