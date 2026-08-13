import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'package:rev_crane_control_ops/models/alarm_indicator_config.dart'
    show AlarmSeverity;
import 'package:rev_crane_control_ops/models/feedback/alarm_feedback_config.dart';
import 'package:rev_crane_control_ops/models/feedback/analog_feedback_config.dart';
import 'package:rev_crane_control_ops/models/feedback/feedback_settings_config.dart';
import 'package:rev_crane_control_ops/models/feedback/led_feedback_config.dart';
import 'package:rev_crane_control_ops/models/feedback/system_feedback_config.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FeedbackManager
//
//   PLC / Sensor / System Status
//           |
//     FeedbackManager
//           |
//   Alarm / Buzzer / LED / Value / Status UI
//
// The single place raw PLC status, analog readings and transport health are
// turned into what the operator actually sees and hears. Everything upstream
// of it is read through [FeedbackSource], an interface with no write method of
// any kind — so "Feedback Settings must not send normal PLC control commands"
// is a structural property here, not a review rule: this class has no way to
// reach a command path even by accident.
//
// It owns only the state that cannot be derived from a single frame of PLC
// status: the alarm latch, the acknowledgement episode, and the heartbeat's
// notion of how long the link has been silent. Everything else is recomputed
// from [config] + [FeedbackSource] on demand.
// ─────────────────────────────────────────────────────────────────────────────

/// Read-only view of every signal feedback is allowed to observe.
///
/// Deliberately narrow. CraneController implements it, but the UI-facing
/// feedback path only ever sees these members, none of which can write to the
/// PLC. Digital status is read from the CONFIRMED readback
/// (`isReportedFieldActive`), never the optimistic command echo — an
/// annunciator must state what IS, not what was asked for.
/// [isCommandedFieldActive] is the one exception, and exists solely so the LED
/// row can draw the commanded-vs-confirmed *disagreement*; it is an intent
/// signal being read, never sent.
abstract interface class FeedbackSource implements Listenable {
  bool isReportedFieldActive(PlcOutputVariant variant);
  bool isCommandedFieldActive(PlcOutputVariant variant);

  /// Raw counts for an analog channel key (`A1`, `A2`, ...); 0 when the
  /// channel has never reported.
  int analogValue(String channelKey);

  /// Whether the transport currently has a usable link to the PLC.
  bool get isPlcConnected;

  /// When the most recent PLC status notification arrived, or null if none
  /// has since the connection was established. The heartbeat is derived from
  /// this — the app never pings the PLC to produce one.
  DateTime? get lastPlcStatusAt;
}

// ─────────────────────────────────────────────────────────────────────────────
// Resolved readings
// ─────────────────────────────────────────────────────────────────────────────

/// One analog channel, scaled and banded — everything the gauge needs.
@immutable
class AnalogFeedbackReading {
  const AnalogFeedbackReading({
    required this.config,
    required this.rawValue,
    required this.value,
    required this.zone,
  });

  final AnalogFeedbackConfig config;

  /// Counts as reported by the PLC, before calibration/scaling.
  final int rawValue;

  /// [rawValue] through the channel's calibration and scaling.
  final double value;

  final AnalogFeedbackZone zone;

  String get displayLabel =>
      config.label.trim().isEmpty ? config.channelKey : config.label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnalogFeedbackReading &&
          other.config == config &&
          other.rawValue == rawValue &&
          other.value == value &&
          other.zone == zone;

  @override
  int get hashCode => Object.hash(config, rawValue, value, zone);
}

/// One LED channel's live state plus the presentation resolved for it.
@immutable
class LedFeedbackReading {
  const LedFeedbackReading({
    required this.variant,
    required this.config,
    required this.commanded,
    required this.confirmed,
    required this.mapped,
  });

  final PlcOutputVariant variant;
  final LedChannelFeedbackConfig config;

  /// What the app asked for (outer ring) and what the PLC confirmed (inner
  /// core). Never merged — their disagreement is the pending state.
  final bool commanded;
  final bool confirmed;

  /// Whether any control in the layout can actually drive this channel.
  final bool mapped;

  String get displayLabel =>
      config.label ?? (variant.isEmergencyStop ? 'ESTOP' : variant.storageKey);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LedFeedbackReading &&
          other.variant == variant &&
          other.config == config &&
          other.commanded == commanded &&
          other.confirmed == confirmed &&
          other.mapped == mapped;

  @override
  int get hashCode =>
      Object.hash(variant, config, commanded, confirmed, mapped);
}

/// Everything the feedback UI renders in one frame-stable value.
@immutable
class FeedbackSnapshot {
  const FeedbackSnapshot({
    this.rawSeverity = AlarmSeverity.normal,
    this.severity = AlarmSeverity.normal,
    this.acknowledged = false,
    this.buzzerActive = false,
    this.comms = CommsHealth.offline,
    this.analog = const <AnalogFeedbackReading>[],
  });

  /// Severity the PLC/sensors/link report right now, before latching and
  /// acknowledgement.
  final AlarmSeverity rawSeverity;

  /// Severity to actually render: [rawSeverity] raised to the latched peak
  /// when latching is on, or [AlarmSeverity.muted] once acknowledged.
  final AlarmSeverity severity;

  final bool acknowledged;

  /// Whether the buzzer should be sounding/pulsing right now — the union of
  /// its own PLC trigger and any enabled escalation source, minus an
  /// acknowledged episode.
  final bool buzzerActive;

  final CommsHealth comms;

  /// Visible analog readers, in configured order.
  final List<AnalogFeedbackReading> analog;

  bool get isAnnunciating => severity.isAnnunciating;

  static bool _analogEqual(
    List<AnalogFeedbackReading> a,
    List<AnalogFeedbackReading> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeedbackSnapshot &&
          other.rawSeverity == rawSeverity &&
          other.severity == severity &&
          other.acknowledged == acknowledged &&
          other.buzzerActive == buzzerActive &&
          other.comms == comms &&
          _analogEqual(other.analog, analog);

  @override
  int get hashCode => Object.hash(
    rawSeverity,
    severity,
    acknowledged,
    buzzerActive,
    comms,
    Object.hashAll(analog),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// FeedbackManager
// ─────────────────────────────────────────────────────────────────────────────

class FeedbackManager extends ChangeNotifier {
  FeedbackManager({
    required FeedbackSource source,
    FeedbackSettingsConfig config = const FeedbackSettingsConfig(),
    DateTime Function()? now,
    Duration heartbeatTick = const Duration(seconds: 1),
  }) : _source = source,
       _config = config,
       _now = now ?? DateTime.now,
       _heartbeatTick = heartbeatTick {
    _source.addListener(_onSourceChanged);
    _snapshot = _compute();
    _syncHeartbeatTimer();
  }

  final FeedbackSource _source;
  final DateTime Function() _now;
  final Duration _heartbeatTick;

  FeedbackSettingsConfig _config;
  FeedbackSnapshot _snapshot = const FeedbackSnapshot();
  Timer? _heartbeatTimer;
  bool _disposed = false;

  /// Highest severity seen since the last acknowledgement while latching is
  /// on. Null once cleared — a non-latched alarm never sets it.
  AlarmSeverity? _latchedSeverity;

  /// Rank of the severity the operator acknowledged, or -1 when there is no
  /// live acknowledgement. Anything at or below this rank renders as muted;
  /// an escalation above it re-annunciates (see [_compute]).
  int _acknowledgedRank = -1;

  /// True once the buzzer has been silenced for the current episode.
  bool _buzzerAcknowledged = false;

  /// Latched-buzzer memory, mirroring [_latchedSeverity] for the audible
  /// channel.
  bool _buzzerLatched = false;

  /// Link state at the last source notification, so a reconnect can be
  /// detected — see [_onSourceChanged].
  late bool _wasConnected = _source.isPlcConnected;

  FeedbackSettingsConfig get config => _config;
  FeedbackSnapshot get snapshot => _snapshot;

  /// Points the manager at a different feedback configuration — called by the
  /// control screens with the layout being rendered, which is the EDIT DRAFT
  /// while Feedback Settings is open, so every change previews live.
  ///
  /// Safe to call from a build: [_publish] defers its notification when the
  /// scheduler is mid-frame, so descendants that already built are never
  /// marked dirty inside the same frame.
  void updateConfig(FeedbackSettingsConfig next) {
    if (next == _config) return;
    _config = next;
    // A latch that is no longer configured must not keep an old peak alive.
    if (!next.alarm.latched) _latchedSeverity = null;
    if (!next.buzzer.latched) _buzzerLatched = false;
    _syncHeartbeatTimer();
    _publish();
  }

  /// Silences the current episode: clears the alarm latch and mutes the
  /// buzzer, for whichever of the two allows acknowledgement. Purely local —
  /// it cannot and does not tell the PLC anything (see [FeedbackSource]).
  void acknowledge() {
    var changed = false;
    if (_config.alarm.acknowledgeEnabled && _snapshot.isAnnunciating) {
      _acknowledgedRank = _snapshot.severity.rank;
      _latchedSeverity = null;
      changed = true;
    }
    if (_config.buzzer.acknowledgeEnabled && _snapshot.buzzerActive) {
      _buzzerAcknowledged = true;
      _buzzerLatched = false;
      changed = true;
    }
    if (changed) _publish();
  }

  /// Drops any acknowledgement/latch state. Called automatically when the link
  /// comes back (see [_onSourceChanged]) so a fresh session never starts
  /// pre-silenced by a previous one, and available to callers that need the
  /// same reset for their own reason.
  void resetEpisode() {
    if (!_clearEpisodeState()) return;
    _publish();
  }

  /// Returns whether anything was actually cleared, so callers can skip a
  /// redundant publish.
  bool _clearEpisodeState() {
    if (_acknowledgedRank < 0 &&
        _latchedSeverity == null &&
        !_buzzerAcknowledged &&
        !_buzzerLatched) {
      return false;
    }
    _acknowledgedRank = -1;
    _latchedSeverity = null;
    _buzzerAcknowledged = false;
    _buzzerLatched = false;
    return true;
  }

  // ── LED / input-output feedback ──────────────────────────────────────────

  /// Resolves the LED row for [variants] — which channels a given PLC model
  /// exposes is a property of the hardware, not of this config, so the caller
  /// supplies the list. [mappedVariants] comes from
  /// ControlLayoutConfig.mappedOutputVariants: a channel outside it is a spare
  /// no control can drive.
  ///
  /// Not part of [snapshot] on purpose — it is a pure projection of source +
  /// config with no episode state behind it, so recomputing it per build is
  /// both correct and cheaper than diffing a list nobody kept.
  List<LedFeedbackReading> resolveLeds({
    required List<PlcOutputVariant> variants,
    required Set<PlcOutputVariant> mappedVariants,
  }) {
    final row = _config.ledRow;
    final readings = <LedFeedbackReading>[];
    for (final variant in variants) {
      final channel = row.channelFor(variant);
      if (!channel.visible) continue;
      final mapped = mappedVariants.contains(variant);
      if (!mapped && !row.showUnmappedChannels) continue;

      final confirmed = _source.isReportedFieldActive(variant);
      readings.add(
        LedFeedbackReading(
          variant: variant,
          config: channel,
          // Suppressing the pending annunciation means reporting the
          // confirmed value on both halves, so ring and core always agree and
          // no blink can be produced downstream.
          commanded: row.showPendingState && channel.blinkWhenPending
              ? _source.isCommandedFieldActive(variant)
              : confirmed,
          confirmed: confirmed,
          mapped: mapped,
        ),
      );
    }
    return readings;
  }

  // ── Resolution ───────────────────────────────────────────────────────────

  void _onSourceChanged() {
    // A reconnect starts a new session: whatever the operator silenced or
    // latched on the previous link is about to be re-evaluated against a PLC
    // that may have changed while we were away, so it must not stay muted.
    final connected = _source.isPlcConnected;
    if (connected && !_wasConnected) _clearEpisodeState();
    _wasConnected = connected;
    _publish();
  }

  void _publish() {
    if (_disposed) return;
    final next = _compute();
    if (next == _snapshot) return;
    _snapshot = next;
    _notifySafely();
  }

  /// Delivers the change without ever marking an already-built descendant
  /// dirty inside the current frame — see [updateConfig].
  void _notifySafely() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
      return;
    }
    notifyListeners();
  }

  FeedbackSnapshot _compute() {
    final analog = _resolveAnalog();
    final comms = _resolveComms();
    final rawSeverity = _resolveRawSeverity(analog: analog, comms: comms);

    // Episode bookkeeping. A raw severity that climbs past what was
    // acknowledged re-annunciates; a return to normal ends the episode
    // outright, so the next event starts un-silenced.
    if (rawSeverity == AlarmSeverity.normal) {
      _acknowledgedRank = -1;
    } else if (rawSeverity.rank > _acknowledgedRank) {
      _acknowledgedRank = -1;
    }
    if (_config.alarm.latched && rawSeverity.isAnnunciating) {
      final latched = _latchedSeverity;
      if (latched == null || rawSeverity.rank > latched.rank) {
        _latchedSeverity = rawSeverity;
      }
    }

    final latched = _config.alarm.latched ? _latchedSeverity : null;
    final held = latched != null && latched.rank > rawSeverity.rank
        ? latched
        : rawSeverity;
    final acknowledged = held.isAnnunciating && _acknowledgedRank >= held.rank;
    final severity = acknowledged ? AlarmSeverity.muted : held;

    final buzzerActive = _resolveBuzzer(
      heldSeverity: held,
      analog: analog,
      comms: comms,
    );

    return FeedbackSnapshot(
      rawSeverity: rawSeverity,
      severity: severity,
      acknowledged: acknowledged,
      buzzerActive: buzzerActive,
      comms: comms,
      analog: analog,
    );
  }

  List<AnalogFeedbackReading> _resolveAnalog() {
    final readings = <AnalogFeedbackReading>[];
    for (final channel in _config.analogChannels) {
      if (!channel.visible) continue;
      final raw = _source.analogValue(channel.channelKey);
      final scaled = channel.scaledValue(raw);
      readings.add(
        AnalogFeedbackReading(
          config: channel,
          rawValue: raw,
          value: scaled,
          zone: channel.zoneFor(scaled),
        ),
      );
    }
    return readings;
  }

  CommsHealth _resolveComms() {
    if (!_source.isPlcConnected) return CommsHealth.offline;
    if (!_config.system.heartbeatEnabled) return CommsHealth.live;
    final last = _source.lastPlcStatusAt;
    // Connected but nothing heard yet is not yet a fault — the PLC only
    // notifies on change, so a quiet, healthy machine is normal.
    if (last == null) return CommsHealth.live;
    final silence = _now().difference(last);
    return silence > _config.system.heartbeatTimeout
        ? CommsHealth.stale
        : CommsHealth.live;
  }

  AlarmSeverity _resolveRawSeverity({
    required List<AnalogFeedbackReading> analog,
    required CommsHealth comms,
  }) {
    var severity = _config.alarm.severityFor(_source.isReportedFieldActive);

    // An analog channel opted into escalation raises the layout alarm when it
    // reaches its own critical band; its warning band stays a gauge-local
    // colour change, matching how operators read a dial.
    for (final reading in analog) {
      if (!reading.config.raiseAlarm) continue;
      if (reading.zone != AnalogFeedbackZone.critical) continue;
      if (AlarmSeverity.alarm.rank > severity.rank) {
        severity = AlarmSeverity.alarm;
      }
    }

    if (_config.system.raiseAlarmOnCommsLoss && comms != CommsHealth.live) {
      final commsSeverity = comms == CommsHealth.offline
          ? AlarmSeverity.critical
          : AlarmSeverity.warning;
      if (commsSeverity.rank > severity.rank) severity = commsSeverity;
    }

    return severity;
  }

  bool _resolveBuzzer({
    required AlarmSeverity heldSeverity,
    required List<AnalogFeedbackReading> analog,
    required CommsHealth comms,
  }) {
    final buzzer = _config.buzzer;
    var triggered = buzzer.horn.trigger.isActive(_source.isReportedFieldActive);

    if (!triggered && _config.alarm.driveBuzzer) {
      triggered =
          heldSeverity.rank >= _config.alarm.minimumBuzzerSeverity.rank &&
          heldSeverity.isAnnunciating;
    }
    if (!triggered) {
      for (final reading in analog) {
        if (reading.config.soundBuzzer &&
            reading.zone == AnalogFeedbackZone.critical) {
          triggered = true;
          break;
        }
      }
    }
    if (!triggered &&
        _config.system.soundBuzzerOnCommsLoss &&
        comms != CommsHealth.live) {
      triggered = true;
    }

    if (buzzer.latched && triggered) _buzzerLatched = true;
    final held = triggered || (buzzer.latched && _buzzerLatched);

    if (!held) {
      // Episode over — the next trigger starts audible again.
      _buzzerAcknowledged = false;
      _buzzerLatched = false;
      return false;
    }
    return !_buzzerAcknowledged;
  }

  // ── Heartbeat ────────────────────────────────────────────────────────────

  /// The link going quiet produces no event of its own, so staleness needs a
  /// clock. The timer runs only while the heartbeat is actually configured,
  /// and each tick publishes only if the resolved snapshot really changed.
  void _syncHeartbeatTimer() {
    final wanted = _config.system.heartbeatEnabled;
    if (!wanted) {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      return;
    }
    if (_heartbeatTimer != null) return;
    _heartbeatTimer = Timer.periodic(_heartbeatTick, (_) => _publish());
  }

  @override
  void dispose() {
    _disposed = true;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _source.removeListener(_onSourceChanged);
    super.dispose();
  }
}
