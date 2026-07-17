import 'dart:convert';

import 'package:flutter/material.dart' show Color, FontWeight;

import 'package:rev_crane_control_ops/models/app_enums.dart'
    show LayoutBucket, PlcType;
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';

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
// Per-axis control type, spring/latch wiring, and height scale — each axis
// (Hoist / Traverse / Travel) has its own independent Control Type, replacing
// the single global switch this app used before per-button editing existed.
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

class AxisConfigSet {
  const AxisConfigSet({
    this.hoist = const AxisControlConfig(),
    this.traverse = const AxisControlConfig(),
    this.travel = const AxisControlConfig(),
  });

  final AxisControlConfig hoist;
  final AxisControlConfig traverse;
  final AxisControlConfig travel;

  AxisControlConfig forAxis(AxisKind axis) => switch (axis) {
    AxisKind.hoist => hoist,
    AxisKind.traverse => traverse,
    AxisKind.travel => travel,
  };

  AxisConfigSet withAxis(AxisKind axis, AxisControlConfig config) =>
      switch (axis) {
        AxisKind.hoist => copyWith(hoist: config),
        AxisKind.traverse => copyWith(traverse: config),
        AxisKind.travel => copyWith(travel: config),
      };

  AxisConfigSet copyWith({
    AxisControlConfig? hoist,
    AxisControlConfig? traverse,
    AxisControlConfig? travel,
  }) {
    return AxisConfigSet(
      hoist: hoist ?? this.hoist,
      traverse: traverse ?? this.traverse,
      travel: travel ?? this.travel,
    );
  }

  Map<String, dynamic> toJson() => {
    'hoist': hoist.toJson(),
    'traverse': traverse.toJson(),
    'travel': travel.toJson(),
  };

  factory AxisConfigSet.fromJson(Map<String, dynamic> json) {
    return AxisConfigSet(
      hoist: json['hoist'] != null
          ? AxisControlConfig.fromJson(json['hoist'] as Map<String, dynamic>)
          : const AxisControlConfig(),
      traverse: json['traverse'] != null
          ? AxisControlConfig.fromJson(json['traverse'] as Map<String, dynamic>)
          : const AxisControlConfig(),
      travel: json['travel'] != null
          ? AxisControlConfig.fromJson(json['travel'] as Map<String, dynamic>)
          : const AxisControlConfig(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AxisConfigSet &&
          other.hoist == hoist &&
          other.traverse == traverse &&
          other.travel == travel;

  @override
  int get hashCode => Object.hash(hoist, traverse, travel);
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
// Named fields for the seven STYLEABLE roles only. There is deliberately no
// `estop` field on this class — a structural (not just validated) guarantee
// that E-Stop's appearance can never be reassigned away from its safety-red
// identity. Attempting to look up or set a style for ControlRole.estop
// throws, by design.
// ─────────────────────────────────────────────────────────────────────────────

class RoleStyleConfig {
  const RoleStyleConfig({
    this.hoistUp = const ButtonStyleConfig(),
    this.hoistDown = const ButtonStyleConfig(),
    this.traverseLeft = const ButtonStyleConfig(),
    this.traverseRight = const ButtonStyleConfig(),
    this.travelForward = const ButtonStyleConfig(),
    this.travelReverse = const ButtonStyleConfig(),
    this.resetEstop = const ButtonStyleConfig(),
  });

  final ButtonStyleConfig hoistUp;
  final ButtonStyleConfig hoistDown;
  final ButtonStyleConfig traverseLeft;
  final ButtonStyleConfig traverseRight;
  final ButtonStyleConfig travelForward;
  final ButtonStyleConfig travelReverse;
  final ButtonStyleConfig resetEstop;

  ButtonStyleConfig forRole(ControlRole role) => switch (role) {
    ControlRole.hoistUp => hoistUp,
    ControlRole.hoistDown => hoistDown,
    ControlRole.traverseLeft => traverseLeft,
    ControlRole.traverseRight => traverseRight,
    ControlRole.travelForward => travelForward,
    ControlRole.travelReverse => travelReverse,
    ControlRole.resetEstop => resetEstop,
    ControlRole.estop => throw ArgumentError(
      'E-Stop appearance is not customizable.',
    ),
  };

  RoleStyleConfig withRole(ControlRole role, ButtonStyleConfig style) =>
      switch (role) {
        ControlRole.hoistUp => copyWith(hoistUp: style),
        ControlRole.hoistDown => copyWith(hoistDown: style),
        ControlRole.traverseLeft => copyWith(traverseLeft: style),
        ControlRole.traverseRight => copyWith(traverseRight: style),
        ControlRole.travelForward => copyWith(travelForward: style),
        ControlRole.travelReverse => copyWith(travelReverse: style),
        ControlRole.resetEstop => copyWith(resetEstop: style),
        ControlRole.estop => throw ArgumentError(
          'E-Stop appearance is not customizable.',
        ),
      };

  RoleStyleConfig copyWith({
    ButtonStyleConfig? hoistUp,
    ButtonStyleConfig? hoistDown,
    ButtonStyleConfig? traverseLeft,
    ButtonStyleConfig? traverseRight,
    ButtonStyleConfig? travelForward,
    ButtonStyleConfig? travelReverse,
    ButtonStyleConfig? resetEstop,
  }) {
    return RoleStyleConfig(
      hoistUp: hoistUp ?? this.hoistUp,
      hoistDown: hoistDown ?? this.hoistDown,
      traverseLeft: traverseLeft ?? this.traverseLeft,
      traverseRight: traverseRight ?? this.traverseRight,
      travelForward: travelForward ?? this.travelForward,
      travelReverse: travelReverse ?? this.travelReverse,
      resetEstop: resetEstop ?? this.resetEstop,
    );
  }

  Map<String, dynamic> toJson() => {
    'hoistUp': hoistUp.toJson(),
    'hoistDown': hoistDown.toJson(),
    'traverseLeft': traverseLeft.toJson(),
    'traverseRight': traverseRight.toJson(),
    'travelForward': travelForward.toJson(),
    'travelReverse': travelReverse.toJson(),
    'resetEstop': resetEstop.toJson(),
  };

  factory RoleStyleConfig.fromJson(Map<String, dynamic> json) {
    ButtonStyleConfig read(String key) => json[key] != null
        ? ButtonStyleConfig.fromJson(json[key] as Map<String, dynamic>)
        : const ButtonStyleConfig();
    return RoleStyleConfig(
      hoistUp: read('hoistUp'),
      hoistDown: read('hoistDown'),
      traverseLeft: read('traverseLeft'),
      traverseRight: read('traverseRight'),
      travelForward: read('travelForward'),
      travelReverse: read('travelReverse'),
      resetEstop: read('resetEstop'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoleStyleConfig &&
          other.hoistUp == hoistUp &&
          other.hoistDown == hoistDown &&
          other.traverseLeft == traverseLeft &&
          other.traverseRight == traverseRight &&
          other.travelForward == travelForward &&
          other.travelReverse == travelReverse &&
          other.resetEstop == resetEstop;

  @override
  int get hashCode => Object.hash(
    hoistUp,
    hoistDown,
    traverseLeft,
    traverseRight,
    travelForward,
    travelReverse,
    resetEstop,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ControlLabelConfig
// ─────────────────────────────────────────────────────────────────────────────

class ControlLabelConfig {
  const ControlLabelConfig({
    this.upLabel = 'UP',
    this.downLabel = 'DOWN',
    this.leftLabel = 'LEFT',
    this.rightLabel = 'RIGHT',
    this.forwardLabel = 'FWD',
    this.reverseLabel = 'REV',
    this.estopSwipeInstruction = 'SWIPE TO EMERGENCY STOP',
    this.resetEstopLabel = 'RESET E-STOP',
    this.screenTitle = '',
  });

  static const int maxLabelLength = 18;
  static const int minLabelLength = 1;

  /// Higher limit for free-form instruction text (E-Stop swipe prompt,
  /// screen title) where a full short sentence is expected.
  static const int maxInstructionLength = 40;

  final String upLabel;
  final String downLabel;
  final String leftLabel;
  final String rightLabel;
  final String forwardLabel;
  final String reverseLabel;

  final String estopSwipeInstruction;

  final String resetEstopLabel;

  final String screenTitle;

  ControlLabelConfig copyWith({
    String? upLabel,
    String? downLabel,
    String? leftLabel,
    String? rightLabel,
    String? forwardLabel,
    String? reverseLabel,
    String? estopSwipeInstruction,
    String? resetEstopLabel,
    String? screenTitle,
  }) {
    return ControlLabelConfig(
      upLabel: upLabel ?? this.upLabel,
      downLabel: downLabel ?? this.downLabel,
      leftLabel: leftLabel ?? this.leftLabel,
      rightLabel: rightLabel ?? this.rightLabel,
      forwardLabel: forwardLabel ?? this.forwardLabel,
      reverseLabel: reverseLabel ?? this.reverseLabel,
      estopSwipeInstruction:
          estopSwipeInstruction ?? this.estopSwipeInstruction,
      resetEstopLabel: resetEstopLabel ?? this.resetEstopLabel,
      screenTitle: screenTitle ?? this.screenTitle,
    );
  }

  Map<String, dynamic> toJson() => {
    'upLabel': upLabel,
    'downLabel': downLabel,
    'leftLabel': leftLabel,
    'rightLabel': rightLabel,
    'forwardLabel': forwardLabel,
    'reverseLabel': reverseLabel,
    'estopSwipeInstruction': estopSwipeInstruction,
    'resetEstopLabel': resetEstopLabel,
    'screenTitle': screenTitle,
  };

  factory ControlLabelConfig.fromJson(Map<String, dynamic> json) {
    return ControlLabelConfig(
      upLabel: json['upLabel'] as String? ?? 'UP',
      downLabel: json['downLabel'] as String? ?? 'DOWN',
      leftLabel: json['leftLabel'] as String? ?? 'LEFT',
      rightLabel: json['rightLabel'] as String? ?? 'RIGHT',
      forwardLabel: json['forwardLabel'] as String? ?? 'FWD',
      reverseLabel: json['reverseLabel'] as String? ?? 'REV',
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
          other.upLabel == upLabel &&
          other.downLabel == downLabel &&
          other.leftLabel == leftLabel &&
          other.rightLabel == rightLabel &&
          other.forwardLabel == forwardLabel &&
          other.reverseLabel == reverseLabel &&
          other.estopSwipeInstruction == estopSwipeInstruction &&
          other.resetEstopLabel == resetEstopLabel &&
          other.screenTitle == screenTitle;

  @override
  int get hashCode => Object.hash(
    upLabel,
    downLabel,
    leftLabel,
    rightLabel,
    forwardLabel,
    reverseLabel,
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

/// Default axis render order (Hoist, Traverse, Travel). PLC38-only meaning —
/// PLC14/PLC21 only ever render the Hoist axis, so order is a no-op there.
const List<AxisKind> kDefaultAxisOrder = [
  AxisKind.hoist,
  AxisKind.traverse,
  AxisKind.travel,
];

class ControlLayoutConfig {
  const ControlLayoutConfig({
    this.sizeConfig = const ControlWidgetSizeConfig(),
    this.labelConfig = const ControlLabelConfig(),
    this.arrangementConfig = const ControlArrangementConfig(),
    this.axisConfigs = const AxisConfigSet(),
    this.roleStyles = const RoleStyleConfig(),
    this.axisOrder = kDefaultAxisOrder,
    this.buttons = const <String, ButtonConfig>{},
    this.controlPageCount = 1,
  });

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
  /// variant list), replacing the old single `plcMapping`-plus-ControlRole/
  /// AxisKind-derivation composition path. Old JSON without `stateMappings`
  /// is migrated on load via ButtonConfig.fromJson, which falls back to
  /// ButtonConfig.migratedStateMappingsFor — reproducing the OLD derivation
  /// exactly as static data — whenever the `stateMappings` key is absent.
  /// Bumped 6 -> 7 by the potentiometer control addition: ButtonType gains
  /// `potentiometer`, with analog range/output metadata stored in
  /// ButtonConfig.customProperties.
  static const int schemaVersion = 7;

  final ControlWidgetSizeConfig sizeConfig;
  final ControlLabelConfig labelConfig;
  final ControlArrangementConfig arrangementConfig;

  /// Per-axis control type, spring/latch wiring, and height scale.
  /// LEGACY (v2 shape) — kept permanently as the migration source for old
  /// saved JSON; no longer the live source of truth once the button-centric
  /// screens/edit sheet are fully switched over (see [buttons]).
  final AxisConfigSet axisConfigs;

  /// Per-role cosmetic overrides (color, corner radius, icon size, ...).
  /// LEGACY (v2 shape) — see [axisConfigs] doc comment.
  final RoleStyleConfig roleStyles;

  /// Display order of the three motion axes. Meaningful on PLC38 only.
  final List<AxisKind> axisOrder;

  /// Button-centric configs, keyed by [ButtonConfig.id] (== `ControlRole.name`
  /// for all 8 legacy buttons). Populated either explicitly (new-format
  /// JSON) or synthesized from [axisConfigs]/[roleStyles]/[labelConfig] on
  /// load when absent (old-format JSON) — see [fromJson].
  final Map<String, ButtonConfig> buttons;

  /// User-requested minimum number of horizontal control pages. Extra pages
  /// are also rendered automatically when buttons occupy higher page indexes.
  final int controlPageCount;

  /// Fallback default buttons map, used only when [buttons] lacks an entry
  /// for a role — this happens exclusively for `const ControlLayoutConfig()`
  /// (whose `buttons` defaults to `{}`), since every config loaded through
  /// [fromJson] always has `buttons` populated for all 8 roles via
  /// [_synthesizeButtonsFromLegacy]. This is the SINGLE fallback point for
  /// the whole app — screens and the edit sheet call [buttonFor] and treat
  /// its result as always non-null for the 8 closed ControlRole values,
  /// rather than each maintaining its own "effectiveX" resolver per field.
  Map<String, ButtonConfig> get resolvedButtons => {
    ..._synthesizeButtonsFromLegacy(axisConfigs, roleStyles, labelConfig),
    ...buttons,
  };

  ButtonConfig? buttonFor(ControlRole role) => resolvedButtons[role.name];

  ControlLayoutConfig withButton(String id, ButtonConfig config) =>
      copyWith(buttons: {...resolvedButtons, id: config});

  ControlLayoutConfig copyWith({
    ControlWidgetSizeConfig? sizeConfig,
    ControlLabelConfig? labelConfig,
    ControlArrangementConfig? arrangementConfig,
    AxisConfigSet? axisConfigs,
    RoleStyleConfig? roleStyles,
    List<AxisKind>? axisOrder,
    Map<String, ButtonConfig>? buttons,
    int? controlPageCount,
  }) {
    return ControlLayoutConfig(
      sizeConfig: sizeConfig ?? this.sizeConfig,
      labelConfig: labelConfig ?? this.labelConfig,
      arrangementConfig: arrangementConfig ?? this.arrangementConfig,
      axisConfigs: axisConfigs ?? this.axisConfigs,
      roleStyles: roleStyles ?? this.roleStyles,
      axisOrder: axisOrder ?? this.axisOrder,
      buttons: buttons ?? this.buttons,
      controlPageCount: controlPageCount ?? this.controlPageCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'sizeConfig': sizeConfig.toJson(),
    'labelConfig': labelConfig.toJson(),
    'arrangementConfig': arrangementConfig.toJson(),
    'axisConfigs': axisConfigs.toJson(),
    'roleStyles': roleStyles.toJson(),
    'axisOrder': axisOrder.map((a) => a.name).toList(),
    'buttons': resolvedButtons.map((id, cfg) => MapEntry(id, cfg.toJson())),
    'controlPageCount': controlPageCount,
  };

  /// Synthesizes the button-centric `buttons` map from the legacy per-axis/
  /// per-role/per-label fields. Pure and idempotent — invoked by [fromJson]
  /// whenever old-format JSON (no `buttons` key) is parsed, so old saved
  /// layouts silently upgrade in memory on load with zero user action, and
  /// get persisted in the new format on the very next save.
  static Map<String, ButtonConfig> _synthesizeButtonsFromLegacy(
    AxisConfigSet axisConfigs,
    RoleStyleConfig roleStyles,
    ControlLabelConfig labelConfig,
  ) {
    String legacyLabelFor(ControlRole role) => switch (role) {
      ControlRole.hoistUp => labelConfig.upLabel,
      ControlRole.hoistDown => labelConfig.downLabel,
      ControlRole.traverseLeft => labelConfig.leftLabel,
      ControlRole.traverseRight => labelConfig.rightLabel,
      ControlRole.travelForward => labelConfig.forwardLabel,
      ControlRole.travelReverse => labelConfig.reverseLabel,
      ControlRole.estop => role.defaultLabel,
      ControlRole.resetEstop => labelConfig.resetEstopLabel,
    };

    final result = <String, ButtonConfig>{};
    for (final role in ControlRole.values) {
      if (role == ControlRole.estop) {
        result[role.name] = ButtonConfig.estopDefault();
        continue;
      }
      if (role == ControlRole.resetEstop) {
        result[role.name] = ButtonConfig.resetEstopDefault(
          legacyLabelFor(role),
          style: roleStyles.resetEstop,
        );
        continue;
      }
      final axis = role.axis!;
      result[role.name] = ButtonConfig.fromLegacyAxis(
        role: role,
        axisConfig: axisConfigs.forAxis(axis),
        style: roleStyles.forRole(role),
        label: legacyLabelFor(role),
      );
    }
    return result;
  }

  static Map<String, ButtonConfig> buttonsFromLegacy({
    AxisConfigSet axisConfigs = const AxisConfigSet(),
    RoleStyleConfig roleStyles = const RoleStyleConfig(),
    ControlLabelConfig labelConfig = const ControlLabelConfig(),
  }) => _synthesizeButtonsFromLegacy(axisConfigs, roleStyles, labelConfig);

  /// Roles hidden by default on PLC14/PLC21 hardware. These PLC types have no
  /// traverse/travel outputs, so those controls start hidden rather than
  /// showing buttons that would silently no-op when pressed.
  static const List<ControlRole> _hoistOnlyHiddenRoles = [
    ControlRole.traverseLeft,
    ControlRole.traverseRight,
    ControlRole.travelForward,
    ControlRole.travelReverse,
  ];

  /// Fresh-install default for [bucket], keeping persisted storage bucketed by
  /// PLC type while sharing the same 2 x 3 control grid model.
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
    final buttons = buttonsFromLegacy();
    if (plcType == PlcType.plc38) {
      return ControlLayoutConfig(buttons: buttons);
    }

    final hoistOnly = {
      ...buttons,
      ControlRole.hoistUp.name: buttons[ControlRole.hoistUp.name]!.copyWith(
        type: ButtonType.sliderButton,
        pageIndex: 0,
        gridX: 0,
        gridY: 0,
        gridColumns: 1,
        gridRows: ButtonConfig.controlGridRows,
        slotIndex: 0,
      ),
      ControlRole.hoistDown.name: buttons[ControlRole.hoistDown.name]!.copyWith(
        type: ButtonType.sliderButton,
        pageIndex: 0,
        gridX: 1,
        gridY: 0,
        gridColumns: 1,
        gridRows: ButtonConfig.controlGridRows,
        slotIndex: 1,
      ),
      for (final role in _hoistOnlyHiddenRoles)
        role.name: buttons[role.name]!.copyWith(visible: false),
    };
    return ControlLayoutConfig(buttons: hoistOnly);
  }

  static AxisKind? _tryParseAxisKind(dynamic name) {
    for (final a in AxisKind.values) {
      if (a.name == name) return a;
    }
    return null;
  }

  static List<AxisKind> _parseAxisOrder(dynamic raw) {
    if (raw is! List) return kDefaultAxisOrder;
    final parsed = raw.map(_tryParseAxisKind).whereType<AxisKind>().toList();
    // Defensive fallback: must be exactly the 3 axis kinds, each once —
    // otherwise a corrupted/hand-edited value silently reverts to default
    // rather than producing a partial or duplicated axis list.
    if (parsed.length != 3 || parsed.toSet().length != 3) {
      return kDefaultAxisOrder;
    }
    return parsed;
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
    final legacyButtons = _synthesizeButtonsFromLegacy(
      axisConfigs,
      roleStyles,
      labelConfig,
    );
    final buttons = json['buttons'] != null
        ? {
            ...legacyButtons,
            ...(json['buttons'] as Map<String, dynamic>).map(
              (id, v) => MapEntry(
                id,
                ButtonConfig.fromJson(v as Map<String, dynamic>),
              ),
            ),
          }
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
      axisConfigs: axisConfigs,
      roleStyles: roleStyles,
      axisOrder: _parseAxisOrder(json['axisOrder']),
      buttons: buttons,
      controlPageCount: _parsePositiveInt(json['controlPageCount']),
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

  static bool _axisOrderEquals(List<AxisKind> a, List<AxisKind> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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
          other.axisConfigs == axisConfigs &&
          other.roleStyles == roleStyles &&
          _axisOrderEquals(other.axisOrder, axisOrder) &&
          _buttonsEqual(other.resolvedButtons, resolvedButtons) &&
          other.controlPageCount == controlPageCount;

  @override
  int get hashCode => Object.hash(
    sizeConfig,
    labelConfig,
    arrangementConfig,
    axisConfigs,
    roleStyles,
    Object.hashAll(axisOrder),
    Object.hashAllUnordered(
      resolvedButtons.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    controlPageCount,
  );
}

int _parsePositiveInt(dynamic value, {int fallback = 1}) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  if (parsed == null || parsed < 1) return fallback;
  return parsed;
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
