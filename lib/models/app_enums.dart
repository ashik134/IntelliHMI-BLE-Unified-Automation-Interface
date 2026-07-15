enum AppScreen { connection, authentication, control, plc38Control }

enum DeviceStaleStatus { active, stale, expired }

enum ControlState { idle, slow, fast }

/// Horizontal traverse direction (PLC38 — Left / Right axis).
enum TraverseDirection { idle, left, right }

/// Longitudinal travel direction (PLC38 — Forward / Reverse axis).
enum TravelDirection { idle, forward, reverse }

enum HoistState { idle, upSlow, upFast, downSlow, downFast }

enum PlcType {
  plc14('IntelliKran MIN'),
  plc21('IntelliKran MID'),
  plc38('IntelliKran MAX'),
  unknown('Unknown PLC');

  const PlcType(this.displayName);

  final String displayName;

  static PlcType fromString(String? value) {
    switch (value?.toUpperCase()) {
      case 'PLC14':
        return PlcType.plc14;
      case 'PLC21':
        return PlcType.plc21;
      case 'PLC38':
        return PlcType.plc38;
      default:
        return PlcType.unknown;
    }
  }
}

/// Which control-layout storage bucket a [PlcType] uses. Each PLC type has an
/// independent persisted layout and factory default.
enum LayoutBucket {
  plc14,
  plc21,
  plc38;

  static LayoutBucket forPlcType(PlcType type) => switch (type) {
    PlcType.plc14 => LayoutBucket.plc14,
    PlcType.plc21 => LayoutBucket.plc21,
    PlcType.plc38 => LayoutBucket.plc38,
    PlcType.unknown => LayoutBucket.plc14,
  };
}

const Map<ControlState, List<int>> plcOutputUp = {
  ControlState.idle: [0, 0, 0, 0],
  ControlState.slow: [0, 1, 0, 0],
  ControlState.fast: [0, 1, 0, 1],
};

const Map<ControlState, List<int>> plcOutputDown = {
  ControlState.idle: [0, 0, 0, 0],
  ControlState.slow: [0, 0, 1, 0],
  ControlState.fast: [0, 0, 1, 1],
};

const List<int> plcConflict = [0, 0, 0, 0];
