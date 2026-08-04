import 'package:flutter/material.dart' show IconData;

import 'package:rev_crane_control_ops/models/button_icon_registry.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/models/joystick_config.dart';
import 'package:rev_crane_control_ops/models/button_rotation.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/legacy_layout_migration.dart';
import 'package:rev_crane_control_ops/models/button_behavior_config.dart';
import 'package:rev_crane_control_ops/models/mutual_exclusion_config.dart';
import 'package:rev_crane_control_ops/models/button_state_output_mapping.dart';

enum ButtonType {
  pushButton,
  toggle,
  sliderButton,
  bidirectionalSlider5Step,
  bidirectionalSlider3Step,
  joystick,
  potentiometer,
  horn,
  alarmIndicator,
  // Analog controls (see analog_wire_config.dart) — all bypass
  // stateMappings entirely, exactly like potentiometer.
  analogJoystick1D,
  analogJoystick2D,
  analogSliderOT,
  analogSliderTOT,
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
    this.iconKey,
    this.catalogEntryId,
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
    this.pageIndex = 0,
    this.gridX = 0,
    this.gridY = 0,
    this.gridColumns = 1,
    this.gridRows = 1,
    this.plcMappingEnabled = true,
    this.stateMappings = const <String, ButtonStateOutputMapping>{},
    this.joystickSubButtonMappings =
        const <String, Map<String, ButtonStateOutputMapping>>{},
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
  static const int controlGridRows = 3;
  static const int minSlotIndex = 0;
  static const int maxSlotIndex = controlSlotCount - 1;

  /// Stable identity. For the two safety controls this is exactly
  /// `ControlRole.name` ('estop'/'resetEstop'); for a button migrated from a
  /// pre-v3 saved layout it's the fixed legacy string id (see
  /// legacy_layout_migration.dart); any other button gets a generated id.
  /// Stable ids keep undo/redo/JSON diffs stable across a save/reload cycle.
  final String id;

  final ButtonType type;

  /// Which PlcOutputCommand field this button ultimately drives. A single
  /// ButtonConfig always has exactly one mapping — a multi-zone slider's two
  /// logical halves each get their own ButtonConfig+mapping.
  final PlcOutputVariant plcMapping;

  /// The legacy ControlRole this button corresponds to, if any. Present for
  /// all 8 migrated buttons; null is reserved for future free-standing
  /// buttons with no fixed role (none created this pass — ControlRole
  /// remains the closed safety enum).
  final ControlRole? role;

  final String label;

  /// Null falls back to the existing hardcoded per-role icon in the widget
  /// layer (e.g. UpPushControlButton's Icons.arrow_upward_rounded).
  final IconData? icon;

  /// Persistence key for [icon] when it was chosen via the customization
  /// sheet's icon picker (see button_icon_registry.dart) — [icon] itself
  /// can't safely round-trip through JSON (codePoint alone loses font
  /// family/package), so [fromJson] resolves [icon] from this key instead.
  /// Null keeps the pre-existing exact behavior: [icon] round-trips to null
  /// and the widget layer's hardcoded default applies.
  final String? iconKey;

  /// The [CatalogEntry.id] this button was placed from, if any — lets
  /// "Reset to default" restore this exact catalogue variant's behavior/
  /// customProperties rather than guessing from [type] alone (several
  /// catalogue entries share one [ButtonType] with different behavior,
  /// e.g. the two push-button variants). Null for buttons created before
  /// this field existed, or any non-catalogue-sourced button — "Reset to
  /// default" falls back to resetting appearance only in that case.
  final String? catalogEntryId;

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

  /// Paged widget-grid placement. These fields are the schema v5 layout
  /// source; [slotIndex] remains as a legacy mirror for older code/templates.
  final int pageIndex;
  final int gridX;
  final int gridY;
  final int gridColumns;
  final int gridRows;
  final bool plcMappingEnabled;

  /// Generic button-state -> PLC-output-variant mapping, keyed by logical
  /// state id (see ButtonTypeLogicalStates.logicalStates). This is the
  /// authoritative source of truth for composition once migrated/populated
  /// — no output variant is ever activated except by an explicit entry
  /// here for that exact state (see CraneController._fieldsFor).
  ///
  /// [PlcOutputVariant]/[plcMappingEnabled] are kept as a cosmetic/orientation
  /// hint (icon defaults, slider drag-orientation) — they no longer drive
  /// composition once a button has real stateMappings entries.
  final Map<String, ButtonStateOutputMapping> stateMappings;

  /// For [ButtonType.joystick] only: per-virtual-sub-button stateMappings,
  /// keyed by the virtual sub-button id (see [joystickVirtualButtonId]).
  /// A joystick decomposes into up to 4 independent per-direction virtual
  /// sub-buttons at runtime (see JoystickButtonStrategy) — each one needs
  /// its own idle/step1/step2 mapping, exactly like a real ButtonConfig's
  /// [stateMappings], but there is no real ButtonConfig for a virtual
  /// sub-button to own it on, so the parent joystick's ButtonConfig holds
  /// all of its sub-buttons' tables here. Freshly-created (non-migrated)
  /// joysticks start with this empty — inert until the user explicitly
  /// configures each sub-button via the edit sheet's JOYSTICK section.
  final Map<String, Map<String, ButtonStateOutputMapping>>
  joystickSubButtonMappings;

  double get resolvedHeight => AxisControlConfig.baseHeight * heightScale;

  int get gridColumnSpan {
    // The 5-zone slider only ever occupies exactly two cells, in one of two
    // fixed shapes: 2x1 (horizontal, default) or 1x2 (vertical). Vertical is
    // signaled by an explicit gridRows > 1 (mirroring gridRowSpan's own
    // check below) — an explicit gridColumns=1 alone can't signal it, since
    // gridColumns=1 is indistinguishable from "not set".
    if (type == ButtonType.bidirectionalSlider5Step) {
      if (gridRows > 1) return 1;
      return gridColumns > 1 ? gridColumns.clamp(1, controlGridColumns) : 2;
    }
    if (gridColumns > 1) return gridColumns.clamp(1, controlGridColumns);
    // The 3-zone slider fits a single cell (1x1) by default, honoring an
    // explicit gridColumns override above like any other type.
    if (type == ButtonType.analogJoystick2D ||
        (type == ButtonType.joystick &&
            JoystickConfig.fromCustomProperties(customProperties).isDualAxis)) {
      return 2;
    }
    return columnSpan.clamp(1, controlGridColumns);
  }

  int get gridRowSpan {
    if (gridRows > 1) return gridRows.clamp(1, controlGridRows);
    if (type == ButtonType.analogJoystick2D ||
        (type == ButtonType.joystick &&
            JoystickConfig.fromCustomProperties(customProperties).isDualAxis)) {
      return 2;
    }
    return 1;
  }

  bool get occupiesMultipleGridCells => gridColumnSpan > 1 || gridRowSpan > 1;

  static (int, int) defaultGridSizeFor(
    ButtonType type, {
    Map<String, dynamic> customProperties = const <String, dynamic>{},
  }) {
    if (type == ButtonType.bidirectionalSlider5Step) {
      return (2, 1);
    }
    if (type == ButtonType.bidirectionalSlider3Step) {
      return (1, 1);
    }
    if (type == ButtonType.analogJoystick2D ||
        (type == ButtonType.joystick &&
            JoystickConfig.fromCustomProperties(customProperties).isDualAxis)) {
      return (2, 2);
    }
    return (1, 1);
  }

  /// E-STOP has no style entry (its appearance is not customizable) and is
  /// always fixed to DF1. `locked: true` since it's never draggable/resizable.
  factory ButtonConfig.estopDefault() {
    return ButtonConfig(
      id: ControlRole.estop.name,
      type: ButtonType.pushButton,
      plcMapping: PlcOutputVariant.df1,
      role: ControlRole.estop,
      label: ControlRole.estop.defaultLabel,
      visible: true,
      locked: true,
      canvasX: 0.04,
      canvasY: 0.02,
    );
  }

  /// resetEstop has no PlcOutputCommand field of its own (it's a
  /// controller-level action — CraneController.resetEStop — not a composed
  /// packet bit); PlcOutputVariant.df1 is only a structural placeholder since
  /// PlcOutputVariant has no "none" option and resetEstop is never composed via
  /// PlcOutputVariant in practice (see CraneController.resetEStop).
  factory ButtonConfig.resetEstopDefault(
    String label, {
    ButtonStyleConfig style = const ButtonStyleConfig(),
  }) {
    return ButtonConfig(
      id: ControlRole.resetEstop.name,
      type: ButtonType.pushButton,
      plcMapping: PlcOutputVariant.df1,
      role: ControlRole.resetEstop,
      label: label,
      style: style,
      visible: true,
      locked: true,
      canvasX: 0.52,
      canvasY: 0.02,
    );
  }

  ButtonConfig copyWith({
    String? id,
    ButtonType? type,
    PlcOutputVariant? plcMapping,
    ControlRole? role,
    String? label,
    IconData? icon,
    String? iconKey,
    String? catalogEntryId,
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
    int? pageIndex,
    int? gridX,
    int? gridY,
    int? gridColumns,
    int? gridRows,
    bool? plcMappingEnabled,
    Map<String, ButtonStateOutputMapping>? stateMappings,
    Map<String, Map<String, ButtonStateOutputMapping>>?
    joystickSubButtonMappings,
    bool clearIcon = false,
    bool clearIconKey = false,
    bool clearCatalogEntryId = false,
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
      iconKey: clearIconKey ? null : (iconKey ?? this.iconKey),
      catalogEntryId: clearCatalogEntryId
          ? null
          : (catalogEntryId ?? this.catalogEntryId),
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
      pageIndex: pageIndex ?? this.pageIndex,
      gridX: gridX ?? this.gridX,
      gridY: gridY ?? this.gridY,
      gridColumns: gridColumns ?? this.gridColumns,
      gridRows: gridRows ?? this.gridRows,
      plcMappingEnabled: plcMappingEnabled ?? this.plcMappingEnabled,
      stateMappings: stateMappings ?? this.stateMappings,
      joystickSubButtonMappings:
          joystickSubButtonMappings ?? this.joystickSubButtonMappings,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'plcMapping': plcMapping.storageKey,
    'role': role?.name,
    'label': label,
    'icon': icon?.codePoint,
    'iconKey': iconKey,
    'catalogEntryId': catalogEntryId,
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
    'pageIndex': pageIndex,
    'gridX': gridX,
    'gridY': gridY,
    'gridColumns': gridColumns,
    'gridRows': gridRows,
    'plcMappingEnabled': plcMappingEnabled,
    'stateMappings': stateMappings.map((k, v) => MapEntry(k, v.toJson())),
    'joystickSubButtonMappings': joystickSubButtonMappings.map(
      (subId, table) => MapEntry(
        subId,
        table.map((stateId, mapping) => MapEntry(stateId, mapping.toJson())),
      ),
    ),
  };

  factory ButtonConfig.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final role = ControlRole.values.firstWhereOrNull(
      (e) => e.name == json['role'],
    );
    // Present only for one of the six legacy motion-control ids a pre-v6
    // saved layout always used as both id and role name — see
    // legacy_layout_migration.dart, the sole consumer of this.
    final legacyMotionId = kLegacyMotionButtonIds.contains(id) ? id : null;
    final (defaultX, defaultY) = switch (role) {
      ControlRole.estop => (0.04, 0.02),
      ControlRole.resetEstop => (0.52, 0.02),
      null => legacyMotionId != null
          ? legacyCanvasPositionFor(legacyMotionId)
          : (0.0, 0.0),
    };
    final slotIndex =
        (json['slotIndex'] as num?)?.toInt() ??
        (legacyMotionId != null ? legacySlotIndexFor(legacyMotionId) : null);
    final (defaultGridX, defaultGridY) = legacyMotionId != null
        ? legacyGridPositionFor(legacyMotionId)
        : (
            slotIndex == null ? 0 : slotIndex % controlGridColumns,
            slotIndex == null ? 0 : slotIndex ~/ controlGridColumns,
          );
    final type = ButtonType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => ButtonType.pushButton,
    );
    final customProperties =
        (json['customProperties'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final (defaultColumns, defaultRows) = defaultGridSizeFor(
      type,
      customProperties: customProperties,
    );

    return ButtonConfig(
      id: id,
      type: type,
      plcMapping:
          PlcOutputVariant.fromStorageKey(
            json['plcMapping'] ?? json['PlcOutputVariant'],
          ) ??
          PlcOutputVariant.df2,
      role: role,
      label: json['label'] as String? ?? '',
      // A bare codePoint (pre-iconKey JSON) intentionally never restores to
      // a renderable IconData (font family/package are lost) — but an
      // iconKey from the curated registry resolves to a real, fully-
      // specified IconData with no ambiguity. See ButtonConfig.iconKey doc
      // comment.
      icon: iconForKey(json['iconKey'] as String?),
      iconKey: json['iconKey'] as String?,
      catalogEntryId: json['catalogEntryId'] as String?,
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
      customProperties: customProperties,
      visible: json['visible'] as bool? ?? true,
      widthScale: (json['widthScale'] as num?)?.toDouble() ?? 1.0,
      columnSpan: _parseColumnSpan(json['columnSpan']),
      enabled: json['enabled'] as bool? ?? true,
      locked: json['locked'] as bool? ?? false,
      canvasX: (json['canvasX'] as num?)?.toDouble() ?? defaultX,
      canvasY: (json['canvasY'] as num?)?.toDouble() ?? defaultY,
      slotIndex: slotIndex,
      pageIndex: _parseNonNegativeInt(json['pageIndex']),
      gridX: _parseNonNegativeInt(json['gridX'], fallback: defaultGridX),
      gridY: _parseNonNegativeInt(json['gridY'], fallback: defaultGridY),
      gridColumns: _parseSpan(
        json['gridColumns'],
        fallback: defaultColumns,
        max: controlGridColumns,
      ),
      gridRows: _parseSpan(
        json['gridRows'],
        fallback: defaultRows,
        max: controlGridRows,
      ),
      plcMappingEnabled: json['plcMappingEnabled'] as bool? ?? (role != null),
      // Old JSON (pre-schema-v6) has no `stateMappings` key at all — fall
      // back to migrating the legacy id-derived behavior into static data,
      // exactly matching what a freshly migrated legacy button bakes in. A
      // present-but-empty map (e.g. a freshly-created custom button) is left
      // empty/inert, NOT migrated — only a genuinely absent stateMappings key
      // AND a recognized legacy motion id trigger the legacy fallback.
      stateMappings: json.containsKey('stateMappings')
          ? _parseStateMappings(json['stateMappings'])
          : (legacyMotionId != null
                ? legacyMotionStateMappings(legacyId: legacyMotionId, type: type)
                : const <String, ButtonStateOutputMapping>{}),
      joystickSubButtonMappings: json.containsKey('joystickSubButtonMappings')
          ? _parseJoystickSubButtonMappings(json['joystickSubButtonMappings'])
          : (type == ButtonType.joystick && legacyMotionId != null
                ? legacyJoystickSubButtonMappings(
                    sourceButtonId: id,
                    legacyId: legacyMotionId,
                    joystickConfig: JoystickConfig.fromCustomProperties(
                      customProperties,
                    ),
                  )
                : const <String, Map<String, ButtonStateOutputMapping>>{}),
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
          other.iconKey == iconKey &&
          other.catalogEntryId == catalogEntryId &&
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
          other.slotIndex == slotIndex &&
          other.pageIndex == pageIndex &&
          other.gridX == gridX &&
          other.gridY == gridY &&
          other.gridColumns == gridColumns &&
          other.gridRows == gridRows &&
          other.plcMappingEnabled == plcMappingEnabled &&
          _stateMappingsEqual(other.stateMappings, stateMappings) &&
          _joystickSubButtonMappingsEqual(
            other.joystickSubButtonMappings,
            joystickSubButtonMappings,
          );

  @override
  int get hashCode => Object.hash(
    id,
    type,
    plcMapping,
    role,
    label,
    icon,
    iconKey,
    catalogEntryId,
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
    Object.hash(
      slotIndex,
      pageIndex,
      gridX,
      gridY,
      gridColumns,
      gridRows,
      plcMappingEnabled,
    ),
    Object.hash(
      Object.hashAllUnordered(
        stateMappings.entries.map((e) => Object.hash(e.key, e.value)),
      ),
      Object.hashAllUnordered(
        joystickSubButtonMappings.entries.map(
          (e) => Object.hash(
            e.key,
            Object.hashAllUnordered(
              e.value.entries.map((s) => Object.hash(s.key, s.value)),
            ),
          ),
        ),
      ),
    ),
  );
}

bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

bool _stateMappingsEqual(
  Map<String, ButtonStateOutputMapping> a,
  Map<String, ButtonStateOutputMapping> b,
) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

Map<String, ButtonStateOutputMapping> _parseStateMappings(dynamic value) {
  final raw = (value as Map?)?.cast<String, dynamic>();
  if (raw == null) return const <String, ButtonStateOutputMapping>{};
  final result = <String, ButtonStateOutputMapping>{};
  for (final entry in raw.entries) {
    if (entry.value is Map) {
      result[entry.key] = ButtonStateOutputMapping.fromJson(
        (entry.value as Map).cast<String, dynamic>(),
      );
    }
  }
  return result;
}

bool _joystickSubButtonMappingsEqual(
  Map<String, Map<String, ButtonStateOutputMapping>> a,
  Map<String, Map<String, ButtonStateOutputMapping>> b,
) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null || !_stateMappingsEqual(other, entry.value)) {
      return false;
    }
  }
  return true;
}

Map<String, Map<String, ButtonStateOutputMapping>>
_parseJoystickSubButtonMappings(dynamic value) {
  final raw = (value as Map?)?.cast<String, dynamic>();
  if (raw == null) {
    return const <String, Map<String, ButtonStateOutputMapping>>{};
  }
  final result = <String, Map<String, ButtonStateOutputMapping>>{};
  for (final entry in raw.entries) {
    if (entry.value is Map) {
      result[entry.key] = _parseStateMappings(entry.value);
    }
  }
  return result;
}

int _parseColumnSpan(dynamic value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  if (parsed == null) return 1;
  return parsed.clamp(1, ButtonConfig.controlGridColumns);
}

int _parseNonNegativeInt(dynamic value, {int fallback = 0}) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  if (parsed == null || parsed < 0) return fallback;
  return parsed;
}

int _parseSpan(dynamic value, {required int fallback, required int max}) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  if (parsed == null) return fallback.clamp(1, max);
  return parsed.clamp(1, max);
}

extension _FirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
