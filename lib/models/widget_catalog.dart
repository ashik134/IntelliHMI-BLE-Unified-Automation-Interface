import 'package:flutter/widgets.dart' show Size;

import 'package:rev_crane_control_ops/models/analog_joystick_config.dart';
import 'package:rev_crane_control_ops/models/analog_slider_config.dart';
import 'package:rev_crane_control_ops/models/button_behavior_config.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart'
    show PushButtonWiringConfig;
import 'package:rev_crane_control_ops/models/joystick_config.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/models/potentiometer_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Widget Catalogue registry
//
// The single source of truth for the Widgets page (see widget_catalog_screen.
// dart): every entry here is a pure data definition — category, subgroup,
// display copy, and exactly enough ButtonType/behavior/customProperties to
// build a real (but inert) preview via ConfigurableButton. The screen itself
// never hardcodes a widget list; it only groups and renders [kWidgetCatalog].
// Registering a new variant is purely additive — append an entry, no screen
// changes required (see CatalogEntry.buildPreviewConfig).
// ─────────────────────────────────────────────────────────────────────────────

enum CatalogCategory { digitalControls, analogControls, feedbackAndStatus }

extension CatalogCategoryInfo on CatalogCategory {
  String get displayName => switch (this) {
    CatalogCategory.digitalControls => 'Digital Controls',
    CatalogCategory.analogControls => 'Analog Controls',
    CatalogCategory.feedbackAndStatus => 'Feedback and Status',
  };
}

class CatalogEntry {
  const CatalogEntry({
    required this.category,
    required this.group,
    required this.name,
    this.notation,
    required this.description,
    required this.tags,
    required this.buttonType,
    this.customProperties = const <String, dynamic>{},
    this.behavior = const ButtonBehaviorConfig(),
    required this.previewSize,
  });

  /// Stable identity for a catalogue entry, persisted on any [ButtonConfig]
  /// placed from it (see `ButtonConfig.catalogEntryId`) so "Reset to
  /// default" can restore this exact variant later — several entries share
  /// one [ButtonType] with different `behavior`/`customProperties` (e.g. the
  /// two push-button variants), so [buttonType] alone is ambiguous.
  /// Derived from category/group/name, which are unique per entry in
  /// [kWidgetCatalog] today; never renamed once shipped, since existing
  /// saved layouts reference it by this exact string.
  String get id => '${category.name}.$group.$name';

  /// Page section, e.g. "Digital Controls".
  final CatalogCategory category;

  /// Control-family subgroup within the category, e.g. "Sliders".
  final String group;

  final String name;

  /// Compact position notation (e.g. "T–O–R"), shown only when non-null.
  final String? notation;

  final String description;
  final List<String> tags;
  final ButtonType buttonType;
  final Map<String, dynamic> customProperties;
  final ButtonBehaviorConfig behavior;

  /// The control's natural, undistorted size — the preview card scales this
  /// down uniformly (never stretched/cropped) to fit its fixed-height stage.
  final Size previewSize;

  /// Same static footprint table every grid-placed button already uses —
  /// shown on the card as "cols × rows", purely informational at this stage.
  (int, int) get gridSize =>
      ButtonConfig.defaultGridSizeFor(buttonType, customProperties: customProperties);

  /// A throwaway, never-persisted config used only to drive a safe preview
  /// (see CatalogPreviewStage) — inert until an operator explicitly places
  /// and configures a real button, matching every other freshly-created
  /// ButtonConfig's "empty stateMappings = inert" convention.
  ButtonConfig buildPreviewConfig() => ButtonConfig(
    id: 'catalog_preview_${category.name}_${group}_$name',
    type: buttonType,
    plcMapping: PlcOutputVariant.df2,
    label: name,
    behavior: behavior,
    customProperties: customProperties,
  );
}

const _digital = CatalogCategory.digitalControls;
const _analog = CatalogCategory.analogControls;

/// The complete, ordered widget catalogue. Render order follows this list:
/// category (enum declaration order), then subgroup (first-seen order
/// within that category) — see groupCatalog().
final List<CatalogEntry> kWidgetCatalog = [
  // ── Digital Controls › Sliders ──────────────────────────────────────────
  const CatalogEntry(
    category: _digital,
    group: 'Sliders',
    name: '3-Step Spring-Return Slider',
    notation: 'O → Step 1 → Step 2',
    description:
        'Three-position momentary slider that returns to the neutral '
        'position after release.',
    tags: ['Digital', '3-Step', 'Spring Return'],
    buttonType: ButtonType.sliderButton,
    previewSize: Size(110, 260),
  ),
  const CatalogEntry(
    category: _digital,
    group: 'Sliders',
    name: '5-Step Bidirectional Spring-Return Slider',
    notation: 'Step 2 ← Step 1 ← O → Step 3 → Step 4',
    description:
        'Bidirectional momentary slider with two progressive stages on '
        'each side of a centred neutral position.',
    tags: ['Digital', '5-Step', 'Bidirectional', 'Spring Return'],
    buttonType: ButtonType.bidirectionalSlider5Step,
    previewSize: Size(260, 120),
  ),
  const CatalogEntry(
    category: _digital,
    group: 'Sliders',
    name: '3-Step Bidirectional Spring-Return Slider',
    notation: 'Step 1 ← O → Step 2',
    description:
        'Three-position bidirectional slider with a centred neutral '
        'position and spring return from both directions.',
    tags: ['Digital', '3-Step', 'Bidirectional', 'Spring Return'],
    buttonType: ButtonType.bidirectionalSlider3Step,
    previewSize: Size(240, 120),
  ),

  // ── Digital Controls › Push Buttons ─────────────────────────────────────
  const CatalogEntry(
    category: _digital,
    group: 'Push Buttons',
    name: 'Latching Push Button',
    description:
        'Digital push button that retains its active state until it is '
        'pressed again or reset.',
    tags: ['Digital', 'Latching'],
    buttonType: ButtonType.pushButton,
    behavior: ButtonBehaviorConfig(wiring: PushButtonWiringConfig.offLatched),
    previewSize: Size(130, 130),
  ),
  const CatalogEntry(
    category: _digital,
    group: 'Push Buttons',
    name: 'Spring-Return Push Button',
    description:
        'Momentary digital push button that returns to its inactive state '
        'after release.',
    tags: ['Digital', 'Spring Return'],
    buttonType: ButtonType.pushButton,
    behavior: ButtonBehaviorConfig(
      wiring: PushButtonWiringConfig.offMomentary,
    ),
    previewSize: Size(130, 130),
  ),

  // ── Digital Controls › Toggle Buttons ───────────────────────────────────
  const CatalogEntry(
    category: _digital,
    group: 'Toggle Buttons',
    name: 'Off–Return Toggle',
    notation: 'O–R',
    description:
        'A two-position toggle containing a stable off position and a '
        'momentary spring-return position.',
    tags: ['Digital', '2-Position', 'Spring Return'],
    buttonType: ButtonType.toggle,
    behavior: ButtonBehaviorConfig(
      wiring: PushButtonWiringConfig.offMomentary,
    ),
    previewSize: Size(120, 230),
  ),
  const CatalogEntry(
    category: _digital,
    group: 'Toggle Buttons',
    name: 'Off–Retained Toggle',
    notation: 'O–T',
    description:
        'A two-position toggle containing a stable off position and a '
        'retained active position.',
    tags: ['Digital', '2-Position', 'Retained'],
    buttonType: ButtonType.toggle,
    behavior: ButtonBehaviorConfig(wiring: PushButtonWiringConfig.offLatched),
    previewSize: Size(120, 230),
  ),
  const CatalogEntry(
    category: _digital,
    group: 'Toggle Buttons',
    name: 'Return–Off–Return Toggle',
    notation: 'R–O–R',
    description:
        'A three-position toggle with a stable centre-off position and '
        'spring-return operation on both sides.',
    tags: ['Digital', '3-Position', 'Spring Return'],
    buttonType: ButtonType.toggle,
    behavior: ButtonBehaviorConfig(
      wiring: PushButtonWiringConfig.springReturnBoth,
    ),
    previewSize: Size(120, 230),
  ),
  const CatalogEntry(
    category: _digital,
    group: 'Toggle Buttons',
    name: 'Retained–Off–Retained Toggle',
    notation: 'T–O–T',
    description:
        'A three-position toggle with retained positions on both sides '
        'and a stable centre-off position.',
    tags: ['Digital', '3-Position', 'Retained'],
    buttonType: ButtonType.toggle,
    behavior: ButtonBehaviorConfig(
      wiring: PushButtonWiringConfig.latchingBoth,
    ),
    previewSize: Size(120, 230),
  ),
  const CatalogEntry(
    category: _digital,
    group: 'Toggle Buttons',
    name: 'Retained–Off–Return Toggle',
    notation: 'T–O–R',
    description:
        'A three-position toggle with a retained position on one side, a '
        'stable centre-off position and a spring-return position on the '
        'other side.',
    tags: ['Digital', '3-Position', 'Mixed'],
    buttonType: ButtonType.toggle,
    behavior: ButtonBehaviorConfig(
      wiring: PushButtonWiringConfig.mixedLeftLatchRightSpring,
    ),
    previewSize: Size(120, 230),
  ),

  // ── Digital Controls › Joysticks ────────────────────────────────────────
  CatalogEntry(
    category: _digital,
    group: 'Joysticks',
    name: '1D Digital Joystick',
    description:
        'Single-axis spring-return joystick that produces discrete digital '
        'directional states.',
    tags: const ['Digital', '1-Axis', 'Spring Return'],
    buttonType: ButtonType.joystick,
    customProperties: const JoystickConfig(
      mode: JoystickMode.singleAxisDigital5,
      axis: JoystickAxis.vertical,
    ).applyToCustomProperties(const {}),
    previewSize: const Size(130, 230),
  ),
  CatalogEntry(
    category: _digital,
    group: 'Joysticks',
    name: '2D Digital Joystick',
    description:
        'Two-axis spring-return joystick that produces discrete digital '
        'directional zones.',
    tags: const ['Digital', '2-Axis', 'Spring Return'],
    buttonType: ButtonType.joystick,
    customProperties: const JoystickConfig(
      mode: JoystickMode.dualAxisDigital4,
    ).applyToCustomProperties(const {}),
    previewSize: const Size(220, 220),
  ),

  // ── Analog Controls › Potentiometers ────────────────────────────────────
  CatalogEntry(
    category: _analog,
    group: 'Potentiometers',
    name: 'Spring-Return Potentiometer',
    description:
        'Continuous analog rotary control that returns to its configured '
        'default value after release.',
    tags: const ['Analog', 'Spring Return'],
    buttonType: ButtonType.potentiometer,
    customProperties: const PotentiometerConfig(
      defaultValue: 0,
    ).applyToCustomProperties(const {}),
    previewSize: const Size(150, 150),
  ),
  CatalogEntry(
    category: _analog,
    group: 'Potentiometers',
    name: 'Retained-Position Potentiometer',
    description:
        'Continuous analog rotary control that remains at the value '
        'selected by the user.',
    tags: const ['Analog', 'Retained'],
    buttonType: ButtonType.potentiometer,
    customProperties: const PotentiometerConfig(
      defaultValue: 50,
    ).applyToCustomProperties(const {}),
    previewSize: const Size(150, 150),
  ),

  // ── Analog Controls › Analog Sliders ────────────────────────────────────
  // Registered as three independent entries over the same two underlying
  // ButtonTypes — proof the catalogue can grow new analog-slider variants
  // (e.g. a future one-sided spring-return) by adding another entry here,
  // never by touching the screen or the rendering pipeline.
  CatalogEntry(
    category: _analog,
    group: 'Analog Sliders',
    name: 'Neutral-to-Retained Analog Slider',
    notation: 'O–T',
    description:
        'Continuous analog slider that starts from a neutral position and '
        'retains the selected value.',
    tags: const ['Analog', 'Retained'],
    buttonType: ButtonType.analogSliderOT,
    customProperties: const AnalogSliderConfig(
      neutralValue: 0,
      springReturnEnabled: false,
    ).applyToCustomProperties(const {}),
    previewSize: const Size(110, 260),
  ),
  CatalogEntry(
    category: _analog,
    group: 'Analog Sliders',
    name: 'Bidirectional Retained Analog Slider',
    notation: 'T–O–T',
    description:
        'Continuous bidirectional analog slider with a centred neutral '
        'position and retained values on both sides.',
    tags: const ['Analog', 'Retained', 'Bidirectional'],
    buttonType: ButtonType.analogSliderTOT,
    customProperties: const AnalogSliderConfig(
      minValue: -100,
      maxValue: 100,
      neutralValue: 0,
      springReturnEnabled: false,
    ).applyToCustomProperties(const {}),
    previewSize: const Size(110, 260),
  ),
  CatalogEntry(
    category: _analog,
    group: 'Analog Sliders',
    name: 'Bidirectional Spring-Return Analog Slider',
    notation: 'R–O–R',
    description:
        'Continuous bidirectional analog slider that returns to its '
        'centred neutral value after release.',
    tags: const ['Analog', 'Spring Return', 'Bidirectional'],
    buttonType: ButtonType.analogSliderTOT,
    customProperties: const AnalogSliderConfig(
      minValue: -100,
      maxValue: 100,
      neutralValue: 0,
      springReturnEnabled: true,
    ).applyToCustomProperties(const {}),
    previewSize: const Size(110, 260),
  ),

  // ── Analog Controls › Analog Joysticks ──────────────────────────────────
  CatalogEntry(
    category: _analog,
    group: 'Analog Joysticks',
    name: '1D Analog Joystick',
    description: 'Single-axis joystick that produces a continuous analog value.',
    tags: const ['Analog', '1-Axis'],
    buttonType: ButtonType.analogJoystick1D,
    customProperties: const AnalogJoystickConfig().applyToCustomProperties(
      const {},
    ),
    previewSize: const Size(130, 230),
  ),
  CatalogEntry(
    category: _analog,
    group: 'Analog Joysticks',
    name: '2D Analog Joystick',
    description:
        'Two-axis joystick that produces continuous X-axis and Y-axis '
        'values.',
    tags: const ['Analog', '2-Axis'],
    buttonType: ButtonType.analogJoystick2D,
    customProperties: const AnalogJoystickConfig().applyToCustomProperties(
      const {},
    ),
    previewSize: const Size(220, 220),
  ),
];

/// Groups [kWidgetCatalog] into category -> subgroup -> entries, preserving
/// [CatalogCategory]'s declaration order for categories and first-seen order
/// for subgroups within each category. A category/subgroup with zero
/// entries (e.g. Feedback and Status today — see CatalogCategory doc) simply
/// never appears, so the screen never has to special-case emptiness.
Map<CatalogCategory, Map<String, List<CatalogEntry>>> groupCatalog(
  List<CatalogEntry> entries,
) {
  final byCategory = <CatalogCategory, Map<String, List<CatalogEntry>>>{};
  for (final entry in entries) {
    final byGroup = byCategory.putIfAbsent(entry.category, () => {});
    byGroup.putIfAbsent(entry.group, () => []).add(entry);
  }
  return byCategory;
}
