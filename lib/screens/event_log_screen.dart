import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/auth_log_entry.dart';
import 'package:rev_crane_control_ops/screens/event_detail_screen.dart';
import 'package:rev_crane_control_ops/services/auth_audit_log_service.dart';
import 'package:rev_crane_control_ops/utils/auth_log_presentation.dart';
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

/// All events sharing one `plcDeviceId` (MAC ID). Entries with no PLC
/// attached (operator-management/system events) land in the `null`-keyed
/// "unassigned" group, which always sorts last.
class _DeviceGroup {
  _DeviceGroup(this.macId);

  final String? macId;
  String? deviceName;
  final List<AuthLogEntry> entries = [];
}

List<_DeviceGroup> _groupByPlc(List<AuthLogEntry> entries) {
  final byKey = <String, _DeviceGroup>{};
  final order = <String>[];
  for (final e in entries) {
    final key = e.plcDeviceId ?? '';
    var group = byKey[key];
    if (group == null) {
      group = _DeviceGroup(e.plcDeviceId);
      byKey[key] = group;
      order.add(key);
    }
    group.deviceName ??= e.plcDeviceName;
    group.entries.add(e);
  }

  final groups = order.map((k) => byKey[k]!).toList();
  // Entries arrive newest-first (AuthAuditLogService.getEntries reverses
  // them), so within each group `entries.first` is already that device's
  // most recent activity — sort groups by that so the busiest/most-recent
  // PLC surfaces first, with the unassigned bucket always last.
  groups.sort((a, b) {
    if (a.macId == null && b.macId == null) return 0;
    if (a.macId == null) return 1;
    if (b.macId == null) return -1;
    return b.entries.first.timestamp.compareTo(a.entries.first.timestamp);
  });
  return groups;
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
  DateTimeRange? _dateRange;
  String? _operatorFilter;
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

  List<AuthLogEntry> _scopedEntries(List<AuthLogEntry> all) {
    if (widget.operatorId == null) return all;
    return all.where((e) => e.operatorId == widget.operatorId).toList();
  }

  List<AuthLogEntry> _filteredEntries(List<AuthLogEntry> scoped) {
    var entries = _applyFilter(scoped, _filter);

    final range = _dateRange;
    if (range != null) {
      final start = DateTime(range.start.year, range.start.month, range.start.day);
      final end = DateTime(
        range.end.year,
        range.end.month,
        range.end.day,
      ).add(const Duration(days: 1));
      entries = entries.where((e) {
        final t = e.timestamp.toLocal();
        return !t.isBefore(start) && t.isBefore(end);
      }).toList();
    }

    final operator = _operatorFilter;
    if (operator != null) {
      entries = entries
          .where((e) => operatorLabelForLogEntry(e) == operator)
          .toList();
    }

    return entries;
  }

  bool get _hasExtraFilters => _dateRange != null || _operatorFilter != null;

  void _clearAllFilters() {
    setState(() {
      _filter = _LogFilter.all;
      _dateRange = null;
      _operatorFilter = null;
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _dateRange,
    );
    if (picked != null) setState(() => _dateRange = picked);
  }

  Future<void> _pickOperator(List<String> operators) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OperatorPickerSheet(
        operators: operators,
        selected: _operatorFilter,
      ),
    );
    if (!mounted) return;
    // A picker result of `''` is the sheet's explicit "All Operators" — a
    // dismiss without picking (null) must leave the current filter alone.
    if (selected == null) return;
    setState(() => _operatorFilter = selected.isEmpty ? null : selected);
  }

  void _openDetail(AuthLogEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => EventDetailScreen(entry: entry)),
    );
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

          final scoped = _scopedEntries(snapshot.data!);
          final entries = _filteredEntries(scoped);
          final operators = widget.operatorId != null
              ? const <String>[]
              : ({
                  for (final e in scoped)
                    if (operatorLabelForLogEntry(e) != null)
                      operatorLabelForLogEntry(e)!,
                }.toList()..sort());
          final groups = _groupByPlc(entries);
          final isFiltered =
              _filter != _LogFilter.all || _hasExtraFilters;

          return Column(
            children: [
              _FilterChipsRow(
                selected: _filter,
                onSelected: (f) => setState(() => _filter = f),
              ),
              _ExtraFiltersRow(
                dateRange: _dateRange,
                onPickDateRange: _pickDateRange,
                onClearDateRange: () => setState(() => _dateRange = null),
                operator: _operatorFilter,
                showOperatorFilter: widget.operatorId == null,
                onPickOperator: () => _pickOperator(operators),
                onClearOperator: () => setState(() => _operatorFilter = null),
              ),
              if (groups.isNotEmpty) const _TableColumnHeader(),
              Expanded(
                child: groups.isEmpty
                    ? _EmptyState(
                        filtered: isFiltered && scoped.isNotEmpty,
                        onClearFilters: _clearAllFilters,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: groups.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _DeviceGroupSection(
                          group: groups[i],
                          onTapEntry: _openDetail,
                        ),
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

/// Second filter row — date range and (when not already operator-scoped)
/// operator — kept visually distinct from the category chips above so the
/// two filter axes (what kind of event vs. when/who) don't blur together.
class _ExtraFiltersRow extends StatelessWidget {
  const _ExtraFiltersRow({
    required this.dateRange,
    required this.onPickDateRange,
    required this.onClearDateRange,
    required this.operator,
    required this.showOperatorFilter,
    required this.onPickOperator,
    required this.onClearOperator,
  });

  final DateTimeRange? dateRange;
  final VoidCallback onPickDateRange;
  final VoidCallback onClearDateRange;
  final String? operator;
  final bool showOperatorFilter;
  final VoidCallback onPickOperator;
  final VoidCallback onClearOperator;

  @override
  Widget build(BuildContext context) {
    final dateActive = dateRange != null;
    final dateLabel = dateActive
        ? '${formatDateShort(dateRange!.start)} – ${formatDateShort(dateRange!.end)}'
        : 'Date range';

    final operatorActive = operator != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _FilterPillButton(
            icon: Icons.event_rounded,
            label: dateLabel,
            active: dateActive,
            onTap: onPickDateRange,
          ),
          if (dateActive) _ClearChipButton(onTap: onClearDateRange),
          if (showOperatorFilter) ...[
            _FilterPillButton(
              icon: Icons.person_outline_rounded,
              label: operator ?? 'Operator',
              active: operatorActive,
              onTap: onPickOperator,
            ),
            if (operatorActive) _ClearChipButton(onTap: onClearOperator),
          ],
        ],
      ),
    );
  }
}

class _FilterPillButton extends StatelessWidget {
  const _FilterPillButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 190),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.brandVioletSoft : AppColors.brandSurface,
            border: Border.all(
              color: active ? AppColors.brandViolet : AppColors.brandBorder,
            ),
            borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: active
                    ? AppColors.brandVioletDeep
                    : AppColors.brandTextSub,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: active
                        ? AppColors.brandVioletDeep
                        : AppColors.brandTextSub,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClearChipButton extends StatelessWidget {
  const _ClearChipButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: Icon(
            Icons.close_rounded,
            size: 16,
            color: AppColors.brandTextMuted,
          ),
        ),
      ),
    );
  }
}

class _OperatorPickerSheet extends StatelessWidget {
  const _OperatorPickerSheet({required this.operators, required this.selected});

  final List<String> operators;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          margin: const EdgeInsets.all(12),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          decoration: BoxDecoration(
            color: AppColors.brandSurface,
            borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
            boxShadow: AppMetrics.shadowMd,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.brandBorderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 14, 18, 6),
                child: Text(
                  'Filter by operator',
                  style: TextStyle(
                    color: AppColors.brandText,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                  children: [
                    _OperatorPickerRow(
                      label: 'All Operators',
                      selected: selected == null,
                      onTap: () => Navigator.of(context).pop(''),
                    ),
                    for (final name in operators)
                      _OperatorPickerRow(
                        label: name,
                        selected: name == selected,
                        onTap: () => Navigator.of(context).pop(name),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OperatorPickerRow extends StatelessWidget {
  const _OperatorPickerRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: selected
                    ? AppColors.brandViolet
                    : AppColors.brandTextMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: AppColors.brandText,
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Column labels for the compact table — shown once above the grouped
/// sections so the PLC/MAC ID header (which each section already carries)
/// isn't repeated on every row.
class _TableColumnHeader extends StatelessWidget {
  const _TableColumnHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: AppColors.brandTextMuted,
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.8,
    );
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        children: [
          SizedBox(width: 22),
          Expanded(flex: 5, child: Text('EVENT', style: style)),
          Expanded(flex: 3, child: Text('TIME', style: style)),
          Expanded(flex: 3, child: Text('OPERATOR', style: style)),
          SizedBox(width: 16),
        ],
      ),
    );
  }
}

class _DeviceGroupSection extends StatelessWidget {
  const _DeviceGroupSection({required this.group, required this.onTapEntry});

  final _DeviceGroup group;
  final ValueChanged<AuthLogEntry> onTapEntry;

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DeviceGroupHeader(group: group),
          const Divider(height: 1, color: AppColors.brandBorder),
          for (var i = 0; i < group.entries.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.brandBorder),
            _EventRow(
              entry: group.entries[i],
              onTap: () => onTapEntry(group.entries[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _DeviceGroupHeader extends StatelessWidget {
  const _DeviceGroupHeader({required this.group});

  final _DeviceGroup group;

  @override
  Widget build(BuildContext context) {
    final macId = group.macId;
    final hasDevice = macId != null;
    final title = hasDevice ? (group.deviceName ?? 'PLC') : 'No PLC Connected';

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: hasDevice
                  ? AppColors.brandVioletSoft
                  : AppColors.brandSurfaceAlt,
              borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
            ),
            child: Icon(
              hasDevice ? Icons.developer_board_rounded : Icons.link_off_rounded,
              size: 17,
              color: hasDevice
                  ? AppColors.brandVioletDeep
                  : AppColors.brandTextMuted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.brandText,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  hasDevice ? macId : 'Operator & system events with no PLC attached',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.brandTextMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          BrandBadge(
            label: '${group.entries.length}',
            tone: BrandTone.neutral,
            dense: true,
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.entry, required this.onTap});

  final AuthLogEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = toneForLogEntry(entry);
    final toneColor = toneColorFor(tone);
    final operatorLabel = operatorLabelForLogEntry(entry) ?? '—';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Center(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: toneColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 5,
                child: Text(
                  titleForLogEntry(entry),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.brandText,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  formatLogTimestampCompact(entry.timestamp),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.brandTextSub,
                    fontSize: 11.5,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  operatorLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.brandTextSub,
                    fontSize: 11.5,
                  ),
                ),
              ),
              const SizedBox(
                width: 16,
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppColors.brandTextMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filtered, required this.onClearFilters});

  final bool filtered;
  final VoidCallback onClearFilters;

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
            child: Icon(
              filtered ? Icons.filter_alt_off_outlined : Icons.receipt_long_outlined,
              color: AppColors.brandTextMuted,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            filtered ? 'No events match your filters' : 'No events yet',
            style: const TextStyle(
              color: AppColors.brandText,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            filtered
                ? 'Try a wider date range or a different operator.'
                : 'Authentication activity will appear here.',
            style: const TextStyle(color: AppColors.brandTextMuted, fontSize: 12.5),
          ),
          if (filtered) ...[
            const SizedBox(height: 16),
            TextButton(onPressed: onClearFilters, child: const Text('Clear filters')),
          ],
        ],
      ),
    );
  }
}
