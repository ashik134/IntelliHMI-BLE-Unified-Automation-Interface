import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/feedback_manager.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev_crane_control_ops/models/alarm_indicator_config.dart' show AlarmSeverity;
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/auth_log_entry.dart';
import 'package:rev_crane_control_ops/models/ble_connection_state.dart';
import 'package:rev_crane_control_ops/models/feedback/analog_feedback_config.dart';
import 'package:rev_crane_control_ops/models/feedback/system_feedback_config.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/services/auth_audit_log_service.dart';
import 'package:rev_crane_control_ops/utils/auth_log_presentation.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/device_info_appbar.dart' show ControlAppBarGlow;
import 'package:rev_crane_control_ops/widgets/control_screen/feedback/feedback_palette.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/screen_activity_detector.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/sensor_row.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DiagnosticsScreen
//
// Instrument-panel-style service/diagnostic dashboard for a technician:
// connection health, heartbeat/communication, safety state, live radial
// sensor gauges (the same AnalogGauge dial the Control Screen uses), animated
// numeric read-outs, per-output command-vs-actual, and a rolling event log.
// Every value is read off the existing CraneController / FeedbackManager /
// LayoutSettingsController state — no new PLC protocol, no mock data. A
// value with no source in the current architecture renders as "N/A" rather
// than being invented.
//
// This widget lives in MainShell's IndexedStack (see main.dart), so it is
// built once at app launch and never disposed while the app runs — that is
// what lets [_localEvents] behave like a real rolling diagnostic log instead
// of resetting every time the operator switches tabs.
// ─────────────────────────────────────────────────────────────────────────────

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key, this.onActivity});

  /// Reports touch activity on this screen back to the caller — wired by the
  /// Control Screen to its own `InactivityController.registerActivity` when
  /// Diagnostics is pushed on top of it (see plc14/plc38_control_screen.dart).
  /// Diagnostics is a separate pushed route, so without this a technician
  /// reading it for a few minutes would never reset the Control Screen's own
  /// inactivity timer — which keeps running underneath, unaware — and could
  /// be sleep/auto-disconnected out from under them despite being active.
  /// Null (e.g. reached from the bottom-nav tab with no PLC session driving
  /// an inactivity timer) simply means nothing to report activity to.
  final VoidCallback? onActivity;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _LocalEvent {
  _LocalEvent({required this.time, required this.title, required this.status, required this.tone});
  final DateTime time;
  final String title;
  final String status;
  final BrandTone tone;
}

class _LogRow {
  _LogRow({required this.time, required this.title, required this.status, required this.tone});
  final DateTime time;
  final String title;
  final String status;
  final BrandTone tone;
}

/// Local stand-in for the light-theme `BrandTone` enum used by
/// `auth_log_presentation.dart`'s helpers — kept so those helpers can still
/// be reused verbatim for text, while colour resolution here maps to the
/// dark instrument-panel palette via [_toneColor].
enum BrandTone { neutral, violet, success, warning, danger, info }

Color _toneColor(BrandTone tone) => switch (tone) {
  BrandTone.success => AppColors.darkSuccess,
  BrandTone.warning => AppColors.accent,
  BrandTone.danger => AppColors.eStopColorLight,
  BrandTone.info => AppColors.darkInfo,
  BrandTone.violet => AppColors.appBarGlow,
  BrandTone.neutral => AppColors.darkTextMuted,
};

class _DiagnosticsScreenState extends State<DiagnosticsScreen> with TickerProviderStateMixin {
  CraneController? _craneRef;
  FeedbackManager? _feedbackRef;

  final List<_LocalEvent> _localEvents = [];
  static const int _maxLocalEvents = 200;
  static const int _maxRowsShown = 30;

  List<AuthLogEntry> _authEntries = const [];
  Timer? _tickTimer;
  Timer? _authRefreshTimer;

  bool? _wasConnected;
  bool? _wasEstopReported;
  bool? _wasEstopLatched;
  Set<PlcOutputVariant>? _wasActiveFields;
  CommsHealth? _wasComms;
  String? _wasDeviceTitle;

  /// Staggered entrance sweep — replayed every time the panel goes from
  /// disconnected to connected, so the dashboard reads as one choreographed
  /// reveal each time a technician actually has something to look at.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final crane = context.read<CraneController>();
    if (!identical(_craneRef, crane)) {
      _craneRef?.removeListener(_onCraneChanged);
      _craneRef = crane;
      crane.addListener(_onCraneChanged);
      _wasConnected = crane.isConnected;
      if (_wasConnected!) {
        _ensureTicking(true);
        _entrance.forward();
      }
    }

    final feedback = context.read<FeedbackManager>();
    if (!identical(_feedbackRef, feedback)) {
      _feedbackRef?.removeListener(_onFeedbackChanged);
      _feedbackRef = feedback;
      feedback.addListener(_onFeedbackChanged);
      _wasComms = feedback.snapshot.comms;
    }
  }

  @override
  void dispose() {
    _craneRef?.removeListener(_onCraneChanged);
    _feedbackRef?.removeListener(_onFeedbackChanged);
    _tickTimer?.cancel();
    _authRefreshTimer?.cancel();
    _entrance.dispose();
    super.dispose();
  }

  void _ensureTicking(bool active) {
    if (active) {
      _tickTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      _authRefreshTimer ??= Timer.periodic(const Duration(seconds: 6), (_) {
        unawaited(_refreshAuthEntries());
      });
    } else {
      _tickTimer?.cancel();
      _tickTimer = null;
      _authRefreshTimer?.cancel();
      _authRefreshTimer = null;
    }
  }

  void _pushEvent(String title, String status, BrandTone tone) {
    _localEvents.insert(0, _LocalEvent(time: DateTime.now(), title: title, status: status, tone: tone));
    if (_localEvents.length > _maxLocalEvents) {
      _localEvents.removeRange(_maxLocalEvents, _localEvents.length);
    }
  }

  Future<void> _refreshAuthEntries() async {
    final crane = _craneRef;
    final macId = crane?.connectionState.connectedDevice?.id;
    if (crane == null || macId == null) {
      if (mounted && _authEntries.isNotEmpty) setState(() => _authEntries = const []);
      return;
    }
    final service = context.read<AuthAuditLogService>();
    final entries = await service.getEntries(limit: 100);
    final scoped = entries.where((e) => e.plcDeviceId == macId).toList();
    if (!mounted) return;
    setState(() => _authEntries = scoped);
  }

  void _onCraneChanged() {
    final crane = _craneRef!;
    final connected = crane.isConnected;

    if (connected != _wasConnected) {
      if (connected) {
        _wasDeviceTitle = crane.connectedDeviceTitle;
        _pushEvent('PLC Connected', crane.connectedDeviceTitle, BrandTone.success);
        _ensureTicking(true);
        unawaited(_refreshAuthEntries());
        _entrance
          ..value = 0
          ..forward();
      } else {
        _pushEvent('PLC Disconnected', _wasDeviceTitle ?? 'Link lost', BrandTone.danger);
        _ensureTicking(false);
        _wasEstopReported = null;
        _wasEstopLatched = null;
        _wasActiveFields = null;
      }
      _wasConnected = connected;
    }

    if (connected) {
      final reportedEstop = crane.reportedStatusCommand.estop;
      if (_wasEstopReported != null && reportedEstop != _wasEstopReported) {
        _pushEvent(
          reportedEstop ? 'E-Stop Activated' : 'E-Stop Cleared',
          'PLC-reported',
          reportedEstop ? BrandTone.danger : BrandTone.success,
        );
      }
      _wasEstopReported = reportedEstop;

      final latched = crane.estopLatched;
      if (_wasEstopLatched != null && latched != _wasEstopLatched) {
        _pushEvent(
          latched ? 'Software E-Stop Latched' : 'Software E-Stop Reset',
          'App safety lock',
          latched ? BrandTone.warning : BrandTone.success,
        );
      }
      _wasEstopLatched = latched;

      final activeFields = crane.reportedStatusCommand.activeFields;
      final previous = _wasActiveFields;
      if (previous != null) {
        for (final v in activeFields.difference(previous)) {
          if (v.isEmergencyStop) continue;
          _pushEvent('${v.storageKey} → ON', 'Output confirmed', BrandTone.info);
        }
        for (final v in previous.difference(activeFields)) {
          if (v.isEmergencyStop) continue;
          _pushEvent('${v.storageKey} → OFF', 'Output confirmed', BrandTone.neutral);
        }
      }
      _wasActiveFields = Set.of(activeFields);
    }

    setState(() {});
  }

  void _onFeedbackChanged() {
    final comms = _feedbackRef!.snapshot.comms;
    if (_wasComms != null && comms != _wasComms) {
      if (comms == CommsHealth.stale) {
        _pushEvent('Heartbeat Timeout', 'Communication link degraded', BrandTone.warning);
      } else if (comms == CommsHealth.live && _wasComms == CommsHealth.stale) {
        _pushEvent('Heartbeat Recovered', 'Communication link restored', BrandTone.success);
      }
    }
    _wasComms = comms;
    setState(() {});
  }

  List<_LogRow> _mergedRows() {
    final rows = <_LogRow>[
      for (final e in _localEvents)
        _LogRow(time: e.time, title: e.title, status: e.status, tone: e.tone),
      for (final e in _authEntries)
        _LogRow(
          time: e.timestamp,
          title: titleForLogEntry(e),
          status: subtitleForLogEntry(e),
          tone: _fromAuthTone(toneForLogEntry(e)),
        ),
    ];
    rows.sort((a, b) => b.time.compareTo(a.time));
    return rows.length > _maxRowsShown ? rows.sublist(0, _maxRowsShown) : rows;
  }

  @override
  Widget build(BuildContext context) {
    final crane = context.watch<CraneController>();
    final connected = crane.isConnected;

    return ScreenActivityDetector(
      onActivity: widget.onActivity ?? _noopActivity,
      child: Scaffold(
        backgroundColor: AppColors.darkBg,
        appBar: AppBar(
          backgroundColor: AppColors.appBarBg,
          foregroundColor: AppColors.darkText,
          elevation: 0,
          titleSpacing: 20,
          flexibleSpace: const ControlAppBarGlow(),
          title: Row(
            children: [
              const Icon(Icons.monitor_heart_rounded, size: 18, color: AppColors.appBarGlow),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'DIAGNOSTICS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.darkText, letterSpacing: 1.0),
                ),
              ),
              if (connected) ...[const SizedBox(width: 10), const _HeartbeatPulse(active: true, size: 8)],
            ],
          ),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(2),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.appBarBanner,
                border: Border(bottom: BorderSide(color: AppColors.appBarBannerBorder)),
              ),
              child: SizedBox(height: 2, width: double.infinity),
            ),
          ),
        ),
        body: connected
            ? _DiagnosticsBody(rows: _mergedRows(), entrance: _entrance)
            : const _NoPlcEmptyState(),
      ),
    );
  }
}

void _noopActivity() {}

BrandTone _fromAuthTone(dynamic tone) {
  // `toneForLogEntry` returns the *light-theme* BrandTone from
  // auth_log_presentation.dart; map by name onto this screen's dark-theme
  // BrandTone so the auth-derived rows and the locally-observed rows share
  // one colour vocabulary without a hard dependency between the two enums.
  final name = tone.toString().split('.').last;
  return BrandTone.values.firstWhere((t) => t.name == name, orElse: () => BrandTone.neutral);
}

class _NoPlcEmptyState extends StatelessWidget {
  const _NoPlcEmptyState();

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
                color: AppColors.darkTextMuted.withAlpha(20),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.darkBorder),
              ),
              child: const Icon(Icons.monitor_heart_outlined, color: AppColors.darkTextMuted, size: 44),
            ),
            const SizedBox(height: 18),
            const Text(
              'No PLC Connected',
              style: TextStyle(color: AppColors.darkText, fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Connect to an IntelliKran device to view diagnostic information.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.darkTextMuted, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Body — assembled once a PLC is connected.
// ─────────────────────────────────────────────────────────────────────────────

class _DiagnosticsBody extends StatelessWidget {
  const _DiagnosticsBody({required this.rows, required this.entrance});

  final List<_LogRow> rows;
  final Animation<double> entrance;

  @override
  Widget build(BuildContext context) {
    final crane = context.watch<CraneController>();
    final feedback = context.watch<FeedbackManager>();
    final layoutSettings = context.watch<LayoutSettingsController>();
    final now = DateTime.now();

    final sections = <Widget>[
      _ConnectionSection(crane: crane, now: now),
      _SessionSection(crane: crane),
      _CommunicationSection(crane: crane, feedback: feedback, now: now),
      _SafetySection(crane: crane, feedback: feedback),
      _LiveFeedbackSection(crane: crane, feedback: feedback),
      _OutputStatusSection(crane: crane, feedback: feedback, layoutSettings: layoutSettings),
      _SystemInfoSection(crane: crane),
      _EventLogSection(rows: rows),
    ];

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.darkBgTop, AppColors.darkBgBottom],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            _Reveal(animation: entrance, slot: i, child: sections[i]),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Staggered entrance — fades + slides each panel in on a shared timeline.
// ─────────────────────────────────────────────────────────────────────────────

class _Reveal extends StatelessWidget {
  const _Reveal({required this.animation, required this.slot, this.each = 0.09, this.span = 0.5, required this.child});

  final Animation<double> animation;
  final int slot;
  final double each;
  final double span;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = (slot * each).clamp(0.0, 0.99);
    final end = (start + span).clamp(start + 0.01, 1.0);
    final curved = CurvedAnimation(parent: animation, curve: Interval(start, end, curve: Curves.easeOutCubic));
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) => Opacity(
        opacity: curved.value.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, (1 - curved.value) * 18), child: child),
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared instrument-panel chrome
// ─────────────────────────────────────────────────────────────────────────────

/// Dark panel card with an icon+title header, an optional trailing badge, and
/// a self-animating alarm border/glow while [highlight] is true — the only
/// state this widget owns is that pulse, everything else is stateless.
class _Panel extends StatefulWidget {
  const _Panel({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
    this.highlight = false,
    this.accentColor = AppColors.appBarGlow,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final bool highlight;
  final Color accentColor;

  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.highlight) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _Panel old) {
    super.didUpdateWidget(old);
    if (widget.highlight && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.highlight && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = widget.highlight ? _pulse.value : 0.0;
        final borderColor = widget.highlight
            ? Color.lerp(AppColors.eStopColorLight.withAlpha(130), AppColors.eStopColorLight, t)!
            : AppColors.panelStroke;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.panelAlt, AppColors.panel],
            ),
            borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
            border: Border.all(color: borderColor, width: widget.highlight ? 1.4 : 1),
            boxShadow: [
              BoxShadow(color: Colors.black.withAlpha(90), blurRadius: 14, offset: const Offset(0, 6)),
              if (widget.highlight)
                BoxShadow(
                  color: AppColors.eStopColorLight.withAlpha((36 + 55 * t).round()),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: child,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: widget.accentColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(widget.icon, size: 15, color: widget.accentColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.title.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.darkTextSub,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              if (widget.trailing != null) Flexible(child: widget.trailing!),
            ],
          ),
          const SizedBox(height: 14),
          widget.child,
        ],
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value, this.valueColor, this.dense = false});

  final String label;
  final String value;
  final Color? valueColor;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 4 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(label, style: const TextStyle(color: AppColors.darkTextSub, fontSize: 12.5)),
          ),
          Expanded(
            flex: 5,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor ?? AppColors.darkText,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small status pill — the dark-theme equivalent of BrandBadge.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color, this.icon, this.dense = false});

  final String label;
  final Color color;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
        border: Border.all(color: color.withAlpha(110)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: dense ? 10 : 12, color: color), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: dense ? 9.5 : 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Responsive grid of equal-width tiles (metric tiles / radial stats).
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.children, this.minItemWidth = 118});

  final List<Widget> children;
  final double minItemWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0;
        final columns = math.max(2, (width / minItemWidth).floor());
        final itemWidth = (width - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final c in children) SizedBox(width: itemWidth, child: c)],
        );
      },
    );
  }
}

/// Animated numeric read-out tile — LCD-style digits that roll smoothly from
/// their previous value to the new one whenever [value] changes.
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    this.unit = '',
    this.valueColor = AppColors.darkText,
    this.iconColor = AppColors.appBarGlow,
    this.formatter,
  });

  final IconData icon;
  final String label;
  final double value;
  final String unit;
  final Color valueColor;
  final Color iconColor;
  final String Function(double)? formatter;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 92,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.panelAlt, AppColors.panel],
        ),
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: iconColor),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.darkTextMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) {
              final text = formatter?.call(v) ?? v.round().toString();
              return FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      text,
                      style: TextStyle(
                        color: valueColor,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (unit.isNotEmpty) ...[
                      const SizedBox(width: 3),
                      Text(
                        unit,
                        style: const TextStyle(color: AppColors.darkTextMuted, fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Compact radial meter — a ring fill (animated) with a centred read-out,
/// used for RSSI signal quality and heartbeat freshness.
class _RadialStat extends StatelessWidget {
  const _RadialStat({
    required this.icon,
    required this.label,
    required this.valueText,
    required this.fraction,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String valueText;
  final double fraction;
  final Color color;

  static const double _dialSize = 58;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 92,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.panelAlt, AppColors.panel],
        ),
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _dialSize,
            height: _dialSize,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 650),
              curve: Curves.easeOutCubic,
              builder: (context, f, _) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    const SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: 1,
                        strokeWidth: 5,
                        valueColor: AlwaysStoppedAnimation(AppColors.darkBorder),
                      ),
                    ),
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: f,
                        strokeWidth: 5,
                        strokeCap: StrokeCap.round,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                    Icon(icon, size: 15, color: color),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  valueText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.darkTextMuted,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    height: 1.2,
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

/// Pulsing live indicator — breathing glow while [active], a flat danger dot
/// otherwise.
class _HeartbeatPulse extends StatefulWidget {
  const _HeartbeatPulse({required this.active, this.size = 12});
  final bool active;
  final double size;

  @override
  State<_HeartbeatPulse> createState() => _HeartbeatPulseState();
}

class _HeartbeatPulseState extends State<_HeartbeatPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.eStopColorLight),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.darkSuccess.withAlpha((140 + 115 * t).round()),
            boxShadow: [
              BoxShadow(
                color: AppColors.darkSuccess.withAlpha((80 * t).round()),
                blurRadius: 6 * t + 2,
                spreadRadius: t * 1.5,
              ),
            ],
          ),
        );
      },
    );
  }
}

String _naOr(String? value) => (value == null || value.trim().isEmpty) ? 'N/A' : value;

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) return '${h}h ${m}m ${s}s';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

String _formatAgo(DateTime? t, DateTime now) {
  if (t == null) return 'N/A';
  final diff = now.difference(t);
  if (diff.isNegative || diff.inSeconds < 1) return 'just now';
  if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  return '${diff.inHours}h ago';
}

String _connectionStatusLabel(BleConnectionStatus s) => switch (s) {
  BleConnectionStatus.disconnected => 'Disconnected',
  BleConnectionStatus.scanning => 'Scanning',
  BleConnectionStatus.connecting => 'Connecting',
  BleConnectionStatus.discoveringServices => 'Discovering Services',
  BleConnectionStatus.configuringNotifications => 'Configuring Notifications',
  BleConnectionStatus.initializingSafeState => 'Initializing Safe State',
  BleConnectionStatus.connected => 'Connected (Pre-Auth)',
  BleConnectionStatus.awaitingAuthentication => 'Awaiting Authentication',
  BleConnectionStatus.authenticating => 'Authenticating',
  BleConnectionStatus.authenticated => 'Authenticated',
  BleConnectionStatus.error => 'Error',
};

String _plcCode(PlcType type) => switch (type) {
  PlcType.plc14 => 'PLC14',
  PlcType.plc21 => 'PLC21',
  PlcType.plc38 => 'PLC38',
  PlcType.unknown => 'N/A',
};

String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

Color _rssiColor(int rssi) {
  if (rssi >= -68) return AppColors.darkSuccess;
  if (rssi >= -80) return AppColors.accent;
  return AppColors.eStopColorLight;
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. PLC / Connection Status
// ─────────────────────────────────────────────────────────────────────────────

class _ConnectionSection extends StatelessWidget {
  const _ConnectionSection({required this.crane, required this.now});

  final CraneController crane;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final device = crane.connectionState.connectedDevice;
    final connectedSince = crane.connectedSince;
    final rssi = crane.connectedDeviceRssi;
    final uptimeSeconds = connectedSince != null ? now.difference(connectedSince).inSeconds.toDouble() : 0.0;

    return _Panel(
      title: 'PLC / Connection Status',
      icon: Icons.developer_board_rounded,
      trailing: _StatusBadge(
        label: _connectionStatusLabel(crane.connectionState.status).toUpperCase(),
        color: crane.isAuthenticated ? AppColors.darkSuccess : AppColors.darkInfo,
        dense: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KeyValueRow(label: 'PLC Type', value: '${_plcCode(crane.connectedPlcType)} · ${crane.connectedPlcType.displayName}'),
          _KeyValueRow(label: 'PLC Name', value: _naOr(device?.name)),
          _KeyValueRow(label: 'MAC Address', value: _naOr(device?.id)),
          const SizedBox(height: 10),
          _StatGrid(
            children: [
              rssi != null
                  ? _RadialStat(
                      icon: Icons.wifi_tethering_rounded,
                      label: 'Signal · ${_naOr(crane.connectedDeviceSignalLabel)}',
                      valueText: '$rssi dBm',
                      fraction: ((rssi + 100) / 100).clamp(0.0, 1.0),
                      color: _rssiColor(rssi),
                    )
                  : const _RadialStat(
                      icon: Icons.wifi_tethering_rounded,
                      label: 'Signal',
                      valueText: 'N/A',
                      fraction: 0,
                      color: AppColors.darkTextMuted,
                    ),
              _MetricTile(
                icon: Icons.timer_outlined,
                label: 'Uptime',
                value: uptimeSeconds,
                formatter: (v) => _formatDuration(Duration(seconds: v.round())),
              ),
              _MetricTile(
                icon: Icons.sync_problem_rounded,
                label: 'Reconnects',
                value: crane.reconnectCount.toDouble(),
                iconColor: crane.reconnectCount > 0 ? AppColors.accent : AppColors.appBarGlow,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Session / Operator
// ─────────────────────────────────────────────────────────────────────────────

class _SessionSection extends StatelessWidget {
  const _SessionSection({required this.crane});

  final CraneController crane;

  @override
  Widget build(BuildContext context) {
    final operator = crane.verifiedOperator;
    final identityMethod = operator != null
        ? 'Face Verification'
        : crane.sessionEmail != null
        ? 'Credentials'
        : 'N/A';

    return _Panel(
      title: 'Session / Operator',
      icon: Icons.badge_outlined,
      trailing: _StatusBadge(
        label: crane.isAuthenticated ? 'AUTHENTICATED' : 'NOT AUTHENTICATED',
        color: crane.isAuthenticated ? AppColors.darkSuccess : AppColors.darkTextMuted,
        dense: true,
      ),
      child: Column(
        children: [
          _KeyValueRow(label: 'Session Email', value: _naOr(crane.sessionEmail)),
          _KeyValueRow(label: 'Identified Operator', value: _naOr(operator?.name)),
          _KeyValueRow(label: 'Operator Role', value: _naOr(operator?.role.displayName)),
          _KeyValueRow(label: 'Identity Method', value: identityMethod),
          _KeyValueRow(label: 'Device Setup', value: crane.isDeviceConfigured ? 'Configured' : 'Not Configured'),
          _KeyValueRow(
            label: 'Biometric Login',
            value: crane.isBiometricEnrolled ? 'Enrolled (this device)' : 'Not Enrolled',
          ),
          _KeyValueRow(
            label: 'Control Access',
            value: crane.isAccessDenied ? 'DENIED' : (crane.isAuthenticated ? 'GRANTED' : 'N/A'),
            valueColor: crane.isAccessDenied ? AppColors.eStopColorLight : null,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Communication / Heartbeat
// ─────────────────────────────────────────────────────────────────────────────

class _CommunicationSection extends StatelessWidget {
  const _CommunicationSection({required this.crane, required this.feedback, required this.now});

  final CraneController crane;
  final FeedbackManager feedback;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final system = feedback.config.system;
    final comms = feedback.snapshot.comms;
    final heartbeatEnabled = system.heartbeatEnabled;
    final commsColor = FeedbackPalette.comms(comms);
    final statusLabel = heartbeatEnabled ? FeedbackPalette.commsLabel(comms).toUpperCase() : 'DISABLED';

    final intervalMs = SafetyConstants.heartbeatInterval.inMilliseconds;

    final lastHb = crane.lastHeartbeatSuccessAt;
    final secsSinceHb = lastHb == null ? null : now.difference(lastHb).inMilliseconds / 1000.0;
    final freshnessFraction = (!heartbeatEnabled || secsSinceHb == null)
        ? 0.0
        : (secsSinceHb / math.max(1, system.heartbeatTimeoutSeconds)).clamp(0.0, 1.0);

    return _Panel(
      title: 'Communication / Heartbeat',
      icon: Icons.podcasts_rounded,
      highlight: heartbeatEnabled && comms == CommsHealth.stale,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HeartbeatPulse(active: heartbeatEnabled && comms == CommsHealth.live),
          const SizedBox(width: 8),
          _StatusBadge(label: statusLabel, color: heartbeatEnabled ? commsColor : AppColors.darkTextMuted, dense: true),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatGrid(
            children: [
              _RadialStat(
                icon: Icons.favorite_rounded,
                label: 'Since Last HB',
                valueText: secsSinceHb != null ? '${secsSinceHb.toStringAsFixed(1)}s' : 'N/A',
                fraction: freshnessFraction,
                color: heartbeatEnabled ? commsColor : AppColors.darkTextMuted,
              ),
              _MetricTile(
                icon: Icons.arrow_upward_rounded,
                label: 'TX Packets',
                value: crane.txPacketCount.toDouble(),
                iconColor: AppColors.darkInfo,
              ),
              _MetricTile(
                icon: Icons.arrow_downward_rounded,
                label: 'RX Packets',
                value: crane.rxPacketCount.toDouble(),
                iconColor: AppColors.darkInfo,
              ),
              _MetricTile(
                icon: Icons.error_outline_rounded,
                label: 'Comm Errors',
                value: crane.commErrorCount.toDouble(),
                valueColor: crane.commErrorCount > 0 ? AppColors.eStopColorLight : AppColors.darkText,
                iconColor: crane.commErrorCount > 0 ? AppColors.eStopColorLight : AppColors.appBarGlow,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _KeyValueRow(label: 'Last Heartbeat', value: _formatAgo(crane.lastHeartbeatSuccessAt, now)),
          _KeyValueRow(label: 'Last Packet Received', value: _formatAgo(crane.lastPlcStatusAt, now)),
          _KeyValueRow(label: 'Heartbeat Interval', value: '$intervalMs ms (app → PLC)'),
          _KeyValueRow(
            label: 'Timeout Threshold',
            value: heartbeatEnabled ? '${system.heartbeatTimeoutSeconds}s' : 'Disabled',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Safety Status
// ─────────────────────────────────────────────────────────────────────────────

class _SafetySection extends StatelessWidget {
  const _SafetySection({required this.crane, required this.feedback});

  final CraneController crane;
  final FeedbackManager feedback;

  @override
  Widget build(BuildContext context) {
    final comms = feedback.snapshot.comms;
    final reportedEstop = crane.reportedStatusCommand.estop;
    final softwareEstop = crane.estopLatched;
    final commsFault = comms != CommsHealth.live;
    final raisesAlarm = feedback.config.system.raiseAlarmOnCommsLoss;

    final heartbeatSafetyColor = !commsFault
        ? AppColors.darkSuccess
        : raisesAlarm
        ? AppColors.eStopColorLight
        : AppColors.accent;
    final heartbeatSafetyLabel = !commsFault
        ? 'OK'
        : raisesAlarm
        ? 'FAULT'
        : 'DEGRADED';

    final snapshot = feedback.snapshot;
    final anyFault =
        reportedEstop || softwareEstop || heartbeatSafetyColor == AppColors.eStopColorLight || snapshot.isAnnunciating;
    final severityColor = FeedbackPalette.severity(snapshot.severity, config: feedback.config.alarm);

    return _Panel(
      title: 'Safety Status',
      icon: Icons.shield_outlined,
      highlight: anyFault,
      accentColor: anyFault ? AppColors.eStopColorLight : AppColors.appBarGlow,
      trailing: _StatusBadge(
        label: anyFault ? 'FAULT ACTIVE' : 'NORMAL',
        color: anyFault ? AppColors.eStopColorLight : AppColors.darkSuccess,
        icon: anyFault ? Icons.warning_amber_rounded : null,
        dense: true,
      ),
      child: Column(
        children: [
          _KeyValueRow(
            label: 'Emergency Stop (PLC)',
            value: reportedEstop ? 'ACTIVE' : 'CLEAR',
            valueColor: reportedEstop ? AppColors.eStopColorLight : AppColors.darkSuccess,
          ),
          _KeyValueRow(
            label: 'Software E-Stop (App Lock)',
            value: softwareEstop ? 'LATCHED' : 'CLEAR',
            valueColor: softwareEstop ? AppColors.accent : AppColors.darkSuccess,
          ),
          const _KeyValueRow(label: 'Hardware E-Stop', value: 'N/A', dense: true),
          _KeyValueRow(label: 'Heartbeat Safety', value: heartbeatSafetyLabel, valueColor: heartbeatSafetyColor),
          _KeyValueRow(
            label: 'Safety Timeout Status',
            value: commsFault ? 'EXCEEDED' : 'Within Limit',
            valueColor: commsFault ? AppColors.eStopColorLight : AppColors.darkSuccess,
          ),
          const _KeyValueRow(label: 'Idle Safety Status', value: 'N/A', dense: true),
          const Divider(height: 18, color: AppColors.darkBorder),
          _KeyValueRow(label: 'Alarm Severity', value: _severityLabel(snapshot.severity), valueColor: severityColor),
          _KeyValueRow(label: 'Alarm Acknowledged', value: snapshot.acknowledged ? 'Yes' : 'No'),
          _KeyValueRow(
            label: 'Buzzer',
            value: snapshot.buzzerActive ? 'SOUNDING' : 'Silent',
            valueColor: snapshot.buzzerActive ? AppColors.accent : null,
          ),
        ],
      ),
    );
  }
}

String _severityLabel(AlarmSeverity s) => switch (s) {
  AlarmSeverity.normal => 'NORMAL',
  AlarmSeverity.warning => 'WARNING',
  AlarmSeverity.alarm => 'ALARM',
  AlarmSeverity.critical => 'CRITICAL',
  AlarmSeverity.muted => 'MUTED',
};

// ─────────────────────────────────────────────────────────────────────────────
// 4. Live Sensor / Feedback — real radial dials (AnalogGaugeCard), the same
// instrument the Control Screen renders for H1/H2.
// ─────────────────────────────────────────────────────────────────────────────

class _LiveFeedbackSection extends StatelessWidget {
  const _LiveFeedbackSection({required this.crane, required this.feedback});

  final CraneController crane;
  final FeedbackManager feedback;

  @override
  Widget build(BuildContext context) {
    final channels = feedback.config.analogChannels;

    return _Panel(
      title: 'Live Feedback',
      icon: Icons.sensors_rounded,
      trailing: _StatusBadge(label: '${channels.length} CHANNELS', color: AppColors.darkTextMuted, dense: true),
      child: channels.isEmpty
          ? const Text(
              'No sensor channels configured.',
              style: TextStyle(color: AppColors.darkTextMuted, fontSize: 12.5),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SensorRow(
                  height: 150,
                  gauges: [
                    for (var i = 0; i < channels.length; i++) _specFor(channels[i], crane.analogValue(channels[i].channelKey), i),
                  ],
                ),
                const SizedBox(height: 10),
                for (final c in channels)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '${c.label.trim().isEmpty ? c.channelKey : c.label} · '
                      'Range ${c.displayMin.toStringAsFixed(0)}–${c.displayMax.toStringAsFixed(0)}'
                      '${c.unit.trim().isEmpty ? '' : ' ${c.unit}'} · '
                      'Raw ${crane.analogValue(c.channelKey)}',
                      style: const TextStyle(color: AppColors.darkTextMuted, fontSize: 10.5),
                    ),
                  ),
              ],
            ),
    );
  }

  SensorGaugeSpec _specFor(AnalogFeedbackConfig config, int raw, int index) {
    final (color, colorLight) = FeedbackPalette.analogChannel(index, override: config.color);
    return SensorGaugeSpec(
      tag: config.channelKey,
      label: config.label.trim().isEmpty ? config.channelKey : config.label,
      value: config.scaledValue(raw),
      color: color,
      colorLight: colorLight,
      unit: config.unit,
      minValue: config.displayMin,
      maxValue: config.displayMax,
      warningFraction: config.warningFraction,
      criticalFraction: config.criticalFraction,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. PLC Output Status
// ─────────────────────────────────────────────────────────────────────────────

class _OutputStatusSection extends StatelessWidget {
  const _OutputStatusSection({required this.crane, required this.feedback, required this.layoutSettings});

  final CraneController crane;
  final FeedbackManager feedback;
  final LayoutSettingsController layoutSettings;

  @override
  Widget build(BuildContext context) {
    final plcType = crane.connectedPlcType;
    final variants = PlcOutputVariant.values.take(plcType.digitalFieldCount).toList();
    final ledRow = feedback.config.ledRow;
    final bucket = LayoutBucket.forPlcType(plcType);
    final mapped = layoutSettings.configFor(bucket).mappedOutputVariants;

    return _Panel(
      title: 'PLC Output Status',
      icon: Icons.toggle_on_outlined,
      trailing: _StatusBadge(label: '${variants.length} OUTPUTS', color: AppColors.darkTextMuted, dense: true),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 8.0;
          final columns = constraints.maxWidth >= 420 ? 3 : 2;
          final itemWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final v in variants)
                SizedBox(
                  width: itemWidth,
                  child: _OutputChip(
                    variant: v,
                    label: ledRow.channelFor(v).label,
                    commanded: crane.isCommandedFieldActive(v),
                    confirmed: crane.isConfirmedFieldActive(v),
                    mapped: mapped.contains(v),
                    activeColor: FeedbackPalette.ledActive(v, ledRow.channelFor(v)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _OutputChip extends StatelessWidget {
  const _OutputChip({
    required this.variant,
    required this.label,
    required this.commanded,
    required this.confirmed,
    required this.mapped,
    required this.activeColor,
  });

  final PlcOutputVariant variant;
  final String? label;
  final bool commanded;
  final bool confirmed;
  final bool mapped;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    final mismatch = commanded != confirmed;
    final dotColor = confirmed ? activeColor : AppColors.darkTextMuted;
    final friendlyName = (label != null && label!.trim().isNotEmpty)
        ? label!
        : (variant.isEmergencyStop ? 'E-Stop' : _capitalize(variant.legacyName));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: mismatch ? [AppColors.accentSoft, AppColors.panel] : [AppColors.panelAlt, AppColors.panel],
        ),
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        border: Border.all(color: mismatch ? AppColors.accent : AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor,
                  boxShadow: confirmed ? [BoxShadow(color: dotColor.withAlpha(150), blurRadius: 5, spreadRadius: 0.5)] : null,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  variant.storageKey,
                  style: const TextStyle(color: AppColors.darkText, fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            friendlyName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.darkTextMuted, fontSize: 10.5),
          ),
          const SizedBox(height: 6),
          Text(
            mismatch ? '${commanded ? 'ON' : 'OFF'} → ${confirmed ? 'ON' : 'OFF'}' : (confirmed ? 'ON' : 'OFF'),
            style: TextStyle(
              color: mismatch
                  ? AppColors.accent
                  : confirmed
                  ? activeColor
                  : AppColors.darkTextSub,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (!mapped) ...[
            const SizedBox(height: 3),
            const Text(
              'unmapped',
              style: TextStyle(color: AppColors.darkTextMuted, fontSize: 9.5, fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// App / Bluetooth System Info
// ─────────────────────────────────────────────────────────────────────────────

class _SystemInfoSection extends StatelessWidget {
  const _SystemInfoSection({required this.crane});

  final CraneController crane;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'App / Bluetooth System',
      icon: Icons.phone_android_rounded,
      child: Column(
        children: [
          _KeyValueRow(label: 'App Device ID', value: _naOr(crane.deviceId)),
          _KeyValueRow(
            label: 'Bluetooth Adapter',
            value: crane.bluetoothReady ? 'ON' : 'OFF',
            valueColor: crane.bluetoothReady ? AppColors.darkSuccess : AppColors.eStopColorLight,
          ),
          _KeyValueRow(
            label: 'App Permissions',
            value: crane.permissionsGranted ? 'Granted' : 'Not Granted',
            valueColor: crane.permissionsGranted ? AppColors.darkSuccess : AppColors.accent,
          ),
          _KeyValueRow(label: 'Biometric Hardware', value: crane.isBiometricAvailable ? 'Available' : 'Not Available'),
          _KeyValueRow(
            label: 'Device Trust (last attempt)',
            value: crane.isDeviceTrustRejected ? 'REJECTED' : 'OK',
            valueColor: crane.isDeviceTrustRejected ? AppColors.eStopColorLight : null,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. Event / Diagnostic Log
// ─────────────────────────────────────────────────────────────────────────────

class _EventLogSection extends StatelessWidget {
  const _EventLogSection({required this.rows});

  final List<_LogRow> rows;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Event / Diagnostic Log',
      icon: Icons.receipt_long_outlined,
      trailing: _StatusBadge(label: '${rows.length}', color: AppColors.darkTextMuted, dense: true),
      child: rows.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No diagnostic events yet this session.',
                style: TextStyle(color: AppColors.darkTextMuted, fontSize: 12.5),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      SizedBox(width: 52, child: _ColHeader('TIME')),
                      Expanded(flex: 5, child: _ColHeader('EVENT')),
                      Expanded(flex: 4, child: _ColHeader('STATUS')),
                    ],
                  ),
                ),
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: AppColors.darkBorder),
                  _FadeInRow(
                    key: ValueKey('${rows[i].time.microsecondsSinceEpoch}-${rows[i].title}'),
                    child: _EventTableRow(row: rows[i]),
                  ),
                ],
              ],
            ),
    );
  }
}

/// Plays a short fade+slide-in exactly once, the first time a row with this
/// widget's [Key] is mounted — a genuinely new event animates in, while a
/// row that already existed on a prior build keeps its settled state.
class _FadeInRow extends StatefulWidget {
  const _FadeInRow({super.key, required this.child});
  final Widget child;

  @override
  State<_FadeInRow> createState() => _FadeInRowState();
}

class _FadeInRowState extends State<_FadeInRow> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) => Opacity(
        opacity: curved.value,
        child: Transform.translate(offset: Offset(0, (1 - curved.value) * 8), child: child),
      ),
      child: widget.child,
    );
  }
}

class _ColHeader extends StatelessWidget {
  const _ColHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(color: AppColors.darkTextMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6),
    );
  }
}

class _EventTableRow extends StatelessWidget {
  const _EventTableRow({required this.row});
  final _LogRow row;

  @override
  Widget build(BuildContext context) {
    final color = _toneColor(row.tone);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Text(
              formatLogTimestampCompact(row.time),
              style: const TextStyle(color: AppColors.darkTextSub, fontSize: 11),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              row.title,
              style: const TextStyle(color: AppColors.darkText, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: 4,
            child: Align(
              alignment: Alignment.centerRight,
              child: _StatusBadge(label: row.status.toUpperCase(), color: color, dense: true),
            ),
          ),
        ],
      ),
    );
  }
}
