import 'package:flutter/material.dart';
import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/widgets/scan_page/device_card.dart';
import 'package:rev_crane_control_ops/widgets/shared/brand_widgets.dart';

class DevicesPanel extends StatefulWidget {
  const DevicesPanel({super.key, required this.controller});

  final CraneController controller;

  @override
  State<DevicesPanel> createState() => _DevicesPanelState();
}

class _DevicesPanelState extends State<DevicesPanel>
    with TickerProviderStateMixin {
  late final AnimationController _spinCtrl;
  late final AnimationController _scanPulseCtrl;
  late final Animation<double> _scanPulseAnim;
  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _scanPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _scanPulseAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _scanPulseCtrl, curve: Curves.easeInOut));
    if (widget.controller.isScanning) _scanPulseCtrl.repeat();
  }

  @override
  void didUpdateWidget(DevicesPanel old) {
    super.didUpdateWidget(old);
    final wasScanning = old.controller.isScanning;
    final isScanning = widget.controller.isScanning;
    if (isScanning && !wasScanning) {
      _scanPulseCtrl.repeat();
    } else if (!isScanning && wasScanning) {
      _scanPulseCtrl.stop();
      _scanPulseCtrl.reset();
    }
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    _scanPulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    if (widget.controller.isScanning ||
        widget.controller.isConnectionActive ||
        widget.controller.isCancellingConnection ||
        widget.controller.isConnected) {
      return;
    }
    await _spinCtrl.forward(from: 0);
    widget.controller.scanForDevices();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final blocked =
        c.isScanning ||
        c.isConnectionActive ||
        c.isCancellingConnection ||
        c.isConnected;
    final count = c.isConnected ? 1 : c.devices.length;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.brandSurface,
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        border: Border.all(color: AppColors.brandBorder),
        boxShadow: AppMetrics.shadowSm,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
            child: Row(
              children: [
                const Text(
                  'NEARBY DEVICES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: AppColors.brandTextMuted,
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: c.isScanning
                      ? const BrandBadge(
                          key: ValueKey('scanning'),
                          label: 'SCANNING',
                          tone: BrandTone.violet,
                          dense: true,
                        )
                      : count > 0
                      ? BrandBadge(
                          key: ValueKey('count-$count'),
                          label: '$count found',
                          tone: BrandTone.neutral,
                          dense: true,
                        )
                      : const SizedBox.shrink(key: ValueKey('none')),
                ),
                const Spacer(),
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: blocked ? null : _onRefresh,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.brandSurface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.brandBorder),
                      ),
                      child: Center(
                        child: RotationTransition(
                          turns: _spinCtrl,
                          child: Icon(
                            Icons.refresh_sharp,
                            size: 15,
                            color: blocked
                                ? AppColors.brandBorder
                                : AppColors.brandTextMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.brandBorder),
          AnimatedBuilder(
            animation: _scanPulseAnim,
            builder: (_, _) {
              final scanning = widget.controller.isScanning;
              if (!scanning) return const SizedBox.shrink();
              return SizedBox(
                height: 2,
                child: CustomPaint(
                  painter: _ScanSweepPainter(progress: _scanPulseAnim.value),
                  size: const Size(double.infinity, 2),
                ),
              );
            },
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final c = widget.controller;

    final targetDevice =
        c.connectionState.connectedDevice ?? c.cancellingDevice;

    if (c.isConnected || c.isConnectionActive || c.isCancellingConnection) {
      if (targetDevice == null) {
        final sorted = [...c.devices]..sort((a, b) => b.rssi.compareTo(a.rssi));
        if (sorted.isEmpty) {
          return const _EmptyDeviceState(
            key: ValueKey('empty-connected'),
            scanning: false,
          );
        }

        return ListView.separated(
          key: const ValueKey('guard-devices-list'),
          padding: const EdgeInsets.all(14),
          itemCount: sorted.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) => AvailableDeviceCard(
            key: ValueKey(sorted[i].id),
            device: sorted[i],
            connecting: true,
            onConnect: () {},
          ),
        );
      }
      // All scanned devices except the target
      final others = c.devices.where((d) => d.id != targetDevice.id).toList();

      return ListView.separated(
        key: const ValueKey('connecting-list'),
        padding: const EdgeInsets.all(14),
        itemCount: 1 + others.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          if (i == 0) {
            return ConnectedDeviceCard(
              key: ValueKey(targetDevice.id),
              device: targetDevice,
              isCancelling: c.isCancellingConnection,
              onCancel: c.cancelConnecting,
            );
          }
          final d = others[i - 1];
          return AvailableDeviceCard(
            key: ValueKey(d.id),
            device: d,
            connecting: true,
            onConnect: () {},
          );
        },
      );
    }

    if (c.devices.isEmpty) {
      return _EmptyDeviceState(
        key: const ValueKey('empty-idle'),
        scanning: c.isScanning,
      );
    }
    final sorted = [...c.devices]..sort((a, b) => b.rssi.compareTo(a.rssi));
    return ListView.separated(
      key: const ValueKey('devices-list'),
      padding: const EdgeInsets.all(14),
      itemCount: sorted.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (_, i) => AvailableDeviceCard(
        key: ValueKey(sorted[i].id),
        device: sorted[i],
        connecting: c.isConnecting,
        onConnect: () => c.connectToDevice(sorted[i]),
      ),
    );
  }
}

class _EmptyDeviceState extends StatefulWidget {
  const _EmptyDeviceState({required this.scanning, super.key});

  final bool scanning;

  @override
  State<_EmptyDeviceState> createState() => _EmptyDeviceStateState();
}

class _EmptyDeviceStateState extends State<_EmptyDeviceState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _scaleAnim = Tween<double>(
      begin: 0.75,
      end: 1.45,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut));
    _opacityAnim = Tween<double>(
      begin: 0.55,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut));
    if (widget.scanning) _pulseCtrl.repeat();
  }

  @override
  void didUpdateWidget(_EmptyDeviceState old) {
    super.didUpdateWidget(old);
    if (widget.scanning && !old.scanning) {
      _pulseCtrl.repeat();
    } else if (!widget.scanning && old.scanning) {
      _pulseCtrl.stop();
      _pulseCtrl.reset();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 84,
              height: 84,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (widget.scanning)
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, _) => Opacity(
                        opacity: _opacityAnim.value,
                        child: Transform.scale(
                          scale: _scaleAnim.value,
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.brandViolet,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: widget.scanning
                          ? AppColors.brandVioletSoft
                          : AppColors.brandSurfaceAlt,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.scanning
                            ? AppColors.brandViolet.withAlpha(70)
                            : AppColors.brandBorder,
                      ),
                    ),
                    child: Icon(
                      widget.scanning
                          ? Icons.radar_rounded
                          : Icons.bluetooth_disabled_rounded,
                      color: widget.scanning
                          ? AppColors.brandViolet
                          : AppColors.brandTextMuted,
                      size: 30,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              widget.scanning
                  ? 'Scanning for Devices...'
                  : 'No Controllers Found',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.brandText,
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.scanning
                  ? 'Looking for ${BLEConstants.manufacturerDataPrefix} controllers nearby.'
                  : 'Power on the PLC controller and keep it in BLE range.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.brandTextMuted,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanSweepPainter extends CustomPainter {
  const _ScanSweepPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const sweepWidth = 120.0;
    final center = progress * (size.width + sweepWidth) - sweepWidth / 2;
    final left = center - sweepWidth / 2;

    final rect = Rect.fromLTWH(left, 0, sweepWidth, size.height);
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          AppColors.brandViolet.withAlpha(0),
          AppColors.brandViolet.withAlpha(200),
          AppColors.brandViolet.withAlpha(0),
        ],
      ).createShader(rect);

    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_ScanSweepPainter old) => old.progress != progress;
}
