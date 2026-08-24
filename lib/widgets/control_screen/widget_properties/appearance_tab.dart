import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/color_picker_field.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/general_tab.dart' show ButtonUpdater;
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/property_field_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AppearanceTab
//
// Colors, corner radius, elevation, icon size, label font — all backed by
// the existing ButtonStyleConfig, which every strategy already resolves at
// render time. Only two color fields exist on the model
// (primaryColor/activeColor); this tab relabels them per family instead of
// adding new per-family color fields — see multi_zone_slider_strategy.dart /
// slider_button_strategy.dart, which already reuse them this way.
// ─────────────────────────────────────────────────────────────────────────────

(String, String) colorLabelsFor(ButtonType type) => switch (type) {
  ButtonType.pushButton => ('Button color', 'Active glow color'),
  ButtonType.toggle => ('Lever accent color', 'Active highlight color'),
  ButtonType.sliderButton => ('Step 1 color', 'Step 2 color'),
  ButtonType.bidirectionalSlider5Step ||
  ButtonType.bidirectionalSlider3Step => ('Near-zone color', 'Far-zone color'),
  ButtonType.joystick ||
  ButtonType.analogJoystick1D ||
  ButtonType.analogJoystick2D => ('Knob color', 'Active highlight color'),
  ButtonType.potentiometer ||
  ButtonType.potentiometerCenterOff => ('Knob / track color', 'Active highlight color'),
  ButtonType.analogSliderOT ||
  ButtonType.analogSliderTOT => ('Track fill color', 'Active highlight color'),
  ButtonType.horn || ButtonType.alarmIndicator => ('Primary color', 'Active color'),
};

const List<(FontWeight, String)> _kFontWeightOptions = [
  (FontWeight.w400, 'Regular'),
  (FontWeight.w500, 'Medium'),
  (FontWeight.w600, 'Semibold'),
  (FontWeight.w700, 'Bold'),
  (FontWeight.w800, 'X-Bold'),
  (FontWeight.w900, 'Black'),
];

class AppearanceTab extends StatelessWidget {
  const AppearanceTab({
    super.key,
    required this.config,
    required this.onUpdate,
  });

  final ButtonConfig config;
  final ButtonUpdater onUpdate;

  @override
  Widget build(BuildContext context) {
    final style = config.style;
    final (primaryLabel, activeLabel) = colorLabelsFor(config.type);

    void updateStyle(ButtonStyleConfig Function(ButtonStyleConfig) f) {
      onUpdate((b) => b.copyWith(style: f(b.style)));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      children: [
        const PropertySectionHeader('Colors', padTop: 4),
        PropertyColorField(
          label: primaryLabel,
          value: style.primaryColor,
          onChanged: (c) => updateStyle(
            (s) => c == null
                ? s.copyWith(clearPrimaryColor: true)
                : s.copyWith(primaryColor: c),
          ),
        ),
        PropertyColorField(
          label: activeLabel,
          value: style.activeColor,
          onChanged: (c) => updateStyle(
            (s) => c == null
                ? s.copyWith(clearActiveColor: true)
                : s.copyWith(activeColor: c),
          ),
        ),
        const PropertySectionHeader('Shape'),
        PropertyLabeledSlider(
          label: 'Corner radius',
          value: style.cornerRadius ?? 12,
          min: ButtonStyleConfig.minCornerRadius,
          max: ButtonStyleConfig.maxCornerRadius,
          valueLabel: (style.cornerRadius ?? 12).toStringAsFixed(0),
          onChanged: (v) => updateStyle((s) => s.copyWith(cornerRadius: v)),
        ),
        PropertyLabeledSlider(
          label: 'Elevation / shadow',
          value: style.elevation ?? 2,
          min: ButtonStyleConfig.minElevation,
          max: ButtonStyleConfig.maxElevation,
          valueLabel: (style.elevation ?? 2).toStringAsFixed(1),
          onChanged: (v) => updateStyle((s) => s.copyWith(elevation: v)),
        ),
        const PropertySectionHeader('Icon & Label'),
        PropertyLabeledSlider(
          label: 'Icon size',
          value: style.iconSize ?? 16,
          min: ButtonStyleConfig.minIconSize,
          max: ButtonStyleConfig.maxIconSize,
          valueLabel: (style.iconSize ?? 16).toStringAsFixed(0),
          onChanged: (v) => updateStyle((s) => s.copyWith(iconSize: v)),
        ),
        PropertyLabeledSlider(
          label: 'Label font size',
          value: style.labelFontSize ?? 11,
          min: ButtonStyleConfig.minLabelFontSize,
          max: ButtonStyleConfig.maxLabelFontSize,
          valueLabel: (style.labelFontSize ?? 11).toStringAsFixed(0),
          onChanged: (v) => updateStyle((s) => s.copyWith(labelFontSize: v)),
        ),
        const SizedBox(height: 4),
        const Text(
          'Label font weight',
          style: TextStyle(
            color: Color(0xFFF3F6F9),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        PropertySegmented<FontWeight>(
          options: _kFontWeightOptions,
          selected: style.labelFontWeight ?? FontWeight.w700,
          onChanged: (w) => updateStyle((s) => s.copyWith(labelFontWeight: w)),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
