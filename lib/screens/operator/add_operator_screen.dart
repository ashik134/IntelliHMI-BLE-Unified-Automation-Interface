import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/auth_log_entry.dart';
import 'package:rev_crane_control_ops/models/face_template.dart';
import 'package:rev_crane_control_ops/models/operator_profile.dart';
import 'package:rev_crane_control_ops/models/operator_role.dart';
import 'package:rev_crane_control_ops/repositories/face_template_repository.dart';
import 'package:rev_crane_control_ops/repositories/operator_repository.dart';
import 'package:rev_crane_control_ops/screens/operator/face_enrollment_screen.dart';
import 'package:rev_crane_control_ops/services/auth_audit_log_service.dart';
import 'package:rev_crane_control_ops/widgets/shared/brand_widgets.dart';

class AddOperatorScreen extends StatefulWidget {
  const AddOperatorScreen({
    super.key,
    required this.repository,
    required this.templateRepository,
    required this.auditLog,
    this.forceAdministratorRole = false,
  });

  final OperatorRepository repository;
  final FaceTemplateRepository templateRepository;
  final AuthAuditLogService auditLog;

  /// True when this is the very first operator on the device — the
  /// bootstrap flow requires it to be an Administrator (see Stage 2 plan).
  final bool forceAdministratorRole;

  @override
  State<AddOperatorScreen> createState() => _AddOperatorScreenState();
}

class _AddOperatorScreenState extends State<AddOperatorScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _employeeIdController = TextEditingController();
  late OperatorRole _role;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _role = widget.forceAdministratorRole
        ? OperatorRole.administrator
        : OperatorRole.operator;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _employeeIdController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final employeeId = _employeeIdController.text.trim();
    setState(() => _saving = true);

    // Fast feedback before even opening the camera — the authoritative
    // check happens again in OperatorRepository.add() below.
    final normalizedId = employeeId.toLowerCase();
    final existing = await widget.repository.getAll();
    final alreadyUsed = existing.any(
      (o) => o.employeeId.trim().toLowerCase() == normalizedId,
    );
    if (alreadyUsed) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('Employee ID "$employeeId" is already in use.');
      return;
    }

    final operatorId = const Uuid().v4();
    if (!mounted) return;
    final template = await Navigator.of(context).push<FaceTemplate>(
      MaterialPageRoute<FaceTemplate>(
        fullscreenDialog: true,
        builder: (_) => FaceEnrollmentScreen(
          operatorId: operatorId,
          templateRepository: widget.templateRepository,
        ),
      ),
    );

    if (!mounted) return;
    if (template == null) {
      // Cancelled, or enrollment/duplicate-face check failed inside the
      // capture screen — no operator record is created either way.
      setState(() => _saving = false);
      return;
    }

    final now = DateTime.now();
    final operator = OperatorProfile(
      operatorId: operatorId,
      name: _nameController.text.trim(),
      employeeId: employeeId,
      role: _role,
      faceTemplateId: template.templateId,
      createdAt: now,
      updatedAt: now,
    );

    // Template written first, then the operator profile that references
    // it — the only ordering where a failure between the two writes can
    // never leave an operator record pointing at a template that doesn't
    // exist. If the operator write fails, the just-written template is
    // deleted so no orphan remains.
    await widget.templateRepository.upsert(template);
    try {
      await widget.repository.add(operator);
    } catch (e) {
      await widget.templateRepository.deleteByOperatorId(operatorId);
      if (!mounted) return;
      setState(() => _saving = false);
      _showError(
        e is DuplicateEmployeeIdException
            ? 'Employee ID "$employeeId" is already in use.'
            : 'Could not save the operator. Please try again.',
      );
      return;
    }

    unawaited(
      widget.auditLog.recordOperatorEvent(
        event: OperatorLifecycleEvent.profileCreated,
        operatorId: operator.operatorId,
        operatorNameSnapshot: operator.name,
        role: operator.role.displayName,
      ),
    );
    unawaited(
      widget.auditLog.recordOperatorEvent(
        event: OperatorLifecycleEvent.enrolled,
        operatorId: operator.operatorId,
        operatorNameSnapshot: operator.name,
        role: operator.role.displayName,
      ),
    );

    if (mounted) Navigator.of(context).pop();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.brandDanger),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.brandBg,
      appBar: AppBar(
        backgroundColor: AppColors.brandSurface,
        foregroundColor: AppColors.brandText,
        elevation: 0,
        title: const Text(
          'Add Operator',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.brandText,
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.forceAdministratorRole)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: BrandStatusBanner(
                  icon: Icons.shield_outlined,
                  title: 'First operator on this device',
                  message:
                      'The first operator added is always an Administrator.',
                  tone: BrandTone.info,
                ),
              ),
            TextFormField(
              controller: _nameController,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: brandInputDecoration(
                label: 'Full name',
                icon: Icons.badge_outlined,
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _employeeIdController,
              enabled: !_saving,
              decoration: brandInputDecoration(
                label: 'Employee ID',
                icon: Icons.badge_outlined,
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            if (widget.forceAdministratorRole)
              _LockedRoleField(role: _role)
            else
              DropdownButtonFormField<OperatorRole>(
                initialValue: _role,
                decoration: brandInputDecoration(
                  label: 'Role',
                  icon: Icons.workspace_premium_outlined,
                ),
                items: [
                  for (final role in OperatorRole.values)
                    DropdownMenuItem(
                      value: role,
                      child: Text(role.displayName),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _role = v ?? _role),
              ),
            const SizedBox(height: 24),
            BrandPrimaryButton(
              label: 'Create Operator',
              icon: Icons.check_rounded,
              busy: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _LockedRoleField extends StatelessWidget {
  const _LockedRoleField({required this.role});

  final OperatorRole role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.brandSurfaceAlt,
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        border: Border.all(color: AppColors.brandBorder),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: AppColors.brandTextMuted,
          ),
          const SizedBox(width: 10),
          Text(
            'Role: ${role.displayName}',
            style: const TextStyle(
              color: AppColors.brandTextSub,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
