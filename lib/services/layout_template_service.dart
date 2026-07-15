import 'package:rev_crane_control_ops/models/app_enums.dart' show LayoutBucket;
import 'package:rev_crane_control_ops/models/button_config.dart';
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
      hoist: axisCfg,
      traverse: axisCfg,
      travel: axisCfg,
    );
    return ControlLayoutConfig.defaultForBucket(bucket).copyWith(
      axisConfigs: axisConfigs,
      buttons: _buttonsForBucketTemplate(bucket, axisConfigs: axisConfigs),
    );
  }

  static ControlLayoutConfig _largeTouchTargets(LayoutBucket bucket) {
    const axisCfg = AxisControlConfig(
      widgetType: ControlWidgetType.pushButton,
      wiringConfig: PushButtonWiringConfig.offMomentary,
      heightScale: 1.35,
    );
    const axisConfigs = AxisConfigSet(
      hoist: axisCfg,
      traverse: axisCfg,
      travel: axisCfg,
    );
    return ControlLayoutConfig.defaultForBucket(bucket).copyWith(
      axisConfigs: axisConfigs,
      sizeConfig: const ControlWidgetSizeConfig(estopButtonHeightScale: 1.25),
      buttons: _buttonsForBucketTemplate(bucket, axisConfigs: axisConfigs),
    );
  }

  static Map<String, ButtonConfig> _buttonsForBucketTemplate(
    LayoutBucket bucket, {
    required AxisConfigSet axisConfigs,
  }) {
    final bucketDefault = ControlLayoutConfig.defaultForBucket(bucket);
    final templateButtons = ControlLayoutConfig.buttonsFromLegacy(
      axisConfigs: axisConfigs,
    );
    if (bucket == LayoutBucket.plc38) {
      return templateButtons;
    }

    return {
      for (final entry in templateButtons.entries)
        entry.key: entry.value.copyWith(
          visible: bucketDefault.resolvedButtons[entry.key]?.visible,
          pageIndex: bucketDefault.resolvedButtons[entry.key]?.pageIndex,
          gridX: bucketDefault.resolvedButtons[entry.key]?.gridX,
          gridY: bucketDefault.resolvedButtons[entry.key]?.gridY,
          gridColumns: bucketDefault.resolvedButtons[entry.key]?.gridColumns,
          gridRows: bucketDefault.resolvedButtons[entry.key]?.gridRows,
          slotIndex: bucketDefault.resolvedButtons[entry.key]?.slotIndex,
        ),
    };
  }
}
