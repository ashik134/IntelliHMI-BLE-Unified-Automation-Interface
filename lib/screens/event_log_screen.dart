import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/auth_log_entry.dart';
import 'package:rev_crane_control_ops/services/auth_audit_log_service.dart';
import 'package:rev_crane_control_ops/widgets/shared/brand_widgets.dart';

/// Filter-chip categories. `ble`/`plc`/`safety` are placeholders per spec
/// section 17 — nothing emits into them until a later stage wires up those
/// event sources, so they always render the empty state for now.
enum _LogFilter {
  all('All'),
  ble('BLE'),
  plc('PLC'),
  safety('Safety'),
  authentication('Authentication'),
  system('System');

  const _LogFilter(this.label);
  final String label;
}

List<AuthLogEntry> _applyFilter(List<AuthLogEntry> entries, _LogFilter filter) {
  switch (filter) {
    case _LogFilter.all:
      return entries;
    case _LogFilter.authentication:
      return entries
          .where(
            (e) =>
                e.category == AuthLogCategory.authentication ||
                e.category == AuthLogCategory.operatorManagement,
          )
          .toList();
    case _LogFilter.system:
      return entries.where((e) => e.category == AuthLogCategory.system).toList();
    case _LogFilter.ble:
    case _LogFilter.plc:
    case _LogFilter.safety:
      return const [];
  }
}

class EventLogScreen extends StatefulWidget {
  const EventLogScreen({super.key, this.operatorId, this.titleOverride});

  /// When set, entries are filtered client-side to this operator — used by
  /// OperatorDetailScreen's "View Authentication History" (Stage 2). No
  /// change to `AuthAuditLogService.getEntries()`'s API was needed for
  /// this; it's a view-level filter on top of the same full fetch.
  final String? operatorId;

  /// Overrides the app bar title (e.g. "Ashik R — History"). Also the
  /// signal for whether this is a pushed sub-screen (show a back arrow)
  /// versus the bottom-nav tab root (no back arrow).
  final String? titleOverride;

  @override
  State<EventLogScreen> createState() => _EventLogScreenState();
}

class _EventLogScreenState extends State<EventLogScreen> {
  _LogFilter _filter = _LogFilter.all;
  late Future<List<AuthLogEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<AuthAuditLogService>().getEntries();
  }

  void _refresh() {
    setState(() {
      _future = context.read<AuthAuditLogService>().getEntries();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.brandBg,
      appBar: AppBar(
        automaticallyImplyLeading: widget.titleOverride != null,
        backgroundColor: AppColors.brandSurface,
        foregroundColor: AppColors.brandText,
        elevation: 0,
        titleSpacing: 20,
        title: Text(
          widget.titleOverride ?? 'Event Log',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.brandText,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
          ),
          const SizedBox(width: 4),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.brandBorder),
        ),
      ),
      body: FutureBuilder<List<AuthLogEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.brandViolet),
            );
          }

          var scoped = snapshot.data!;
          if (widget.operatorId != null) {
            scoped = scoped
                .where((e) => e.operatorId == widget.operatorId)
                .toList();
          }
          final entries = _applyFilter(scoped, _filter);
          return Column(
            children: [
              _FilterChipsRow(
                selected: _filter,
                onSelected: (f) => setState(() => _filter = f),
              ),
              Expanded(
                child: entries.isEmpty
                    ? const _EmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: entries.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) =>
                            _LogEntryCard(entry: entries[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilterChipsRow extends StatelessWidget {
  const _FilterChipsRow({required this.selected, required this.onSelected});

  final _LogFilter selected;
  final ValueChanged<_LogFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        itemCount: _LogFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final filter = _LogFilter.values[i];
          final isSelected = filter == selected;
          return ChoiceChip(
            label: Text(filter.label),
            selected: isSelected,
            onSelected: (_) => onSelected(filter),
            showCheckmark: false,
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : AppColors.brandTextSub,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
            selectedColor: AppColors.brandViolet,
            backgroundColor: AppColors.brandSurface,
            side: BorderSide(
              color: isSelected ? AppColors.brandViolet : AppColors.brandBorder,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
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
              Icons.receipt_long_outlined,
              color: AppColors.brandTextMuted,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No events yet',
            style: TextStyle(
              color: AppColors.brandText,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Authentication activity will appear here.',
            style: TextStyle(color: AppColors.brandTextMuted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _LogEntryCard extends StatelessWidget {
  const _LogEntryCard({required this.entry});

  final AuthLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final tone = _toneFor(entry);
    final toneColor = _toneColor(tone);

    return BrandCard(
      padding: EdgeInsets.zero,
      // ExpansionTile paints its ListTile's ink/highlight on the nearest
      // Material ancestor — without this, BrandCard's own colored
      // background sits between it and the Scaffold's Material and hides
      // the ink entirely. ClipRRect keeps the splash inside the card's
      // rounded corners.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        child: Material(
          color: Colors.transparent,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.fromLTRB(14, 2, 10, 2),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: toneColor.withAlpha(28),
                  borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
                ),
                child: Icon(_iconFor(entry), color: toneColor, size: 18),
              ),
              title: Text(
                _titleFor(entry),
                style: const TextStyle(
                  color: AppColors.brandText,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${_formatTimestamp(entry.timestamp)} · ${_subtitleFor(entry)}',
                  style: const TextStyle(
                    color: AppColors.brandTextMuted,
                    fontSize: 11.5,
                  ),
                ),
              ),
              trailing: BrandBadge(
                label: _badgeLabelFor(entry),
                tone: tone,
                dense: true,
              ),
              children: [_DetailRows(entry: entry)],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRows extends StatelessWidget {
  const _DetailRows({required this.entry});

  final AuthLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final rows = <MapEntry<String, String>>[
      if (entry.userIdentifier != null)
        MapEntry('User', entry.userIdentifier!),
      if (entry.operatorId != null) MapEntry('Operator ID', entry.operatorId!),
      if (entry.deviceId != null) MapEntry('Device ID', entry.deviceId!),
      if (entry.plcDeviceName != null)
        MapEntry('PLC Device', entry.plcDeviceName!),
      if (entry.plcType != null) MapEntry('PLC Type', entry.plcType!),
      if (entry.connectionStatus != null)
        MapEntry('Connection', entry.connectionStatus!),
      if (entry.sessionCorrelationId != null)
        MapEntry('Session', entry.sessionCorrelationId!),
      if (entry.detailCode != null) MapEntry('Detail Code', entry.detailCode!),
      if (entry.failureReason != null)
        MapEntry('Reason', entry.failureReason!),
    ];

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 16, color: AppColors.brandBorder),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    row.key,
                    style: const TextStyle(
                      color: AppColors.brandTextMuted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.value,
                    style: const TextStyle(
                      color: AppColors.brandText,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

BrandTone _toneFor(AuthLogEntry entry) {
  switch (entry.category) {
    case AuthLogCategory.authentication:
      switch (entry.result) {
        case AuthEventResult.success:
          return BrandTone.success;
        case AuthEventResult.failed:
        case AuthEventResult.error:
          return BrandTone.danger;
        case AuthEventResult.cancelled:
          return BrandTone.warning;
        case null:
          return BrandTone.neutral;
      }
    case AuthLogCategory.operatorManagement:
      return BrandTone.info;
    case AuthLogCategory.system:
      return BrandTone.neutral;
  }
}

Color _toneColor(BrandTone tone) {
  switch (tone) {
    case BrandTone.success:
      return AppColors.brandSuccess;
    case BrandTone.danger:
      return AppColors.brandDanger;
    case BrandTone.warning:
      return AppColors.brandWarning;
    case BrandTone.info:
      return AppColors.brandInfo;
    case BrandTone.violet:
      return AppColors.brandViolet;
    case BrandTone.neutral:
      return AppColors.brandTextSub;
  }
}

IconData _iconFor(AuthLogEntry entry) {
  switch (entry.category) {
    case AuthLogCategory.authentication:
      switch (entry.method) {
        case AuthEventMethod.biometric:
          return Icons.fingerprint_rounded;
        case AuthEventMethod.face:
          return Icons.face_retouching_natural_rounded;
        case AuthEventMethod.pin:
          return Icons.pin_rounded;
        case AuthEventMethod.password:
        case null:
          return Icons.lock_outline_rounded;
      }
    case AuthLogCategory.operatorManagement:
      return Icons.badge_outlined;
    case AuthLogCategory.system:
      return Icons.info_outline_rounded;
  }
}

String _titleFor(AuthLogEntry entry) {
  switch (entry.category) {
    case AuthLogCategory.authentication:
      final method = entry.method?.displayName ?? 'Unknown';
      return '$method Authentication';
    case AuthLogCategory.operatorManagement:
      return entry.lifecycleEvent?.displayName ?? 'Operator Management';
    case AuthLogCategory.system:
      return 'System Notice';
  }
}

String _subtitleFor(AuthLogEntry entry) {
  final name = entry.operatorNameSnapshot ?? entry.userIdentifier;
  if (name == null) return entry.category.displayName;
  if (entry.role == null) return name;
  return '$name · ${entry.role}';
}

String _badgeLabelFor(AuthLogEntry entry) {
  if (entry.result != null) return entry.result!.displayName.toUpperCase();
  if (entry.lifecycleEvent != null) {
    return entry.lifecycleEvent!.displayName.toUpperCase();
  }
  return entry.category.displayName.toUpperCase();
}

String _formatTimestamp(DateTime timestamp) {
  final t = timestamp.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}
