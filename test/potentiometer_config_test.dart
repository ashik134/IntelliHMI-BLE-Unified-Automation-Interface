import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/plc_mapping.dart';
import 'package:rev_crane_control_ops/models/potentiometer_config.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';

void main() {
  test('potentiometer config normalizes ranges and snaps to step size', () {
    const config = PotentiometerConfig(
      minValue: -100,
      maxValue: 100,
      stepSize: 5,
      defaultValue: 12,
      unit: '%',
    );

    final normalized = config.normalized();

    expect(normalized.defaultValue, 10);
    expect(normalized.clampAndSnap(13), 15);
    expect(normalized.formatValue(13), '15%');
    expect(normalized.valueForNormalized(0.5), 0);
  });

  test('ButtonConfig persists potentiometer custom properties', () {
    const potentiometer = PotentiometerConfig(
      minValue: 0,
      maxValue: 1023,
      stepSize: 1,
      defaultValue: 512,
      unit: '',
      outputVariantId: 'a4',
      outputChannel: 'AO1',
    );
    final config = ButtonConfig(
      id: 'custom_pot',
      type: ButtonType.potentiometer,
      plcMapping: PlcMapping.up,
      label: 'Analog',
      customProperties: potentiometer.applyToCustomProperties(const {}),
    );

    final restored = ButtonConfig.fromJson(config.toJson());
    final restoredPot = PotentiometerConfig.fromCustomProperties(
      restored.customProperties,
    );

    expect(restored.type, ButtonType.potentiometer);
    expect(restored.stateMappings, isEmpty);
    expect(restoredPot.maxValue, 1023);
    expect(restoredPot.defaultValue, 512);
    expect(restoredPot.outputVariantId, 'a4');
    expect(restoredPot.outputChannel, 'AO1');
  });

  test('potentiometer resolves to inert digital command mapping', () {
    const layout = ControlLayoutConfig(
      buttons: {
        'custom_pot': ButtonConfig(
          id: 'custom_pot',
          type: ButtonType.potentiometer,
          plcMapping: PlcMapping.up,
          label: 'Analog',
        ),
      },
    );

    final resolved = resolveButtonCommand(
      buttonId: 'custom_pot',
      state: ControlState.fast,
      layoutCfg: layout,
    );

    expect(resolved.stateId, 'analog');
    expect(resolved.activeVariants, isEmpty);
  });
}
