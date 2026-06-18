import 'package:flutter/material.dart';
import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/widgets/scan_page/device_card.dart';

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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.connBorder),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                const Text(
                  'NEARBY DEVICES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: AppColors.connTextMuted,
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: c.isScanning
                      ? const _Badge(
                          key: ValueKey('scanning'),
                          label: 'SCANNING',
                          color: AppColors.scanning,
                          bg: AppColors.scanningBg,
                          border: AppColors.scanningBorder,
                        )
                      : count > 0
                      ? _Badge(
                          key: ValueKey('count-$count'),
                          label: '$count found',
                          color: AppColors.connPrimary,
                          bg: AppColors.primarySoft,
                          border: AppColors.connBorder,
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
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.connBorder),
                      ),
                      child: Center(
                        child: RotationTransition(
                          turns: _spinCtrl,
                          child: Icon(
                            Icons.refresh_sharp,
                            size: 15,
                            color: blocked
                                ? AppColors.connBorder
                                : AppColors.connTextMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
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
          Expanded(
            child: Stack(
              children: [
                Center(
                  child: ShaderMask(
                    shaderCallback: (Rect bounds) {
                      return LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withAlpha(100),
                          Colors.white.withAlpha(255),
                        ],
                      ).createShader(bounds);
                    },
                    blendMode: BlendMode.dstOut,
                    child: const Image(
                      image: AssetImage('assets/images/app_icon1.png'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                // assetImages('assets/images/app_icon1.png',filterQuality: FilterQuality.high, fit: BoxFit.cover,),
                _buildBody(),
              ],
            ),
          ),
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
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.scanning) ...[
              SizedBox(
                width: 80,
                height: 80,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer pulse ring
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
                                color: AppColors.scanning,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Center radar icon
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.scanningBg,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.scanningBorder),
                      ),
                      child: const Icon(
                        Icons.radar_rounded,
                        color: AppColors.scanning,
                        size: 30,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else
              const SizedBox(height: 14),
            Text(
              widget.scanning
                  ? 'Scanning for Devices...'
                  : 'No Controllers Found',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.connText,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.scanning
                  ? 'Looking for ${BLEConstants.scanNamePrefix}* nearby.'
                  : 'Power on the PLC controller and keep it in BLE range.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.connTextMuted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    super.key,
    required this.label,
    required this.color,
    required this.bg,
    required this.border,
  });

  final String label;
  final Color color;
  final Color bg;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: color,
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
    // final right = center + sweepWidth / 2;

    final rect = Rect.fromLTWH(left, 0, sweepWidth, size.height);
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          AppColors.scanning.withAlpha(0),
          AppColors.scanning.withAlpha(200),
          AppColors.scanning.withAlpha(0),
        ],
      ).createShader(rect);

    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_ScanSweepPainter old) => old.progress != progress;
}
