import 'package:flutter/material.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/features/operator_auth/application/operator_enrollment_service.dart';
import 'package:rev_crane_control_ops/features/operator_auth/data/operator_database.dart';
import 'package:rev_crane_control_ops/features/operator_auth/data/operator_repository.dart';
import 'package:rev_crane_control_ops/features/operator_auth/domain/operator_audit_event.dart';
import 'package:rev_crane_control_ops/features/operator_auth/domain/operator_record.dart';
import 'package:rev_crane_control_ops/features/operator_auth/face/three_divi_face_recognition_engine.dart';
import 'package:rev_crane_control_ops/features/operator_auth/presentation/face_enrollment_screen.dart';

class AddOperatorScreen extends StatefulWidget {
  const AddOperatorScreen({required this.repository, super.key});

  final OperatorRepository repository;

  @override
  State<AddOperatorScreen> createState() => _AddOperatorScreenState();
}

class _AddOperatorScreenState extends State<AddOperatorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _employeeId = TextEditingController();
  final _name = TextEditingController();
  OperatorAccessLevel _role = OperatorAccessLevel.operator;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _employeeId.dispose();
    _name.dispose();
    super.dispose();
  }

  OperatorInput get _input => OperatorInput(
    employeeId: _employeeId.text,
    name: _name.text,
    role: _role,
  );

  Future<void> _beginEnrollment() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final input = _input;
    setState(() {
      _busy = true;
      _error = null;
    });

    if (await widget.repository.employeeIdExists(input.employeeId)) {
      await widget.repository.recordRejection(
        type: OperatorAuditEventType.duplicateEmployeeIdRejected,
        input: input,
        reason: 'Employee ID already exists.',
      );
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'This Employee ID is already registered.';
        });
      }
      return;
    }

    final engine = ThreeDiviFaceRecognitionEngine();
    try {
      if (!mounted) return;
      setState(() => _busy = false);
      final capture = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FaceEnrollmentScreen(engine: engine),
        ),
      );
      if (!mounted) return;
      if (capture == null) {
        await widget.repository.recordRejection(
          type: OperatorAuditEventType.faceEnrollmentFailed,
          input: input,
          reason: 'Enrollment was cancelled before a template was produced.',
        );
        return;
      }

      setState(() {
        _busy = true;
        _error = null;
      });
      final service = OperatorEnrollmentService(
        repository: widget.repository,
        engine: engine,
      );
      await service.register(input: input, capture: capture);
      if (mounted) Navigator.of(context).pop(true);
    } on DuplicateFaceException {
      if (mounted) {
        setState(() {
          _error = 'This face is already registered to another operator.';
        });
      }
    } on DuplicateEmployeeIdException {
      if (mounted) {
        setState(() => _error = 'This Employee ID is already registered.');
      }
    } catch (error) {
      await widget.repository.recordRejection(
        type: OperatorAuditEventType.faceEnrollmentFailed,
        input: input,
        reason: 'Enrollment or transactional operator storage failed.',
      );
      if (mounted) {
        setState(() => _error = 'Operator registration failed: $error');
      }
    } finally {
      await engine.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.connBg,
      appBar: AppBar(
        title: const Text('Add Operator'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.connText,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Operator Details',
                          style: TextStyle(
                            color: AppColors.connText,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'The account is committed only after 3DiVi quality, liveness, template, and duplicate-face checks all succeed.',
                          style: TextStyle(
                            color: AppColors.connTextMuted,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _employeeId,
                          enabled: !_busy,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Employee ID',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                          validator: (_) => _input.validate(),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _name,
                          enabled: !_busy,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Operator Name',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? 'Operator name is required.'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<OperatorAccessLevel>(
                          initialValue: _role,
                          decoration: const InputDecoration(
                            labelText: 'Role / Access Level',
                            prefixIcon: Icon(Icons.manage_accounts_outlined),
                          ),
                          items: OperatorAccessLevel.values
                              .map(
                                (role) => DropdownMenuItem(
                                  value: role,
                                  child: Text(role.label),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: _busy
                              ? null
                              : (value) {
                                  if (value != null) setState(() => _role = value);
                                },
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.brandDangerSoft,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: AppColors.brandDanger,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed: _busy ? null : _beginEnrollment,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.face_retouching_natural_rounded),
                          label: Text(
                            _busy
                                ? 'Validating biometric enrollment…'
                                : 'Continue to Face Enrollment',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
