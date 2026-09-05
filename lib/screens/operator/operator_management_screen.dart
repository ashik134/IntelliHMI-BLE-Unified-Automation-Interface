import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/operator_profile.dart';
import 'package:rev_crane_control_ops/repositories/face_template_repository.dart';
import 'package:rev_crane_control_ops/repositories/operator_repository.dart';
import 'package:rev_crane_control_ops/screens/operator/add_operator_screen.dart';
import 'package:rev_crane_control_ops/screens/operator/face_verify_screen.dart';
import 'package:rev_crane_control_ops/screens/operator/operator_detail_screen.dart';
import 'package:rev_crane_control_ops/services/auth_audit_log_service.dart';
import 'package:rev_crane_control_ops/widgets/shared/brand_widgets.dart';

typedef AddOperatorScreenBuilder =
    Widget Function(
      OperatorRepository repository,
      FaceTemplateRepository templateRepository,
      AuthAuditLogService auditLog,
      bool forceAdministratorRole,
    );

class OperatorManagementScreen extends StatefulWidget {
  const OperatorManagementScreen({
    super.key,
    this.repository,
    this.templateRepository,
    this.addOperatorScreenBuilder,
  });

  /// Injectable for consistency with AddOperatorScreen/OperatorDetailScreen
  /// (which require one) and for tests; defaults to lazily resolving the
  /// real on-device store via [OperatorRepository.open] when null.
  final OperatorRepository? repository;

  /// Same pattern as [repository], via [FaceTemplateRepository.open].
  final FaceTemplateRepository? templateRepository;

  @visibleForTesting
  final AddOperatorScreenBuilder? addOperatorScreenBuilder;

  @override
  State<OperatorManagementScreen> createState() =>
      _OperatorManagementScreenState();
}

class _OperatorManagementScreenState extends State<OperatorManagementScreen> {
  OperatorRepository? _repository;
  FaceTemplateRepository? _templateRepository;
  List<OperatorProfile> _operators = const [];
  Object? _loadError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository;
    _templateRepository = widget.templateRepository;
    unawaited(_reload());
  }

  Future<
    ({OperatorRepository repository, FaceTemplateRepository templateRepository})
  >
  _ensureStores() async {
    final repo = _repository ??= await OperatorRepository.open();
    final templateRepo = _templateRepository ??=
        await FaceTemplateRepository.open();
    return (repository: repo, templateRepository: templateRepo);
  }

  Future<List<OperatorProfile>> _loadOperators() async {
    final stores = await _ensureStores();
    // OperatorRepository.getAll() returns a `const []` when the store file
    // doesn't exist yet (fresh install) — .toList() first so .sort() below
    // never throws on that unmodifiable list.
    final all = (await stores.repository.getAll()).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return all;
  }

  Future<void> _reload({bool showLoading = false}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }

    try {
      final operators = await _loadOperators();
      if (!mounted) return;
      setState(() {
        _operators = operators;
        _loadError = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  void _upsertVisibleOperator(OperatorProfile operator) {
    final updated = [
      for (final existing in _operators)
        if (existing.operatorId != operator.operatorId) existing,
      operator,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    setState(() {
      _operators = updated;
      _loadError = null;
      _loading = false;
    });
  }

  void _removeVisibleOperator(String operatorId) {
    setState(() {
      _operators = _operators
          .where((operator) => operator.operatorId != operatorId)
          .toList();
      _loadError = null;
      _loading = false;
    });
  }

  Future<void> _addOperator() async {
    final stores = await _ensureStores();
    final repo = stores.repository;
    final templateRepo = stores.templateRepository;
    final isFirstOperator = (await repo.getAll()).isEmpty;
    if (!mounted) return;

    final auditLog = context.read<AuthAuditLogService>();
    final created = await Navigator.of(context).push<OperatorProfile>(
      MaterialPageRoute<OperatorProfile>(
        builder: (_) =>
            widget.addOperatorScreenBuilder?.call(
              repo,
              templateRepo,
              auditLog,
              isFirstOperator,
            ) ??
            AddOperatorScreen(
              repository: repo,
              templateRepository: templateRepo,
              auditLog: auditLog,
              forceAdministratorRole: isFirstOperator,
            ),
      ),
    );
    if (!mounted) return;
    if (created != null) _upsertVisibleOperator(created);
    unawaited(_reload());
  }

  Future<void> _openDetail(OperatorProfile operator) async {
    final stores = await _ensureStores();
    final repo = stores.repository;
    final templateRepo = stores.templateRepository;
    if (!mounted) return;

    final deletedOperatorId = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => OperatorDetailScreen(
          operator: operator,
          repository: repo,
          templateRepository: templateRepo,
          auditLog: context.read<AuthAuditLogService>(),
        ),
      ),
    );
    if (!mounted) return;
    if (deletedOperatorId != null) _removeVisibleOperator(deletedOperatorId);
    unawaited(_reload());
  }

  /// Debug-only tool (see the `kDebugMode`-gated action button below) —
  /// live camera face verification against enrolled templates, for
  /// confirming enrollment actually captured a matchable face without
  /// needing a full face-login flow. Read-only, no audit log entry.
  Future<void> _verifyFace() async {
    final repo = _repository;
    final templateRepo = _templateRepository;
    if (repo == null || templateRepo == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => FaceVerifyScreen(
          operatorRepository: repo,
          templateRepository: templateRepo,
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
          if (kDebugMode)
            IconButton(
              tooltip: 'Verify Face (Debug)',
              icon: const Icon(Icons.fact_check_outlined),
              onPressed: _verifyFace,
            ),
          IconButton(
            tooltip: 'Add Operator',
            icon: const Icon(Icons.person_add_alt_1_rounded),
            onPressed: _loading ? null : _addOperator,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final loadError = _loadError;
    if (loadError != null && _operators.isEmpty) {
      return _ErrorState(
        error: loadError,
        onRetry: () => unawaited(_reload(showLoading: true)),
      );
    }
    if (_loading && _operators.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.brandViolet),
      );
    }

    final operators = _operators;
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
    final last = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
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
                        Row(
                          children: [
                            Icon(
                              operator.faceTemplateId != null
                                  ? Icons.face_retouching_natural_rounded
                                  : Icons.face_outlined,
                              size: 12,
                              color: AppColors.brandTextMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              operator.faceTemplateId != null
                                  ? 'Face enrolled'
                                  : 'Not enrolled yet',
                              style: const TextStyle(
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
