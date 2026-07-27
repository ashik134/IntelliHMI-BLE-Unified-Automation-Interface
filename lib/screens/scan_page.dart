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
            : SafeArea(
                child: Column(
                  children: [
                    _ScanAppBar(controller: controller, onBack: _leaveToHome),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                        child: Column(
                          children: [
                            HeroStatusCard(controller: controller),
                            const SizedBox(height: 12),
                            QuickStatusRow(controller: controller),
                            const SizedBox(height: 16),
                            const BrandSectionLabel(label: 'Available Devices'),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: _devicesPanelHeight(context),
                              child: DevicesPanel(controller: controller),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  double _devicesPanelHeight(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return (h * 0.46).clamp(320.0, 560.0);
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
// Scan App Bar — dark industrial header matching the Home hero &
// Control Screen's violet-tinted app bar language.
// ═══════════════════════════════════════════════════════════════

class _ScanAppBar extends StatelessWidget {
  const _ScanAppBar({required this.controller, required this.onBack});

  final CraneController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final isScanning = controller.isScanning;
    final canScan =
        !controller.isConnectionActive &&
        !controller.isCancellingConnection &&
        !controller.isConnected &&
        controller.bluetoothReady &&
        controller.permissionsGranted;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brandInk, AppColors.brandInkAlt],
        ),
      ),
      child: Row(
        children: [
          BrandIconButton(
            icon: Icons.arrow_back_rounded,
            dark: true,
            tooltip: 'Back to Home',
            onTap: onBack,
          ),
          const SizedBox(width: 10),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.brandViolet.withAlpha(46),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.brandViolet.withAlpha(90)),
            ),
            child: const Icon(
              Icons.bluetooth_searching_rounded,
              color: AppColors.brandViolet,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Scan Devices',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandOnDark,
                    letterSpacing: -0.2,
                    height: 1.1,
                  ),
                ),
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
          _ScanButton(
            isScanning: isScanning,
            canScan: canScan,
            onScan: controller.scanForDevices,
            onStop: controller.stopScan,
          ),
        ],
      ),
    );
  }
}

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
        height: 40,
        child: OutlinedButton.icon(
          onPressed: onStop,
          icon: const Icon(Icons.stop_rounded, size: 16),
          label: const Text(
            'STOP',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.brandDanger,
            side: BorderSide(
              color: AppColors.brandDanger.withAlpha(150),
              width: 1.4,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            minimumSize: const Size(70, 40),
          ),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: FilledButton.icon(
        onPressed: canScan ? onScan : null,
        icon: const Icon(Icons.bluetooth_searching_rounded, size: 16),
        label: const Text(
          'SCAN',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brandViolet,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.white.withAlpha(20),
          disabledForegroundColor: Colors.white.withAlpha(90),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          minimumSize: const Size(80, 40),
          elevation: 0,
        ),
      ),
    );
  }
}
