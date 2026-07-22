/// Closed set of digital PLC output variants in wire order.
///
/// The names are intentionally generic because this app can control any
/// supported PLC output layout, not only crane motion. DF1 is reserved for
/// E-STOP; DF2-DF10 are user-configurable digital field outputs.
enum PlcOutputVariant {
  df1,
  df2,
  df3,
  df4,
  df5,
  df6,
  df7,
  df8,
  df9,
  df10;

  String get storageKey => 'DF${index + 1}';

  String get genericLabel =>
      this == PlcOutputVariant.df1 ? 'DF1 / E-STOP' : storageKey;

  bool get isEmergencyStop => this == PlcOutputVariant.df1;

  bool get isUserConfigurable => !isEmergencyStop;

  String get legacyName => switch (this) {
    PlcOutputVariant.df1 => 'estop',
    PlcOutputVariant.df2 => 'up',
    PlcOutputVariant.df3 => 'down',
    PlcOutputVariant.df4 => 'fastUd',
    PlcOutputVariant.df5 => 'left',
    PlcOutputVariant.df6 => 'right',
    PlcOutputVariant.df7 => 'fastLr',
    PlcOutputVariant.df8 => 'forward',
    PlcOutputVariant.df9 => 'reverse',
    PlcOutputVariant.df10 => 'fastFb',
  };

  /// Compatibility alias for older UI/config code that already spoke DF IDs.
  String get variantId => storageKey;

  static PlcOutputVariant? fromStorageKey(Object? raw) {
    if (raw == null) return null;
    final value = raw.toString().trim();
    final normalized = value.toUpperCase();

    for (final variant in PlcOutputVariant.values) {
      if (variant.storageKey == normalized ||
          variant.name == value ||
          variant.legacyName == value) {
        return variant;
      }
    }
    return null;
  }

  static PlcOutputVariant? fromVariantId(String id) => fromStorageKey(id);
}
