import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/services/plc_webserver_service.dart';

/// IntelliHMI-hosted view of the PLC's local configuration portal.
///
/// The app process remains routed through the PLC Wi-Fi for this route's
/// complete lifetime. Closing this page restores the normal network route,
/// but deliberately does not disconnect from the PLC access point.
class PlcWebPortalScreen extends StatefulWidget {
  const PlcWebPortalScreen({
    super.key,
    required this.wifiSsid,
    this.routingAlreadyBound = false,
  });

  final String wifiSsid;
  final bool routingAlreadyBound;

  @override
  State<PlcWebPortalScreen> createState() => _PlcWebPortalScreenState();
}

class _PlcWebPortalScreenState extends State<PlcWebPortalScreen>
    with WidgetsBindingObserver {
  static final Uri _portalUri = Uri.parse(PlcWebserverConstants.webserverUrl);
  static final Uri _loginUri = Uri.parse(PlcWebserverConstants.loginUrl);

  late final WebViewController _webViewController;

  bool _routingHeld = false;
  bool _isLoading = true;
  bool _isClosing = false;
  double _loadProgress = 0;
  _PortalLoadError? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _routingHeld = widget.routingAlreadyBound;
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.surface)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: _onProgress,
          onPageStarted: _onPageStarted,
          onPageFinished: _onPageFinished,
          onWebResourceError: _onWebResourceError,
        ),
      );
    unawaited(_loadPortal());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isClosing) {
      unawaited(_ensureWifiRouting());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_routingHeld) {
      _routingHeld = false;
      unawaited(PlcWebserverService.releaseWifiRouting());
    }
    super.dispose();
  }

  Future<bool> _ensureWifiRouting() async {
    final wasAlreadyBound = _routingHeld;
    final bound = await PlcWebserverService.bindWifiRouting();
    if (!mounted) return false;

    if (bound || wasAlreadyBound) {
      if (!_routingHeld) setState(() => _routingHeld = true);
      return true;
    }

    _showLoadError(
      const _PortalLoadError(
        title: 'PLC network route unavailable',
        message:
            'IntelliHMI could not route local traffic through the PLC Wi-Fi. '
            'Keep the PLC network selected, then try again.',
      ),
    );
    return false;
  }

  Future<void> _loadPortal() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadProgress = 0;
        _loadError = null;
      });
    }

    if (!await _ensureWifiRouting()) return;

    try {
      await _webViewController.loadRequest(_portalUri);
    } catch (error) {
      _showLoadError(
        _PortalLoadError(
          title: 'PLC Web Portal unavailable',
          message:
              'The PLC Wi-Fi route is active, but the web portal could not '
              'be opened. Check that the PLC web server is running, then '
              'try again.',
          detail: error.toString(),
        ),
      );
    }
  }

  void _onProgress(int progress) {
    if (!mounted || _loadError != null) return;
    setState(() {
      _loadProgress = progress.clamp(0, 100) / 100;
      _isLoading = progress < 100;
    });
  }

  void _onPageStarted(String _) {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadProgress = 0;
      _loadError = null;
    });
  }

  void _onPageFinished(String _) {
    if (!mounted || _loadError != null) return;
    setState(() {
      _isLoading = false;
      _loadProgress = 1;
    });
  }

  void _onWebResourceError(WebResourceError error) {
    if (error.isForMainFrame == false) return;
    _showLoadError(
      _PortalLoadError(
        title: 'PLC Web Portal unavailable',
        message:
            'IntelliHMI is connected to the PLC Wi-Fi, but no page responded '
            'at 192.168.4.1. Check the PLC web server and try again.',
        detail: error.description,
      ),
    );
  }

  void _showLoadError(_PortalLoadError error) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _loadProgress = 0;
      _loadError = error;
    });
  }

  Future<void> _handleBack() async {
    if (_isClosing) return;

    if (_loadError != null) {
      await _closePortal();
      return;
    }

    final currentUri = await _currentPageUri();
    if (currentUri != null && !_hasSamePortalOrigin(currentUri, _portalUri)) {
      await _closePortal();
      return;
    }

    if (_isLoginPage(currentUri)) {
      await _closePortal();
      return;
    }

    await _openLoginPage();
  }

  Future<Uri?> _currentPageUri() async {
    try {
      final currentUrl = await _webViewController.currentUrl();
      return currentUrl == null ? null : Uri.tryParse(currentUrl);
    } catch (_) {
      return null;
    }
  }

  bool _isLoginPage(Uri? uri) {
    if (uri == null || !_hasSamePortalOrigin(uri, _loginUri)) return false;

    final currentPath = _normalizedPath(uri.path);
    final loginPath = _normalizedPath(_loginUri.path);
    if (currentPath == loginPath) return true;

    return uri.pathSegments.any((segment) {
      final normalizedSegment = segment.toLowerCase();
      return normalizedSegment == 'login' ||
          normalizedSegment == 'signin' ||
          normalizedSegment == 'sign-in' ||
          normalizedSegment.startsWith('login.');
    });
  }

  bool _hasSamePortalOrigin(Uri first, Uri second) {
    return first.scheme.toLowerCase() == second.scheme.toLowerCase() &&
        first.host.toLowerCase() == second.host.toLowerCase() &&
        first.port == second.port;
  }

  String _normalizedPath(String path) {
    final normalized = path.trim().toLowerCase();
    if (normalized.isEmpty || normalized == '/') return '/';
    return normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
  }

  Future<void> _openLoginPage() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadProgress = 0;
        _loadError = null;
      });
    }

    if (!await _ensureWifiRouting()) return;

    try {
      await _webViewController.loadRequest(_loginUri);
    } catch (error) {
      _showLoadError(
        _PortalLoadError(
          title: 'PLC login page unavailable',
          message:
              'The PLC Wi-Fi route is active, but the login page could not '
              'be opened. Return to IntelliHMI and try again.',
          detail: error.toString(),
        ),
      );
    }
  }

  Future<void> _closePortal() async {
    if (_isClosing) return;
    _isClosing = true;

    if (_routingHeld) {
      _routingHeld = false;
      await PlcWebserverService.releaseWifiRouting();
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleBack());
      },
      child: Scaffold(
        backgroundColor: AppColors.connBg,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.connText,
          elevation: 0,
          toolbarHeight: 66,
          titleSpacing: 0,
          leading: IconButton(
            tooltip: 'Back',
            onPressed: _handleBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PLC Web Portal',
                style: TextStyle(
                  color: AppColors.connText,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              _PortalConnectionStatus(
                wifiSsid: widget.wifiSsid,
                routingHeld: _routingHeld,
              ),
            ],
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: _isLoading
                ? LinearProgressIndicator(
                    value: _loadProgress == 0 ? null : _loadProgress,
                    minHeight: 3,
                    backgroundColor: AppColors.scanningBg,
                    color: AppColors.scanning,
                  )
                : const Divider(height: 1, color: AppColors.divider),
          ),
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: AppColors.surface,
                child: WebViewWidget(controller: _webViewController),
              ),
            ),
            if (_loadError case final error?)
              Positioned.fill(
                child: _PortalErrorView(error: error, onRetry: _loadPortal),
              ),
          ],
        ),
      ),
    );
  }
}

class _PortalConnectionStatus extends StatelessWidget {
  const _PortalConnectionStatus({
    required this.wifiSsid,
    required this.routingHeld,
  });

  final String wifiSsid;
  final bool routingHeld;

  @override
  Widget build(BuildContext context) {
    final statusColor = routingHeld ? AppColors.connected : AppColors.scanning;
    final statusText = routingHeld
        ? 'PLC Wi-Fi connected - $wifiSsid'
        : 'Connecting PLC network route';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            statusText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: statusColor,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _PortalErrorView extends StatelessWidget {
  const _PortalErrorView({required this.error, required this.onRetry});

  final _PortalLoadError error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.connBg,
      child: SafeArea(
        top: false,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: AppColors.warningBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.warningBorder),
                    ),
                    child: const Icon(
                      Icons.router_rounded,
                      color: AppColors.connWarning,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    error.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.connText,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.connTextSub,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  if (error.detail case final detail?
                      when detail.trim().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.connTextMuted,
                        fontSize: 10.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Retry'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.connPrimary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(132, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    PlcWebserverConstants.webserverUrl,
                    style: TextStyle(
                      color: AppColors.connTextMuted,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PortalLoadError {
  const _PortalLoadError({
    required this.title,
    required this.message,
    this.detail,
  });

  final String title;
  final String message;
  final String? detail;
}
