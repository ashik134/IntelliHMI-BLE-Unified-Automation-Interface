import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/widgets/scan_page/devices_panel.dart';
import 'package:rev_crane_control_ops/widgets/scan_page/heros_status_card.dart';
import 'package:rev_crane_control_ops/widgets/scan_page/quick_status_row.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  CraneController? _controller;
  String? _lastShownError;

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
                  ? AppColors.connWarning
                  : AppColors.error,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
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
                            fontWeight: FontWeight.w500,
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

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CraneController>();

    return Scaffold(
      backgroundColor: AppColors.connBg,
      body: controller.isInitializing
          ? const _InitializingView()
          : Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFF7F9FC), AppColors.connBg],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    _buildAppBar(controller),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Column(
                          children: [
                            HeroStatusCard(controller: controller),
                            const SizedBox(height: 12),
                            QuickStatusRow(controller: controller),
                            const SizedBox(height: 12),
                            Expanded(
                              child: DevicesPanel(controller: controller),
                            ),
                            const SizedBox(height: 12),
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
}

Widget _buildAppBar(CraneController controller) {
  return IndustrialAppBar(
    title: 'Scan Devices',

    showBackButton: true,
    onBackPressed: () {},
    isScanning: controller.isScanning,
    canScan:
        !controller.isConnectionActive &&
        !controller.isCancellingConnection &&
        !controller.isConnected &&
        controller.bluetoothReady &&
        controller.permissionsGranted,
    onScanPressed: controller.scanForDevices,
    onStopScan: controller.stopScan,
    onSettingsPressed: () {
      // Navigate to settings
      // Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
    },
  );
}

class _InitializingView extends StatelessWidget {
  const _InitializingView();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF7F9FC), AppColors.connBg],
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: AppColors.connPrimary,
              strokeWidth: 2.5,
            ),
            SizedBox(height: 18),
            Text(
              'Preparing BLE Runtime',
              style: TextStyle(
                color: AppColors.connText,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 5),
            Text(
              'Checking Bluetooth and permissions...',
              style: TextStyle(color: AppColors.connTextMuted, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

class IndustrialAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onScanPressed;
  final VoidCallback? onSettingsPressed;
  final bool isScanning;
  final bool canScan;
  final VoidCallback? onStopScan;
  final bool showBackButton;
  final VoidCallback? onBackPressed;
  final List<Widget>? actions;
  final Color? backgroundColor;
  final double? elevation;

  const IndustrialAppBar({
    super.key,
    required this.title,
    this.onScanPressed,
    this.onSettingsPressed,
    this.isScanning = false,
    this.canScan = false,
    this.onStopScan,
    this.showBackButton = true,
    this.onBackPressed,
    this.actions,
    this.backgroundColor,
    this.elevation = 0.5,
  });

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: preferredSize.height,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: backgroundColor ?? AppColors.surface,
          border: const Border(
            bottom: BorderSide(color: AppColors.borderStrong, width: 1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha((0.04 * 255).toInt()),
              blurRadius: elevation! * 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            if (showBackButton) _buildBackButton(context),

            _buildBrandSection(),

            const Spacer(),

            ...?actions,

            if (onScanPressed != null) _buildScanButton(context),

            // Settings Button
            // if (onSettingsPressed != null) _buildSettingsButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBackButton(BuildContext context) {
    final canPop = Navigator.canPop(context);

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () {
            if (canPop) {
              Navigator.pop(context);
            } else if (onBackPressed != null) {
              onBackPressed!();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('No previous screen to return to'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(10),
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.connBorder, width: 1),
            ),
            child: Icon(
              Icons.arrow_back_sharp,
              size: 20,
              color: canPop ? AppColors.lightText : AppColors.lightTextMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandSection() {
    return Row(
      children: [
        const Icon(Icons.bluetooth, color: Colors.blueAccent, size: 24),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.lightText,
                letterSpacing: -0.5,
                height: 1,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildScanButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 40,
        child: isScanning
            ? OutlinedButton(
                onPressed: onStopScan,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: BorderSide(
                    color: AppColors.error.withAlpha(115),
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(70, 40),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.stop_rounded, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'STOP',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              )
            : FilledButton(
                onPressed: canScan ? onScanPressed : null,
                style: FilledButton.styleFrom(
                  // backgroundColor: AppColors.divider,
                  foregroundColor: AppColors.darkBg,
                  disabledBackgroundColor: AppColors.neutral.withAlpha(115),
                  disabledForegroundColor: AppColors.lightText.withAlpha(115),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: AppColors.darkBorder)
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  minimumSize: const Size(80, 40),
                  elevation: 2,
                  shadowColor: AppColors.divider.withAlpha(115),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bluetooth_searching_rounded, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'SCAN',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  // Widget _buildSettingsButton(BuildContext context) {
  //   return Material(
  //     color: Colors.transparent,
  //     borderRadius: BorderRadius.circular(10),
  //     child: InkWell(
  //       onTap: onSettingsPressed,
  //       borderRadius: BorderRadius.circular(10),
  //       customBorder: RoundedRectangleBorder(
  //         borderRadius: BorderRadius.circular(10),
  //       ),
  //       child: const Icon(
  //         Icons.settings_rounded,
  //         color: AppColors.lightText,
  //         size: 26,
  //       ),
  //     ),
  //   );
  // }
}
