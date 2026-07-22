import 'dart:convert';
import 'dart:typed_data';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';

// Retained for PLC14/PLC21 UI backward-compatibility.
enum HoistDirection { idle, up, down }

enum HoistSpeed { idle, slow, fast }

/// Represents the logical output state of a crane PLC across all supported
/// axes.  Wire serialisation is PLC-type–aware via [wireFormatFor] /
/// [wireBytesFor].
///
/// Field layout:
///   PLC14/PLC21  →  [estop, up, down, fast_ud]                     (4 fields)
///   PLC38        →  [estop, up, down, fast_ud,
///                    left, right, fast_lr,
///                    forward, reverse, fast_fb]                    (10 fields)
class PlcOutputCommand {
  const PlcOutputCommand._({
    required this.estop,
    required this.up,
    required this.down,
    required this.fastUd,
    required this.left,
    required this.right,
    required this.fastLr,
    required this.forward,
    required this.reverse,
    required this.fastFb,
  });

  final bool estop;

  // ── Vertical axis (all models) ───────────────────────────────────────────────
  final bool up;
  final bool down;
  final bool fastUd;

  // ── Horizontal traverse (PLC38) ─────────────────────────────────────────────
  final bool left;
  final bool right;
  final bool fastLr;

  // ── Longitudinal travel (PLC38) ─────────────────────────────────────────────
  final bool forward;
  final bool reverse;
  final bool fastFb;

  // ── Factories ────────────────────────────────────────────────────────────────

  factory PlcOutputCommand.idle() {
    return const PlcOutputCommand._(
      estop: false,
      up: false,
      down: false,
      fastUd: false,
      left: false,
      right: false,
      fastLr: false,
      forward: false,
      reverse: false,
      fastFb: false,
    );
  }

  factory PlcOutputCommand.emergencyStop() {
    return const PlcOutputCommand._(
      estop: true,
      up: false,
      down: false,
      fastUd: false,
      left: false,
      right: false,
      fastLr: false,
      forward: false,
      reverse: false,
      fastFb: false,
    );
  }

  /// Vertical hoist motion — compatible with PLC14, PLC21, and PLC38.
  factory PlcOutputCommand.motion({
    required HoistDirection direction,
    required HoistSpeed speed,
  }) {
    return PlcOutputCommand._(
      estop: false,
      up: direction == HoistDirection.up,
      down: direction == HoistDirection.down,
      fastUd: speed == HoistSpeed.fast,
      left: false,
      right: false,
      fastLr: false,
      forward: false,
      reverse: false,
      fastFb: false,
    );
  }

  /// Horizontal traverse command (PLC38).  Preserves existing vertical and
  /// travel states from [existing] when provided.
  factory PlcOutputCommand.traverse({
    required TraverseDirection direction,
    required ControlState speed,
    PlcOutputCommand? existing,
  }) {
    final base = existing ?? PlcOutputCommand.idle();
    return PlcOutputCommand._(
      estop: false,
      up: base.up,
      down: base.down,
      fastUd: base.fastUd,
      left: direction == TraverseDirection.left,
      right: direction == TraverseDirection.right,
      fastLr: speed == ControlState.fast,
      forward: base.forward,
      reverse: base.reverse,
      fastFb: base.fastFb,
    );
  }

  /// Longitudinal travel command (PLC38).  Preserves existing vertical and
  /// traverse states from [existing] when provided.
  factory PlcOutputCommand.travel({
    required TravelDirection direction,
    required ControlState speed,
    PlcOutputCommand? existing,
  }) {
    final base = existing ?? PlcOutputCommand.idle();
    return PlcOutputCommand._(
      estop: false,
      up: base.up,
      down: base.down,
      fastUd: base.fastUd,
      left: base.left,
      right: base.right,
      fastLr: base.fastLr,
      forward: direction == TravelDirection.forward,
      reverse: direction == TravelDirection.reverse,
      fastFb: speed == ControlState.fast,
    );
  }

  /// Compose a full command from explicit field values — used by the controller
  /// when building composed PLC38 commands from independent axis states.
  factory PlcOutputCommand.compose({
    required bool estop,
    required bool up,
    required bool down,
    required bool fastUd,
    required bool left,
    required bool right,
    required bool fastLr,
    required bool forward,
    required bool reverse,
    required bool fastFb,
  }) {
    return PlcOutputCommand._(
      estop: estop,
      up: up,
      down: down,
      fastUd: fastUd,
      left: left,
      right: right,
      fastLr: fastLr,
      forward: forward,
      reverse: reverse,
      fastFb: fastFb,
    );
  }

  /// Parses a PLC status notification.  Auto-detects 4-field (PLC14/PLC21)
  /// and 10-field (PLC38) formats based on the number of values present.
  factory PlcOutputCommand.fromStatusNotification(List<int> bytes) {
    try {
      final raw = utf8.decode(bytes).trim();
      final cleaned = raw.replaceAll('[', '').replaceAll(']', '');
      final parts = cleaned
          .split(',')
          .map((s) => int.tryParse(s.trim()) ?? 0)
          .toList();

      if (parts.isEmpty) return PlcOutputCommand.idle();

      final estop = parts[0] != 0;
      if (estop) return PlcOutputCommand.emergencyStop();

      if (parts.length >= 10) {
        // PLC38: [estop, up, down, fast_ud, left, right, fast_lr,
        //         forward, reverse, fast_fb]
        return PlcOutputCommand._(
          estop: false,
          up: parts[1] != 0,
          down: parts[2] != 0,
          fastUd: parts[3] != 0,
          left: parts[4] != 0,
          right: parts[5] != 0,
          fastLr: parts[6] != 0,
          forward: parts[7] != 0,
          reverse: parts[8] != 0,
          fastFb: parts[9] != 0,
        );
      }

      // PLC14/PLC21: [estop, up, down, fast]
      final up = parts.length > 1 ? parts[1] != 0 : false;
      final down = parts.length > 2 ? parts[2] != 0 : false;
      final fast = parts.length > 3 ? parts[3] != 0 : false;

      return PlcOutputCommand._(
        estop: false,
        up: up,
        down: down,
        fastUd: fast,
        left: false,
        right: false,
        fastLr: false,
        forward: false,
        reverse: false,
        fastFb: false,
      );
    } catch (_) {
      return PlcOutputCommand.idle();
    }
  }

  // ── Derived PLC14-compatible properties ────────────────────────────────────

  HoistDirection get direction {
    if (up) return HoistDirection.up;
    if (down) return HoistDirection.down;
    return HoistDirection.idle;
  }

  HoistSpeed get speed {
    if (up || down) return fastUd ? HoistSpeed.fast : HoistSpeed.slow;
    return HoistSpeed.idle;
  }

  TraverseDirection get traverseDirection {
    if (left) return TraverseDirection.left;
    if (right) return TraverseDirection.right;
    return TraverseDirection.idle;
  }

  TravelDirection get travelDirection {
    if (forward) return TravelDirection.forward;
    if (reverse) return TravelDirection.reverse;
    return TravelDirection.idle;
  }

  bool get isIdle =>
      !estop && !up && !down && !left && !right && !forward && !reverse;

  bool get isValid {
    if (estop) {
      return !up && !down && !left && !right && !forward && !reverse;
    }
    if (up && down) return false;
    if (left && right) return false;
    if (forward && reverse) return false;
    return true;
  }

  /// Generic per-[PlcOutputVariant] field lookup — reads this command's live
  /// boolean for any of the 10 wire fields without the caller needing a
  /// switch of its own. Used by PLC-status-driven feedback widgets (horn/
  /// buzzer, alarm indicator) that watch one or more output/status variants
  /// (e.g. "is A2 on", "are A5 and A6 both on") rather than one fixed field
  /// the way the ledUp/ledDown-style getters on CraneController do.
  bool fieldValue(PlcOutputVariant mapping) => switch (mapping) {
    PlcOutputVariant.df1 => estop,
    PlcOutputVariant.df2 => up,
    PlcOutputVariant.df3 => down,
    PlcOutputVariant.df4 => fastUd,
    PlcOutputVariant.df5 => left,
    PlcOutputVariant.df6 => right,
    PlcOutputVariant.df7 => fastLr,
    PlcOutputVariant.df8 => forward,
    PlcOutputVariant.df9 => reverse,
    PlcOutputVariant.df10 => fastFb,
  };

  // ── Wire format ─────────────────────────────────────────────────────────────

  int _b(bool v) => v ? 1 : 0;

  /// Returns the PLC-type-specific wire format string.
  String wireFormatFor(PlcType plcType) {
    if (plcType == PlcType.plc38) {
      return '[${_b(estop)},${_b(up)},${_b(down)},${_b(fastUd)},'
          '${_b(left)},${_b(right)},${_b(fastLr)},'
          '${_b(forward)},${_b(reverse)},${_b(fastFb)}]';
    }
    // PLC14 / PLC21 / unknown — 4-field format
    return '[${_b(estop)},${_b(up)},${_b(down)},${_b(fastUd)}]';
  }

  /// Returns UTF-8–encoded wire bytes for the given PLC type.
  Uint8List wireBytesFor(PlcType plcType) =>
      Uint8List.fromList(utf8.encode(wireFormatFor(plcType)));

  /// Legacy getter — defaults to PLC14 4-field format.
  String get wireFormat => wireFormatFor(PlcType.plc14);
  Uint8List get wireBytes => wireBytesFor(PlcType.plc14);

  // ── Status label ─────────────────────────────────────────────────────────────

  String get statusLabel {
    if (estop) return 'Emergency Stop';
    if (isIdle) return 'Idle';
    final parts = <String>[];
    if (up) parts.add('Up${fastUd ? ' Fast' : ' Slow'}');
    if (down) parts.add('Down${fastUd ? ' Fast' : ' Slow'}');
    if (left) parts.add('Left${fastLr ? ' Fast' : ' Slow'}');
    if (right) parts.add('Right${fastLr ? ' Fast' : ' Slow'}');
    if (forward) parts.add('Fwd${fastFb ? ' Fast' : ' Slow'}');
    if (reverse) parts.add('Rev${fastFb ? ' Fast' : ' Slow'}');
    return parts.join(' \u00b7 ');
  }

  // ── copyWith ─────────────────────────────────────────────────────────────────

  PlcOutputCommand copyWith({
    bool? estop,
    bool? up,
    bool? down,
    bool? fastUd,
    bool? left,
    bool? right,
    bool? fastLr,
    bool? forward,
    bool? reverse,
    bool? fastFb,
  }) {
    return PlcOutputCommand._(
      estop: estop ?? this.estop,
      up: up ?? this.up,
      down: down ?? this.down,
      fastUd: fastUd ?? this.fastUd,
      left: left ?? this.left,
      right: right ?? this.right,
      fastLr: fastLr ?? this.fastLr,
      forward: forward ?? this.forward,
      reverse: reverse ?? this.reverse,
      fastFb: fastFb ?? this.fastFb,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlcOutputCommand &&
        other.estop == estop &&
        other.up == up &&
        other.down == down &&
        other.fastUd == fastUd &&
        other.left == left &&
        other.right == right &&
        other.fastLr == fastLr &&
        other.forward == forward &&
        other.reverse == reverse &&
        other.fastFb == fastFb;
  }

  @override
  int get hashCode => Object.hash(
    estop,
    up,
    down,
    fastUd,
    left,
    right,
    fastLr,
    forward,
    reverse,
    fastFb,
  );
}
