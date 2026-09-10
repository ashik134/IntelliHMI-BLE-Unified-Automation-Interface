import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/models/ble_connection_state.dart';
import 'package:rev_crane_control_ops/models/operator_profile.dart';
import 'package:rev_crane_control_ops/services/biometric_service.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/widgets/shared/brand_widgets.dart';

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

  // Tracks the last error message to avoid showing duplicate snackbars.
  String? _lastShownError;

  // Local-only: true while the device biometric prompt / the follow-up PLC
  // round-trip it triggers is in flight. Distinct from
  // controller.isAuthenticating so the biometric button can show its own
  // spinner without the manual form fields also disabling mid-scan — both
  // paths end up inside the SAME controller.authenticate() call, so once the
  // PLC round-trip actually starts, controller.isAuthenticating covers it too.
  bool _biometricInFlight = false;
  _AuthErrorState? _biometricError;

  CraneController? _controllerRef;

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

    final controller = context.read<CraneController>();

    // Attach controller listener once.
    if (_controllerRef != controller) {
      _controllerRef?.removeListener(_onControllerChanged);
      _controllerRef = controller;
      controller.addListener(_onControllerChanged);
    }

    if (_seeded) {
      return;
    }

    _emailController.text = controller.savedEmail;
    _seeded = true;
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final controller = _controllerRef;
    if (controller == null) return;

    final message = controller.errorMessage;
    if (message == null || message == _lastShownError) return;

    final isTimeout =
        message == BLEConstants.authTimeout ||
        message.toLowerCase().contains('timed out');

    if (isTimeout) {
      _lastShownError = message;
      _showTimedOutSnack();
    }
  }

  void _showTimedOutSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 5),
          backgroundColor: AppColors.brandWarning,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          ),
          content: const Row(
            children: [
              Icon(Icons.timer_off_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Authentication Timed Out',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'PLC did not receive credentials in time. Please try again.',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }

  @override
  void dispose() {
    _controllerRef?.removeListener(_onControllerChanged);
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
      backgroundColor: AppColors.brandBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 920;
            final edgePadding = constraints.maxWidth >= 1100 ? 28.0 : 16.0;

            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(edgePadding, 16, edgePadding, 18),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1080),
                      child: isWide
                          ? IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: _contextPanel(controller),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    flex: 6,
                                    child: _buildFormPanel(
                                      controller: controller,
                                      isWide: true,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _contextPanel(controller),
                                const SizedBox(height: 14),
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
            );
          },
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
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppMetrics.radiusXl),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brandInk, AppColors.brandInkAlt],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -70,
            right: -70,
            child: IgnorePointer(
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.brandViolet.withAlpha(40),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  BrandMark(size: 36, dark: true),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'INTELLIHMI',
                      style: TextStyle(
                        color: AppColors.brandOnDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const BrandBadge(
                label: 'SECURE BLE LINK',
                tone: BrandTone.violet,
                icon: Icons.shield_rounded,
              ),
              const SizedBox(height: 22),
              Center(
                child: _BeaconPulse(
                  animation: _pulseController,
                  active: controller.isAuthenticating || linkReady,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Authenticate Operator Session',
                style: TextStyle(
                  color: AppColors.brandOnDark,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Connection is established. Verify credentials before crane commands are enabled.',
                style: TextStyle(
                  color: AppColors.brandOnDarkSub,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
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
            ],
          ),
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
    // Access-denied is PLC-authenticated at the transport level but must
    // never render as a success — it renders the error-banner branch below
    // instead, same as every other authentication failure in this flow.
    final authenticated = controller.isAuthenticated && !controller.isAccessDenied;
    final verifiedOperator = controller.verifiedOperator;

    return Container(
      padding: EdgeInsets.all(isWide ? 28 : 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppMetrics.radiusXl),
        color: AppColors.brandSurface,
        border: Border.all(color: AppColors.brandBorder),
        boxShadow: AppMetrics.shadowMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (verifiedOperator != null) ...[
            _VerifiedOperatorCard(operatorProfile: verifiedOperator),
            const SizedBox(height: 18),
          ],
          Text(
            verifiedOperator != null ? 'PLC Authentication' : 'Operator Login',
            style: const TextStyle(
              color: AppColors.brandText,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            verifiedOperator != null
                ? 'Enter PLC credentials to open a secure control session.'
                : 'Sign in to start a secure crane control session.',
            style: const TextStyle(
              color: AppColors.brandTextSub,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 16),
          _buildLiveStatusBanner(controller),
          if (authenticated) ...[
            const SizedBox(height: 16),
            _AuthenticatedCard(
              biometricAvailable: controller.isBiometricAvailable,
              showEnrollmentOffer: controller.hasPendingEnrollmentOffer,
              enrolling: controller.isAuthenticating,
              onContinue: () => _continueAfterAuthentication(controller),
              onEnroll:
                  controller.isBiometricAvailable &&
                      controller.hasPendingEnrollmentOffer
                  ? () => _continueAfterAuthentication(
                      controller,
                      enrollBiometric: true,
                    )
                  : null,
            ),
          ],
          if (controller.isAuthenticating) ...[
            const SizedBox(height: 12),
            const _BusyCard(),
          ],
          if (!authenticated) ...[
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
                        onVerifyIdentity:
                            !controller.isDeviceConfigured &&
                                errorState.title == 'Invalid credentials'
                            ? controller.requestIdentityVerificationFallback
                            : null,
                      ),
                    ),
            ),
            if (!authSessionReady) ...[
              const SizedBox(height: 12),
              _AuthErrorCard(
                state: const _AuthErrorState(
                  title: 'Connection ended',
                  message:
                      'The authentication link is no longer active. Return to scan and reconnect to the PLC.',
                  icon: Icons.bluetooth_disabled_rounded,
                ),
                onBackToScan: controller.disconnect,
              ),
            ],
          ],
          if (!authenticated &&
              controller.isBiometricAvailable &&
              controller.isBiometricEnrolled) ...[
            const SizedBox(height: 18),
            _BiometricLoginButton(
              busy: _biometricInFlight,
              enabled: !controller.isAuthenticating && !_biometricInFlight,
              onPressed: _submitBiometric,
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _biometricError == null
                  ? const SizedBox.shrink()
                  : Padding(
                      key: ValueKey('biometric_${_biometricError!.message}'),
                      padding: const EdgeInsets.only(top: 12),
                      child: _AuthErrorCard(state: _biometricError!),
                    ),
            ),
            const _OrDivider(label: 'OR SIGN IN WITH CREDENTIALS'),
          ],
          if (!authenticated) ...[
            const SizedBox(height: 18),
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
                      color: AppColors.brandText,
                      fontSize: 14,
                    ),
                    decoration: brandInputDecoration(
                      label: 'Operator email',
                      hint: 'operator@company.com',
                      icon: Icons.alternate_email_rounded,
                    ),
                    validator: (value) {
                      final candidate = value?.trim() ?? '';
                      if (candidate.isEmpty) {
                        return 'Email is required to authenticate with the PLC.';
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
                      color: AppColors.brandText,
                      fontSize: 14,
                    ),
                    decoration: brandInputDecoration(
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
                          color: AppColors.brandTextMuted,
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
                          'Remember operator email',
                          style: TextStyle(
                            color: AppColors.brandTextSub.withValues(
                              alpha: 0.9,
                            ),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Switch.adaptive(
                        value: controller.rememberOperatorEmail,
                        activeThumbColor: AppColors.brandViolet,
                        activeTrackColor: AppColors.brandViolet.withValues(
                          alpha: 0.35,
                        ),
                        onChanged: controller.isAuthenticating
                            ? null
                            : controller.setRememberOperatorEmail,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            BrandPrimaryButton(
              label: controller.isAuthenticating
                  ? 'AUTHENTICATING...'
                  : 'AUTHENTICATE SESSION',
              icon: Icons.lock_open_rounded,
              busy: controller.isAuthenticating,
              onPressed: _submit,
            ),
            const SizedBox(height: 10),
            BrandSecondaryButton(
              label: 'Back to Scan',
              icon: Icons.arrow_back_rounded,
              onPressed: controller.isAuthenticating
                  ? null
                  : controller.disconnect,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveStatusBanner(CraneController controller) {
    final status = controller.connectionState.status;
    final bool busy = controller.isAuthenticating;
    final BrandTone tone = switch (status) {
      BleConnectionStatus.connected ||
      BleConnectionStatus.awaitingAuthentication ||
      BleConnectionStatus.authenticating => BrandTone.violet,
      BleConnectionStatus.authenticated => BrandTone.success,
      BleConnectionStatus.error => BrandTone.danger,
      _ => BrandTone.neutral,
    };
    final String message = switch (status) {
      BleConnectionStatus.connected ||
      BleConnectionStatus.awaitingAuthentication =>
        'Connected and waiting for credentials.',
      BleConnectionStatus.authenticating =>
        'Credentials are being verified by the PLC.',
      BleConnectionStatus.authenticated =>
        'Authentication accepted by the PLC.',
      BleConnectionStatus.error =>
        'Authentication needs attention before continuing.',
      _ => 'Return to scanning if connection is unavailable.',
    };

    final colors = _toneFgBg(tone);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.$2,
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        border: Border.all(color: colors.$1.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: busy
                ? CircularProgressIndicator(strokeWidth: 2.2, color: colors.$1)
                : Icon(Icons.info_outline_rounded, color: colors.$1, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.brandTextSub,
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

  (Color, Color) _toneFgBg(BrandTone tone) => switch (tone) {
    BrandTone.violet => (AppColors.brandViolet, AppColors.brandVioletSoft),
    BrandTone.success => (AppColors.brandSuccess, AppColors.brandSuccessSoft),
    BrandTone.warning => (AppColors.brandWarning, AppColors.brandWarningSoft),
    BrandTone.danger => (AppColors.brandDanger, AppColors.brandDangerSoft),
    BrandTone.info => (AppColors.brandInfo, AppColors.brandInfoSoft),
    BrandTone.neutral => (AppColors.brandTextSub, AppColors.brandSurfaceAlt),
  };

  bool _hasAuthenticationSession(CraneController controller) {
    final status = controller.connectionState.status;
    final hasDevice = controller.connectionState.connectedDevice != null;
    return status == BleConnectionStatus.awaitingAuthentication ||
        (status == BleConnectionStatus.connected && hasDevice) ||
        status == BleConnectionStatus.authenticating ||
        (status == BleConnectionStatus.authenticated && hasDevice) ||
        (status == BleConnectionStatus.error && hasDevice);
  }

  String _statusTitle(BleConnectionStatus status) {
    return switch (status) {
      BleConnectionStatus.awaitingAuthentication => 'READY',
      BleConnectionStatus.connected => 'READY',
      BleConnectionStatus.authenticating => 'AUTHENTICATING',
      BleConnectionStatus.authenticated => 'AUTHENTICATED',
      BleConnectionStatus.error => 'RETRY REQUIRED',
      _ => 'PENDING',
    };
  }

  String _statusSubtitle(BleConnectionStatus status) {
    return switch (status) {
      BleConnectionStatus.awaitingAuthentication =>
        'Waiting for operator credentials',
      BleConnectionStatus.connected => 'Waiting for operator credentials',
      BleConnectionStatus.authenticating => 'Handshake in progress',
      BleConnectionStatus.authenticated => 'Operator verified',
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

    if (raw.startsWith('ACCESS DENIED')) {
      return _AuthErrorState(
        title: 'Access denied',
        message: raw.replaceFirst(RegExp(r'^ACCESS DENIED\n?'), ''),
        icon: Icons.block_rounded,
      );
    }

    if (raw == BLEConstants.authTimeout) {
      return const _AuthErrorState(
        title: 'Authentication timeout',
        message:
            'PLC did not respond in time. Stay close to the device and retry.',
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

    final controller = context.read<CraneController>();
    if (controller.isAuthenticated && !controller.isAccessDenied) {
      _continueAfterAuthentication(controller);
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

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

  Future<void> _submitBiometric() async {
    final controller = context.read<CraneController>();
    if (controller.isAuthenticated && !controller.isAccessDenied) {
      _continueAfterAuthentication(controller);
      return;
    }

    if (!_hasAuthenticationSession(controller)) {
      _showSnack(
        'Connection session ended. Return to scan and reconnect before retrying.',
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _biometricInFlight = true;
      _biometricError = null;
    });

    final result = await controller.authenticateWithBiometrics();

    if (!mounted) return;

    // Cancellation is not an error — the operator changed their mind or the
    // OS prompt was dismissed. Stay on the page with no banner, exactly as
    // if they'd never tapped the button (per the "stay on the Authentication
    // Page" requirement for failed/cancelled biometric attempts).
    if (result.isCancelled) {
      setState(() => _biometricInFlight = false);
      return;
    }

    if (!result.isSuccess) {
      setState(() {
        _biometricInFlight = false;
        _biometricError = _errorStateForBiometricResult(result);
      });
      return;
    }

    setState(() => _biometricInFlight = false);
    // Success already ran the real PLC authenticate() call underneath (see
    // CraneController.authenticateWithBiometrics) — controller.isAuthenticated
    // now reflects a genuine PLC-verified session, so the existing
    // "authenticated" branch of the form just renders itself via the
    // controller listener; nothing else to trigger here.
  }

  _AuthErrorState _errorStateForBiometricResult(BiometricAuthResult result) {
    final message = result.message ?? 'Biometric authentication failed.';
    return switch (result.status) {
      BiometricAuthStatus.notEnrolled => _AuthErrorState(
        title: 'No biometrics enrolled',
        message: message,
        icon: Icons.fingerprint_rounded,
      ),
      BiometricAuthStatus.notAvailable => _AuthErrorState(
        title: 'Biometrics unavailable',
        message: message,
        icon: Icons.no_encryption_gmailerrorred_rounded,
      ),
      BiometricAuthStatus.lockedOut => _AuthErrorState(
        title: 'Biometrics temporarily locked',
        message: message,
        icon: Icons.lock_clock_rounded,
      ),
      BiometricAuthStatus.permanentlyLockedOut => _AuthErrorState(
        title: 'Biometrics locked',
        message: message,
        icon: Icons.lock_rounded,
      ),
      BiometricAuthStatus.credentialsMissing => _AuthErrorState(
        title: 'Biometric login expired',
        message: message,
        icon: Icons.fingerprint_rounded,
      ),
      BiometricAuthStatus.failure => _AuthErrorState(
        title: 'Sign-in rejected',
        message: message,
        icon: Icons.lock_person_rounded,
      ),
      _ => _AuthErrorState(
        title: 'Biometric authentication failed',
        message: message,
        icon: Icons.error_outline_rounded,
      ),
    };
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          backgroundColor: AppColors.brandDanger,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
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

  Future<void> _continueAfterAuthentication(
    CraneController controller, {
    bool enrollBiometric = false,
  }) async {
    if (enrollBiometric) {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      if (email.isNotEmpty && password.isNotEmpty) {
        final enrolled = await controller.enrollBiometrics(
          email: email,
          password: password,
        );
        if (!mounted) return;
        if (!enrolled) {
          _showSnack('Could not save biometric login on this device.');
          return;
        }
      }
    }
    controller.completePendingEnrollmentOffer();
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
                    color: AppColors.brandViolet.withValues(
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
                      color: AppColors.brandViolet.withValues(alpha: 0.5),
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
          gradient: const LinearGradient(
            colors: [AppColors.brandViolet, AppColors.brandVioletDeep],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.brandViolet.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(
          Icons.bluetooth_searching_rounded,
          color: Colors.white,
          size: 34,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Verified operator card — shows the face-verification result (see
// FaceVerificationScreen / CraneController.verifiedOperator) before the
// PLC credential fields. Purely informational: identifies who is
// attempting to authenticate, never itself grants PLC access.
// ═══════════════════════════════════════════════════════════════

class _VerifiedOperatorCard extends StatelessWidget {
  const _VerifiedOperatorCard({required this.operatorProfile});

  final OperatorProfile operatorProfile;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        color: AppColors.brandSuccessSoft,
        border: Border.all(color: AppColors.brandSuccess.withAlpha(70)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.brandSuccess.withAlpha(30),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: AppColors.brandSuccess,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Welcome, ${operatorProfile.name}',
                  style: const TextStyle(
                    color: AppColors.brandSuccess,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Employee ID: ${operatorProfile.employeeId}  •  Role: ${operatorProfile.role.displayName}',
                  style: const TextStyle(
                    color: AppColors.brandTextSub,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
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
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.brandViolet),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.brandOnDark.withValues(alpha: 0.7),
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
                color: AppColors.brandOnDark,
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

// ═══════════════════════════════════════════════════════════════
// Biometric sign-in — a convenience local unlock only. Success here
// still runs the real PLC authenticate() call underneath (see
// CraneController.authenticateWithBiometrics); this button never grants
// crane-control access on its own.
// ═══════════════════════════════════════════════════════════════

class _BiometricLoginButton extends StatelessWidget {
  const _BiometricLoginButton({
    required this.busy,
    required this.enabled,
    required this.onPressed,
  });

  final bool busy;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
            color: AppColors.brandVioletSoft,
            border: Border.all(color: AppColors.brandViolet.withAlpha(70)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.brandViolet.withAlpha(60),
                  ),
                ),
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: AppColors.brandViolet,
                        ),
                      )
                    : const Icon(
                        Icons.fingerprint_rounded,
                        color: AppColors.brandViolet,
                        size: 24,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      busy
                          ? 'Verifying biometrics…'
                          : 'Sign in with biometrics',
                      style: const TextStyle(
                        color: AppColors.brandVioletDeep,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      busy
                          ? 'Confirm with fingerprint, face, or device unlock'
                          : 'Use this device\'s fingerprint or face unlock',
                      style: TextStyle(
                        color: AppColors.brandTextSub.withValues(alpha: 0.9),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (!busy)
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: AppColors.brandViolet,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          const Expanded(
            child: Divider(color: AppColors.brandBorder, height: 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.brandTextMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const Expanded(
            child: Divider(color: AppColors.brandBorder, height: 1),
          ),
        ],
      ),
    );
  }
}

class _AuthenticatedCard extends StatelessWidget {
  const _AuthenticatedCard({
    required this.biometricAvailable,
    required this.showEnrollmentOffer,
    required this.enrolling,
    required this.onContinue,
    this.onEnroll,
  });

  final bool biometricAvailable;
  final bool showEnrollmentOffer;
  final bool enrolling;
  final VoidCallback onContinue;
  final VoidCallback? onEnroll;

  @override
  Widget build(BuildContext context) {
    final canOfferBiometrics = biometricAvailable && showEnrollmentOffer;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        color: AppColors.brandSuccessSoft,
        border: Border.all(color: AppColors.brandSuccess.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_user_rounded, color: AppColors.brandSuccess),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Operator verified',
                  style: TextStyle(
                    color: AppColors.brandSuccess,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            canOfferBiometrics
                ? 'The PLC accepted these credentials. Biometric access can be saved on this device before opening controls.'
                : 'The PLC accepted these credentials. Controls are ready to open.',
            style: const TextStyle(
              color: AppColors.brandTextSub,
              fontSize: 12.5,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: enrolling ? null : onContinue,
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Open controls'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandSuccess,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (canOfferBiometrics && onEnroll != null)
                OutlinedButton.icon(
                  onPressed: enrolling ? null : onEnroll,
                  icon: const Icon(Icons.fingerprint_rounded, size: 16),
                  label: const Text('Save biometric login'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brandSuccess,
                    side: BorderSide(
                      color: AppColors.brandSuccess.withValues(alpha: 0.35),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BusyCard extends StatelessWidget {
  const _BusyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        color: AppColors.brandVioletSoft,
        border: Border.all(color: AppColors.brandViolet.withAlpha(60)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Authenticating with PLC...',
            style: TextStyle(
              color: AppColors.brandVioletDeep,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(4)),
            child: LinearProgressIndicator(
              minHeight: 5,
              backgroundColor: Color(0xFFE1D4FC),
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.brandViolet),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Waiting for controller response. This usually takes a few seconds.',
            style: TextStyle(
              color: AppColors.brandTextSub,
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
  const _AuthErrorCard({
    required this.state,
    this.onRetry,
    this.onBackToScan,
    this.onVerifyIdentity,
  });

  final _AuthErrorState state;
  final VoidCallback? onRetry;
  final VoidCallback? onBackToScan;

  /// Shown only for the first-time-setup "invalid credentials" case — an
  /// opt-in detour into Face Verification so an already-enrolled operator
  /// can confirm who they are before retrying their PLC credentials.
  final VoidCallback? onVerifyIdentity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        color: AppColors.brandDangerSoft,
        border: Border.all(color: AppColors.brandDanger.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(state.icon, color: AppColors.brandDanger, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.title,
                  style: const TextStyle(
                    color: AppColors.brandDanger,
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
              color: AppColors.brandTextSub,
              fontSize: 12.5,
              height: 1.3,
            ),
          ),
          if (onRetry != null || onVerifyIdentity != null) ...[
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
                      backgroundColor: AppColors.brandDanger,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppMetrics.radiusSm,
                        ),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: Size.zero,
                    ),
                  ),
                if (onVerifyIdentity != null)
                  OutlinedButton.icon(
                    onPressed: onVerifyIdentity,
                    icon: const Icon(
                      Icons.face_retouching_natural_rounded,
                      size: 14,
                    ),
                    label: const Text('Verify your identity'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.brandDanger,
                      side: BorderSide(
                        color: AppColors.brandDanger.withAlpha(140),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppMetrics.radiusSm,
                        ),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: Size.zero,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
