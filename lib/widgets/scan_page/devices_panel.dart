import 'package:flutter/material.dart';
import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';

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
                const Spacer(),
                Text(
                  _countLabel(widget.controller),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.connTextMuted,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  String _countLabel(CraneController controller) {
    if (controller.isConnected) return '1 connected';
    if (controller.isConnecting) return 'connecting...';
    return '${controller.devices.length} found';
  }

  Widget _buildBody() {
    if (widget.controller.isConnected || widget.controller.isConnecting) {
      final device = widget.controller.connectionState.connectedDevice;
      if (device == null) {
        return const _EmptyDeviceState(
          key: ValueKey('empty-connected'),
          scanning: false,
        );
      }
      return ListView(
        key: const ValueKey('connected-list'),
        padding: const EdgeInsets.all(14),
        children: [
          _ConnectedDeviceCard(
            device: device,
            isConnecting: widget.controller.isConnecting,
            onDisconnect: widget.controller.disconnect,
          ),
        ],
      );
    }

    if (widget.controller.devices.isEmpty) {
      return _EmptyDeviceState(
        key: const ValueKey('empty-idle'),
        scanning: widget.controller.isScanning,
      );
    }

    return ListView.separated(
      key: const ValueKey('devices-list'),
      padding: const EdgeInsets.all(14),
      itemCount: widget.controller.devices.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _AvailableDeviceCard(
        device: widget.controller.devices[i],
        connecting: widget.controller.isConnecting,
        onConnect: () =>
            widget.controller.connectToDevice(widget.controller.devices[i]),
      ),
    );
  }
}