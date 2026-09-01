import 'package:flutter/material.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/features/operator_auth/security/administrator_credential_service.dart';

const bool administratorCommissioningEnabled = bool.fromEnvironment(
  'ADMIN_COMMISSIONING_ENABLED',
  defaultValue: false,
);

Future<bool> requestAdministratorAuthorization(
  BuildContext context, {
  AdministratorCredentialService? service,
}) async {
  final credentialService = service ?? AdministratorCredentialService();
  final commissioned = await credentialService.isCommissioned;
  if (!context.mounted) return false;

  if (!commissioned && !administratorCommissioningEnabled) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Administrator access is not commissioned'),
        content: const Text(
          'Operator Management remains locked. Commission this device using an explicitly enabled deployment build; there is no default password and PLC credentials cannot be used here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    return false;
  }

  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _AdministratorCredentialDialog(
          service: credentialService,
          commissioning: !commissioned,
        ),
      ) ??
      false;
}

class _AdministratorCredentialDialog extends StatefulWidget {
  const _AdministratorCredentialDialog({
    required this.service,
    required this.commissioning,
  });

  final AdministratorCredentialService service;
  final bool commissioning;

  @override
  State<_AdministratorCredentialDialog> createState() =>
      _AdministratorCredentialDialogState();
}

class _AdministratorCredentialDialogState
    extends State<_AdministratorCredentialDialog> {
  final _formKey = GlobalKey<FormState>();
  final _credential = TextEditingController();
  final _confirmation = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _credential.clear();
    _confirmation.clear();
    _credential.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.commissioning) {
        await widget.service.commission(_credential.text);
        if (mounted) Navigator.of(context).pop(true);
        return;
      }

      final result = await widget.service.verify(_credential.text);
      if (!mounted) return;
      switch (result.status) {
        case AdministratorVerificationStatus.success:
          Navigator.of(context).pop(true);
        case AdministratorVerificationStatus.temporarilyLocked:
          final seconds = result.retryAfter?.inSeconds ?? 30;
          setState(() => _error = 'Too many attempts. Retry in $seconds seconds.');
        case AdministratorVerificationStatus.invalidCredential:
          setState(() => _error = 'Administrator credential was not accepted.');
        case AdministratorVerificationStatus.notCommissioned:
          setState(() => _error = 'Administrator access is not commissioned.');
      }
    } on AdministratorCredentialException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Secure administrator storage is unavailable.');
      }
    } finally {
      _credential.clear();
      _confirmation.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final commissioning = widget.commissioning;
    return AlertDialog(
      title: Text(
        commissioning
            ? 'Commission Administrator Access'
            : 'Administrator Authorization',
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                commissioning
                    ? 'Enter the deployment-provided local PIN or password. Only a salted verifier will be stored in Keystore-backed secure storage.'
                    : 'Face identity and PLC credentials cannot unlock administrator functions.',
                style: const TextStyle(
                  color: AppColors.brandTextSub,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _credential,
                enabled: !_busy,
                autofocus: true,
                obscureText: _obscure,
                enableSuggestions: false,
                autocorrect: false,
                textInputAction: commissioning
                    ? TextInputAction.next
                    : TextInputAction.done,
                onFieldSubmitted: commissioning ? null : (_) => _submit(),
                decoration: InputDecoration(
                  labelText: commissioning
                      ? 'Administrator PIN or password'
                      : 'Administrator credential',
                  prefixIcon: const Icon(Icons.admin_panel_settings_rounded),
                  suffixIcon: IconButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                    ),
                  ),
                ),
                validator: (value) {
                  if (!commissioning) {
                    return (value ?? '').isEmpty
                        ? 'Administrator credential is required.'
                        : null;
                  }
                  return AdministratorCredentialService.validateCredential(
                    value ?? '',
                  );
                },
              ),
              if (commissioning) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmation,
                  enabled: !_busy,
                  obscureText: _obscure,
                  enableSuggestions: false,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Confirm credential',
                    prefixIcon: Icon(Icons.verified_user_rounded),
                  ),
                  validator: (value) => value != _credential.text
                      ? 'Credentials do not match.'
                      : null,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.brandDanger,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.lock_open_rounded),
          label: Text(commissioning ? 'Commission' : 'Authorize'),
        ),
      ],
    );
  }
}
