import 'package:uuid/uuid.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Generates and persistently stores a unique device identity UUID.

class DeviceIdentityService {
  DeviceIdentityService._();

  static const String _kDeviceId = 'device_identity_uuid_v1';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static String? _cachedId;

  static Future<String> getOrCreate() async {
    if (_cachedId != null) return _cachedId!;

    try {
      final stored = await _storage.read(key: _kDeviceId);
      if (stored != null && stored.isNotEmpty) {
        _cachedId = stored;
        return _cachedId!;
      }
    } catch (_) {
      // read failure
    }

    final generated = const Uuid().v4();
    try {
      await _storage.write(key: _kDeviceId, value: generated);
    } catch (_) {}
    _cachedId = generated;
    return _cachedId!;
  }

  static String? get cachedId => _cachedId;
}
