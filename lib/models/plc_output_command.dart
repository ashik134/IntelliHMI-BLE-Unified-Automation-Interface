import 'dart:convert';
import 'dart:typed_data';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';

/// Represents the logical output state of a PLC as a generic set of asserted
/// [PlcOutputVariant] fields. Wire serialisation is PLC-type-aware via
/// [wireFormatFor] / [wireBytesFor].
///
/// Field layout (positional, [PlcOutputVariant.values] order — DF1..DF10),
/// per [PlcType.digitalFieldCount]:
///   PLC14  →  [DF1..DF5]   (5 fields — E-STOP + 3 digital outputs + relay)
///   PLC21  →  [DF1..DF4]   (4 fields)
///   PLC38  →  [DF1..DF10]  (10 fields)
class PlcOutputCommand {
  const PlcOutputCommand._(this.activeFields);

  /// The exact set of PLC output variants currently asserted. Never implies
  /// anything beyond what's explicitly present — the single source of truth
  /// for every field this command will assert on the wire.
  final Set<PlcOutputVariant> activeFields;

  // ── Factories ────────────────────────────────────────────────────────────────

  factory PlcOutputCommand.idle() => const PlcOutputCommand._({});

  factory PlcOutputCommand.emergencyStop() =>
      const PlcOutputCommand._({PlcOutputVariant.df1});

  /// Compose a command from an explicit field set — used by the controller
  /// when building a command from every button's currently-claimed fields.
  factory PlcOutputCommand.compose(Set<PlcOutputVariant> fields) =>
      PlcOutputCommand._(fields);

  /// Parses a PLC status notification. Auto-detects the 4-field (PLC21),
  /// 5-field (PLC14), and 10-field (PLC38) formats based on the number of
  /// values present — see [PlcType.digitalFieldCount].
  ///
  /// Status feedback contains the physical output levels. DF1/E-STOP is
  /// wired active-low, so its status bit has the opposite polarity from the
  /// logical command bit: `0` means E-STOP active and `1` means safe/inactive.
  /// DF2 onward remain active-high (`1` means active).
  factory PlcOutputCommand.fromStatusNotification(List<int> bytes) =>
      tryParseStatusNotification(bytes) ?? PlcOutputCommand.idle();

  /// Strict form used by the live BLE path. Returning null lets the service
  /// retain the last valid PLC state instead of turning a malformed or still-
  /// encrypted packet into a plausible but incorrect all-off indication.
  static PlcOutputCommand? tryParseStatusNotification(List<int> bytes) {
    try {
      var payload = utf8.decode(bytes).trim();
      if (payload.startsWith('[') && payload.endsWith(']')) {
        payload = payload.substring(1, payload.length - 1).trim();
      }

      final tokens = payload.split(',');
      const validLengths = {4, 5, 10};
      if (!validLengths.contains(tokens.length)) return null;
      final parts = <int>[];
      for (final token in tokens) {
        final value = token.trim();
        if (value != '0' && value != '1') return null;
        parts.add(value == '1' ? 1 : 0);
      }

      if (parts[0] == 0) return PlcOutputCommand.emergencyStop();

      final fields = <PlcOutputVariant>{};
      for (
        var i = 1;
        i < parts.length && i < PlcOutputVariant.values.length;
        i++
      ) {
        if (parts[i] != 0) fields.add(PlcOutputVariant.values[i]);
      }
      return PlcOutputCommand._(fields);
    } catch (_) {
      return null;
    }
  }

  // ── Derived properties ──────────────────────────────────────────────────────

  bool get estop => activeFields.contains(PlcOutputVariant.df1);

  bool get isIdle => activeFields.isEmpty;

  /// Generic invariant: E-STOP excludes every other field. There is no more
  /// pairwise "opposite direction" validation here — per-field conflicts are
  /// prevented upstream by the controller's field-ownership map, which is
  /// generic (one buttonId owns a field at a time), not axis-shaped.
  bool get isValid => !estop || activeFields.length == 1;

  /// Generic per-[PlcOutputVariant] field lookup — reads this command's live
  /// boolean for any of the wire fields without the caller needing a switch
  /// of its own. Used by PLC-status-driven feedback widgets (horn/buzzer,
  /// alarm indicator) that watch one or more output/status variants.
  bool fieldValue(PlcOutputVariant mapping) => activeFields.contains(mapping);

  // ── Wire format ─────────────────────────────────────────────────────────────

  /// Returns the PLC-type-specific wire format string. [PlcOutputVariant]
  /// is already in DF1..DF10 wire order, so this simply takes the first 4 or
  /// all 10 variants and reads each one's asserted bit — no per-field name
  /// mapping needed.
  String wireFormatFor(PlcType plcType) {
    final count = plcType.digitalFieldCount;
    final bits = PlcOutputVariant.values
        .take(count)
        .map((v) => fieldValue(v) ? '1' : '0');
    return '[${bits.join(',')}]';
  }

  /// Returns UTF-8–encoded wire bytes for the given PLC type.
  Uint8List wireBytesFor(PlcType plcType) =>
      Uint8List.fromList(utf8.encode(wireFormatFor(plcType)));

  /// Legacy getter — defaults to PLC14 4-field format.
  String get wireFormat => wireFormatFor(PlcType.plc14);
  Uint8List get wireBytes => wireBytesFor(PlcType.plc14);

  // ── Status label ─────────────────────────────────────────────────────────────

  /// Generic active-output summary — lists the DF fields currently asserted
  /// (e.g. "DF2 · DF4"), never a crane-worded description.
  String get statusLabel {
    if (estop) return 'E-STOP';
    if (isIdle) return 'Idle';
    final active = PlcOutputVariant.values.where(
      (v) => !v.isEmergencyStop && fieldValue(v),
    );
    return active.map((v) => v.storageKey).join(' · ');
  }

  // ── copyWith ─────────────────────────────────────────────────────────────────

  PlcOutputCommand copyWith({Set<PlcOutputVariant>? activeFields}) =>
      PlcOutputCommand._(activeFields ?? this.activeFields);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlcOutputCommand &&
        other.activeFields.length == activeFields.length &&
        other.activeFields.containsAll(activeFields);
  }

  @override
  int get hashCode =>
      activeFields.fold(0, (acc, field) => acc ^ field.hashCode);
}
