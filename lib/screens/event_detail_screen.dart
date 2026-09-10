import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/auth_log_entry.dart';
import 'package:rev_crane_control_ops/utils/auth_log_presentation.dart';
import 'package:rev_crane_control_ops/widgets/shared/brand_widgets.dart';

/// Full detail view for a single [AuthLogEntry]. Pushed when a row is
/// tapped in the Event Log's grouped table (event_log_screen.dart), which
/// intentionally only shows a PLC/MAC ID, Event, Time and Operator summary
/// per row — everything else about the event lives here instead.
class EventDetailScreen extends StatelessWidget {
  const EventDetailScreen({super.key, required this.entry});

  final AuthLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final tone = toneForLogEntry(entry);
    final toneColor = toneColorFor(tone);
    final deviceRows = _deviceRows(entry);
    final operatorRows = _operatorRows(entry);
    final sessionRows = _sessionRows(entry);

    return Scaffold(
      backgroundColor: AppColors.brandBg,
      appBar: AppBar(
        backgroundColor: AppColors.brandSurface,
        foregroundColor: AppColors.brandText,
        elevation: 0,
        titleSpacing: 20,
        title: const Text(
          'Event Details',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.brandText,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.brandBorder),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _DetailHero(entry: entry, tone: tone, toneColor: toneColor),
          if (deviceRows.isNotEmpty) ...[
            const SizedBox(height: 12),
            _DetailSection(label: 'Device', rows: deviceRows),
          ],
          if (operatorRows.isNotEmpty) ...[
            const SizedBox(height: 12),
            _DetailSection(label: 'Operator', rows: operatorRows),
          ],
          if (sessionRows.isNotEmpty) ...[
            const SizedBox(height: 12),
            _DetailSection(label: 'Session', rows: sessionRows),
          ],
        ],
      ),
    );
  }
}

List<MapEntry<String, String>> _deviceRows(AuthLogEntry entry) => [
  if (entry.plcDeviceId != null) MapEntry('PLC / MAC ID', entry.plcDeviceId!),
  if (entry.plcDeviceName != null) MapEntry('PLC Device', entry.plcDeviceName!),
  if (entry.plcType != null) MapEntry('PLC Type', entry.plcType!),
  if (entry.connectionStatus != null)
    MapEntry('Connection', entry.connectionStatus!),
  if (entry.deviceId != null) MapEntry('App Device ID', entry.deviceId!),
];

List<MapEntry<String, String>> _operatorRows(AuthLogEntry entry) => [
  if (entry.operatorNameSnapshot != null)
    MapEntry('Operator', entry.operatorNameSnapshot!),
  if (entry.operatorId != null) MapEntry('Operator ID', entry.operatorId!),
  if (entry.role != null) MapEntry('Role', entry.role!),
  if (entry.userIdentifier != null)
    MapEntry('User Identifier', entry.userIdentifier!),
];

List<MapEntry<String, String>> _sessionRows(AuthLogEntry entry) => [
  if (entry.sessionCorrelationId != null)
    MapEntry('Session', entry.sessionCorrelationId!),
  if (entry.detailCode != null) MapEntry('Detail Code', entry.detailCode!),
  if (entry.failureReason != null) MapEntry('Reason', entry.failureReason!),
];

class _DetailHero extends StatelessWidget {
  const _DetailHero({
    required this.entry,
    required this.tone,
    required this.toneColor,
  });

  final AuthLogEntry entry;
  final BrandTone tone;
  final Color toneColor;

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: toneColor.withAlpha(28),
                  borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                ),
                child: Icon(iconForLogEntry(entry), color: toneColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleForLogEntry(entry),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatLogTimestampFull(entry.timestamp),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.brandTextMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              BrandBadge(label: badgeLabelForLogEntry(entry), tone: tone),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.brandBorder),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.category_outlined,
                size: 14,
                color: AppColors.brandTextMuted,
              ),
              const SizedBox(width: 6),
              Text(
                entry.category.displayName,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.brandTextSub,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.label, required this.rows});

  final String label;
  final List<MapEntry<String, String>> rows;

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BrandSectionLabel(label: label),
          const SizedBox(height: 12),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      row.key,
                      style: const TextStyle(
                        color: AppColors.brandTextMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      row.value,
                      style: const TextStyle(
                        color: AppColors.brandText,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
