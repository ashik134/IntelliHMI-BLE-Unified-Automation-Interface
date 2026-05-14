import 'package:flutter/material.dart';

class AppConstants {
  static const String plcName = 'PLC 14';
  static const String appTitle = 'IntelliMotion HMI';
  static const String appVersion = '1.0.0';
  static const String prefsKeyEmail = 'saved_email';
  static const String prefsKeyPassword = 'saved_password';
  static const String prefsKeyDeviceId = 'last_device_id';
  static const String prefsKeyLayoutConfig = 'control_layout_config_v1';
  static const String defaultAdminEmail = 'admin@plc.com';
  static const String defaultAdminPassword = 'Admin123';
}
class BLEConstants {
  static const String serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String analogCharUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const String digitalCharUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
  static const String authCharUuid = '6e400004-b5a3-f393-e0a9-e50e24dcca9e';
  static const String statusCharUuid = '6e400005-b5a3-f393-e0a9-e50e24dcca9e';

  static const String deviceName = 'PLC14_BLE_2';

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

/// Single color palette for the entire app.
/// Sections: [Dark] crane control screen · [Home] home screen · [Conn] connection/login/settings
class AppColors {
  // ── Dark theme – Crane Control Screen ───────────────────────────────
  static const Color darkBg = Color(0xFF0D1117);
  static const Color darkBgTop = Color(0xFF0C1A26);
  static const Color darkBgBottom = Color(0xFF061018);
  static const Color panel = Color(0xFF102131);
  static const Color panelAlt = Color(0xFF142838);
  static const Color panelStroke = Color(0xFF24394C);
  static const Color inputFill = Color(0xFF0B1823);
  static const Color accent = Color(0xFFFFB000);
  static const Color accentSoft = Color(0xFF3B2C0B);
  static const Color darkSuccess = Color(0xFF38C793);
  static const Color darkSuccessSoft = Color(0xFF123527);
  static const Color darkInfo = Color(0xFF4BB7F3);
  static const Color disabled = Color(0xFF556270);
  // Hoist
  static const Color upColor = Color(0xFF238636);
  static const Color upColorLight = Color(0xFF3FB950);
  static const Color downColor = Color(0xFF1F6FEB);
  static const Color downColorLight = Color(0xFF58A6FF);
  static const Color fastColor = Color(0xFFD29922);
  static const Color fastColorLight = Color(0xFFE3B341);
  // E-Stop
  static const Color eStopColor = Color(0xFFDA3633);
  static const Color eStopColorLight = Color(0xFFF85149);
  // Danger
  static const Color darkDanger = Color(0xFFE24949);
  static const Color darkDangerSoft = Color(0xFF3E1414);
  static const Color idleColor = Color(0xFF30363D);
  // Text / border (dark)
  static const Color darkText = Color(0xFFF3F6F9);
  static const Color darkTextSub = Color(0xFF8B949E);
  static const Color darkTextMuted = Color(0xFF94A6B7);
  static const Color darkBorder = Color(0xFF30363D);

  // ── Light theme – Home Screen ────────────────────────────────────────
  static const Color homeBg = Color(0xFFF5F7FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color homeSurfaceAlt = Color(0xFFF0F2F5);
  static const Color homeBorder = Color(0xFFE2E6EA);
  static const Color borderStrong = Color(0xFFD0D5DA);
  // Home brand
  static const Color homePrimary = Color(0xFF1A56DB);
  static const Color homePrimaryLight = Color(0xFFEBF0FA);
  static const Color homePrimaryDark = Color(0xFF1347B8);
  // Home semantic
  static const Color homeSuccess = Color(0xFF059669);
  static const Color homeSuccessLight = Color(0xFFECFDF5);
  static const Color homeWarning = Color(0xFFD97706);
  static const Color homeWarningLight = Color(0xFFFFFBEB);
  static const Color homeDanger = Color(0xFFDC2626);
  static const Color homeDangerLight = Color(0xFFFEF2F2);
  static const Color homeInfo = Color(0xFF6366F1);
  // Text (light)
  static const Color lightText = Color(0xFF111827);
  static const Color lightTextSub = Color(0xFF6B7280);
  static const Color lightTextMuted = Color(0xFF9CA3AF);
  // Nav bar
  static const Color navBarBg = Color(0xFFFFFFFF);
  static const Color navBarBorder = Color(0xFFE5E7EB);
  static const Color navBarActive = Color(0xFF1A56DB);
  static const Color navBarInactive = Color(0xFF9CA3AF);
  static const Color shadowLight = Color(0x0A000000);
  static const Color shadowMedium = Color(0x14000000);

  // ── Light theme – Connection / Login / Settings ──────────────────────
  static const Color connBg = Color(0xFFF0F3F8);
  static const Color connSurfaceAlt = Color(0xFFF8FAFC);
  static const Color connPrimary = Color(0xFF1C3A5E);
  static const Color primarySoft = Color(0xFFE6EDF6);
  // Connection states
  static const Color connected = Color(0xFF0D8A4A);
  static const Color connectedBg = Color(0xFFEAF9F1);
  static const Color connectedBorder = Color(0xFFA3DFC0);
  static const Color scanning = Color(0xFF1D5FA8);
  static const Color scanningBg = Color(0xFFE8F1FB);
  static const Color scanningBorder = Color(0xFF93BDE9);
  static const Color connWarning = Color(0xFFC07800);
  static const Color warningBg = Color(0xFFFFF8E6);
  static const Color warningBorder = Color(0xFFEDC96A);
  static const Color error = Color(0xFFCC2222);
  static const Color errorBg = Color(0xFFFDF0F0);
  static const Color errorBorder = Color(0xFFF0AAAA);
  static const Color neutral = Color(0xFF68778A);
  static const Color neutralBg = Color(0xFFF1F4F8);
  static const Color neutralBorder = Color(0xFFCDD5E0);
  // Text / border (conn)
  static const Color connText = Color(0xFF0F1B2D);
  static const Color connTextSub = Color(0xFF3A4F68);
  static const Color connTextMuted = Color(0xFF68778A);
  static const Color connBorder = Color(0xFFD0D9E4);
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
