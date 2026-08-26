import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/operator_profile.dart';
import 'package:rev_crane_control_ops/repositories/operator_repository.dart';
import 'package:rev_crane_control_ops/screens/operator/add_operator_screen.dart';
import 'package:rev_crane_control_ops/screens/operator/operator_detail_screen.dart';
import 'package:rev_crane_control_ops/services/auth_audit_log_service.dart';
import 'package:rev_crane_control_ops/widgets/shared/brand_widgets.dart';

class OperatorManagementScreen extends StatefulWidget {
  const OperatorManagementScreen({super.key, this.repository});

  /// Injectable for consistency with AddOperatorScreen/OperatorDetailScreen
  /// (which require one) and for tests; defaults to lazily resolving the
  /// real on-device store via [OperatorRepository.open] when null.
  final OperatorRepository? repository;

  @override
  State<OperatorManagementScreen> createState() =>
      _OperatorManagementScreenState();
}

class _OperatorManagementScreenState extends State<OperatorManagementScreen> {
  OperatorRepository? _repository;
  late Future<List<OperatorProfile>> _future;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository;
    _future = _load();
  }

  Future<List<OperatorProfile>> _load() async {
    final repo = _repository ??= await OperatorRepository.open();
    // OperatorRepository.getAll() returns a `const []` when the store file
    // doesn't exist yet (fresh install) — .toList() first so .sort() below
    // never throws on that unmodifiable list.
    final all = (await repo.getAll()).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return all;
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _addOperator() async {
    final repo = _repository;
    if (repo == null) return;
    final isFirstOperator = (await repo.getAll()).isEmpty;
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AddOperatorScreen(
          repository: repo,
          auditLog: context.read<AuthAuditLogService>(),
          forceAdministratorRole: isFirstOperator,
        ),
      ),
    );
    _reload();
  }

  Future<void> _openDetail(OperatorProfile operator) async {
    final repo = _repository;
    if (repo == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OperatorDetailScreen(
          operator: operator,
          repository: repo,
          auditLog: context.read<AuthAuditLogService>(),
        ),
      ),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.brandBg,
      appBar: AppBar(
        backgroundColor: AppColors.brandSurface,
        foregroundColor: AppColors.brandText,
        elevation: 0,
        titleSpacing: 20,
        title: const Text(
          'Operators',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.brandText,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Add Operator',
            icon: const Icon(Icons.person_add_alt_1_rounded),
            onPressed: _addOperator,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: FutureBuilder<List<OperatorProfile>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorState(error: snapshot.error, onRetry: _reload);
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.brandViolet),
            );
          }

          final operators = snapshot.data!;
          if (operators.isEmpty) {
            return _EmptyOperatorsState(onAdd: _addOperator);
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: operators.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _OperatorCard(
              operator: operators[i],
              onTap: () => _openDetail(operators[i]),
            ),
          );
        },
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.brandDanger,
              size: 40,
            ),
            const SizedBox(height: 16),
            const Text(
              'Could not load operators',
              style: TextStyle(
                color: AppColors.brandText,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.brandTextMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            BrandSecondaryButton(label: 'Retry', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

class _EmptyOperatorsState extends StatelessWidget {
  const _EmptyOperatorsState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.brandTextMuted.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.people_outline_rounded,
                color: AppColors.brandTextMuted,
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No operators yet',
              style: TextStyle(
                color: AppColors.brandText,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Add the first operator to get started. The first operator '
              'added on this device becomes an Administrator.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.brandTextMuted, fontSize: 12.5),
            ),
            const SizedBox(height: 20),
            BrandPrimaryButton(
              label: 'Add Operator',
              icon: Icons.person_add_alt_1_rounded,
              expand: false,
              onPressed: onAdd,
            ),
          ],
        ),
      ),
    );
  }
}

class _OperatorCard extends StatelessWidget {
  const _OperatorCard({required this.operator, required this.onTap});

  final OperatorProfile operator;
  final VoidCallback onTap;

  String get _initials {
    final parts = operator.name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 && parts.last.isNotEmpty
        ? parts.last[0]
        : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final avatarColor = operator.enabled
        ? AppColors.brandViolet
        : AppColors.brandTextMuted;

    return BrandCard(
      padding: EdgeInsets.zero,
      // Same reasoning as EventLogScreen's entry cards: without a nearer
      // Material ancestor, BrandCard's own background hides InkWell's
      // splash entirely.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: avatarColor.withAlpha(28),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      _initials,
                      style: TextStyle(
                        color: avatarColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          operator.name,
                          style: const TextStyle(
                            color: AppColors.brandText,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          operator.role.displayName,
                          style: const TextStyle(
                            color: AppColors.brandTextMuted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Row(
                          children: [
                            Icon(
                              Icons.face_outlined,
                              size: 12,
                              color: AppColors.brandTextMuted,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Not enrolled yet',
                              style: TextStyle(
                                color: AppColors.brandTextMuted,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  BrandBadge(
                    label: operator.enabled ? 'ENABLED' : 'DISABLED',
                    tone: operator.enabled
                        ? BrandTone.success
                        : BrandTone.neutral,
                    dense: true,
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
