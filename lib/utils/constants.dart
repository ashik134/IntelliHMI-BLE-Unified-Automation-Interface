import 'package:flutter/material.dart';

class AppConstants {
  static const String plcName = 'PLC 14';
  static const String appTitle = '$plcName Crane Remote Control';
  static const String appVersion = '1.0.0';
  static const String prefsKeyEmail = 'saved_email';
  static const String prefsKeyPassword = 'saved_password';
  static const String prefsKeyDeviceId = 'last_device_id';
  static const String defaultAdminEmail = 'admin@plc.com';
  static const String defaultAdminPassword = 'Admin123';
}
class BLEConstants {
  static const String serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String analogCharUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const String digitalCharUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
  static const String authCharUuid = '6e400004-b5a3-f393-e0a9-e50e24dcca9e';
  static const String statusCharUuid = '6e400005-b5a3-f393-e0a9-e50e24dcca9e';

  static const String deviceName = 'PLC14_BLE';

  static const String authRequest = 'AUTH_REQ:email|password';
  static const String authSuccess = 'AUTH_OK';
  static const String authFailed = 'AUTH_FAIL';
  static const String authTimeout = 'AUTH_TIMEOUT';
}

class SafetyConstants {
  static const Duration scanTimeout = Duration(seconds: 8);
  static const Duration authReplyTimeout = Duration(seconds: 6);
  static const Duration estopPulse = Duration(milliseconds: 300);
}

class AppColors {
  static const Color background = Color(0xFF0D1117);
  static const Color backgroundTop = Color(0xFF0C1A26);
  static const Color backgroundBottom = Color(0xFF061018);

  static const Color panel = Color(0xFF102131);
  static const Color panelAlt = Color(0xFF142838);
  static const Color panelStroke = Color(0xFF24394C);
  static const Color inputFill = Color(0xFF0B1823);
  static const Color accent = Color(0xFFFFB000);
  static const Color accentSoft = Color(0xFF3B2C0B);
  static const Color success = Color(0xFF38C793);
  static const Color successSoft = Color(0xFF123527);
  static const Color info = Color(0xFF4BB7F3);
  static const Color disabled = Color(0xFF556270);
  // ── Hoist UP
  static const Color upColor = Color(0xFF238636);
  static const Color upColorLight = Color(0xFF3FB950);

  // ── Hoist DOWN
  static const Color downColor = Color(0xFF1F6FEB);
  static const Color downColorLight = Color(0xFF58A6FF);

  // ── FAST modifier
  static const Color fastColor = Color(0xFFD29922);
  static const Color fastColorLight = Color(0xFFE3B341);

  // ── Emergency Stop
  static const Color eStopColor = Color(0xFFDA3633);
  static const Color eStopColorLight = Color(0xFFF85149);
  // ── Danger / error
  static const Color danger = Color(0xFFE24949);
  static const Color dangerSoft = Color(0xFF3E1414);
  // ── Idle / neutral
  static const Color idleColor = Color(0xFF30363D);
  // ── Text
  static const Color textPrimary = Color(0xFFF3F6F9);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textMuted = Color(0xFF94A6B7);
  // ── Border
  static const Color border = Color(0xFF30363D);
}

// ─── Light industrial palette used exclusively by ConnectionScreen ───────────
class ConnectionColors {
  // Backgrounds
  static const Color background = Color(0xFFF0F3F8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF8FAFC);

  // Brand
  static const Color primary = Color(0xFF1C3A5E);
  static const Color primarySoft = Color(0xFFE6EDF6);

  // Semantic: connected
  static const Color connected = Color(0xFF0D8A4A);
  static const Color connectedBg = Color(0xFFEAF9F1);
  static const Color connectedBorder = Color(0xFFA3DFC0);

  // Semantic: scanning / connecting
  static const Color scanning = Color(0xFF1D5FA8);
  static const Color scanningBg = Color(0xFFE8F1FB);
  static const Color scanningBorder = Color(0xFF93BDE9);

  // Semantic: warning
  static const Color warning = Color(0xFFC07800);
  static const Color warningBg = Color(0xFFFFF8E6);
  static const Color warningBorder = Color(0xFFEDC96A);

  // Semantic: error
  static const Color error = Color(0xFFCC2222);
  static const Color errorBg = Color(0xFFFDF0F0);
  static const Color errorBorder = Color(0xFFF0AAAA);

  // Neutral
  static const Color neutral = Color(0xFF68778A);
  static const Color neutralBg = Color(0xFFF1F4F8);
  static const Color neutralBorder = Color(0xFFCDD5E0);

  // Text
  static const Color textPrimary = Color(0xFF0F1B2D);
  static const Color textSecondary = Color(0xFF3A4F68);
  static const Color textMuted = Color(0xFF68778A);

  // Border / divider
  static const Color border = Color(0xFFD0D9E4);
  static const Color divider = Color(0xFFE8ECF2);
}

enum ControlState { idle, slow, fast }

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
