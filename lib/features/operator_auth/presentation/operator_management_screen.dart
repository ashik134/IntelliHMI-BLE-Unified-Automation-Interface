import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/features/operator_auth/application/operator_enrollment_service.dart';
import 'package:rev_crane_control_ops/features/operator_auth/data/operator_repository.dart';
import 'package:rev_crane_control_ops/features/operator_auth/domain/operator_record.dart';
import 'package:rev_crane_control_ops/features/operator_auth/face/three_divi_face_recognition_engine.dart';
import 'package:rev_crane_control_ops/features/operator_auth/presentation/add_operator_screen.dart';
import 'package:rev_crane_control_ops/features/operator_auth/presentation/face_enrollment_screen.dart';

class OperatorManagementScreen extends StatefulWidget {
  const OperatorManagementScreen({super.key});

  @override
  State<OperatorManagementScreen> createState() =>
      _OperatorManagementScreenState();
}

class _OperatorManagementScreenState extends State<OperatorManagementScreen>
    with WidgetsBindingObserver {
  static const Duration _authorizationLifetime = Duration(minutes: 5);

  final OperatorRepository _repository = OperatorRepository();
  final TextEditingController _search = TextEditingController();
  Timer? _authorizationTimer;
  List<OperatorRecord> _operators = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authorizationTimer = Timer(_authorizationLifetime, _expireAuthorization);
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _expireAuthorization();
    }
  }

  void _expireAuthorization() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final managementRoute = ModalRoute.of(context);
      final navigator = Navigator.of(context);
      if (managementRoute == null) return;
      navigator.popUntil((route) => route == managementRoute);
      if (navigator.canPop()) navigator.pop();
    });
  }

  Future<void> _load() async {
    try {
      final operators = await _repository.listOperators(search: _search.text);
      if (!mounted) return;
      setState(() {
        _operators = operators;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load operators: $error';
        });
      }
    }
  }

  Future<void> _addOperator() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddOperatorScreen(repository: _repository),
      ),
    );
    if (created == true) await _load();
  }

  Future<void> _setEnabled(OperatorRecord operator, bool enabled) async {
    try {
      await _repository.setEnabled(operator, enabled);
      await _load();
    } catch (error) {
      _showError('Could not update operator status: $error');
    }
  }

  Future<void> _reenroll(OperatorRecord operator) async {
    final engine = ThreeDiviFaceRecognitionEngine();
    try {
      final capture = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FaceEnrollmentScreen(engine: engine),
        ),
      );
      if (capture == null) return;
      final enrollment = OperatorEnrollmentService(
        repository: _repository,
        engine: engine,
      );
      await enrollment.reenroll(operator: operator, capture: capture);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Face re-enrollment completed.')),
        );
      }
      await _load();
    } on DuplicateFaceException {
      _showError('This face is already registered to another operator.');
    } catch (error) {
      _showError('Face re-enrollment failed: $error');
    } finally {
      await engine.dispose();
    }
  }

  Future<void> _delete(OperatorRecord operator) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete operator?'),
        content: Text(
          '${operator.name} (${operator.employeeId}) will immediately lose biometric authentication. Audit snapshots will be retained.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandDanger,
            ),
            child: const Text('Delete Operator'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.deleteOperator(operator);
      await _load();
    } catch (error) {
      _showError('Could not delete operator: $error');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.brandDanger,
        ),
      );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authorizationTimer?.cancel();
    _search.dispose();
    unawaited(_repository.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.connBg,
      appBar: AppBar(
        title: const Text('Operator Management'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.connText,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _addOperator,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add Operator'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: (_) => _load(),
                decoration: const InputDecoration(
                  hintText: 'Search by Employee ID or name',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addOperator,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add Operator'),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_operators.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No operators are registered. Administrator authorization is required before adding the first operator.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.connTextMuted, height: 1.5),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: _operators.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final operator = _operators[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: operator.enabled
                  ? AppColors.brandSuccessSoft
                  : AppColors.brandSurfaceAlt,
              child: Icon(
                Icons.face_rounded,
                color: operator.enabled
                    ? AppColors.brandSuccess
                    : AppColors.connTextMuted,
              ),
            ),
            title: Text(
              operator.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${operator.employeeId} · ${operator.role.label} · Face enrolled',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch.adaptive(
                  value: operator.enabled,
                  onChanged: (value) => _setEnabled(operator, value),
                ),
                PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'reenroll') _reenroll(operator);
                    if (action == 'delete') _delete(operator);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'reenroll',
                      child: ListTile(
                        leading: Icon(Icons.face_retouching_natural_rounded),
                        title: Text('Re-enroll Face'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.brandDanger,
                        ),
                        title: Text('Delete Operator'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
