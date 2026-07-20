import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rev_crane_control_ops/models/ble_connection_state.dart';
import 'package:rev_crane_control_ops/testing/ble_gateway/ble_gateway_protocol.dart';
import 'package:rev_crane_control_ops/testing/ble_gateway/ble_gateway_server.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';

class GatewayModeScreen extends StatefulWidget {
  const GatewayModeScreen({super.key});

  @override
  State<GatewayModeScreen> createState() => _GatewayModeScreenState();
}

class _GatewayModeScreenState extends State<GatewayModeScreen> {
  final BleGatewayServer _server = BleGatewayServer();
  final TextEditingController _portController = TextEditingController(
    text: BleGatewayProtocol.defaultPort.toString(),
  );
  final List<String> _logs = [];

  StreamSubscription<BleGatewayServerSnapshot>? _snapshotSub;
  StreamSubscription<String>? _logSub;
  BleGatewayServerSnapshot _snapshot =
      const BleGatewayServerSnapshot.initial();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _snapshotSub = _server.snapshots.listen((snapshot) {
      if (mounted) {
        setState(() => _snapshot = snapshot);
      }
    });
    _logSub = _server.logs.listen(_appendLog);
  }

  @override
  void dispose() {
    _snapshotSub?.cancel();
    _logSub?.cancel();
    _portController.dispose();
    unawaited(_server.dispose());
    super.dispose();
  }

  Future<void> _startServer() async {
    if (_busy) {
      return;
    }
    final port = int.tryParse(_portController.text.trim());
    if (port == null || port <= 0 || port > 65535) {
      _showSnack('Enter a valid WebSocket port.');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _busy = true);
    try {
      await _server.start(port: port);
    } catch (error) {
      _showSnack('Gateway start failed: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _stopServer() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _server.stop();
    } catch (error) {
      _showSnack('Gateway stop failed: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _copyEndpoint(String host) {
    final endpoint = '$host:${_snapshot.port}';
    Clipboard.setData(ClipboardData(text: endpoint));
    _showSnack('Copied $endpoint');
  }

  void _appendLog(String line) {
    if (!mounted) {
      return;
    }
    setState(() {
      _logs.insert(0, line);
      if (_logs.length > 160) {
        _logs.removeLast();
      }
    });
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(message),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final running = _snapshot.running;
    return Scaffold(
      backgroundColor: AppColors.connBg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.connText,
        elevation: 0,
        titleSpacing: 0,
        title: const Text(
          'Gateway Mode',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.connText,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.divider),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _GatewayCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _HeaderRow(
                  icon: Icons.phone_android_rounded,
                  title: 'Phone BLE Gateway',
                  subtitle: 'This phone owns BLE and exposes a local WebSocket.',
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        enabled: !running && !_busy,
                        controller: _portController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: 'WebSocket port',
                          prefixIcon: Icon(Icons.settings_ethernet_rounded),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : running
                            ? _stopServer
                            : _startServer,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                running
                                    ? Icons.stop_rounded
                                    : Icons.play_arrow_rounded,
                                size: 18,
                              ),
                        label: Text(running ? 'STOP' : 'START'),
                        style: FilledButton.styleFrom(
                          backgroundColor: running
                              ? AppColors.brandDanger
                              : AppColors.connPrimary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _GatewayCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _HeaderRow(
                  icon: Icons.router_rounded,
                  title: 'Local Endpoint',
                  subtitle: 'Enter one of these addresses on the tablet.',
                ),
                const SizedBox(height: 12),
                if (!running)
                  const _MutedText('Start the gateway to show phone IPs.')
                else if (_snapshot.ipAddresses.isEmpty)
                  const _MutedText('No local Wi-Fi IPv4 address found.')
                else
                  ..._snapshot.ipAddresses.map(
                    (ip) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _EndpointRow(
                        host: ip,
                        port: _snapshot.port,
                        onCopy: () => _copyEndpoint(ip),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _GatewayCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _HeaderRow(
                  icon: Icons.sync_alt_rounded,
                  title: 'Runtime Status',
                  subtitle: 'Tablet WebSocket and phone BLE state.',
                ),
                const SizedBox(height: 12),
                _StatusRow(
                  label: 'WebSocket Server',
                  value: running ? 'Running' : 'Stopped',
                  active: running,
                ),
                _StatusRow(
                  label: 'Tablet Client',
                  value: _snapshot.tabletConnected ? 'Connected' : 'Waiting',
                  active: _snapshot.tabletConnected,
                ),
                _StatusRow(
                  label: 'BLE State',
                  value: _statusLabel(_snapshot.bleStatus),
                  active: _snapshot.bleStatus == BleConnectionStatus.connected ||
                      _snapshot.bleStatus ==
                          BleConnectionStatus.awaitingAuthentication ||
                      _snapshot.bleStatus ==
                          BleConnectionStatus.authenticated,
                ),
                if (_snapshot.connectedDeviceName != null)
                  _StatusRow(
                    label: 'PLC Device',
                    value:
                        '${_snapshot.connectedDeviceName} (${_snapshot.connectedDeviceId})',
                    active: true,
                  ),
                if (_snapshot.lastError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _snapshot.lastError!,
                      style: const TextStyle(
                        color: AppColors.brandDanger,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _GatewayCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _HeaderRow(
                  icon: Icons.receipt_long_rounded,
                  title: 'Gateway Logs',
                  subtitle: 'Server, tablet, BLE command, and error events.',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 260,
                  child: _logs.isEmpty
                      ? const Center(
                          child: Text(
                            'No gateway logs yet.',
                            style: TextStyle(
                              color: AppColors.connTextMuted,
                              fontSize: 12,
                            ),
                          ),
                        )
                      : ListView.builder(
                          reverse: true,
                          itemCount: _logs.length,
                          itemBuilder: (context, index) => Text(
                            _logs[index],
                            style: const TextStyle(
                              color: AppColors.connTextSub,
                              fontFamily: 'monospace',
                              fontSize: 11,
                              height: 1.35,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(BleConnectionStatus status) {
    return switch (status) {
      BleConnectionStatus.disconnected => 'Disconnected',
      BleConnectionStatus.scanning => 'Scanning',
      BleConnectionStatus.connecting => 'Connecting',
      BleConnectionStatus.discoveringServices => 'Discovering services',
      BleConnectionStatus.configuringNotifications =>
        'Configuring notifications',
      BleConnectionStatus.initializingSafeState => 'Initializing safe state',
      BleConnectionStatus.connected => 'Connected',
      BleConnectionStatus.awaitingAuthentication => 'Awaiting auth',
      BleConnectionStatus.authenticating => 'Authenticating',
      BleConnectionStatus.authenticated => 'Authenticated',
      BleConnectionStatus.error => 'Error',
    };
  }
}

class _GatewayCard extends StatelessWidget {
  const _GatewayCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.connPrimary.withAlpha(28),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.connPrimary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.connText,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.connTextMuted,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EndpointRow extends StatelessWidget {
  const _EndpointRow({
    required this.host,
    required this.port,
    required this.onCopy,
  });

  final String host;
  final int port;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.connBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$host:$port',
              style: const TextStyle(
                color: AppColors.connPrimary,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded, size: 18),
            color: AppColors.connPrimary,
            tooltip: 'Copy endpoint',
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
    required this.active,
  });

  final String label;
  final String value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.brandSuccess : AppColors.connTextMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.connTextSub,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MutedText extends StatelessWidget {
  const _MutedText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.connTextMuted,
        fontSize: 12,
        height: 1.4,
      ),
    );
  }
}
