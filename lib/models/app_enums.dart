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

/// Which control-layout storage bucket a [PlcType] uses. PLC14/PLC21 share
/// one bucket (both route to the same hoist-only control screen and
/// hardware class today); PLC38 gets its own with all three motion axes
/// visible by default. Introduced so each hardware class keeps an
/// independent persisted layout — customizing PLC14's grid must never
/// affect PLC38's, and vice versa.
enum LayoutBucket {
  hoistOnly,
  full;

  static LayoutBucket forPlcType(PlcType type) => switch (type) {
    PlcType.plc38 => LayoutBucket.full,
    PlcType.plc14 || PlcType.plc21 || PlcType.unknown => LayoutBucket.hoistOnly,
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
