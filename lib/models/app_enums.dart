enum AppScreen {
  connection,
  faceVerification,
  authentication,
  setupMode,
  control,
  plc38Control,
}

enum DeviceStaleStatus { active, stale, expired }

/// Generic gesture-depth level a digital control reports for the physical
/// touch it's currently tracking. Not a PLC output itself — each button-type
/// strategy translates this into a neutral logical state id (e.g. 'idle',
/// 'active', 'step1', 'step2', 'zone1'..'zone5', 'center'), and only that
/// state id's `ButtonConfig.stateMappings[stateId].activeVariants` ever
/// reaches the PLC.
enum ControlState { idle, level1, level2 }

enum PlcType {
  plc14('IntelliKran MIN'),
  plc21('IntelliKran MID'),
  plc38('IntelliKran MAX'),
  unknown('Unknown PLC');

  const PlcType(this.displayName);

  final String displayName;

  /// Number of wire-format digital output fields (DF1..DFN, in
  /// [PlcOutputVariant.values] order) this PLC model exposes. DF1 is always
  /// E-STOP; DF2..DFN are the type's addressable/configurable outputs.
  ///
  ///   PLC14 (IntelliKran MIN) → 5  (E-STOP + 3 digital outputs + 1 relay)
  ///   PLC21 (IntelliKran MID) → 4  (E-STOP + 3 digital outputs)
  ///   PLC38 (IntelliKran MAX) → 10 (E-STOP + 9 digital outputs)
  ///
  /// [unknown] defaults to PLC14/PLC21's 4-field count — the smallest
  /// non-empty format — so a not-yet-identified device is never granted
  /// outputs it may not physically have.
  int get digitalFieldCount => switch (this) {
    PlcType.plc14 => 5,
    PlcType.plc21 => 4,
    PlcType.plc38 => 10,
    PlcType.unknown => 4,
  };

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
