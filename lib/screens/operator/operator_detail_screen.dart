import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/auth_log_entry.dart';
import 'package:rev_crane_control_ops/models/face_template.dart';
import 'package:rev_crane_control_ops/models/operator_profile.dart';
import 'package:rev_crane_control_ops/models/operator_role.dart';
import 'package:rev_crane_control_ops/repositories/face_template_repository.dart';
import 'package:rev_crane_control_ops/repositories/operator_repository.dart';
import 'package:rev_crane_control_ops/screens/event_log_screen.dart';
import 'package:rev_crane_control_ops/screens/operator/face_enrollment_screen.dart';
import 'package:rev_crane_control_ops/services/auth_audit_log_service.dart';
import 'package:rev_crane_control_ops/widgets/settings/admin_pin_gate_sheet.dart';
import 'package:rev_crane_control_ops/widgets/shared/brand_widgets.dart';

class OperatorDetailScreen extends StatefulWidget {
  const OperatorDetailScreen({
    super.key,
    required this.operator,
    required this.repository,
    required this.templateRepository,
    required this.auditLog,
  });

  final OperatorProfile operator;
  final OperatorRepository repository;
  final FaceTemplateRepository templateRepository;
  final AuthAuditLogService auditLog;

  @override
  State<OperatorDetailScreen> createState() => _OperatorDetailScreenState();
}

class _OperatorDetailScreenState extends State<OperatorDetailScreen> {
  late OperatorProfile _operator;
  bool _editing = false;
  bool _busy = false;

  late final TextEditingController _nameController;
  late final TextEditingController _employeeIdController;
  late OperatorRole _role;

  @override
  void initState() {
    super.initState();
    _operator = widget.operator;
    _nameController = TextEditingController(text: _operator.name);
    _employeeIdController = TextEditingController(text: _operator.employeeId);
    _role = _operator.role;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _employeeIdController.dispose();
    super.dispose();
  }

  void _cancelEdit() {
    setState(() {
      _editing = false;
      _nameController.text = _operator.name;
      _employeeIdController.text = _operator.employeeId;
      _role = _operator.role;
    });
  }

  Future<void> _saveEdits() async {
    setState(() => _busy = true);
    final updated = _operator.copyWith(
      name: _nameController.text.trim(),
      employeeId: _employeeIdController.text.trim(),
      role: _role,
      updatedAt: DateTime.now(),
    );
    await widget.repository.update(updated);
    if (!mounted) return;
    setState(() {
      _operator = updated;
      _editing = false;
      _busy = false;
    });
  }

  Future<void> _toggleEnabled() async {
    setState(() => _busy = true);
    final newEnabled = !_operator.enabled;
    await widget.repository.setEnabled(_operator.operatorId, newEnabled);
    unawaited(
      widget.auditLog.recordOperatorEvent(
        event: newEnabled
            ? OperatorLifecycleEvent.enabled
            : OperatorLifecycleEvent.disabled,
        operatorId: _operator.operatorId,
        operatorNameSnapshot: _operator.name,
        role: _operator.role.displayName,
      ),
    );
    if (!mounted) return;
    setState(() {
      _operator = _operator.copyWith(
        enabled: newEnabled,
        updatedAt: DateTime.now(),
      );
      _busy = false;
    });
  }

  Future<void> _reenrollFace() async {
    final confirmed = await requireAdminPin(context);
    if (!mounted || !confirmed) return;

    final template = await Navigator.of(context).push<FaceTemplate>(
      MaterialPageRoute<FaceTemplate>(
        fullscreenDialog: true,
        builder: (_) => FaceEnrollmentScreen(
          operatorId: _operator.operatorId,
          templateRepository: widget.templateRepository,
        ),
      ),
    );
    if (!mounted || template == null) return;

    setState(() => _busy = true);
    // Template first, then the operator profile that references it —
    // same ordering/reasoning as initial enrollment in AddOperatorScreen.
    await widget.templateRepository.upsert(template);
    final updated = _operator.copyWith(
      faceTemplateId: template.templateId,
      updatedAt: DateTime.now(),
    );
    await widget.repository.update(updated);
    unawaited(
      widget.auditLog.recordOperatorEvent(
        event: OperatorLifecycleEvent.reenrolled,
        operatorId: updated.operatorId,
        operatorNameSnapshot: updated.name,
        role: updated.role.displayName,
      ),
    );
    if (!mounted) return;
    setState(() {
      _operator = updated;
      _busy = false;
    });
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete operator?'),
        content: Text(
          "This permanently removes ${_operator.name}'s profile. "
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.brandDanger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    await widget.repository.delete(_operator.operatorId);
    await widget.templateRepository.deleteByOperatorId(_operator.operatorId);
    unawaited(
      widget.auditLog.recordOperatorEvent(
        event: OperatorLifecycleEvent.deleted,
        operatorId: _operator.operatorId,
        operatorNameSnapshot: _operator.name,
        role: _operator.role.displayName,
      ),
    );
    if (mounted) Navigator.of(context).pop(_operator.operatorId);
  }

  void _viewHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EventLogScreen(
          operatorId: _operator.operatorId,
          titleOverride: '${_operator.name} — History',
        ),
      ),
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
        title: Text(
          _operator.name,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.brandText,
          ),
        ),
        actions: [
          if (!_editing)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: _busy ? null : () => setState(() => _editing = true),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_editing) ..._buildEditForm() else ..._buildViewFields(),
          const SizedBox(height: 20),
          const Divider(color: AppColors.brandBorder),
          const SizedBox(height: 4),
          _ActionTile(
            icon: Icons.face_retouching_natural_outlined,
            label: _operator.faceTemplateId != null
                ? 'Re-enroll Face'
                : 'Enroll Face',
            enabled: !_busy,
            onTap: _reenrollFace,
          ),
          _ActionTile(
            icon: _operator.enabled
                ? Icons.block_outlined
                : Icons.check_circle_outline_rounded,
            label: _operator.enabled ? 'Disable Operator' : 'Enable Operator',
            enabled: !_busy,
            onTap: _toggleEnabled,
          ),
          _ActionTile(
            icon: Icons.history_rounded,
            label: 'View Authentication History',
            enabled: !_busy,
            onTap: _viewHistory,
          ),
          _ActionTile(
            icon: Icons.delete_outline_rounded,
            label: 'Delete Operator',
            enabled: !_busy,
            danger: true,
            onTap: _confirmDelete,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildViewFields() {
    return [
      _InfoRow(label: 'Name', value: _operator.name),
      const SizedBox(height: 10),
      _InfoRow(label: 'Employee ID', value: _operator.employeeId),
      const SizedBox(height: 10),
      _InfoRow(label: 'Role', value: _operator.role.displayName),
      const SizedBox(height: 10),
      _InfoRow(
        label: 'Status',
        value: _operator.enabled ? 'Enabled' : 'Disabled',
      ),
      const SizedBox(height: 10),
      _InfoRow(
        label: 'Face Enrollment',
        value: _operator.faceTemplateId != null ? 'Enrolled' : 'Not enrolled',
      ),
      const SizedBox(height: 10),
      _InfoRow(
        label: 'Created',
        value: _operator.createdAt.toLocal().toIso8601String().split('.').first,
      ),
    ];
  }

  List<Widget> _buildEditForm() {
    return [
      TextField(
        controller: _nameController,
        enabled: !_busy,
        decoration: brandInputDecoration(
          label: 'Full name',
          icon: Icons.badge_outlined,
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _employeeIdController,
        enabled: !_busy,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(8),
        ],
        decoration: brandInputDecoration(
          label: 'Employee ID',
          icon: Icons.badge_outlined,
        ),
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<OperatorRole>(
        initialValue: _role,
        decoration: brandInputDecoration(
          label: 'Role',
          icon: Icons.workspace_premium_outlined,
        ),
        items: [
          for (final role in OperatorRole.values)
            DropdownMenuItem(value: role, child: Text(role.displayName)),
        ],
        onChanged: _busy ? null : (v) => setState(() => _role = v ?? _role),
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: BrandSecondaryButton(
              label: 'Cancel',
              onPressed: _busy ? null : _cancelEdit,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: BrandPrimaryButton(
              label: 'Save',
              busy: _busy,
              onPressed: _saveEdits,
            ),
          ),
        ],
      ),
    ];
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.brandTextMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.brandText,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.enabled,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool enabled;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? AppColors.brandTextMuted
        : (danger ? AppColors.brandDanger : AppColors.brandText);

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: color),
        title: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.brandTextMuted,
                ),
              )
            : null,
        onTap: enabled ? onTap : null,
      ),
    );
  }
}
