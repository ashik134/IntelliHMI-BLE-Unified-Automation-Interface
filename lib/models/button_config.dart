import 'package:flutter/material.dart' show IconData;

import 'package:rev_crane_control_ops/models/button_behavior_config.dart';
import 'package:rev_crane_control_ops/models/button_rotation.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/models/joystick_config.dart';
import 'package:rev_crane_control_ops/models/mutual_exclusion_config.dart';
import 'package:rev_crane_control_ops/models/plc_mapping.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ButtonType
//
// Distinct from the legacy ControlWidgetType enum (kept for the axis path)
// but intentionally identical in spirit/values so migration is a straight
// mapping. `crossTravel` is new: the combined-slider "type", kept as an
// optional selectable type, decomposed into two logical buttons under the
// hood (see CrossTravelStrategy). joystick uses the same button-centric model;
// analog PLC wire output can be added when the protocol exposes analog fields.
// ─────────────────────────────────────────────────────────────────────────────

enum ButtonType {
  pushButton,
  toggle,
  sliderButton,
  crossTravel,
  crossTravelSlowOnly,
  joystick,
}

// ─────────────────────────────────────────────────────────────────────────────
// ButtonConfig
//
// The per-button config in the button-centric model. Every button (motion
// role or, in the future, a free-standing control) owns its own type, size,
// style, behavior, PLC mapping, and mutual-exclusion rules independently —
// editing one button never requires touching another.
// ─────────────────────────────────────────────────────────────────────────────

class ButtonConfig {
  const ButtonConfig({
    required this.id,
    required this.type,
    required this.plcMapping,
    this.role,
    this.label = '',
    this.icon,
    this.heightScale = 1.0,
    this.rotation = ButtonRotation.none,
    this.style = const ButtonStyleConfig(),
    this.behavior = const ButtonBehaviorConfig(),
    this.mutualExclusion = const MutualExclusionConfig(),
    this.group,
    this.customProperties = const <String, dynamic>{},
    this.visible = true,
    this.widthScale = 1.0,
    this.columnSpan = 1,
    this.enabled = true,
    this.locked = false,
    this.canvasX = 0.0,
    this.canvasY = 0.0,
    this.slotIndex,
  });

  static const double minHeightScale = AxisControlConfig.minHeightScale;
  static const double maxHeightScale = AxisControlConfig.maxHeightScale;

  /// Same bounds as height — width is always a relative multiplier (there is
  /// no independent "base width" the way [AxisControlConfig.baseHeight]
  /// exists for height), consumed only as a Row/Expanded flex weight in live
  /// mode (see ConfigurableButton call sites in the control screens).
  static const double minWidthScale = AxisControlConfig.minHeightScale;
  static const double maxWidthScale = AxisControlConfig.maxHeightScale;

  /// Minimum rendered motion-control slot size. The values are intentionally
  /// larger than the 48px mobile minimum so the HMI remains usable with gloves.
  static const double minButtonWidthPx = 140.0;
  static const double minButtonHeightPx = 96.0;

  static const int controlSlotCount = 6;
  static const int controlGridColumns = 2;
  static const int minSlotIndex = 0;
  static const int maxSlotIndex = controlSlotCount - 1;

  /// Stable identity. For the 8 legacy roles this is exactly `ControlRole.name`
  /// ('hoistUp', 'hoistDown', ..., 'estop', 'resetEstop') — chosen so
  /// migration needs no id-generation/lookup table and undo/redo/JSON diffs
  /// stay stable across a save/reload cycle. Future free-standing buttons
  /// (not tied to a legacy role) would get a generated id — out of scope
  /// this pass, since no such button exists yet.
  final String id;

  final ButtonType type;

  /// Which PlcOutputCommand field this button ultimately drives. A single
  /// ButtonConfig always has exactly one mapping — cross-travel's two
  /// logical halves each get their own ButtonConfig+mapping.
  final PlcMapping plcMapping;

  /// The legacy ControlRole this button corresponds to, if any. Present for
  /// all 8 migrated buttons; null is reserved for future free-standing
  /// buttons with no fixed role (none created this pass — ControlRole
  /// remains the closed safety enum).
  final ControlRole? role;

  final String label;

  /// Null falls back to the existing hardcoded per-role icon in the widget
  /// layer (e.g. UpPushControlButton's Icons.arrow_upward_rounded) — no
  /// change in visual behavior until a "change icon" editor exists.
  final IconData? icon;

  final double heightScale;
  final ButtonRotation rotation;
  final ButtonStyleConfig style;
  final ButtonBehaviorConfig behavior;
  final MutualExclusionConfig mutualExclusion;

  /// Optional free-form tag for future grouping features. No editor UI this
  /// pass — forward-compatibility placeholder.
  final String? group;

  /// Forward-compatibility bag for future per-type custom fields (e.g. a
  /// future joystick's dead-zone radius) without another schema bump. No
  /// editor UI this pass. Values must be JSON-primitive (bool/num/String/
  /// List/Map) to keep toJson/fromJson trivial.
  final Map<String, dynamic> customProperties;

  final bool visible;

  /// Live-mode Row/Expanded flex weight, mirroring [heightScale]'s
  /// multiplier semantics. See ConfigurableButton call sites: every Row of
  /// sibling motion-control buttons uses `Expanded(flex: (widthScale *
  /// 100).round())`, so the default `1.0` reproduces today's bare
  /// `Expanded(child:)` (implicit flex 1) exactly.
  final double widthScale;
  final int columnSpan;

  /// Distinct from [visible]. `visible = false` -> not rendered at all.
  /// `enabled = false` -> still rendered/still occupies layout space, but
  /// grayed out and non-interactive (passed as `isDisabled: true` into
  /// ConfigurableButton regardless of mutual-exclusion state).
  final bool enabled;

  /// Canvas-only concept: freezes position/size editing in
  /// CustomizationCanvas. Does not prevent editing other fields (type,
  /// label, style, ...) via the pencil badge.
  final bool locked;

  /// Normalized top-left origin within the customization canvas, [0.0, 1.0].
  /// Never read by any live-mode rendering path — see ConfigurableButton /
  /// CustomizationCanvas doc comments.
  final double canvasX;
  final double canvasY;

  /// Fixed grid slot for motion controls. Slots are zero-based and map to the
  /// 2 column x 3 row control grid in row-major order. Safety controls live
  /// outside that grid, so their slot is null.
  final int? slotIndex;

  double get resolvedHeight => AxisControlConfig.baseHeight * heightScale;

  int get gridColumnSpan {
    if (type == ButtonType.crossTravel) return 2;
    if (type == ButtonType.joystick &&
        JoystickConfig.fromCustomProperties(customProperties).isDualAxis) {
      return 2;
    }
    return columnSpan.clamp(1, controlGridColumns);
  }

  int get gridRowSpan {
    if (type == ButtonType.joystick &&
        JoystickConfig.fromCustomProperties(customProperties).isDualAxis) {
      return 2;
    }
    return 1;
  }

  bool get occupiesMultipleGridCells => gridColumnSpan > 1 || gridRowSpan > 1;

  static int? defaultSlotIndexFor(ControlRole role) => switch (role) {
    ControlRole.hoistUp => 0,
    ControlRole.hoistDown => 1,
    ControlRole.traverseLeft => 2,
    ControlRole.traverseRight => 3,
    ControlRole.travelForward => 4,
    ControlRole.travelReverse => 5,
    ControlRole.estop || ControlRole.resetEstop => null,
  };

  /// Builds a button-centric ButtonConfig from the legacy per-axis/per-role
  /// config for a single ControlRole. Used both by
  /// ControlLayoutConfig.fromJson's migration branch (old JSON with no
  /// `buttons` key) and as the seed for a brand-new default config, so
  /// "migrated" and "freshly defaulted" go through one code path.
  factory ButtonConfig.fromLegacyAxis({
    required ControlRole role,
    required AxisControlConfig axisConfig,
    required ButtonStyleConfig style,
    required String label,
  }) {
    final (defaultX, defaultY) = defaultCanvasPositionFor(role);
    return ButtonConfig(
      id: role.name,
      type: switch (axisConfig.widgetType) {
        ControlWidgetType.pushButton => ButtonType.pushButton,
        ControlWidgetType.toggle => ButtonType.toggle,
        // Traverse's slider type has always rendered as the COMBINED
        // CrossTravelSlider (both directions in one widget) whenever both
        // resolved to slider type — preserve that default visual behavior
        // under the new per-button model rather than silently regressing
        // migrated layouts to two independent sliders.
        ControlWidgetType.sliderButton when role.axis == AxisKind.traverse =>
          ButtonType.crossTravel,
        ControlWidgetType.sliderButton => ButtonType.sliderButton,
        ControlWidgetType.joystick => ButtonType.joystick,
        ControlWidgetType.rotary => ButtonType.sliderButton,
      },
      plcMapping: role.plcMapping!,
      role: role,
      label: label,
      heightScale: axisConfig.heightScale,
      rotation: ButtonRotation.none,
      style: style,
      behavior: ButtonBehaviorConfig(wiring: axisConfig.wiringConfig),
      mutualExclusion: role.defaultMutualExclusion,
      canvasX: defaultX,
      canvasY: defaultY,
      slotIndex: defaultSlotIndexFor(role),
    );
  }

  /// Default canvas placement for a role, mirroring today's actual visual
  /// arrangement (hoist row, then traverse row, then travel row; safety
  /// controls in their own band) so migrated/freshly-defaulted buttons start
  /// in sensible, non-overlapping positions. Exposed publicly so the SIZE
  /// tab's "reset position" control can reuse the same table.
  static (double, double) defaultCanvasPositionFor(ControlRole role) =>
      _kDefaultCanvasPosition[role] ?? (0.04, 0.04);

  /// E-Stop has no AxisControlConfig/RoleStyleConfig entry (it's structurally
  /// excluded from RoleStyleConfig by design) and is never wrapped in
  /// EditableControlTile or placed on the customization canvas — this entry
  /// exists mainly for id-space completeness in the `buttons` map; the
  /// customization UI continues to hard-block editing it exactly as today.
  /// `locked: true` for consistency now that a position/lock concept exists,
  /// even though it's never reachable via the canvas either way.
  factory ButtonConfig.estopDefault() {
    final (x, y) = defaultCanvasPositionFor(ControlRole.estop);
    return ButtonConfig(
      id: ControlRole.estop.name,
      type: ButtonType.pushButton,
      plcMapping: PlcMapping.estop,
      role: ControlRole.estop,
      label: ControlRole.estop.defaultLabel,
      visible: true,
      locked: true,
      canvasX: x,
      canvasY: y,
      slotIndex: defaultSlotIndexFor(ControlRole.estop),
    );
  }

  /// resetEstop has no PlcOutputCommand field of its own (it's a
  /// controller-level action — CraneController.resetEStop — not a composed
  /// packet bit); plcMapping is estop only as a structural placeholder since
  /// PlcMapping has no "none" option and resetEstop is never composed via
  /// plcMapping in practice (see CraneController.resetEStop).
  factory ButtonConfig.resetEstopDefault(
    String label, {
    ButtonStyleConfig style = const ButtonStyleConfig(),
  }) {
    final (x, y) = defaultCanvasPositionFor(ControlRole.resetEstop);
    return ButtonConfig(
      id: ControlRole.resetEstop.name,
      type: ButtonType.pushButton,
      plcMapping: PlcMapping.estop,
      role: ControlRole.resetEstop,
      label: label,
      style: style,
      visible: true,
      locked: true,
      canvasX: x,
      canvasY: y,
      slotIndex: defaultSlotIndexFor(ControlRole.resetEstop),
    );
  }

  ButtonConfig copyWith({
    String? id,
    ButtonType? type,
    PlcMapping? plcMapping,
    ControlRole? role,
    String? label,
    IconData? icon,
    double? heightScale,
    ButtonRotation? rotation,
    ButtonStyleConfig? style,
    ButtonBehaviorConfig? behavior,
    MutualExclusionConfig? mutualExclusion,
    String? group,
    Map<String, dynamic>? customProperties,
    bool? visible,
    double? widthScale,
    int? columnSpan,
    bool? enabled,
    bool? locked,
    double? canvasX,
    double? canvasY,
    int? slotIndex,
    bool clearIcon = false,
    bool clearGroup = false,
    bool clearSlotIndex = false,
  }) {
    return ButtonConfig(
      id: id ?? this.id,
      type: type ?? this.type,
      plcMapping: plcMapping ?? this.plcMapping,
      role: role ?? this.role,
      label: label ?? this.label,
      icon: clearIcon ? null : (icon ?? this.icon),
      heightScale: heightScale ?? this.heightScale,
      rotation: rotation ?? this.rotation,
      style: style ?? this.style,
      behavior: behavior ?? this.behavior,
      mutualExclusion: mutualExclusion ?? this.mutualExclusion,
      group: clearGroup ? null : (group ?? this.group),
      customProperties: customProperties ?? this.customProperties,
      visible: visible ?? this.visible,
      widthScale: widthScale ?? this.widthScale,
      columnSpan: columnSpan ?? this.columnSpan,
      enabled: enabled ?? this.enabled,
      locked: locked ?? this.locked,
      canvasX: canvasX ?? this.canvasX,
      canvasY: canvasY ?? this.canvasY,
      slotIndex: clearSlotIndex ? null : (slotIndex ?? this.slotIndex),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'plcMapping': plcMapping.name,
    'role': role?.name,
    'label': label,
    'icon': icon?.codePoint,
    'heightScale': heightScale,
    'rotation': rotation.degrees,
    'style': style.toJson(),
    'behavior': behavior.toJson(),
    'mutualExclusion': mutualExclusion.toJson(),
    'group': group,
    'customProperties': customProperties,
    'visible': visible,
    'widthScale': widthScale,
    'columnSpan': columnSpan,
    'enabled': enabled,
    'locked': locked,
    'canvasX': canvasX,
    'canvasY': canvasY,
    'slotIndex': slotIndex,
  };

  factory ButtonConfig.fromJson(Map<String, dynamic> json) {
    final role = ControlRole.values.firstWhereOrNull(
      (e) => e.name == json['role'],
    );
    final (defaultX, defaultY) = role != null
        ? defaultCanvasPositionFor(role)
        : (0.0, 0.0);

    return ButtonConfig(
      id: json['id'] as String,
      type: ButtonType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ButtonType.pushButton,
      ),
      plcMapping: PlcMapping.values.firstWhere(
        (e) => e.name == json['plcMapping'],
        orElse: () => PlcMapping.up,
      ),
      role: role,
      label: json['label'] as String? ?? '',
      icon: null, // codePoint-only round trip intentionally not restored to
      // a renderable IconData (font family/package are lost) — the widget
      // layer's hardcoded per-role default is used instead, matching
      // migration's own behavior. See ButtonConfig.icon doc comment.
      heightScale: (json['heightScale'] as num?)?.toDouble() ?? 1.0,
      rotation: buttonRotationFromJson(json['rotation']),
      style: json['style'] != null
          ? ButtonStyleConfig.fromJson(json['style'] as Map<String, dynamic>)
          : const ButtonStyleConfig(),
      behavior: json['behavior'] != null
          ? ButtonBehaviorConfig.fromJson(
              json['behavior'] as Map<String, dynamic>,
            )
          : const ButtonBehaviorConfig(),
      mutualExclusion: json['mutualExclusion'] != null
          ? MutualExclusionConfig.fromJson(
              json['mutualExclusion'] as Map<String, dynamic>,
            )
          : const MutualExclusionConfig(),
      group: json['group'] as String?,
      customProperties:
          (json['customProperties'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
      visible: json['visible'] as bool? ?? true,
      widthScale: (json['widthScale'] as num?)?.toDouble() ?? 1.0,
      columnSpan: _parseColumnSpan(json['columnSpan']),
      enabled: json['enabled'] as bool? ?? true,
      locked: json['locked'] as bool? ?? false,
      canvasX: (json['canvasX'] as num?)?.toDouble() ?? defaultX,
      canvasY: (json['canvasY'] as num?)?.toDouble() ?? defaultY,
      slotIndex:
          (json['slotIndex'] as num?)?.toInt() ??
          (role != null ? defaultSlotIndexFor(role) : null),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ButtonConfig &&
          other.id == id &&
          other.type == type &&
          other.plcMapping == plcMapping &&
          other.role == role &&
          other.label == label &&
          other.icon == icon &&
          other.heightScale == heightScale &&
          other.rotation == rotation &&
          other.style == style &&
          other.behavior == behavior &&
          other.mutualExclusion == mutualExclusion &&
          other.group == group &&
          _mapEquals(other.customProperties, customProperties) &&
          other.visible == visible &&
          other.widthScale == widthScale &&
          other.columnSpan == columnSpan &&
          other.enabled == enabled &&
          other.locked == locked &&
          other.canvasX == canvasX &&
          other.canvasY == canvasY &&
          other.slotIndex == slotIndex;

  @override
  int get hashCode => Object.hash(
    id,
    type,
    plcMapping,
    role,
    label,
    icon,
    heightScale,
    rotation,
    style,
    behavior,
    mutualExclusion,
    group,
    Object.hash(
      visible,
      widthScale,
      columnSpan,
      enabled,
      locked,
      canvasX,
      canvasY,
    ),
    slotIndex,
  );
}

/// Default canvas positions mirroring today's visual arrangement (hoist row,
/// then traverse row, then travel row; safety controls in their own band).
const Map<ControlRole, (double, double)> _kDefaultCanvasPosition = {
  ControlRole.hoistUp: (0.04, 0.30),
  ControlRole.hoistDown: (0.52, 0.30),
  ControlRole.traverseLeft: (0.04, 0.56),
  ControlRole.traverseRight: (0.52, 0.56),
  ControlRole.travelForward: (0.04, 0.79),
  ControlRole.travelReverse: (0.52, 0.79),
  ControlRole.estop: (0.04, 0.02),
  ControlRole.resetEstop: (0.52, 0.02),
};

bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

int _parseColumnSpan(dynamic value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  if (parsed == null) return 1;
  return parsed.clamp(1, ButtonConfig.controlGridColumns);
}

extension _FirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
