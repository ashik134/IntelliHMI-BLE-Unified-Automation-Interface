import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rev_crane_control_ops/testing/ble_gateway/ble_gateway_protocol.dart';
import 'package:rev_crane_control_ops/testing/ble_gateway/gateway_hmi_shell.dart';
import 'package:rev_crane_control_ops/testing/ble_gateway/remote_ble_transport.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';

class RemoteBleSetupScreen extends StatefulWidget {
  const RemoteBleSetupScreen({super.key});

  @override
  State<RemoteBleSetupScreen> createState() => _RemoteBleSetupScreenState();
}

class _RemoteBleSetupScreenState extends State<RemoteBleSetupScreen> {
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: BleGatewayProtocol.defaultPort.toString(),
  );
  final List<String> _logs = [];

  StreamSubscription<String>? _logSub;
  RemoteBleTransport? _transport;
  bool _connecting = false;
  bool _handedOff = false;
  String? _error;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _logSub?.cancel();
    if (!_handedOff) {
      _transport?.dispose();
    }
    super.dispose();
  }

  Future<void> _connect() async {
    if (_connecting) {
      return;
    }

    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    if (host.isEmpty || port == null || port <= 0 || port > 65535) {
      setState(() {
        _error = 'Enter a valid phone IP address and port.';
      });
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _connecting = true;
      _error = null;
      _logs.clear();
    });

    final transport = RemoteBleTransport(host: host, port: port);
    _transport = transport;
    await _logSub?.cancel();
    _logSub = transport.logs.listen(_appendLog);

    try {
      await transport.connectGateway();
      _handedOff = true;
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => GatewayRemoteHmiApp(transport: transport),
        ),
      );
    } catch (error) {
      transport.dispose();
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Could not connect to phone gateway: $error';
        _connecting = false;
        _transport = null;
      });
    }
  }

  void _appendLog(String line) {
    if (!mounted) {
      return;
    }
    setState(() {
      _logs.insert(0, line);
      if (_logs.length > 80) {
        _logs.removeLast();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.connBg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.connText,
        elevation: 0,
        titleSpacing: 0,
        title: const Text(
          'Remote BLE Mode',
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
          _SetupCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _HeaderRow(
                  icon: Icons.tablet_android_rounded,
                  title: 'Tablet HMI Client',
                  subtitle: 'Connect this tablet to the Android phone gateway.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _hostController,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Phone IP address',
                    hintText: '192.168.1.25',
                    prefixIcon: Icon(Icons.wifi_tethering_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: (_) => _connect(),
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    prefixIcon: Icon(Icons.settings_ethernet_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.brandDanger,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _connecting ? null : _connect,
                    icon: _connecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.link_rounded, size: 18),
                    label: Text(_connecting ? 'CONNECTING...' : 'CONNECT'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.connPrimary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SetupCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _HeaderRow(
                  icon: Icons.receipt_long_rounded,
                  title: 'Tablet Logs',
                  subtitle: 'WebSocket connection and remote BLE commands.',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 220,
                  child: _logs.isEmpty
                      ? const Center(
                          child: Text(
                            'No tablet gateway logs yet.',
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
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.child});

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
