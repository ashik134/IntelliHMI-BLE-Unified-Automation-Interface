import 'package:flutter/material.dart';

class AppColors {
  AppColors._();
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
  // Horizontal traverse (PLC38 — Left / Right)
  static const Color traverseColor = Color(0xFF8250DF);
  static const Color traverseColorLight = Color(0xFFA371F7);
  // Longitudinal travel (PLC38 — Forward / Reverse)
  static const Color travelColor = Color(0xFF1A7F74);
  static const Color travelColorLight = Color(0xFF3DC9B0);
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

  // ── Control Screen AppBar (violet-tinted) ─────────────────────────────
  static const Color appBarBg = Color(0xFF12101E);
  static const Color appBarGlow = Color(0xFF8B5CF6);
  static const Color appBarBanner = Color(0x1A7C3AED); // violet-600 @ 10%
  static const Color appBarBannerBorder = Color(0x338B5CF6); // violet-500 @ 20%
  // Solid, more saturated violet used only while Customization/Edit Mode is
  // active, so the AppBar itself reads as visually distinct from normal mode.
  static const Color appBarEditingBg = Color(0xFF1F1533);

  // ── Selection overlay (customization mode, violet-tinted) ────────────
  static const Color selectionViolet = Color(0xFF8B5CF6); // violet-500
  static const Color selectionVioletDeep = Color(0xFF7C3AED); // violet-600
  static const Color selectionGlow = Color(0x668B5CF6); // violet-500 @ 40%
  static const Color selectionHandleFill = Color(0xFFFFFFFF);
  static const Color selectionDotGrid = Color(0x14FFFFFF); // white @ 8%

  // ── Customization toolbar (floating circular action row) ─────────────
  // Dark graphite, deliberately NOT violet/saturated — the accent is
  // reserved for the selected-item and Done affordances so it never reads
  // as a live PLC control state.
  static const Color toolbarCircleBg = Color(0xFF20232B);
  static const Color toolbarCircleBgPressed = Color(0xFF2C2F39);
  static const Color toolbarCircleBgSelected = Color(0xFF2A2440);

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
  static const Color connSuccess = Color(0xFF059669);

  // ── Unified brand system – Home / Scan / Auth ─────────────────────────
  // Shared industrial-HMI language for the three "onboarding" screens,
  // built on the same violet accent as the Control Screen AppBar so the
  // whole app reads as one product.
  static const Color brandInk = Color(0xFF0B1120); // deep slate, hero surfaces
  static const Color brandInkAlt = Color(0xFF141B2E);
  static const Color brandSurface = Color(0xFFFFFFFF);
  static const Color brandSurfaceAlt = Color(0xFFF4F5F9);
  static const Color brandBg = Color(0xFFF1F2F7);
  static const Color brandBorder = Color(0xFFE3E5EE);
  static const Color brandBorderStrong = Color(0xFFD3D6E3);
  static const Color brandText = Color(0xFF13172A);
  static const Color brandTextSub = Color(0xFF5B6178);
  static const Color brandTextMuted = Color(0xFF9498AC);
  static const Color brandOnDark = Color(0xFFF5F6FB);
  static const Color brandOnDarkSub = Color(0xFFAEB3C9);

  // Violet brand accent (matches Control Screen appBarGlow/selectionViolet)
  static const Color brandViolet = Color(0xFF8B5CF6); // violet-500
  static const Color brandVioletDeep = Color(0xFF6D28D9); // violet-700
  static const Color brandVioletSoft = Color(0xFFF1EBFE);
  static const Color brandVioletGlow = Color(0x668B5CF6); // violet-500 @ 40%

  // Status language shared by all three screens
  static const Color brandSuccess = Color(0xFF12B76A);
  static const Color brandSuccessSoft = Color(0xFFE7F9F1);
  static const Color brandWarning = Color(0xFFF79009);
  static const Color brandWarningSoft = Color(0xFFFEF3E2);
  static const Color brandDanger = Color(0xFFF04438);
  static const Color brandDangerSoft = Color(0xFFFEECEB);
  static const Color brandInfo = Color(0xFF3B82F6);
  static const Color brandInfoSoft = Color(0xFFEAF1FE);
}

/// Shared spacing / radius / elevation scale for the Home, Scan and
/// Authentication screens so all three read as one design system.
class AppMetrics {
  AppMetrics._();

  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 20;
  static const double radiusXl = 26;
  static const double radiusPill = 999;

  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 20;
  static const double space2xl = 28;

  static const List<BoxShadow> shadowSm = [
    BoxShadow(color: Color(0x0A0B1120), blurRadius: 8, offset: Offset(0, 2)),
  ];

  static const List<BoxShadow> shadowMd = [
    BoxShadow(color: Color(0x140B1120), blurRadius: 20, offset: Offset(0, 8)),
  ];
}
