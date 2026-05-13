import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:rev6_crane_control_ops/utils/constants.dart';
import 'package:rev6_crane_control_ops/services/ble_service.dart';
import 'package:rev6_crane_control_ops/controllers/crane_controllers.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _seeded = false;
  bool _obscurePassword = true;
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;

  late final AnimationController _introController;
  late final AnimationController _pulseController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _fadeAnimation = CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOutCubic,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(
          CurvedAnimation(parent: _introController, curve: Curves.easeOutCubic),
        );

    _introController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) {
      return;
    }

    final controller = context.read<CraneController>();
    _emailController.text = controller.savedEmail;
    _passwordController.text = controller.savedPassword;
    _seeded = true;
  }

  @override
  void dispose() {
    _introController.dispose();
    _pulseController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CraneController>();

    return Scaffold(
      backgroundColor: AppColors.connBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF8FBFF), AppColors.connBg],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -120,
              right: -90,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.scanning.withValues(alpha: 0.08),
                ),
              ),
            ),
            Positioned(
              bottom: -120,
              left: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.connPrimary.withValues(alpha: 0.06),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 920;
                  final edgePadding = constraints.maxWidth >= 1100
                      ? 28.0
                      : 16.0;

                  return Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        edgePadding,
                        16,
                        edgePadding,
                        18,
                      ),
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1100),
                            child: Container(
                              padding: EdgeInsets.all(isWide ? 18 : 12),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFF2F7FD,
                                ).withValues(alpha: 0.86),
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(
                                  color: AppColors.connBorder,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.connPrimary.withValues(
                                      alpha: 0.08,
                                    ),
                                    blurRadius: 28,
                                    offset: const Offset(0, 14),
                                  ),
                                ],
                              ),
                              child: isWide
                                  ? Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Flexible(
                                          flex: 5,
                                          child: _contextPanel(controller),
                                        ),
                                        const SizedBox(width: 16),
                                        Flexible(
                                          flex: 6,
                                          child: _buildFormPanel(
                                            controller: controller,
                                            isWide: true,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _contextPanel(controller),
                                        const SizedBox(height: 12),
                                        _buildFormPanel(
                                          controller: controller,
                                          isWide: false,
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contextPanel(CraneController controller) {
    final connectedDevice =
        controller.connectionState.connectedDevice?.name ??
        BLEConstants.deviceName;
    final statusLabel = _statusTitle(controller.connectionState.status);
    final statusCaption = _statusSubtitle(controller.connectionState.status);
    final linkReady = _hasAuthenticationSession(controller);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.connPrimary, Color(0xFF225A95)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: Colors.white.withValues(alpha: 0.16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: const Text(
              'SECURE BLE LINK',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: _BeaconPulse(
              animation: _pulseController,
              active: controller.isAuthenticating || linkReady,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Authenticate Operator Session',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Connection is established. Verify credentials before crane commands are enabled.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          _ContextInfoPill(
            icon: Icons.bluetooth_connected_rounded,
            label: 'Connected device',
            value: connectedDevice,
          ),
          const SizedBox(height: 8),
          _ContextInfoPill(
            icon: Icons.settings_ethernet_rounded,
            label: 'Transport state',
            value: statusLabel,
          ),
          const SizedBox(height: 8),
          _ContextInfoPill(
            icon: controller.isAuthenticating
                ? Icons.sync_rounded
                : Icons.radar_rounded,
            label: 'Session',
            value: statusCaption,
          ),
          // const SizedBox(height: 18),
          // const _JourneyStep(
          //   done: true,
          //   active: false,
          //   title: 'Scan and connect',
          //   subtitle: 'Nearby PLC discovered and paired.',
          // ),
          // const SizedBox(height: 8),
          // const _JourneyStep(
          //   done: false,
          //   active: true,
          //   title: 'Authenticate operator',
          //   subtitle: 'Confirm access credentials with PLC14.',
          // ),
          // const SizedBox(height: 8),
          // const _JourneyStep(
          //   done: false,
          //   active: false,
          //   title: 'Open controls',
          //   subtitle: 'Control screen unlocks after success.',
          // ),
        ],
      ),
    );
  }

  Widget _buildFormPanel({
    required CraneController controller,
    required bool isWide,
  }) {
    final authSessionReady = _hasAuthenticationSession(controller);
    final errorState = _resolveErrorState(controller.errorMessage);

    return Container(
      padding: EdgeInsets.all(isWide ? 26 : 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: AppColors.surface,
        border: Border.all(color: AppColors.connBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Operator Login',
            style: TextStyle(
              color: AppColors.connText,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Sign in to start a secure crane control session.',
            style: TextStyle(color: AppColors.connTextMuted, fontSize: 13.5),
          ),
          const SizedBox(height: 14),
          _buildLiveStatusBanner(controller),
          if (controller.isAuthenticating) ...[
            const SizedBox(height: 12),
            const _BusyCard(),
          ],
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: errorState == null
                ? const SizedBox.shrink()
                : Padding(
                    key: ValueKey(errorState.message),
                    padding: const EdgeInsets.only(top: 12),
                    child: _AuthErrorCard(
                      state: errorState,
                      onRetry: controller.isAuthenticating ? null : _submit,
                      onBackToScan: controller.disconnect,
                    ),
                  ),
          ),
          if (!authSessionReady) ...[
            const SizedBox(height: 12),
            _AuthErrorCard(
              state: const _AuthErrorState(
                title: 'Connection ended',
                message:
                    'The authentication link is no longer active. Return to scan and reconnect to PLC14.',
                icon: Icons.bluetooth_disabled_rounded,
              ),
              onBackToScan: controller.disconnect,
            ),
          ],
          const SizedBox(height: 16),
          Form(
            key: _formKey,
            autovalidateMode: _autovalidateMode,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _emailController,
                  enabled: !controller.isAuthenticating,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(
                    color: AppColors.connText,
                    fontSize: 14,
                  ),
                  decoration: _inputDecoration(
                    label: 'Operator email',
                    hint: 'operator@company.com',
                    icon: Icons.alternate_email_rounded,
                  ),
                  validator: (value) {
                    final candidate = value?.trim() ?? '';
                    if (candidate.isEmpty) {
                      return 'Email is required to authenticate with PLC14.';
                    }
                    final validEmail = RegExp(
                      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                    ).hasMatch(candidate);
                    if (!validEmail) {
                      return 'Enter a valid email format (example: user@domain.com).';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  enabled: !controller.isAuthenticating,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  style: const TextStyle(
                    color: AppColors.connText,
                    fontSize: 14,
                  ),
                  decoration: _inputDecoration(
                    label: 'Password',
                    hint: 'Enter your password',
                    icon: Icons.lock_outline_rounded,
                    suffix: IconButton(
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: AppColors.connTextMuted,
                        size: 20,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Password is required for operator access.';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Remember credentials on this device',
                        style: TextStyle(
                          color: AppColors.connTextSub.withValues(
                            alpha: 0.85,
                          ),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Switch.adaptive(
                      value: controller.rememberCredentials,
                      activeThumbColor: AppColors.scanning,
                      activeTrackColor: AppColors.scanning.withValues(
                        alpha: 0.35,
                      ),
                      onChanged: controller.isAuthenticating
                          ? null
                          : controller.setRememberCredentials,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: controller.isAuthenticating ? null : _submit,
              icon: controller.isAuthenticating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.lock_open_rounded, size: 18),
              label: Text(
                controller.isAuthenticating
                    ? 'AUTHENTICATING...'
                    : 'AUTHENTICATE SESSION',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.scanning,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.neutral,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: controller.isAuthenticating
                      ? null
                      : controller.disconnect,
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: const Text('Back to Scan'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.connTextSub,
                    side: const BorderSide(color: AppColors.connBorder),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              // const SizedBox(width: 8),
              // Expanded(
              //   child: TextButton.icon(
              //     onPressed: controller.isAuthenticating
              //         ? null
              //         : _showDefaultCredentials,
              //     icon: const Icon(Icons.admin_panel_settings_outlined, size: 16),
              //     label: const Text('Default Login'),
              //     style: TextButton.styleFrom(
              //       foregroundColor: AppColors.connPrimary,
              //       padding: const EdgeInsets.symmetric(vertical: 12),
              //       shape: RoundedRectangleBorder(
              //         borderRadius: BorderRadius.circular(12),
              //         side: const BorderSide(color: AppColors.primarySoft),
              //       ),
              //     ),
              //   ),
              // ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLiveStatusBanner(CraneController controller) {
    final status = controller.connectionState.status;
    final bool busy = controller.isAuthenticating;
    final Color tone = switch (status) {
      BleConnectionStatus.awaitingAuthentication ||
      BleConnectionStatus.authenticating => AppColors.scanning,
      BleConnectionStatus.error => AppColors.error,
      _ => AppColors.neutral,
    };
    final String message = switch (status) {
      BleConnectionStatus.awaitingAuthentication =>
        'Connected and waiting for credentials.',
      BleConnectionStatus.authenticating =>
        'Credentials are being verified by PLC14.',
      BleConnectionStatus.error =>
        'Authentication needs attention before continuing.',
      _ => 'Return to scanning if connection is unavailable.',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: busy
                ? CircularProgressIndicator(strokeWidth: 2.2, color: tone)
                : Icon(Icons.info_outline_rounded, color: tone, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.connTextSub,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.connTextMuted),
      labelStyle: const TextStyle(color: AppColors.connTextMuted),
      prefixIcon: Icon(icon, color: AppColors.connTextMuted, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF8FAFD),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.connBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.connBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: AppColors.scanning,
          width: 1.6,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error, width: 1.6),
      ),
    );
  }

  bool _hasAuthenticationSession(CraneController controller) {
    final status = controller.connectionState.status;
    final hasDevice = controller.connectionState.connectedDevice != null;
    return status == BleConnectionStatus.awaitingAuthentication ||
        status == BleConnectionStatus.authenticating ||
        (status == BleConnectionStatus.error && hasDevice);
  }

  String _statusTitle(BleConnectionStatus status) {
    return switch (status) {
      BleConnectionStatus.awaitingAuthentication => 'READY',
      BleConnectionStatus.authenticating => 'AUTHENTICATING',
      BleConnectionStatus.error => 'RETRY REQUIRED',
      _ => 'PENDING',
    };
  }

  String _statusSubtitle(BleConnectionStatus status) {
    return switch (status) {
      BleConnectionStatus.awaitingAuthentication =>
        'Waiting for operator credentials',
      BleConnectionStatus.authenticating => 'Handshake in progress',
      BleConnectionStatus.error => 'Action required',
      _ => 'Link state unavailable',
    };
  }

  _AuthErrorState? _resolveErrorState(String? message) {
    if (message == null || message.trim().isEmpty) {
      return null;
    }

    final raw = message.trim();
    final normalized = raw.toLowerCase();

    if (raw == BLEConstants.authFailed ||
        normalized.contains('credentials were rejected')) {
      return const _AuthErrorState(
        title: 'Invalid credentials',
        message:
            'The PLC rejected this email or password. Check both fields and try again.',
        icon: Icons.lock_person_rounded,
      );
    }

    if (raw == BLEConstants.authTimeout || normalized.contains('timed out')) {
      return const _AuthErrorState(
        title: 'Authentication timeout',
        message:
            'PLC14 or User did not respond in time. Stay close to the device and retry.',
        icon: Icons.timer_off_rounded,
      );
    }

    if (normalized.contains('not ready') ||
        normalized.contains('connection') ||
        normalized.contains('disconnect')) {
      return const _AuthErrorState(
        title: 'Connection issue',
        message:
            'The BLE session became unstable during login. Return to scan and reconnect.',
        icon: Icons.bluetooth_disabled_rounded,
      );
    }

    return _AuthErrorState(
      title: 'Authentication error',
      message: raw,
      icon: Icons.error_outline_rounded,
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _autovalidateMode = AutovalidateMode.onUserInteraction;
    });

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final controller = context.read<CraneController>();
    if (!_hasAuthenticationSession(controller)) {
      _showSnack(
        'Connection session ended. Return to scan and reconnect before retrying.',
      );
      return;
    }

    final success = await controller.authenticate(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted || success) {
      return;
    }

    final resolved = _resolveErrorState(controller.errorMessage);
    if (resolved != null) {
      _showSnack('${resolved.title}: ${resolved.message}');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          backgroundColor: AppColors.error,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
  }
}

class _BeaconPulse extends StatelessWidget {
  const _BeaconPulse({required this.animation, required this.active});

  final Animation<double> animation;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final progress = animation.value;
        final waveScale = 1 + (progress * 0.35);
        final innerScale = 0.88 + (progress * 0.2);
        final waveOpacity = active ? (0.4 - (progress * 0.35)) : 0.08;

        return SizedBox(
          width: 130,
          height: 130,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: waveScale,
                child: Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(
                      alpha: waveOpacity.clamp(0.05, 0.42).toDouble(),
                    ),
                  ),
                ),
              ),
              Transform.scale(
                scale: innerScale,
                child: Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
              child!,
            ],
          ),
        );
      },
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.96),
        ),
        child: const Icon(
          Icons.bluetooth_searching_rounded,
          color: AppColors.connPrimary,
          size: 34,
        ),
      ),
    );
  }
}

class _ContextInfoPill extends StatelessWidget {
  const _ContextInfoPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _JourneyStep extends StatelessWidget {
  const _JourneyStep({
    required this.done,
    required this.active,
    required this.title,
    required this.subtitle,
  });

  final bool done;
  final bool active;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final Color iconColor = done || active
        ? Colors.white
        : Colors.white.withValues(alpha: 0.55);
    final Color bubbleColor = done
        ? Colors.white.withValues(alpha: 0.26)
        : active
        ? Colors.white.withValues(alpha: 0.22)
        : Colors.white.withValues(alpha: 0.1);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: bubbleColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          ),
          child: Icon(
            done
                ? Icons.check_rounded
                : active
                ? Icons.adjust_rounded
                : Icons.circle_outlined,
            color: iconColor,
            size: 14,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withValues(
                    alpha: done || active ? 0.98 : 0.7,
                  ),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.74),
                  fontSize: 11.5,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BusyCard extends StatelessWidget {
  const _BusyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppColors.scanningBg,
        border: Border.all(color: AppColors.scanningBorder),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Authenticating with PLC14...',
            style: TextStyle(
              color: AppColors.scanning,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          SizedBox(height: 7),
          LinearProgressIndicator(
            minHeight: 4,
            backgroundColor: Color(0xFFC8DBF3),
            valueColor: AlwaysStoppedAnimation<Color>(
              AppColors.scanning,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Waiting for controller response. This usually takes a few seconds.',
            style: TextStyle(
              color: AppColors.connTextSub,
              fontSize: 12,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthErrorState {
  const _AuthErrorState({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;
}

class _AuthErrorCard extends StatelessWidget {
  const _AuthErrorCard({required this.state, this.onRetry, this.onBackToScan});

  final _AuthErrorState state;
  final VoidCallback? onRetry;
  final VoidCallback? onBackToScan;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppColors.errorBg,
        border: Border.all(color: AppColors.errorBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(state.icon, color: AppColors.error, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.title,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            state.message,
            style: const TextStyle(
              color: AppColors.connTextSub,
              fontSize: 12.5,
              height: 1.3,
            ),
          ),
          if (onRetry != null || onBackToScan != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onRetry != null)
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: const Text('Retry'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: Size.zero,
                    ),
                  ),
                // if (onBackToScan != null)
                //   OutlinedButton.icon(
                //     onPressed: onBackToScan,
                //     icon: const Icon(Icons.bluetooth_searching_rounded, size: 14),
                //     label: const Text('Back to scan'),
                //     style: OutlinedButton.styleFrom(
                //       foregroundColor: AppColors.error,
                //       side: BorderSide(
                //         color: AppColors.error.withValues(alpha: 0.35),
                //       ),
                //       padding: const EdgeInsets.symmetric(
                //         horizontal: 12,
                //         vertical: 10,
                //       ),
                //       textStyle: const TextStyle(
                //         fontSize: 12,
                //         fontWeight: FontWeight.w700,
                //       ),
                //       tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                //       minimumSize: Size.zero,
                //     ),
                //   ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
