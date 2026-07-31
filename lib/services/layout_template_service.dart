import 'package:rev_crane_control_ops/models/app_enums.dart' show LayoutBucket;
import 'package:rev_crane_control_ops/models/control_layout_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LayoutTemplateService
//
// Built-in starting-point layouts a future layout editor can load into a
// draft (still requires an explicit save/apply step to persist — loading a
// template is just another draft mutation, fully undoable/discardable).
// Kept to a small, curated set rather than a general template CRUD system.
// ─────────────────────────────────────────────────────────────────────────────

class LayoutTemplate {
  const LayoutTemplate({
    required this.name,
    required this.description,
    required this.build,
  });

  final String name;
  final String description;
  final ControlLayoutConfig Function(LayoutBucket bucket) build;
}

class LayoutTemplateService {
  const LayoutTemplateService();

  List<LayoutTemplate> get templates => const [
    LayoutTemplate(
      name: 'Factory Default',
      description: 'Factory controls for the connected PLC type.',
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

  static ControlLayoutConfig _factoryDefault(LayoutBucket bucket) =>
      ControlLayoutConfig.defaultForBucket(bucket);

  static ControlLayoutConfig _pushButtonPanel(LayoutBucket bucket) {
    const axisCfg = AxisControlConfig(
      widgetType: ControlWidgetType.pushButton,
      wiringConfig: PushButtonWiringConfig.offMomentary,
    );
    const axisConfigs = AxisConfigSet(
      primary: axisCfg,
      secondary: axisCfg,
      tertiary: axisCfg,
    );
    return ControlLayoutConfig.defaultForBucket(bucket).copyWith(
      axisConfigs: axisConfigs,
      buttons: ControlLayoutConfig.buttonsFromLegacy(axisConfigs: axisConfigs),
    );
  }

  static ControlLayoutConfig _largeTouchTargets(LayoutBucket bucket) {
    const axisCfg = AxisControlConfig(
      widgetType: ControlWidgetType.pushButton,
      wiringConfig: PushButtonWiringConfig.offMomentary,
      heightScale: 1.35,
    );
    const axisConfigs = AxisConfigSet(
      primary: axisCfg,
      secondary: axisCfg,
      tertiary: axisCfg,
    );
    return ControlLayoutConfig.defaultForBucket(bucket).copyWith(
      axisConfigs: axisConfigs,
      sizeConfig: const ControlWidgetSizeConfig(estopButtonHeightScale: 1.25),
      buttons: ControlLayoutConfig.buttonsFromLegacy(axisConfigs: axisConfigs),
    );
  }
}
