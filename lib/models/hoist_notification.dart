/// One decrypted notification from the firmware's analog/hoist BLE
/// characteristic.
///
/// The firmware emits exactly one of these plaintext shapes before AES-GCM
/// encryption:
///
/// ```text
/// H1,<unsigned-value>
/// H2,<unsigned-value>
/// H1,<unsigned-value>,H2,<unsigned-value>
/// ```
class HoistNotification {
  HoistNotification._(Map<String, int> values)
    : values = Map.unmodifiable(values);

  static const String hoist1Key = 'H1';
  static const String hoist2Key = 'H2';
  static const List<String> channelKeys = [hoist1Key, hoist2Key];

  /// Largest value produced by the current 12-bit firmware conversion:
  /// `uint16_t((4095 - 400) * 3.0303f)`.
  static const double firmwareFullScale = 11196;

  /// The C++ payload fields are formatted from `uint16_t` values with `%u`.
  static const int maxWireValue = 0xFFFF;

  /// Values present in this packet. A single-hoist notification intentionally
  /// contains only one entry; callers can merge it into their last snapshot.
  final Map<String, int> values;

  static HoistNotification? tryParse(String payload) {
    final fields = payload.split(',');

    if (fields.length == 2) {
      final key = fields[0].trim();
      if (key != hoist1Key && key != hoist2Key) return null;

      final value = _tryParseValue(fields[1]);
      if (value == null) return null;
      return HoistNotification._({key: value});
    }

    // notifyHoistValues() always formats the combined selection in H1/H2
    // order. Keeping that order in the contract rejects malformed or
    // duplicated packets instead of partially applying them.
    if (fields.length == 4 &&
        fields[0].trim() == hoist1Key &&
        fields[2].trim() == hoist2Key) {
      final hoist1 = _tryParseValue(fields[1]);
      final hoist2 = _tryParseValue(fields[3]);
      if (hoist1 == null || hoist2 == null) return null;
      return HoistNotification._({hoist1Key: hoist1, hoist2Key: hoist2});
    }

    return null;
  }

  static int? _tryParseValue(String field) {
    final text = field.trim();
    if (text.isEmpty || !RegExp(r'^\d+$').hasMatch(text)) return null;

    final value = int.tryParse(text);
    if (value == null || value > maxWireValue) return null;
    return value;
  }
}
