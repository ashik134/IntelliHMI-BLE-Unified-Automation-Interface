import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/models/auth_log_entry.dart';
import 'package:rev_crane_control_ops/services/admin_access_pin_service.dart';
import 'package:rev_crane_control_ops/services/auth_audit_log_service.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';

/// Gates Operator Management behind the Administrator Access PIN — showing
/// a setup form the first time (no PIN exists yet) or a verify form every
/// subsequent time (there's no persistent administrator session until
/// Stage 4). Returns `true` only once the PIN has been created or
/// correctly verified.
Future<bool> requireAdminPin(BuildContext context) async {
  final alreadySet = await AdminAccessPinService.isSet();
  if (!context.mounted) return false;

  final auditLog = context.read<AuthAuditLogService>();

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AdminPinGateSheet(setupMode: !alreadySet, auditLog: auditLog),
  );

  return result ?? false;
}

class _AdminPinGateSheet extends StatefulWidget {
  const _AdminPinGateSheet({required this.setupMode, required this.auditLog});

  final bool setupMode;
  final AuthAuditLogService auditLog;

  @override
  State<_AdminPinGateSheet> createState() => _AdminPinGateSheetState();
}

class _AdminPinGateSheetState extends State<_AdminPinGateSheet> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _errorText;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pinController.text.trim();

    if (!AdminAccessPinService.isValidPinFormat(pin)) {
      setState(
        () => _errorText =
            'PIN must be at least ${AdminAccessPinService.minPinLength} digits.',
      );
      return;
    }

    if (widget.setupMode) {
      if (pin != _confirmController.text.trim()) {
        setState(() => _errorText = 'PINs do not match.');
        return;
      }
      setState(() {
        _busy = true;
        _errorText = null;
      });
      await AdminAccessPinService.setPin(pin);
      unawaited(
        widget.auditLog.record(
          result: AuthEventResult.success,
          method: AuthEventMethod.pin,
          detailCode: 'admin_access_pin_created',
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _busy = true;
      _errorText = null;
    });
    final outcome = await AdminAccessPinService.verify(pin);
    if (!mounted) return;

    switch (outcome) {
      case AdminPinVerifyResult.success:
        unawaited(
          widget.auditLog.record(
            result: AuthEventResult.success,
            method: AuthEventMethod.pin,
            detailCode: 'admin_access_pin',
          ),
        );
        Navigator.of(context).pop(true);
      case AdminPinVerifyResult.incorrect:
        unawaited(
          widget.auditLog.record(
            result: AuthEventResult.failed,
            method: AuthEventMethod.pin,
            detailCode: 'admin_access_pin',
            failureReason: 'Incorrect Administrator Access PIN.',
          ),
        );
        setState(() {
          _busy = false;
          _errorText = 'Incorrect PIN.';
        });
        _pinController.clear();
      case AdminPinVerifyResult.lockedOut:
        final remaining = await AdminAccessPinService.remainingLockoutSeconds();
        unawaited(
          widget.auditLog.record(
            result: AuthEventResult.failed,
            method: AuthEventMethod.pin,
            detailCode: 'admin_access_pin_locked_out',
            failureReason: 'Too many incorrect attempts.',
          ),
        );
        if (!mounted) return;
        setState(() {
          _busy = false;
          _errorText = 'Too many attempts. Try again in ${_formatDuration(remaining)}.';
        });
        _pinController.clear();
    }
  }

  static String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    if (minutes <= 0) return '${secs}s';
    return '${minutes}m ${secs}s';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(
                      Icons.admin_panel_settings_outlined,
                      color: AppColors.connPrimary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.setupMode
                            ? 'Create Administrator Access PIN'
                            : 'Administrator Access PIN',
                        style: const TextStyle(
                          color: AppColors.connText,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  widget.setupMode
                      ? 'This device has no Administrator Access PIN yet. '
                            'Create one now — it gates Operator Management '
                            'and cannot be reset from within the app.'
                      : 'Enter the Administrator Access PIN to manage '
                            'operators.',
                  style: const TextStyle(
                    color: AppColors.connTextMuted,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pinController,
                  enabled: !_busy,
                  autofocus: true,
                  style: const TextStyle(color: AppColors.connText),
                  obscureText: _obscure,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 10,
                  onSubmitted: (_) => widget.setupMode ? null : _submit(),
                  decoration: InputDecoration(
                    labelText: widget.setupMode ? 'New PIN' : 'PIN',
                    counterText: '',
                    prefixIcon: const Icon(Icons.pin_outlined, size: 19),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        size: 18,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    filled: true,
                    fillColor: AppColors.connBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                if (widget.setupMode) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _confirmController,
                    enabled: !_busy,
                    obscureText: _obscure,
                     style: const TextStyle(color: AppColors.connText),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 10,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Confirm PIN',
                      counterText: '',
                      prefixIcon: const Icon(Icons.pin_outlined, size: 19),
                      filled: true,
                      fillColor: AppColors.connBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
                if (_errorText != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _errorText!,
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.connPrimary,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(widget.setupMode ? 'Create PIN' : 'Verify'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
