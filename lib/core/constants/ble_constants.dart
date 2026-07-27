class BLEConstants {
  BLEConstants._();

  static const String serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String analogCharUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const String digitalCharUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
  static const String authCharUuid = '6e400004-b5a3-f393-e0a9-e50e24dcca9e';
  static const String statusCharUuid = '6e400005-b5a3-f393-e0a9-e50e24dcca9e';
  static const String heartbeatCharUuid =
      '6e400006-b5a3-f393-e0a9-e50e24dcca9e';
  static const String analogOutCharUuid =
      '6e400007-b5a3-f393-e0a9-e50e24dcca9e';

  static const String deviceName = 'IntelliKran PLC';

  static const String manufacturerDataPrefix = 'PLC';

  static const String authRequest = 'AUTH_REQ:email|password';
  static const String authSuccess = 'AUTH_OK';
  static const String authFailed = 'AUTH_FAIL';
  static const String authFailedPrefix = 'AUTH_FAIL:';
  static const String authUntrustedDeviceReason = 'UNTRUSTED_DEVICE';
  static const String authTimeout = 'AUTH_TIMEOUT';
  static const String authUntrusted = 'AUTH_UNTRUSTED';

  static const String heartbeatPayload = 'HB';
}
