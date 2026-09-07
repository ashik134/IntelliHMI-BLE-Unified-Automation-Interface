import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/navigation_controller.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/widgets/scan_page/devices_panel.dart';
import 'package:rev_crane_control_ops/widgets/scan_page/heros_status_card.dart';
import 'package:rev_crane_control_ops/widgets/scan_page/quick_status_row.dart';
import 'package:rev_crane_control_ops/widgets/shared/brand_widgets.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  CraneController? _controller;
  String? _lastShownError;
  bool _leavingToHome = false;

  // This screen is never disposed while the app is running — it lives
  // inside MainShell's IndexedStack (tab switches don't unmount it) and
  // stays mounted underneath the auth/control sub-shell route pushed on
  // top of it once a connection begins. So initState/dispose can't tell us
  // when the user can and can't actually see this page; only the
  // combination of "Control tab selected" and "controller hasn't moved past
  // the connection screen" (computed in build()) can. This tracks the last
  // value seen so scanning starts/stops only on a genuine visibility edge,
  // never re-fires on unrelated rebuilds, and — since a manual STOP doesn't
  // itself change tab index or currentScreen — a manual stop naturally
  // holds until the user actually leaves and returns to this page.
  bool _scanPageWasVisible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<CraneController>();
    if (_controller != controller) {
      _controller?.removeListener(_onControllerChanged);
      _controller = controller;
      _controller!.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final error = _controller?.errorMessage;
    if (error != null && error != _lastShownError) {
      _lastShownError = error;

      final errorLower = error.toLowerCase();

      final bool isUnreachable =
          errorLower.contains('unreachable') ||
          errorLower.contains('timed out') ||
          errorLower.contains('timeout') ||
          errorLower.contains('out of range') ||
          errorLower.contains('offline');
      final String snackTitle = isUnreachable
          ? 'Device Unavailable'
          : 'Connection Error';

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: isUnreachable
                  ? AppColors.brandWarning
                  : AppColors.brandDanger,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
              ),
              duration: const Duration(seconds: 4),
              dismissDirection: DismissDirection.horizontal,
              onVisible: () {},
              content: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(51),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isUnreachable
                          ? Icons.wifi_off_rounded
                          : Icons.error_outline_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          snackTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          error,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withAlpha(230),
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.swipe_rounded,
                    color: Colors.white.withAlpha(200),
                    size: 16,
                  ),
                ],
              ),
            ),
          );
      });
    }
  }

  /// Starts/stops BLE scanning as this screen's actual visibility changes.
  /// Deferred to a post-frame callback because provider mutations must not
  /// happen synchronously inside build().
  void _syncScanWithVisibility(bool isVisible) {
    if (isVisible == _scanPageWasVisible) return;
    _scanPageWasVisible = isVisible;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<CraneController>();
      if (isVisible) {
        controller.scanForDevices();
      } else {
        controller.stopScan();
      }
    });
  }

  Future<void> _leaveToHome() async {
    if (_leavingToHome) return;
    _leavingToHome = true;

    final controller = context.read<CraneController>();
    final navigation = context.read<NavigationController>();

    try {
      if (controller.isScanning) {
        await controller.stopScan();
      }

      if (controller.isConnecting ||
          controller.isDiscoveringServices ||
          controller.isConfiguringNotifications) {
        await controller.cancelConnecting();
      }

      if (controller.isConnectionActive ||
          controller.isConnected ||
          controller.connectionState.connectedDevice != null) {
        await controller.disconnect();
      }
    } finally {
      if (!mounted) {
        // ignore: control_flow_in_finally
        return;
      }
      navigation.navigateToHome();
      _leavingToHome = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CraneController>();
    final isActiveTab = context.watch<NavigationController>().currentIndex == 1;
    final isScanPageVisible =
        isActiveTab && controller.currentScreen == AppScreen.connection;
    _syncScanWithVisibility(isScanPageVisible);

    return PopScope(
      canPop: !isActiveTab,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (!isActiveTab) return;
        _leaveToHome();
      },
      child: Scaffold(
        backgroundColor: AppColors.brandBg,
        body: controller.isInitializing
            ? const _InitializingView()
            // The console header paints edge-to-edge behind the status bar,
            // so the SafeArea inset is applied inside it rather than around
            // the whole page.
            : Column(
                children: [
                  _ScanConsoleHeader(
                    controller: controller,
                    onBack: _leaveToHome,
                  ),
                  Expanded(
                    child: SafeArea(
                      top: false,
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          // Collapses to nothing in the routine scanning and
                          // idle states, so the sheet rises to meet the
                          // header instead of leaving a hole. Owns its own
                          // padding for that reason.
                          HeroStatusCard(controller: controller),
                          // The device list is the page's only scroll
                          // surface — the panel flexes to fill whatever the
                          // status card leaves and bleeds to the bottom
                          // edge, so nothing scrolls inside a scroller.
                          Expanded(
                            child: DevicesPanel(controller: controller),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _InitializingView extends StatelessWidget {
  const _InitializingView();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.brandBg,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: AppColors.brandViolet,
              strokeWidth: 2.5,
            ),
            SizedBox(height: 18),
            Text(
              'Preparing BLE Runtime',
              style: TextStyle(
                color: AppColors.brandText,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 5),
            Text(
              'Checking Bluetooth and permissions...',
              style: TextStyle(color: AppColors.brandTextMuted, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Scan Console Header
//
// The dark "instrument console" the light content sheet lifts off.
// Carries the title row, the scan control and the at-a-glance status
// chips, over a radar backdrop that comes alive while scanning so the
// screen's core activity is legible without reading any text.
// ═══════════════════════════════════════════════════════════════

class _ScanConsoleHeader extends StatefulWidget {
  const _ScanConsoleHeader({required this.controller, required this.onBack});

  final CraneController controller;
  final VoidCallback onBack;

  @override
  State<_ScanConsoleHeader> createState() => _ScanConsoleHeaderState();
}

class _ScanConsoleHeaderState extends State<_ScanConsoleHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _radarCtrl;

  @override
  void initState() {
    super.initState();
    _radarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    if (widget.controller.isScanning) _radarCtrl.repeat();
  }

  @override
  void didUpdateWidget(_ScanConsoleHeader old) {
    super.didUpdateWidget(old);
    final isScanning = widget.controller.isScanning;
    if (isScanning && !_radarCtrl.isAnimating) {
      _radarCtrl.repeat();
    } else if (!isScanning && _radarCtrl.isAnimating) {
      _radarCtrl.stop();
      _radarCtrl.reset();
    }
  }

  @override
  void dispose() {
    _radarCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final isScanning = controller.isScanning;
    final canScan =
        !controller.isConnectionActive &&
        !controller.isCancellingConnection &&
        !controller.isConnected &&
        controller.bluetoothReady &&
        controller.permissionsGranted;

    final topInset = MediaQuery.paddingOf(context).top;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brandInk, AppColors.brandInkAlt],
        ),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(AppMetrics.radiusXl),
        ),
        boxShadow: AppMetrics.shadowMd,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Radar backdrop — always drawn faintly so the console reads as an
          // instrument even at rest, and lit up while a scan is running.
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _radarCtrl,
                builder: (_, _) => CustomPaint(
                  painter: _RadarBackdropPainter(
                    progress: _radarCtrl.value,
                    active: isScanning,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, topInset + 10, 14, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    BrandIconButton(
                      icon: Icons.arrow_back_rounded,
                      dark: true,
                      tooltip: 'Back to Home',
                      onTap: widget.onBack,
                    ),
                    const SizedBox(width: 10),
                    _HeaderGlyph(active: isScanning),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Scan Devices',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppColors.brandOnDark,
                              letterSpacing: -0.3,
                              height: 1.1,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Discover nearby PLC controllers',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.brandOnDarkSub,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ScanButton(
                      isScanning: isScanning,
                      canScan: canScan,
                      onScan: controller.scanForDevices,
                      onStop: controller.stopScan,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ScanStatusChips(controller: controller),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Title glyph — a violet tile that gains a soft glow ring while scanning.
class _HeaderGlyph extends StatelessWidget {
  const _HeaderGlyph({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.brandViolet.withAlpha(active ? 64 : 40),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.brandViolet.withAlpha(active ? 160 : 90),
        ),
        boxShadow: active
            ? const [
                BoxShadow(
                  color: AppColors.brandVioletGlow,
                  blurRadius: 16,
                  spreadRadius: -2,
                ),
              ]
            : const [],
      ),
      child: const Icon(
        Icons.radar_rounded,
        color: AppColors.brandViolet,
        size: 20,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Radar backdrop
// ═══════════════════════════════════════════════════════════════

/// Concentric range rings with a rotating sweep and an outward pulse,
/// centred off the header's trailing edge so it sits behind the scan
/// control without competing with the title text.
class _RadarBackdropPainter extends CustomPainter {
  const _RadarBackdropPainter({required this.progress, required this.active});

  /// 0..1 loop driving both the sweep rotation and the expanding pulse.
  final double progress;

  /// Whether a scan is running. At rest only the static rings are drawn.
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final center = Offset(size.width * 0.84, size.height * 0.30);
    final maxRadius = size.height * 1.35;

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.brandViolet.withAlpha(active ? 74 : 40);

    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, maxRadius * i / 4, ring);
    }

    // Cross hairs, cropped to the outer ring.
    final hair = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.brandViolet.withAlpha(active ? 52 : 28);
    canvas.drawLine(
      Offset(center.dx - maxRadius, center.dy),
      Offset(center.dx + maxRadius, center.dy),
      hair,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - maxRadius),
      Offset(center.dx, center.dy + maxRadius),
      hair,
    );

    if (!active) return;

    // Rotating sweep wedge — a fading tail behind the leading edge.
    final sweepRect = Rect.fromCircle(center: center, radius: maxRadius);
    final sweep = Paint()
      ..shader = SweepGradient(
        colors: [
          AppColors.brandViolet.withAlpha(0),
          AppColors.brandViolet.withAlpha(0),
          AppColors.brandViolet.withAlpha(92),
          AppColors.brandViolet.withAlpha(0),
        ],
        stops: const [0.0, 0.62, 0.97, 1.0],
        transform: GradientRotation(progress * math.pi * 2),
      ).createShader(sweepRect);
    canvas.drawCircle(center, maxRadius, sweep);

    // Outward pulse, fading as it expands.
    final pulseAlpha = ((1.0 - progress) * 110).round().clamp(0, 255);
    if (pulseAlpha > 0) {
      canvas.drawCircle(
        center,
        maxRadius * progress,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = AppColors.brandViolet.withAlpha(pulseAlpha),
      );
    }
  }

  @override
  bool shouldRepaint(_RadarBackdropPainter old) =>
      old.progress != progress || old.active != active;
}

// ═══════════════════════════════════════════════════════════════
// Scan / Stop control
// ═══════════════════════════════════════════════════════════════

class _ScanButton extends StatelessWidget {
  const _ScanButton({
    required this.isScanning,
    required this.canScan,
    required this.onScan,
    required this.onStop,
  });

  final bool isScanning;
  final bool canScan;
  final VoidCallback onScan;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    if (isScanning) {
      return SizedBox(
        height: 42,
        child: FilledButton.icon(
          onPressed: onStop,
          icon: const Icon(Icons.stop_rounded, size: 17),
          label: const Text(
            'STOP',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
            ),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brandDanger.withAlpha(38),
            foregroundColor: AppColors.brandDanger,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
              side: BorderSide(
                color: AppColors.brandDanger.withAlpha(150),
                width: 1.4,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            minimumSize: const Size(84, 42),
            elevation: 0,
          ),
        ),
      );
    }

    return SizedBox(
      height: 42,
      child: FilledButton.icon(
        onPressed: canScan ? onScan : null,
        icon: const Icon(Icons.bluetooth_searching_rounded, size: 17),
        label: const Text(
          'SCAN',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.9,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brandViolet,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.white.withAlpha(20),
          disabledForegroundColor: Colors.white.withAlpha(90),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          minimumSize: const Size(92, 42),
          elevation: 0,
        ),
      ),
    );
  }
}
