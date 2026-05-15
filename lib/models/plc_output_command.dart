import 'dart:convert';
import 'dart:typed_data';

enum HoistDirection { idle, up, down }

enum HoistSpeed { idle, slow, fast }

class PlcOutputCommand {
  const PlcOutputCommand._({
    required this.estop,
    required this.direction,
    required this.speed,
  });

  final bool estop;
  final HoistDirection direction;
  final HoistSpeed speed;

  factory PlcOutputCommand.idle() {
    return const PlcOutputCommand._(
      estop: false,
      direction: HoistDirection.idle,
      speed: HoistSpeed.idle,
    );
  }

  factory PlcOutputCommand.emergencyStop() {
    return const PlcOutputCommand._(
      estop: true,
      direction: HoistDirection.idle,
      speed: HoistSpeed.idle,
    );
  }

  factory PlcOutputCommand.motion({
    required HoistDirection direction,
    required HoistSpeed speed,
  }) {
    return PlcOutputCommand._(estop: false, direction: direction, speed: speed);
  }

  factory PlcOutputCommand.fromStatusNotification(List<int> bytes) {
    try {
      final raw = utf8.decode(bytes).trim();
      final cleaned = raw.replaceAll('[', '').replaceAll(']', '');
      final parts = cleaned
          .split(',')
          .map((s) => int.tryParse(s.trim()) ?? 0)
          .toList();
      // PLC firmware publishes status as "estop,up,down".
      // Accept an optional 4th legacy value for backward compatibility.
      if (parts.length < 3) return PlcOutputCommand.idle();

      final estop = parts[0] != 0;
      final up = parts[1] != 0;
      final down = parts[2] != 0;
      final fast = parts.length > 3 ? parts[3] != 0 : false;

      if (estop) return PlcOutputCommand.emergencyStop();
      if (!up && !down) return PlcOutputCommand.idle();

      final direction = up ? HoistDirection.up : HoistDirection.down;
      final speed = fast ? HoistSpeed.fast : HoistSpeed.slow;
      return PlcOutputCommand.motion(direction: direction, speed: speed);
    } catch (_) {
      return PlcOutputCommand.idle();
    }
  }

  int get estopBit => estop ? 1 : 0;
  int get upBit => direction == HoistDirection.up ? 1 : 0;
  int get downBit => direction == HoistDirection.down ? 1 : 0;
  int get fastBit => speed == HoistSpeed.fast ? 1 : 0;

  bool get isIdle => !estop && direction == HoistDirection.idle;

  bool get isValid {
    if (estop) {
      return direction == HoistDirection.idle && speed == HoistSpeed.idle;
    }

    if (direction == HoistDirection.idle) {
      return speed == HoistSpeed.idle;
    }

    return speed == HoistSpeed.slow || speed == HoistSpeed.fast;
  }

  // PLC command format is strictly [estop,up,down].
  String get wireFormat => '[$estopBit,$upBit,$downBit]';
  Uint8List get wireBytes => Uint8List.fromList(utf8.encode(wireFormat));

  String get statusLabel {
    if (estop) {
      return 'Emergency Stop';
    }
    if (direction == HoistDirection.idle) {
      return 'Idle';
    }

    final speedLabel = speed == HoistSpeed.fast ? 'Fast' : 'Slow';
    final directionLabel = direction == HoistDirection.up ? 'Up' : 'Down';
    return '$directionLabel $speedLabel';
  }

  PlcOutputCommand copyWith({
    bool? estop,
    HoistDirection? direction,
    HoistSpeed? speed,
  }) {
    return PlcOutputCommand._(
      estop: estop ?? this.estop,
      direction: direction ?? this.direction,
      speed: speed ?? this.speed,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is PlcOutputCommand &&
        other.estop == estop &&
        other.direction == direction &&
        other.speed == speed;
  }

  @override
  int get hashCode => Object.hash(estop, direction, speed);
}
