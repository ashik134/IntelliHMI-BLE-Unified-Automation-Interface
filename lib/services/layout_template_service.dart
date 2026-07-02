import 'package:rev_crane_control_ops/models/control_layout_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LayoutTemplateService
//
// Built-in starting-point layouts an operator can load into the draft during
// Customization Mode (still requires Apply to persist — loading a template
// is just another draft mutation, fully undoable/discardable). Kept to a
// small, curated set rather than a general template CRUD system.
// ─────────────────────────────────────────────────────────────────────────────

class LayoutTemplate {
  const LayoutTemplate({
    required this.name,
    required this.description,
    required this.build,
  });

  final String name;
  final String description;
  final ControlLayoutConfig Function() build;
}

class LayoutTemplateService {
  const LayoutTemplateService();

  List<LayoutTemplate> get templates => const [
    LayoutTemplate(
      name: 'Factory Default',
      description: 'Sliders on every axis, standard sizing.',
      build: _factoryDefault,
    ),
    LayoutTemplate(
      name: 'Push Button Panel',
      description: 'Spring-return push buttons on every axis.',
      build: _pushButtonPanel,
    ),
    LayoutTemplate(
      name: 'Large Touch Targets',
      description: 'Push buttons scaled up for gloved operation.',
      build: _largeTouchTargets,
    ),
  ];

  static ControlLayoutConfig _factoryDefault() => const ControlLayoutConfig();

  static ControlLayoutConfig _pushButtonPanel() {
    const axisCfg = AxisControlConfig(
      widgetType: ControlWidgetType.pushButton,
      wiringConfig: PushButtonWiringConfig.offMomentary,
    );
    return const ControlLayoutConfig().copyWith(
      axisConfigs: const AxisConfigSet(
        hoist: axisCfg,
        traverse: axisCfg,
        travel: axisCfg,
      ),
    );
  }

  static ControlLayoutConfig _largeTouchTargets() {
    const axisCfg = AxisControlConfig(
      widgetType: ControlWidgetType.pushButton,
      wiringConfig: PushButtonWiringConfig.offMomentary,
      heightScale: 1.35,
    );
    return const ControlLayoutConfig().copyWith(
      axisConfigs: const AxisConfigSet(
        hoist: axisCfg,
        traverse: axisCfg,
        travel: axisCfg,
      ),
      sizeConfig: const ControlWidgetSizeConfig(estopButtonHeightScale: 1.25),
    );
  }
}
