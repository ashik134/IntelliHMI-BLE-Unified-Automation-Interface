import 'package:rev_crane_control_ops/models/button_behavior_config.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/button_rotation.dart';
import 'package:rev_crane_control_ops/models/button_state_output_mapping.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/models/joystick_config.dart';
import 'package:rev_crane_control_ops/models/mutual_exclusion_config.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';

// ─────────────────────────────────────────────────────────────────────────────
// legacy_layout_migration.dart
//
// ONE-TIME migration only. This is the sole file in the app that still speaks
// the pre-v3 per-axis/per-role saved-layout shape (six fixed motion-control
// ids, each hardwired to one PLC field). It exists purely so an existing
// install's saved SharedPreferences JSON keeps loading correctly.
//
// Nothing live — CraneController, any button-type strategy, or default-layout
// generation for a fresh install — may import from this file. It is consulted
// only by ControlLayoutConfig.fromJson's legacy-shape branch and
// ButtonConfig.fromJson's pre-schema-v6 fallback.
//
// Every ButtonConfig this file produces is a completely ordinary, generic
// button (role: null) — its behavior comes entirely from the stateMappings
// baked in here once, reproducing exactly what the old role/axis-derived
// composition used to compute live.
// ─────────────────────────────────────────────────────────────────────────────

/// The six legacy motion-control ids a pre-v3 saved layout always had.
const List<String> kLegacyMotionButtonIds = [
  'hoistUp',
  'hoistDown',
  'traverseLeft',
  'traverseRight',
  'travelForward',
  'travelReverse',
];

const Map<String, PlcOutputVariant> _legacyPlcMapping = {
  'hoistUp': PlcOutputVariant.df2,
  'hoistDown': PlcOutputVariant.df3,
  'traverseLeft': PlcOutputVariant.df5,
  'traverseRight': PlcOutputVariant.df6,
  'travelForward': PlcOutputVariant.df8,
  'travelReverse': PlcOutputVariant.df9,
};

const Map<String, PlcOutputVariant> _legacyFastMapping = {
  'hoistUp': PlcOutputVariant.df4,
  'hoistDown': PlcOutputVariant.df4,
  'traverseLeft': PlcOutputVariant.df7,
  'traverseRight': PlcOutputVariant.df7,
  'travelForward': PlcOutputVariant.df10,
  'travelReverse': PlcOutputVariant.df10,
};

const Map<String, int> _legacySlotIndex = {
  'hoistUp': 0,
  'hoistDown': 1,
  'traverseLeft': 2,
  'traverseRight': 3,
  'travelForward': 4,
  'travelReverse': 5,
};

const Map<String, (double, double)> _legacyCanvasPosition = {
  'hoistUp': (0.04, 0.30),
  'hoistDown': (0.52, 0.30),
  'traverseLeft': (0.04, 0.56),
  'traverseRight': (0.52, 0.56),
  'travelForward': (0.04, 0.79),
  'travelReverse': (0.52, 0.79),
};

const Map<String, String> _legacyPairedId = {
  'hoistUp': 'hoistDown',
  'hoistDown': 'hoistUp',
  'traverseLeft': 'traverseRight',
  'traverseRight': 'traverseLeft',
  'travelForward': 'travelReverse',
  'travelReverse': 'travelForward',
};

bool _isSecondAxisId(String legacyId) =>
    legacyId == 'traverseLeft' || legacyId == 'traverseRight';

int? legacySlotIndexFor(String legacyId) => _legacySlotIndex[legacyId];

(double, double) legacyCanvasPositionFor(String legacyId) =>
    _legacyCanvasPosition[legacyId] ?? (0.04, 0.04);

(int, int) legacyGridPositionFor(String legacyId) {
  final slot = legacySlotIndexFor(legacyId);
  if (slot == null) return (0, 0);
  return (slot % ButtonConfig.controlGridColumns, slot ~/ ButtonConfig.controlGridColumns);
}

/// Builds a generic ButtonConfig for one of the six legacy motion ids,
/// reproducing exactly what the old per-role/per-axis migration used to
/// build — but with `role: null`, since the button is fully generic from
/// here on.
ButtonConfig buildLegacyMotionButton({
  required String legacyId,
  required AxisControlConfig axisConfig,
  required ButtonStyleConfig style,
  required String label,
}) {
  final (defaultX, defaultY) = legacyCanvasPositionFor(legacyId);
  final (gridX, gridY) = legacyGridPositionFor(legacyId);
  final isPairedSlider =
      axisConfig.widgetType == ControlWidgetType.sliderButton &&
      _isSecondAxisId(legacyId);
  final gridColumns =
      isPairedSlider || axisConfig.widgetType == ControlWidgetType.joystick
      ? 2
      : 1;
  final gridRows = axisConfig.widgetType == ControlWidgetType.joystick ? 2 : 1;
  final migratedType = switch (axisConfig.widgetType) {
    ControlWidgetType.pushButton => ButtonType.pushButton,
    ControlWidgetType.toggle => ButtonType.toggle,
    // The paired axis's slider type has always rendered as the COMBINED
    // MultiZoneSliderButton (both directions in one widget) — preserved here
    // so an old saved layout doesn't silently regress to two independent
    // sliders on migration.
    ControlWidgetType.sliderButton when _isSecondAxisId(legacyId) =>
      ButtonType.bidirectionalSlider5Step,
    ControlWidgetType.sliderButton => ButtonType.sliderButton,
    ControlWidgetType.joystick => ButtonType.joystick,
    ControlWidgetType.rotary => ButtonType.potentiometer,
  };
  final pairedId = _legacyPairedId[legacyId];
  return ButtonConfig(
    id: legacyId,
    type: migratedType,
    plcMapping: _legacyPlcMapping[legacyId]!,
    role: null,
    label: label,
    heightScale: axisConfig.heightScale,
    rotation: ButtonRotation.none,
    style: style,
    behavior: ButtonBehaviorConfig(wiring: axisConfig.wiringConfig),
    mutualExclusion: MutualExclusionConfig(
      excludedButtonIds: pairedId != null ? {pairedId} : const {},
    ),
    canvasX: defaultX,
    canvasY: defaultY,
    slotIndex: legacySlotIndexFor(legacyId),
    gridX: gridX,
    gridY: gridY,
    gridColumns: gridColumns,
    gridRows: gridRows,
    stateMappings: legacyMotionStateMappings(
      legacyId: legacyId,
      type: migratedType,
    ),
    joystickSubButtonMappings: migratedType == ButtonType.joystick
        ? legacyJoystickSubButtonMappings(
            sourceButtonId: legacyId,
            legacyId: legacyId,
            joystickConfig: const JoystickConfig(),
          )
        : const <String, Map<String, ButtonStateOutputMapping>>{},
  );
}

/// Reproduces the OLD role/axis-derived composition behavior as static baked
/// data, one time, so the generic stateMappings-only composer never needs to
/// re-derive it.
///
/// Old derivation being preserved exactly:
///   idle-equivalent state   -> {}
///   level1-equivalent state -> {legacy field}
///   level2-equivalent state -> {legacy field, axis fast field}
Map<String, ButtonStateOutputMapping> legacyMotionStateMappings({
  required String legacyId,
  required ButtonType type,
}) {
  final ownField = _legacyPlcMapping[legacyId];
  if (ownField == null) return const <String, ButtonStateOutputMapping>{};
  final fastField = _legacyFastMapping[legacyId];

  const Set<PlcOutputVariant> idleVariants = {};
  final Set<PlcOutputVariant> level1Variants = {ownField};
  final Set<PlcOutputVariant> level2Variants = {ownField, ?fastField};

  Map<String, ButtonStateOutputMapping> entry(
    String id,
    Set<PlcOutputVariant> variants,
  ) => {id: ButtonStateOutputMapping(stateId: id, activeVariants: variants)};

  switch (type) {
    case ButtonType.pushButton:
      return {
        ...entry('idle', idleVariants),
        ...entry('active', level1Variants),
      };
    case ButtonType.sliderButton:
    case ButtonType.joystick:
      return {
        ...entry('idle', idleVariants),
        ...entry('step1', level1Variants),
        ...entry('step2', level2Variants),
      };
    case ButtonType.potentiometer:
    case ButtonType.horn:
    case ButtonType.alarmIndicator:
    case ButtonType.analogJoystick1D:
    case ButtonType.analogJoystick2D:
    case ButtonType.analogSliderOT:
    case ButtonType.analogSliderTOT:
      return const <String, ButtonStateOutputMapping>{};
    case ButtonType.toggle:
      return {
        ...entry('left', level1Variants),
        ...entry('center', idleVariants),
        ...entry('right', level2Variants),
      };
    case ButtonType.bidirectionalSlider5Step:
      if (legacyId == 'traverseLeft') {
        return {
          ...entry('zone1', level2Variants),
          ...entry('zone2', level1Variants),
          ...entry('center', idleVariants),
          ...entry('zone4', const {}),
          ...entry('zone5', const {}),
        };
      }
      if (legacyId == 'traverseRight') {
        return {
          ...entry('zone1', const {}),
          ...entry('zone2', const {}),
          ...entry('center', idleVariants),
          ...entry('zone4', level1Variants),
          ...entry('zone5', level2Variants),
        };
      }
      return const <String, ButtonStateOutputMapping>{};
    case ButtonType.bidirectionalSlider3Step:
      if (legacyId == 'traverseLeft') {
        return {
          ...entry('zone1', level1Variants),
          ...entry('center', idleVariants),
          ...entry('zone3', const {}),
        };
      }
      if (legacyId == 'traverseRight') {
        return {
          ...entry('zone1', const {}),
          ...entry('center', idleVariants),
          ...entry('zone3', level1Variants),
        };
      }
      return const <String, ButtonStateOutputMapping>{};
  }
}

/// Migration for a joystick's virtual per-direction sub-buttons: reproduces
/// the OLD derivation (own field for step1, own field + axis fast field for
/// step2) as static data, now keyed by the new direction-based virtual ids
/// (see [joystickVirtualButtonId]) instead of the old DF-number-embedded
/// ones. [legacyId] is the parent's own legacy motion id if it has one, or
/// null for a legacy-schema joystick with no fixed role.
Map<String, Map<String, ButtonStateOutputMapping>> legacyJoystickSubButtonMappings({
  required String sourceButtonId,
  required String? legacyId,
  required JoystickConfig joystickConfig,
}) {
  Map<String, ButtonStateOutputMapping> subMappingFor(
    PlcOutputVariant field,
    PlcOutputVariant? fastField,
  ) {
    return {
      'idle': const ButtonStateOutputMapping(stateId: 'idle'),
      'step1': ButtonStateOutputMapping(
        stateId: 'step1',
        activeVariants: {field},
      ),
      'step2': ButtonStateOutputMapping(
        stateId: 'step2',
        activeVariants: {field, ?fastField},
      ),
    };
  }

  if (joystickConfig.isDualAxis) {
    // Dual-axis always drove the second axis (x) + third axis (y) regardless
    // of the parent's own role — matching the old hardcoded pairing exactly.
    return {
      joystickVirtualButtonId(sourceButtonId, JoystickDirection.posX):
          subMappingFor(
            _legacyPlcMapping['traverseRight']!,
            _legacyFastMapping['traverseRight'],
          ),
      joystickVirtualButtonId(sourceButtonId, JoystickDirection.negX):
          subMappingFor(
            _legacyPlcMapping['traverseLeft']!,
            _legacyFastMapping['traverseLeft'],
          ),
      joystickVirtualButtonId(sourceButtonId, JoystickDirection.posY):
          subMappingFor(
            _legacyPlcMapping['travelForward']!,
            _legacyFastMapping['travelForward'],
          ),
      joystickVirtualButtonId(sourceButtonId, JoystickDirection.negY):
          subMappingFor(
            _legacyPlcMapping['travelReverse']!,
            _legacyFastMapping['travelReverse'],
          ),
    };
  }

  final (positiveId, negativeId) = switch (legacyId) {
    'traverseLeft' || 'traverseRight' => ('traverseRight', 'traverseLeft'),
    'travelForward' || 'travelReverse' => ('travelForward', 'travelReverse'),
    _ => ('hoistUp', 'hoistDown'),
  };
  return {
    joystickVirtualButtonId(sourceButtonId, JoystickDirection.posX):
        subMappingFor(
          _legacyPlcMapping[positiveId]!,
          _legacyFastMapping[positiveId],
        ),
    joystickVirtualButtonId(sourceButtonId, JoystickDirection.negX):
        subMappingFor(
          _legacyPlcMapping[negativeId]!,
          _legacyFastMapping[negativeId],
        ),
  };
}

/// Synthesizes the full legacy button-centric map from the pre-v3
/// per-axis/per-role/per-label shape. Pure and idempotent — invoked whenever
/// old-format JSON (no `buttons` key) is parsed, so old saved layouts
/// silently upgrade in memory on load and persist in the new format on the
/// next save.
Map<String, ButtonConfig> synthesizeLegacyButtons({
  required AxisConfigSet axisConfigs,
  required RoleStyleConfig roleStyles,
  required ControlLabelConfig labelConfig,
}) {
  const labelFor = <String, String Function(ControlLabelConfig)>{
    'hoistUp': _upLabel,
    'hoistDown': _downLabel,
    'traverseLeft': _leftLabel,
    'traverseRight': _rightLabel,
    'travelForward': _forwardLabel,
    'travelReverse': _reverseLabel,
  };
  const axisConfigFor = <String, AxisControlConfig Function(AxisConfigSet)>{
    'hoistUp': _primaryAxis,
    'hoistDown': _primaryAxis,
    'traverseLeft': _secondaryAxis,
    'traverseRight': _secondaryAxis,
    'travelForward': _tertiaryAxis,
    'travelReverse': _tertiaryAxis,
  };
  const styleFor = <String, ButtonStyleConfig Function(RoleStyleConfig)>{
    'hoistUp': _slot1Style,
    'hoistDown': _slot2Style,
    'traverseLeft': _slot3Style,
    'traverseRight': _slot4Style,
    'travelForward': _slot5Style,
    'travelReverse': _slot6Style,
  };

  final result = <String, ButtonConfig>{
    ControlRole.estop.name: ButtonConfig.estopDefault(),
    ControlRole.resetEstop.name: ButtonConfig.resetEstopDefault(
      labelConfig.resetEstopLabel,
      style: roleStyles.resetEstop,
    ),
  };
  for (final legacyId in kLegacyMotionButtonIds) {
    result[legacyId] = buildLegacyMotionButton(
      legacyId: legacyId,
      axisConfig: axisConfigFor[legacyId]!(axisConfigs),
      style: styleFor[legacyId]!(roleStyles),
      label: labelFor[legacyId]!(labelConfig),
    );
  }
  return result;
}

String _upLabel(ControlLabelConfig c) => c.legacySlot1Label;
String _downLabel(ControlLabelConfig c) => c.legacySlot2Label;
String _leftLabel(ControlLabelConfig c) => c.legacySlot3Label;
String _rightLabel(ControlLabelConfig c) => c.legacySlot4Label;
String _forwardLabel(ControlLabelConfig c) => c.legacySlot5Label;
String _reverseLabel(ControlLabelConfig c) => c.legacySlot6Label;
AxisControlConfig _primaryAxis(AxisConfigSet c) => c.primary;
AxisControlConfig _secondaryAxis(AxisConfigSet c) => c.secondary;
AxisControlConfig _tertiaryAxis(AxisConfigSet c) => c.tertiary;
ButtonStyleConfig _slot1Style(RoleStyleConfig c) => c.slot1;
ButtonStyleConfig _slot2Style(RoleStyleConfig c) => c.slot2;
ButtonStyleConfig _slot3Style(RoleStyleConfig c) => c.slot3;
ButtonStyleConfig _slot4Style(RoleStyleConfig c) => c.slot4;
ButtonStyleConfig _slot5Style(RoleStyleConfig c) => c.slot5;
ButtonStyleConfig _slot6Style(RoleStyleConfig c) => c.slot6;
