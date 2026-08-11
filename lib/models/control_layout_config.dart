import 'dart:convert';

import 'package:flutter/material.dart' show Color, FontWeight;

import 'package:rev_crane_control_ops/models/app_enums.dart'
    show LayoutBucket, PlcType;
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/models/grid_layout_option.dart';
import 'package:rev_crane_control_ops/models/horn_config.dart';
import 'package:rev_crane_control_ops/models/legacy_layout_migration.dart';
import 'package:rev_crane_control_ops/models/plc_condition_config.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';

/// Fresh layouts sound the AppBar buzzer when any non-E-STOP digital status
/// reported by the PLC is active. DF1 keeps its dedicated safety indication.
const HornConfig kDefaultAppBarBuzzerConfig = HornConfig(
  trigger: PlcConditionConfig(
    watchedFields: <PlcOutputVariant>{
      PlcOutputVariant.df2,
      PlcOutputVariant.df3,
      PlcOutputVariant.df4,
      PlcOutputVariant.df5,
      PlcOutputVariant.df6,
      PlcOutputVariant.df7,
      PlcOutputVariant.df8,
      PlcOutputVariant.df9,
      PlcOutputVariant.df10,
    },
  ),
  hapticFeedback: false,
);

// ─────────────────────────────────────────────────────────────────────────────
// ControlWidgetType
// ─────────────────────────────────────────────────────────────────────────────

enum ControlWidgetType { sliderButton, pushButton, toggle, joystick, rotary }

// ─────────────────────────────────────────────────────────────────────────────
// ControlWidgetSizeConfig
// ─────────────────────────────────────────────────────────────────────────────

/// E-Stop-only sizing. Per-axis motion-control sizing lives on
/// [AxisControlConfig.heightScale] instead — there's only ever one E-Stop
/// button, so no per-axis concept applies to it.
class ControlWidgetSizeConfig {
  const ControlWidgetSizeConfig({
    this.estopButtonHeightScale = 1.0,
    this.estopButtonWidthScale = 1.0,
  });

  static const double minHeightScale = 0.7;
  static const double maxHeightScale = 1.5;

  /// Same bounds as height — width is a relative multiplier of
  /// [baseEstopButtonWidth], with no independent concept of its own.
  static const double minWidthScale = 0.7;
  static const double maxWidthScale = 1.5;

  /// Base height for the E-Stop swipe button.
  static const double baseEstopButtonHeight = 74.0;

  /// Base width for the E-Stop button, used only while [estopButtonWidthScale]
  /// differs from 1.0 — at the default scale the button still stretches to
  /// fill its parent (see SafetyActionPanel), matching prior behavior.
  static const double baseEstopButtonWidth = 320.0;

  /// Industrial HMI minimum touch target (per IEC 62264 / Material guidance).
  static const double minTouchTargetPx = 48.0;

  final double estopButtonHeightScale;
  final double estopButtonWidthScale;

  double get resolvedEstopHeight =>
      baseEstopButtonHeight * estopButtonHeightScale;

  double get resolvedEstopWidth => baseEstopButtonWidth * estopButtonWidthScale;

  /// `null` at the default width scale (1.0) — callers should fall back to
  /// filling the available panel width, matching pre-customization behavior.
  /// Otherwise the operator-configured absolute width, capped by the panel
  /// at render time so it never overflows on a narrow screen.
  double? get resolvedEstopWidthOrFill =>
      estopButtonWidthScale == 1.0 ? null : resolvedEstopWidth;

  ControlWidgetSizeConfig copyWith({
    double? estopButtonHeightScale,
    double? estopButtonWidthScale,
  }) {
    return ControlWidgetSizeConfig(
      estopButtonHeightScale:
          estopButtonHeightScale ?? this.estopButtonHeightScale,
      estopButtonWidthScale:
          estopButtonWidthScale ?? this.estopButtonWidthScale,
    );
  }

  Map<String, dynamic> toJson() => {
    'estopButtonHeightScale': estopButtonHeightScale,
    'estopButtonWidthScale': estopButtonWidthScale,
  };

  factory ControlWidgetSizeConfig.fromJson(Map<String, dynamic> json) {
    return ControlWidgetSizeConfig(
      estopButtonHeightScale:
          (json['estopButtonHeightScale'] as num?)?.toDouble() ?? 1.0,
      estopButtonWidthScale:
          (json['estopButtonWidthScale'] as num?)?.toDouble() ?? 1.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ControlWidgetSizeConfig &&
          other.estopButtonHeightScale == estopButtonHeightScale &&
          other.estopButtonWidthScale == estopButtonWidthScale;

  @override
  int get hashCode =>
      Object.hash(estopButtonHeightScale, estopButtonWidthScale);
}

// ─────────────────────────────────────────────────────────────────────────────
// AxisControlConfig
//
// LEGACY JSON SHAPE ONLY (see AxisConfigSet doc comment) — control type,
// spring/latch wiring, and height scale for one of the three legacy axis
// slots. Read via fromJson for backward-compat with pre-v3 saved layouts.
// ─────────────────────────────────────────────────────────────────────────────

class AxisControlConfig {
  const AxisControlConfig({
    this.widgetType = ControlWidgetType.sliderButton,
    this.wiringConfig = PushButtonWiringConfig.offMomentary,
    this.heightScale = 1.0,
  });

  /// Base (unscaled) height for a push/toggle button row, or a slider pair.
  static const double baseHeight = 185.0;

  static const double minHeightScale = 0.7;
  static const double maxHeightScale = 1.5;

  /// Industrial HMI minimum touch target (per IEC 62264 / Material guidance).
  static const double minTouchTargetPx = 48.0;

  final ControlWidgetType widgetType;

  /// Consulted only when [widgetType] is pushButton or toggle.
  final PushButtonWiringConfig wiringConfig;

  final double heightScale;

  double get resolvedHeight => baseHeight * heightScale;

  AxisControlConfig copyWith({
    ControlWidgetType? widgetType,
    PushButtonWiringConfig? wiringConfig,
    double? heightScale,
  }) {
    return AxisControlConfig(
      widgetType: widgetType ?? this.widgetType,
      wiringConfig: wiringConfig ?? this.wiringConfig,
      heightScale: heightScale ?? this.heightScale,
    );
  }

  Map<String, dynamic> toJson() => {
    'widgetType': widgetType.name,
    'wiringConfig': wiringConfig.name,
    'heightScale': heightScale,
  };

  factory AxisControlConfig.fromJson(Map<String, dynamic> json) {
    return AxisControlConfig(
      widgetType: ControlWidgetType.values.firstWhere(
        (e) => e.name == json['widgetType'],
        orElse: () => ControlWidgetType.sliderButton,
      ),
      wiringConfig: PushButtonWiringConfig.values.firstWhere(
        (e) => e.name == json['wiringConfig'],
        orElse: () => PushButtonWiringConfig.offMomentary,
      ),
      heightScale: (json['heightScale'] as num?)?.toDouble() ?? 1.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AxisControlConfig &&
          other.widgetType == widgetType &&
          other.wiringConfig == wiringConfig &&
          other.heightScale == heightScale;

  @override
  int get hashCode => Object.hash(widgetType, wiringConfig, heightScale);
}

// ─────────────────────────────────────────────────────────────────────────────
// AxisConfigSet
// ─────────────────────────────────────────────────────────────────────────────

/// LEGACY JSON SHAPE ONLY. Read via [fromJson] for backward-compat with
/// pre-v3 saved layouts (JSON keys 'hoist'/'traverse'/'travel'); never
/// written by new code, never consulted by any live command/rendering path
/// — see legacy_layout_migration.dart, the only consumer.
class AxisConfigSet {
  const AxisConfigSet({
    this.primary = const AxisControlConfig(),
    this.secondary = const AxisControlConfig(),
    this.tertiary = const AxisControlConfig(),
  });

  final AxisControlConfig primary;
  final AxisControlConfig secondary;
  final AxisControlConfig tertiary;

  AxisConfigSet copyWith({
    AxisControlConfig? primary,
    AxisControlConfig? secondary,
    AxisControlConfig? tertiary,
  }) {
    return AxisConfigSet(
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      tertiary: tertiary ?? this.tertiary,
    );
  }

  Map<String, dynamic> toJson() => {
    'hoist': primary.toJson(),
    'traverse': secondary.toJson(),
    'travel': tertiary.toJson(),
  };

  factory AxisConfigSet.fromJson(Map<String, dynamic> json) {
    return AxisConfigSet(
      primary: json['hoist'] != null
          ? AxisControlConfig.fromJson(json['hoist'] as Map<String, dynamic>)
          : const AxisControlConfig(),
      secondary: json['traverse'] != null
          ? AxisControlConfig.fromJson(json['traverse'] as Map<String, dynamic>)
          : const AxisControlConfig(),
      tertiary: json['travel'] != null
          ? AxisControlConfig.fromJson(json['travel'] as Map<String, dynamic>)
          : const AxisControlConfig(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AxisConfigSet &&
          other.primary == primary &&
          other.secondary == secondary &&
          other.tertiary == tertiary;

  @override
  int get hashCode => Object.hash(primary, secondary, tertiary);
}

// ─────────────────────────────────────────────────────────────────────────────
// ButtonStyleConfig
//
// Cosmetic overrides for a single button. All fields are nullable — null
// means "use the role's theme default," resolved at render time so future
// theme changes still propagate to buttons that haven't been customized.
// ─────────────────────────────────────────────────────────────────────────────

class ButtonStyleConfig {
  const ButtonStyleConfig({
    this.primaryColor,
    this.activeColor,
    this.cornerRadius,
    this.elevation,
    this.iconSize,
    this.labelFontSize,
    this.labelFontWeight,
    this.showLabel = true,
  });

  static const double minCornerRadius = 0.0;
  static const double maxCornerRadius = 32.0;
  static const double minElevation = 0.0;
  static const double maxElevation = 12.0;
  static const double minIconSize = 16.0;
  static const double maxIconSize = 96.0;
  static const double minLabelFontSize = 8.0;
  static const double maxLabelFontSize = 28.0;

  final Color? primaryColor;
  final Color? activeColor;
  final double? cornerRadius;
  final double? elevation;
  final double? iconSize;
  final double? labelFontSize;
  final FontWeight? labelFontWeight;
  final bool showLabel;

  Color resolvePrimary(Color fallback) => primaryColor ?? fallback;
  Color resolveActive(Color fallback) => activeColor ?? fallback;

  ButtonStyleConfig copyWith({
    Color? primaryColor,
    Color? activeColor,
    double? cornerRadius,
    double? elevation,
    double? iconSize,
    double? labelFontSize,
    FontWeight? labelFontWeight,
    bool? showLabel,
    bool clearPrimaryColor = false,
    bool clearActiveColor = false,
  }) {
    return ButtonStyleConfig(
      primaryColor: clearPrimaryColor
          ? null
          : (primaryColor ?? this.primaryColor),
      activeColor: clearActiveColor ? null : (activeColor ?? this.activeColor),
      cornerRadius: cornerRadius ?? this.cornerRadius,
      elevation: elevation ?? this.elevation,
      iconSize: iconSize ?? this.iconSize,
      labelFontSize: labelFontSize ?? this.labelFontSize,
      labelFontWeight: labelFontWeight ?? this.labelFontWeight,
      showLabel: showLabel ?? this.showLabel,
    );
  }

  Map<String, dynamic> toJson() => {
    'primaryColor': primaryColor?.toARGB32(),
    'activeColor': activeColor?.toARGB32(),
    'cornerRadius': cornerRadius,
    'elevation': elevation,
    'iconSize': iconSize,
    'labelFontSize': labelFontSize,
    'labelFontWeight': labelFontWeight?.value,
    'showLabel': showLabel,
  };

  factory ButtonStyleConfig.fromJson(Map<String, dynamic> json) {
    final primary = json['primaryColor'] as num?;
    final active = json['activeColor'] as num?;
    final weightValue = json['labelFontWeight'] as num?;
    return ButtonStyleConfig(
      primaryColor: primary != null ? Color(primary.toInt()) : null,
      activeColor: active != null ? Color(active.toInt()) : null,
      cornerRadius: (json['cornerRadius'] as num?)?.toDouble(),
      elevation: (json['elevation'] as num?)?.toDouble(),
      iconSize: (json['iconSize'] as num?)?.toDouble(),
      labelFontSize: (json['labelFontSize'] as num?)?.toDouble(),
      labelFontWeight: weightValue != null
          ? FontWeight.values.firstWhere(
              (w) => w.value == weightValue.toInt(),
              orElse: () => FontWeight.w900,
            )
          : null,
      showLabel: json['showLabel'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ButtonStyleConfig &&
          other.primaryColor == primaryColor &&
          other.activeColor == activeColor &&
          other.cornerRadius == cornerRadius &&
          other.elevation == elevation &&
          other.iconSize == iconSize &&
          other.labelFontSize == labelFontSize &&
          other.labelFontWeight == labelFontWeight &&
          other.showLabel == showLabel;

  @override
  int get hashCode => Object.hash(
    primaryColor,
    activeColor,
    cornerRadius,
    elevation,
    iconSize,
    labelFontSize,
    labelFontWeight,
    showLabel,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// RoleStyleConfig
//
// LEGACY JSON SHAPE ONLY. Named fields for the six legacy motion-slot styles
// plus Reset E-STOP. Read via [fromJson] for backward-compat with pre-v3
// saved layouts; never written by new code, never consulted by any live
// command/rendering path — see legacy_layout_migration.dart, the only
// consumer. There is deliberately no `estop` field — E-STOP's appearance was
// never customizable, migrated or otherwise.
// ─────────────────────────────────────────────────────────────────────────────

class RoleStyleConfig {
  const RoleStyleConfig({
    this.slot1 = const ButtonStyleConfig(),
    this.slot2 = const ButtonStyleConfig(),
    this.slot3 = const ButtonStyleConfig(),
    this.slot4 = const ButtonStyleConfig(),
    this.slot5 = const ButtonStyleConfig(),
    this.slot6 = const ButtonStyleConfig(),
    this.resetEstop = const ButtonStyleConfig(),
  });

  final ButtonStyleConfig slot1;
  final ButtonStyleConfig slot2;
  final ButtonStyleConfig slot3;
  final ButtonStyleConfig slot4;
  final ButtonStyleConfig slot5;
  final ButtonStyleConfig slot6;
  final ButtonStyleConfig resetEstop;

  RoleStyleConfig copyWith({
    ButtonStyleConfig? slot1,
    ButtonStyleConfig? slot2,
    ButtonStyleConfig? slot3,
    ButtonStyleConfig? slot4,
    ButtonStyleConfig? slot5,
    ButtonStyleConfig? slot6,
    ButtonStyleConfig? resetEstop,
  }) {
    return RoleStyleConfig(
      slot1: slot1 ?? this.slot1,
      slot2: slot2 ?? this.slot2,
      slot3: slot3 ?? this.slot3,
      slot4: slot4 ?? this.slot4,
      slot5: slot5 ?? this.slot5,
      slot6: slot6 ?? this.slot6,
      resetEstop: resetEstop ?? this.resetEstop,
    );
  }

  Map<String, dynamic> toJson() => {
    'hoistUp': slot1.toJson(),
    'hoistDown': slot2.toJson(),
    'traverseLeft': slot3.toJson(),
    'traverseRight': slot4.toJson(),
    'travelForward': slot5.toJson(),
    'travelReverse': slot6.toJson(),
    'resetEstop': resetEstop.toJson(),
  };

  factory RoleStyleConfig.fromJson(Map<String, dynamic> json) {
    ButtonStyleConfig read(String key) => json[key] != null
        ? ButtonStyleConfig.fromJson(json[key] as Map<String, dynamic>)
        : const ButtonStyleConfig();
    return RoleStyleConfig(
      slot1: read('hoistUp'),
      slot2: read('hoistDown'),
      slot3: read('traverseLeft'),
      slot4: read('traverseRight'),
      slot5: read('travelForward'),
      slot6: read('travelReverse'),
      resetEstop: read('resetEstop'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoleStyleConfig &&
          other.slot1 == slot1 &&
          other.slot2 == slot2 &&
          other.slot3 == slot3 &&
          other.slot4 == slot4 &&
          other.slot5 == slot5 &&
          other.slot6 == slot6 &&
          other.resetEstop == resetEstop;

  @override
  int get hashCode =>
      Object.hash(slot1, slot2, slot3, slot4, slot5, slot6, resetEstop);
}

// ─────────────────────────────────────────────────────────────────────────────
// ControlLabelConfig
// ─────────────────────────────────────────────────────────────────────────────

class ControlLabelConfig {
  const ControlLabelConfig({
    this.legacySlot1Label = 'UP',
    this.legacySlot2Label = 'DOWN',
    this.legacySlot3Label = 'LEFT',
    this.legacySlot4Label = 'RIGHT',
    this.legacySlot5Label = 'FWD',
    this.legacySlot6Label = 'REV',
    this.estopSwipeInstruction = 'SWIPE TO EMERGENCY STOP',
    this.resetEstopLabel = 'RESET E-STOP',
    this.screenTitle = '',
  });

  static const int maxLabelLength = 18;
  static const int minLabelLength = 1;

  /// Higher limit for free-form instruction text (E-Stop swipe prompt,
  /// screen title) where a full short sentence is expected.
  static const int maxInstructionLength = 40;

  /// LEGACY JSON SHAPE ONLY — see legacy_layout_migration.dart, the only
  /// consumer. Not read by any live rendering path.
  final String legacySlot1Label;
  final String legacySlot2Label;
  final String legacySlot3Label;
  final String legacySlot4Label;
  final String legacySlot5Label;
  final String legacySlot6Label;

  /// Live — read directly by the control screens' safety panel.
  final String estopSwipeInstruction;

  /// Live — read directly by the control screens' safety panel.
  final String resetEstopLabel;

  /// Live — read directly by the control screens' AppBar title.
  final String screenTitle;

  ControlLabelConfig copyWith({
    String? legacySlot1Label,
    String? legacySlot2Label,
    String? legacySlot3Label,
    String? legacySlot4Label,
    String? legacySlot5Label,
    String? legacySlot6Label,
    String? estopSwipeInstruction,
    String? resetEstopLabel,
    String? screenTitle,
  }) {
    return ControlLabelConfig(
      legacySlot1Label: legacySlot1Label ?? this.legacySlot1Label,
      legacySlot2Label: legacySlot2Label ?? this.legacySlot2Label,
      legacySlot3Label: legacySlot3Label ?? this.legacySlot3Label,
      legacySlot4Label: legacySlot4Label ?? this.legacySlot4Label,
      legacySlot5Label: legacySlot5Label ?? this.legacySlot5Label,
      legacySlot6Label: legacySlot6Label ?? this.legacySlot6Label,
      estopSwipeInstruction:
          estopSwipeInstruction ?? this.estopSwipeInstruction,
      resetEstopLabel: resetEstopLabel ?? this.resetEstopLabel,
      screenTitle: screenTitle ?? this.screenTitle,
    );
  }

  Map<String, dynamic> toJson() => {
    'upLabel': legacySlot1Label,
    'downLabel': legacySlot2Label,
    'leftLabel': legacySlot3Label,
    'rightLabel': legacySlot4Label,
    'forwardLabel': legacySlot5Label,
    'reverseLabel': legacySlot6Label,
    'estopSwipeInstruction': estopSwipeInstruction,
    'resetEstopLabel': resetEstopLabel,
    'screenTitle': screenTitle,
  };

  factory ControlLabelConfig.fromJson(Map<String, dynamic> json) {
    return ControlLabelConfig(
      legacySlot1Label: json['upLabel'] as String? ?? 'UP',
      legacySlot2Label: json['downLabel'] as String? ?? 'DOWN',
      legacySlot3Label: json['leftLabel'] as String? ?? 'LEFT',
      legacySlot4Label: json['rightLabel'] as String? ?? 'RIGHT',
      legacySlot5Label: json['forwardLabel'] as String? ?? 'FWD',
      legacySlot6Label: json['reverseLabel'] as String? ?? 'REV',
      estopSwipeInstruction:
          json['estopSwipeInstruction'] as String? ?? 'SWIPE TO EMERGENCY STOP',
      resetEstopLabel: json['resetEstopLabel'] as String? ?? 'RESET E-STOP',
      screenTitle: json['screenTitle'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ControlLabelConfig &&
          other.legacySlot1Label == legacySlot1Label &&
          other.legacySlot2Label == legacySlot2Label &&
          other.legacySlot3Label == legacySlot3Label &&
          other.legacySlot4Label == legacySlot4Label &&
          other.legacySlot5Label == legacySlot5Label &&
          other.legacySlot6Label == legacySlot6Label &&
          other.estopSwipeInstruction == estopSwipeInstruction &&
          other.resetEstopLabel == resetEstopLabel &&
          other.screenTitle == screenTitle;

  @override
  int get hashCode => Object.hash(
    legacySlot1Label,
    legacySlot2Label,
    legacySlot3Label,
    legacySlot4Label,
    legacySlot5Label,
    legacySlot6Label,
    estopSwipeInstruction,
    resetEstopLabel,
    screenTitle,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ControlArrangementConfig
// ─────────────────────────────────────────────────────────────────────────────

class ControlArrangementConfig {
  const ControlArrangementConfig({
    this.showSensorRow = true,
    this.showLiveLEDs = true,
    this.showConnectionSubtitle = true,
  });

  final bool showSensorRow;

  final bool showLiveLEDs;

  /// The small "● Connected" subtitle under the AppBar title. The only
  /// chrome element that has no on-screen tile to attach a delete badge to,
  /// so it's toggled from the customization overflow menu instead.
  final bool showConnectionSubtitle;

  ControlArrangementConfig copyWith({
    bool? showSensorRow,
    bool? showLiveLEDs,
    bool? showConnectionSubtitle,
  }) {
    return ControlArrangementConfig(
      showSensorRow: showSensorRow ?? this.showSensorRow,
      showLiveLEDs: showLiveLEDs ?? this.showLiveLEDs,
      showConnectionSubtitle:
          showConnectionSubtitle ?? this.showConnectionSubtitle,
    );
  }

  Map<String, dynamic> toJson() => {
    'showSensorRow': showSensorRow,
    'showLiveLEDs': showLiveLEDs,
    'showConnectionSubtitle': showConnectionSubtitle,
  };

  factory ControlArrangementConfig.fromJson(Map<String, dynamic> json) {
    return ControlArrangementConfig(
      showSensorRow: json['showSensorRow'] as bool? ?? true,
      showLiveLEDs: json['showLiveLEDs'] as bool? ?? true,
      showConnectionSubtitle: json['showConnectionSubtitle'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ControlArrangementConfig &&
          other.showSensorRow == showSensorRow &&
          other.showLiveLEDs == showLiveLEDs &&
          other.showConnectionSubtitle == showConnectionSubtitle;

  @override
  int get hashCode =>
      Object.hash(showSensorRow, showLiveLEDs, showConnectionSubtitle);
}

// ─────────────────────────────────────────────────────────────────────────────
// ControlLayoutConfig  (top-level)
// ─────────────────────────────────────────────────────────────────────────────

class ControlLayoutConfig {
  const ControlLayoutConfig({
    this.sizeConfig = const ControlWidgetSizeConfig(),
    this.labelConfig = const ControlLabelConfig(),
    this.arrangementConfig = const ControlArrangementConfig(),
    this.appBarBuzzerConfig = kDefaultAppBarBuzzerConfig,
    this.axisConfigs = const AxisConfigSet(),
    this.roleStyles = const RoleStyleConfig(),
    this.buttons = const <String, ButtonConfig>{},
    this.controlPageCount = 1,
    this.gridLayout = GridLayoutOption.fallback,
    bool buttonsAreAuthoritative = false,
  }) : _buttonsAreAuthoritative = buttonsAreAuthoritative;

  /// Schema version. Bumped 2 → 3 by the button-centric refactor: adds the
  /// `buttons` map AND, for the first time, this field is actually written
  /// into the JSON itself (previously only tracked as an in-code marker for
  /// the SharedPreferences key name — see AppConstants.prefsKeyLayoutConfig,
  /// which stays unchanged so existing saved layouts keep loading). Future
  /// schema changes should prefer bumping this in-JSON field over renaming
  /// the prefs key, which would silently discard existing user layouts.
  ///
  /// Bumped 5 → 6 by the generic PLC-output-variant refactor: each
  /// ButtonConfig gains a `stateMappings` field (button-state -> PLC output
  /// variant list), replacing the old single `PlcOutputVariant`-plus-ControlRole/
  /// AxisKind-derivation composition path. Old JSON without `stateMappings`
  /// is migrated on load via ButtonConfig.fromJson, which falls back to
  /// ButtonConfig.migratedStateMappingsFor — reproducing the OLD derivation
  /// exactly as static data — whenever the `stateMappings` key is absent.
  /// Bumped 6 -> 7 by the potentiometer control addition: ButtonType gains
  /// `potentiometer`, with analog range/output metadata stored in
  /// ButtonConfig.customProperties.
  ///
  /// Bumped 7 -> 8 by true button deletion: a present `buttons` map is now
  /// authoritative. Missing entries are deleted controls, not legacy defaults
  /// to synthesize back in.
  ///
  /// Bumped 8 -> 9 by the configurable grid layout feature: adds
  /// `gridLayout` (see [GridLayoutOption]), replacing the previously fixed
  /// 2-column x 3-row page grid. Old JSON without a `gridLayout` key falls
  /// back to [GridLayoutOption.fallback] (`twoByThree`) via [fromJson],
  /// which reproduces the pre-existing fixed grid exactly — no other
  /// migration is needed.
  /// Bumped 9 -> 10 by the configurable AppBar PLC-status buzzer.
  static const int schemaVersion = 10;

  final ControlWidgetSizeConfig sizeConfig;
  final ControlLabelConfig labelConfig;
  final ControlArrangementConfig arrangementConfig;
  final HornConfig appBarBuzzerConfig;

  /// Per-axis control type, spring/latch wiring, and height scale.
  /// LEGACY (v2 shape) — kept permanently as the migration source for old
  /// saved JSON; no longer the live source of truth once the button-centric
  /// screens/edit sheet are fully switched over (see [buttons]).
  final AxisConfigSet axisConfigs;

  /// Per-role cosmetic overrides (color, corner radius, icon size, ...).
  /// LEGACY (v2 shape) — see [axisConfigs] doc comment.
  final RoleStyleConfig roleStyles;

  /// Button-centric configs, keyed by [ButtonConfig.id]. Populated either
  /// explicitly (new-format JSON) or synthesized from
  /// [axisConfigs]/[roleStyles]/[labelConfig] on load when absent (old-format
  /// JSON) — see [fromJson].
  final Map<String, ButtonConfig> buttons;
  final bool _buttonsAreAuthoritative;

  /// User-requested minimum number of horizontal control pages. Extra pages
  /// are also rendered automatically when buttons occupy higher page indexes.
  final int controlPageCount;

  /// The active button-grid shape (columns x rows) for this layout's page
  /// grid — operator-selectable via the Customization Toolbar's Layout tool
  /// (see GridLayoutToolbar / LayoutEditController.applyGridLayout).
  final GridLayoutOption gridLayout;

  /// Effective button map. The bare `const ControlLayoutConfig()` constructor
  /// still resolves to synthesized legacy defaults so tests and fallback
  /// callers have a useful layout. Once [buttons] is present, the map is
  /// treated as authoritative: missing ids are intentionally deleted controls.
  Map<String, ButtonConfig> get resolvedButtons =>
      _buttonsAreAuthoritative || buttons.isNotEmpty
      ? buttons
      : synthesizeLegacyButtons(
          axisConfigs: axisConfigs,
          roleStyles: roleStyles,
          labelConfig: labelConfig,
        );

  ButtonConfig? buttonFor(ControlRole role) => resolvedButtons[role.name];

  /// Every PLC output channel some control in this layout can actually drive.
  ///
  /// Derived from the authoritative composition source — each button's
  /// [ButtonConfig.stateMappings] plus, for joysticks, every virtual
  /// sub-button table in [ButtonConfig.joystickSubButtonMappings]. A channel
  /// absent from this set is UNMAPPED: no gesture anywhere in the layout can
  /// command it, which is why output indicators draw it as a dashed grey ring
  /// rather than as a permanently-off output.
  ///
  /// DF1 is always present. It is the controller-owned E-STOP channel and is
  /// deliberately never allowed into a stateMappings entry (see
  /// `ButtonStateOutputMapping.isValid`), so deriving it would report the
  /// safety channel as unmapped on every layout.
  ///
  /// Deliberately ignores [ButtonConfig.plcMappingEnabled] and `visible` /
  /// `enabled`: those are cosmetic/gating flags, and a channel a hidden or
  /// momentarily-disabled control owns is still a mapped channel, not a
  /// spare one.
  Set<PlcOutputVariant> get mappedOutputVariants {
    final mapped = <PlcOutputVariant>{PlcOutputVariant.df1};
    for (final button in resolvedButtons.values) {
      for (final mapping in button.stateMappings.values) {
        mapped.addAll(mapping.activeVariants);
      }
      for (final subTable in button.joystickSubButtonMappings.values) {
        for (final mapping in subTable.values) {
          mapped.addAll(mapping.activeVariants);
        }
      }
    }
    return mapped;
  }

  ControlLayoutConfig withButton(String id, ButtonConfig config) =>
      copyWith(buttons: {...resolvedButtons, id: config});

  ControlLayoutConfig copyWith({
    ControlWidgetSizeConfig? sizeConfig,
    ControlLabelConfig? labelConfig,
    ControlArrangementConfig? arrangementConfig,
    HornConfig? appBarBuzzerConfig,
    AxisConfigSet? axisConfigs,
    RoleStyleConfig? roleStyles,
    Map<String, ButtonConfig>? buttons,
    int? controlPageCount,
    GridLayoutOption? gridLayout,
  }) {
    return ControlLayoutConfig(
      sizeConfig: sizeConfig ?? this.sizeConfig,
      labelConfig: labelConfig ?? this.labelConfig,
      arrangementConfig: arrangementConfig ?? this.arrangementConfig,
      appBarBuzzerConfig: appBarBuzzerConfig ?? this.appBarBuzzerConfig,
      axisConfigs: axisConfigs ?? this.axisConfigs,
      roleStyles: roleStyles ?? this.roleStyles,
      buttons: buttons ?? this.buttons,
      controlPageCount: controlPageCount ?? this.controlPageCount,
      gridLayout: gridLayout ?? this.gridLayout,
      buttonsAreAuthoritative: buttons != null
          ? true
          : _buttonsAreAuthoritative,
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'sizeConfig': sizeConfig.toJson(),
    'labelConfig': labelConfig.toJson(),
    'arrangementConfig': arrangementConfig.toJson(),
    'appBarBuzzerConfig': appBarBuzzerConfig.toJson(),
    'axisConfigs': axisConfigs.toJson(),
    'roleStyles': roleStyles.toJson(),
    'buttons': resolvedButtons.map((id, cfg) => MapEntry(id, cfg.toJson())),
    'controlPageCount': controlPageCount,
    'gridLayout': gridLayout.name,
  };

  /// Synthesizes the button-centric `buttons` map from the legacy per-axis/
  /// per-role/per-label fields — delegates to legacy_layout_migration.dart,
  /// the sole owner of that derivation. Pure and idempotent — invoked by
  /// [fromJson] whenever old-format JSON (no `buttons` key) is parsed, so old
  /// saved layouts silently upgrade in memory on load with zero user action,
  /// and get persisted in the new format on the very next save.
  static Map<String, ButtonConfig> buttonsFromLegacy({
    AxisConfigSet axisConfigs = const AxisConfigSet(),
    RoleStyleConfig roleStyles = const RoleStyleConfig(),
    ControlLabelConfig labelConfig = const ControlLabelConfig(),
  }) => synthesizeLegacyButtons(
    axisConfigs: axisConfigs,
    roleStyles: roleStyles,
    labelConfig: labelConfig,
  );

  /// Fresh-install default for [bucket]: just the two safety controls
  /// (E-STOP, Reset E-STOP) — no synthetic motion buttons. An existing
  /// install's saved layout still loads/migrates via [fromJson] regardless;
  /// this only affects what a brand-new install starts with.
  factory ControlLayoutConfig.defaultForBucket(LayoutBucket bucket) {
    return switch (bucket) {
      LayoutBucket.plc14 => ControlLayoutConfig.defaultForPlcType(
        PlcType.plc14,
      ),
      LayoutBucket.plc21 => ControlLayoutConfig.defaultForPlcType(
        PlcType.plc21,
      ),
      LayoutBucket.plc38 => ControlLayoutConfig.defaultForPlcType(
        PlcType.plc38,
      ),
    };
  }

  factory ControlLayoutConfig.defaultForPlcType(PlcType plcType) {
    return ControlLayoutConfig(
      buttons: {
        ControlRole.estop.name: ButtonConfig.estopDefault(),
        ControlRole.resetEstop.name: ButtonConfig.resetEstopDefault(
          const ControlLabelConfig().resetEstopLabel,
        ),
      },
    );
  }

  factory ControlLayoutConfig.fromJson(Map<String, dynamic> json) {
    final axisConfigs = json['axisConfigs'] != null
        ? AxisConfigSet.fromJson(json['axisConfigs'] as Map<String, dynamic>)
        : const AxisConfigSet();
    final roleStyles = json['roleStyles'] != null
        ? RoleStyleConfig.fromJson(json['roleStyles'] as Map<String, dynamic>)
        : const RoleStyleConfig();
    final labelConfig = json['labelConfig'] != null
        ? ControlLabelConfig.fromJson(
            json['labelConfig'] as Map<String, dynamic>,
          )
        : const ControlLabelConfig();

    // No `buttons` key => pre-v3 JSON (schemaVersion was never itself
    // serialized before this refactor, so v1 and v2 are indistinguishable
    // and handled identically here). Silently upgrade in memory; this gets
    // persisted in the new format on the very next save.
    final legacyButtons = synthesizeLegacyButtons(
      axisConfigs: axisConfigs,
      roleStyles: roleStyles,
      labelConfig: labelConfig,
    );
    final schema = _parseSchemaVersion(json['schemaVersion']);
    final hasButtons = json['buttons'] != null;
    final buttons = hasButtons
        ? _buttonsFromJson(
            json['buttons'],
            legacyButtons: legacyButtons,
            completeFromLegacy: schema < 8,
          )
        : legacyButtons;

    return ControlLayoutConfig(
      sizeConfig: json['sizeConfig'] != null
          ? ControlWidgetSizeConfig.fromJson(
              json['sizeConfig'] as Map<String, dynamic>,
            )
          : const ControlWidgetSizeConfig(),
      labelConfig: labelConfig,
      arrangementConfig: json['arrangementConfig'] != null
          ? ControlArrangementConfig.fromJson(
              json['arrangementConfig'] as Map<String, dynamic>,
            )
          : const ControlArrangementConfig(),
      appBarBuzzerConfig: _appBarBuzzerConfigFromJson(
        json['appBarBuzzerConfig'],
      ),
      axisConfigs: axisConfigs,
      roleStyles: roleStyles,
      buttons: buttons,
      controlPageCount: _parsePositiveInt(json['controlPageCount']),
      gridLayout: GridLayoutOption.fromName(json['gridLayout'] as String?),
      buttonsAreAuthoritative: hasButtons && schema >= 8,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory ControlLayoutConfig.fromJsonString(String source) {
    try {
      return ControlLayoutConfig.fromJson(
        jsonDecode(source) as Map<String, dynamic>,
      );
    } catch (_) {
      return const ControlLayoutConfig();
    }
  }

  static bool _buttonsEqual(
    Map<String, ButtonConfig> a,
    Map<String, ButtonConfig> b,
  ) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ControlLayoutConfig &&
          other.sizeConfig == sizeConfig &&
          other.labelConfig == labelConfig &&
          other.arrangementConfig == arrangementConfig &&
          other.appBarBuzzerConfig == appBarBuzzerConfig &&
          other.axisConfigs == axisConfigs &&
          other.roleStyles == roleStyles &&
          _buttonsEqual(other.resolvedButtons, resolvedButtons) &&
          other.controlPageCount == controlPageCount &&
          other.gridLayout == gridLayout;

  @override
  int get hashCode => Object.hash(
    sizeConfig,
    labelConfig,
    arrangementConfig,
    appBarBuzzerConfig,
    axisConfigs,
    roleStyles,
    Object.hashAllUnordered(
      resolvedButtons.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    controlPageCount,
    gridLayout,
  );
}

HornConfig _appBarBuzzerConfigFromJson(dynamic value) {
  try {
    if (value is Map<String, dynamic>) return HornConfig.fromJson(value);
    if (value is Map) {
      return HornConfig.fromJson(value.cast<String, dynamic>());
    }
  } catch (_) {}
  return kDefaultAppBarBuzzerConfig;
}

int _parsePositiveInt(dynamic value, {int fallback = 1}) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  if (parsed == null || parsed < 1) return fallback;
  return parsed;
}

int _parseSchemaVersion(dynamic value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  return parsed ?? 0;
}

Map<String, ButtonConfig> _buttonsFromJson(
  dynamic raw, {
  required Map<String, ButtonConfig> legacyButtons,
  required bool completeFromLegacy,
}) {
  final parsed = (raw as Map<String, dynamic>).map(
    (id, v) => MapEntry(id, ButtonConfig.fromJson(v as Map<String, dynamic>)),
  );
  if (!completeFromLegacy) return parsed;
  return {...legacyButtons, ...parsed};
}

// ─────────────────────────────────────────────────────────────────────────────
// PushButtonWiringConfig
//
// Industrial electrical wiring terminology for the toggle switch mechanism.
// Maps directly to the five standard 2-position / 3-position switch schemas
// used in industrial HMI panel design.
// ─────────────────────────────────────────────────────────────────────────────

enum PushButtonWiringConfig {
  // ── Two-position (push button + toggle) ──────────────────────────────────
  offMomentary, // O-T  spring-return one side
  offLatched, // O-R  latching one side
  // ── Three-position (toggle switch only) ──────────────────────────────────
  springReturnBoth, // R-O-R  neutral center, both sides spring-return
  latchingBoth, // T-O-T  neutral center, both sides latch
  mixedLeftLatchRightSpring, // T-O-R  left latches, right spring-returns
}

// ─────────────────────────────────────────────────────────────────────────────
// PushButtonWiringConfig helpers
// ─────────────────────────────────────────────────────────────────────────────

extension PushButtonWiringConfigInfo on PushButtonWiringConfig {
  String get label => switch (this) {
    PushButtonWiringConfig.offMomentary => '0-T  ·  Off → Momentary',
    PushButtonWiringConfig.offLatched => '0-R  ·  Off → Latched',
    PushButtonWiringConfig.springReturnBoth => 'R-O-R  ·  Spring Return Both',
    PushButtonWiringConfig.latchingBoth => 'T-O-T  ·  Latching Both Sides',
    PushButtonWiringConfig.mixedLeftLatchRightSpring =>
      'T-O-R  ·  Mixed  (Latch ← O → Spring)',
  };

  String get description => switch (this) {
    PushButtonWiringConfig.offMomentary =>
      'Hold to activate. Release to stop. Spring-returns to OFF.',
    PushButtonWiringConfig.offLatched =>
      'Tap to latch ON. Tap again to latch OFF. Maintains state after release.',
    PushButtonWiringConfig.springReturnBoth =>
      'Hold top for first direction, hold bottom for second. '
          'Both sides spring-return to neutral on release. Toggle Switch only.',
    PushButtonWiringConfig.latchingBoth =>
      'Tap top or bottom to latch that direction. '
          'Tap the active side again to return to neutral. Toggle Switch only.',
    PushButtonWiringConfig.mixedLeftLatchRightSpring =>
      'Top side latches (maintained). '
          'Bottom side is momentary (spring-returns). Toggle Switch only.',
  };

  /// Whether the UP / top side is spring-return.
  /// For three-position toggle-only modes the push-button fallback is false.
  bool get upIsSpringReturn => switch (this) {
    PushButtonWiringConfig.offMomentary => true,
    _ => false,
  };

  bool get isSpringReturn => upIsSpringReturn;

  bool get downIsSpringReturn => switch (this) {
    PushButtonWiringConfig.offMomentary => true,
    _ => false,
  };

  /// True for modes that only make visual sense on a Toggle Switch widget.
  /// The behavior tab hides these options when the button type is not toggle.
  bool get isToggleOnly => switch (this) {
    PushButtonWiringConfig.springReturnBoth ||
    PushButtonWiringConfig.latchingBoth ||
    PushButtonWiringConfig.mixedLeftLatchRightSpring => true,
    _ => false,
  };
}
