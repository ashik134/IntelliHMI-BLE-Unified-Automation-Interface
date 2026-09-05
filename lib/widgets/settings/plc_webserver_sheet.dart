import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:rev_crane_control_ops/screens/plc_web_portal_screen.dart';
import 'package:rev_crane_control_ops/services/plc_webserver_service.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';

/// Opens the PLC webserver registration helper as a modal bottom sheet.
///
/// [deviceId] is shown (with a copy action) so the user can paste it into
/// the PLC's registration form once the webserver page loads.
Future<void> showPlcWebserverSheet(
  BuildContext context, {
  required String deviceId,
}) async {
  final launchRequest = await showModalBottomSheet<_PlcWebPortalLaunchRequest>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => _PlcWebserverSheet(deviceId: deviceId),
  );

  if (launchRequest == null) return;
  if (!context.mounted) {
    if (launchRequest.routingAlreadyBound) {
      await PlcWebserverService.releaseWifiRouting();
    }
    return;
  }

  try {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PlcWebPortalScreen(
          wifiSsid: launchRequest.wifiSsid,
          routingAlreadyBound: launchRequest.routingAlreadyBound,
        ),
      ),
    );
  } finally {
    await PlcWebserverService.releaseWifiRouting();
  }
}

class _PlcWebPortalLaunchRequest {
  const _PlcWebPortalLaunchRequest({
    required this.wifiSsid,
    required this.routingAlreadyBound,
  });

  final String wifiSsid;
  final bool routingAlreadyBound;
}

class _PlcWebserverSheet extends StatefulWidget {
  const _PlcWebserverSheet({required this.deviceId});

  final String deviceId;

  @override
  State<_PlcWebserverSheet> createState() => _PlcWebserverSheetState();
}

class _PlcWebserverSheetState extends State<_PlcWebserverSheet> {
  final PlcWebserverService _service = PlcWebserverService();
  late final TextEditingController _ssidController;
  late final TextEditingController _passwordController;
  late final StreamSubscription<PlcWebserverStatus> _statusSubscription;
  PlcWebserverStatus _status = PlcWebserverStatus.idle;
  bool _copied = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _ssidController = TextEditingController(
      text: PlcWebserverConstants.wifiSsid,
    );
    _passwordController = TextEditingController(
      text: PlcWebserverConstants.wifiPassword,
    );
    _statusSubscription = _service.statusStream.listen((status) {
      if (mounted) setState(() => _status = status);
    });
  }

  @override
  void dispose() {
    unawaited(_statusSubscription.cancel());
    _ssidController.dispose();
    _passwordController.dispose();
    _service.dispose();
    super.dispose();
  }

  bool get _isBusy =>
      _status == PlcWebserverStatus.connectingToWifi ||
      _status == PlcWebserverStatus.waitingForApproval ||
      _status == PlcWebserverStatus.openingWebserver;

  String get _wifiSsid => _ssidController.text.trim();
  String get _wifiPassword => _passwordController.text;
  bool get _hasWifiPassword => _wifiPassword.trim().isNotEmpty;
  bool get _canConnect => !_isBusy && _wifiSsid.isNotEmpty;

  void _copyDeviceId() {
    if (widget.deviceId.isEmpty) return;
    Clipboard.setData(ClipboardData(text: widget.deviceId));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _connectAndOpen() async {
    final ssid = _wifiSsid;
    if (ssid.isEmpty) return;
    FocusScope.of(context).unfocus();
    final ready = await _service.startRegistrationFlow(
      wifiSsid: ssid,
      wifiPassword: _wifiPassword,
    );
    if (!ready) return;

    if (!mounted) {
      await PlcWebserverService.releaseWifiRouting();
      return;
    }

    Navigator.of(context).pop(
      _PlcWebPortalLaunchRequest(wifiSsid: ssid, routingAlreadyBound: true),
    );
  }

  Future<void> _openWifiSettings() => _service.openWifiSettingsManually();

  void _openWebserverDirectly() {
    Navigator.of(context).pop(
      _PlcWebPortalLaunchRequest(
        wifiSsid: _wifiSsid.isEmpty
            ? PlcWebserverConstants.wifiSsid
            : _wifiSsid,
        routingAlreadyBound: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isBusy,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.92,
            ),
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(40),
                    blurRadius: 24,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Handle(),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'PLC Webserver Registration',
                            style: TextStyle(
                              color: AppColors.connText,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: AppColors.connTextMuted,
                          ),
                          onPressed: _isBusy
                              ? null
                              : () => Navigator.of(context).maybePop(),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Connect to the PLC’s own Wi-Fi network and open its '
                      'onboard webserver to register this device.',
                      style: TextStyle(
                        color: AppColors.connTextMuted,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _DeviceIdRow(
                      deviceId: widget.deviceId,
                      copied: _copied,
                      onCopy: _copyDeviceId,
                    ),
                    const SizedBox(height: 12),
                    _WifiCredentialsFields(
                      ssidController: _ssidController,
                      passwordController: _passwordController,
                      enabled: !_isBusy,
                      obscurePassword: _obscurePassword,
                      onChanged: () => setState(() {}),
                      onTogglePassword: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                    const SizedBox(height: 12),
                    _TargetNetworkRow(
                      ssid: _wifiSsid,
                      hasPassword: _hasWifiPassword,
                    ),
                    const SizedBox(height: 16),
                    _StatusBanner(status: _status),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _canConnect ? _connectAndOpen : null,
                        icon: _isBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.wifi_rounded, size: 18),
                        label: Text(
                          _isBusy
                              ? 'Working…'
                              : (_status == PlcWebserverStatus.opened
                                    ? 'Reconnect & Open Again'
                                    : 'Connect & Open Webserver'),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.connPrimary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.connPrimary
                              .withAlpha(120),
                          disabledForegroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isBusy ? null : _openWifiSettings,
                        icon: const Icon(Icons.settings_rounded, size: 16),
                        label: const Text('Open Wi-Fi Settings Instead'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.connText,
                          side: const BorderSide(color: AppColors.connBorder),
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Already connected? ',
                            style: TextStyle(
                              color: Colors.black87,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          GestureDetector(
                            onTap: _isBusy ? null : _openWebserverDirectly,
                            child: Text(
                              'Open PLC Web Portal',
                              style: TextStyle(
                                color: _isBusy
                                    ? AppColors.connPrimary
                                    : const Color.fromARGB(
                                        255,
                                        0,
                                        160,
                                        253,
                                      ).withValues(alpha: 0.5),

                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                                decorationColor: const Color.fromARGB(
                                        255,
                                        0,
                                        160,
                                        253,
                                      ).withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.divider,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _DeviceIdRow extends StatelessWidget {
  const _DeviceIdRow({
    required this.deviceId,
    required this.copied,
    required this.onCopy,
  });

  final String deviceId;
  final bool copied;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final displayId = deviceId.isEmpty ? 'Initializing…' : deviceId;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.connBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Device ID to register',
                  style: TextStyle(
                    color: AppColors.connTextMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  displayId,
                  style: const TextStyle(
                    color: AppColors.connPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: deviceId.isEmpty ? null : onCopy,
            icon: Icon(
              copied ? Icons.check_rounded : Icons.copy_rounded,
              size: 18,
              color: copied ? AppColors.homeSuccess : AppColors.connPrimary,
            ),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _WifiCredentialsFields extends StatelessWidget {
  const _WifiCredentialsFields({
    required this.ssidController,
    required this.passwordController,
    required this.enabled,
    required this.obscurePassword,
    required this.onChanged,
    required this.onTogglePassword,
  });

  final TextEditingController ssidController;
  final TextEditingController passwordController;
  final bool enabled;
  final bool obscurePassword;
  final VoidCallback onChanged;
  final VoidCallback onTogglePassword;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: ssidController,
          enabled: enabled,
          style: const TextStyle(color: AppColors.brandInkAlt),
          textInputAction: TextInputAction.next,
          onChanged: (_) => onChanged(),
          decoration: _plcWebserverInputDecoration(
            label: 'PLC Wi-Fi SSID',
            hint: PlcWebserverConstants.wifiSsid,
            icon: Icons.wifi_rounded,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: passwordController,
          enabled: enabled,
          style: const TextStyle(color: AppColors.brandInkAlt),
          obscureText: obscurePassword,
          onChanged: (_) => onChanged(),
          decoration: _plcWebserverInputDecoration(
            label: 'Wi-Fi password',
            hint: 'Leave blank for open network',
            icon: Icons.lock_outline_rounded,
            suffix: IconButton(
              tooltip: obscurePassword ? 'Show password' : 'Hide password',
              icon: Icon(
                obscurePassword
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                size: 18,
                color: AppColors.connTextMuted,
              ),
              onPressed: enabled ? onTogglePassword : null,
            ),
          ),
        ),
      ],
    );
  }
}

InputDecoration _plcWebserverInputDecoration({
  required String label,
  required String hint,
  required IconData icon,
  Widget? suffix,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: Icon(icon, color: AppColors.connTextMuted, size: 19),
    suffixIcon: suffix,
    filled: true,
    fillColor: AppColors.connBg,
    labelStyle: const TextStyle(color: AppColors.connTextMuted),
    hintStyle: const TextStyle(
      color: Color.fromARGB(255, 11, 87, 187),
      fontSize: 12,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.divider),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.divider),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColors.divider.withAlpha(120)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.connPrimary, width: 1.4),
    ),
  );
}

class _TargetNetworkRow extends StatelessWidget {
  const _TargetNetworkRow({required this.ssid, required this.hasPassword});

  final String ssid;
  final bool hasPassword;

  @override
  Widget build(BuildContext context) {
    final ssidLabel = ssid.isEmpty ? ssid : 'SSID required';
    final securityLabel = hasPassword ? 'secured' : 'open';

    return Row(
      children: [
        const Icon(
          Icons.router_rounded,
          size: 15,
          color: AppColors.connTextMuted,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Target: $ssidLabel - $securityLabel - '
            '${PlcWebserverConstants.webserverUrl}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.connTextMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});

  final PlcWebserverStatus status;

  (Color, Color, IconData, String) _presentation() {
    switch (status) {
      case PlcWebserverStatus.idle:
        return (
          AppColors.connSurfaceAlt,
          AppColors.connTextMuted,
          Icons.info_outline_rounded,
          'Ready when you are.',
        );
      case PlcWebserverStatus.connectingToWifi:
        return (
          AppColors.scanningBg,
          AppColors.scanning,
          Icons.wifi_rounded,
          'Connecting to PLC Wi-Fi…',
        );
      case PlcWebserverStatus.waitingForApproval:
        return (
          AppColors.scanningBg,
          AppColors.scanning,
          Icons.touch_app_rounded,
          'Waiting for your approval — check for a system Wi-Fi prompt.',
        );
      case PlcWebserverStatus.openingWebserver:
        return (
          AppColors.scanningBg,
          AppColors.scanning,
          Icons.public_rounded,
          'Preparing the in-app PLC Web Portal…',
        );
      case PlcWebserverStatus.opened:
        return (
          AppColors.connectedBg,
          AppColors.connected,
          Icons.check_circle_rounded,
          'PLC Wi-Fi connected. Opening the portal…',
        );
      case PlcWebserverStatus.unableToConnect:
        return (
          AppColors.errorBg,
          AppColors.error,
          Icons.wifi_off_rounded,
          'Unable to connect to the PLC Wi-Fi. Try again, or connect '
              'manually via Wi-Fi Settings.',
        );
      case PlcWebserverStatus.webserverUnavailable:
        return (
          AppColors.warningBg,
          AppColors.connWarning,
          Icons.error_outline_rounded,
          'The PLC Wi-Fi connected, but IntelliHMI could not route portal '
              'traffic through it. Try again.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon, message) = _presentation();
    final isBusy =
        status == PlcWebserverStatus.connectingToWifi ||
        status == PlcWebserverStatus.waitingForApproval ||
        status == PlcWebserverStatus.openingWebserver;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg.withAlpha(90)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          isBusy
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              : Icon(icon, size: 16, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
