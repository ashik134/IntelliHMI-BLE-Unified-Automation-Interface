import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/button_state_output_mapping.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/horn_config.dart';
import 'package:rev_crane_control_ops/models/plc_mapping.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';

void main() {
  test('horn config round-trips through JSON with defaults', () {
    const config = HornConfig(
      soundPattern: HornSoundPattern.pulsing,
      hapticFeedback: false,
      visualBeepAnimation: false,
    );

    final restored = HornConfig.fromJson(config.toJson());

    expect(restored, config);
    expect(HornConfig.fromJson(const {}).soundPattern, HornSoundPattern.steady);
    expect(HornConfig.fromJson(const {}).hapticFeedback, true);
  });

  test('ButtonConfig persists horn custom properties', () {
    const horn = HornConfig(
      soundPattern: HornSoundPattern.doubleBeep,
      hapticFeedback: true,
      visualBeepAnimation: true,
    );
    final config = ButtonConfig(
      id: 'custom_horn',
      type: ButtonType.horn,
      plcMapping: PlcMapping.up,
      label: 'Horn',
      customProperties: horn.applyToCustomProperties(const {}),
    );

    final restored = ButtonConfig.fromJson(config.toJson());
    final restoredHorn = HornConfig.fromCustomProperties(
      restored.customProperties,
    );

    expect(restored.type, ButtonType.horn);
    expect(restoredHorn.soundPattern, HornSoundPattern.doubleBeep);
  });

  test('horn resolves to real idle/active digital command mapping', () {
    const layout = ControlLayoutConfig(
      buttons: {
        'custom_horn': ButtonConfig(
          id: 'custom_horn',
          type: ButtonType.horn,
          plcMapping: PlcMapping.up,
          label: 'Horn',
          stateMappings: {
            'idle': ButtonStateOutputMapping(stateId: 'idle'),
            'active': ButtonStateOutputMapping(
              stateId: 'active',
              activeVariants: {PlcMapping.up},
            ),
          },
        ),
      },
    );

    final idleResolved = resolveButtonCommand(
      buttonId: 'custom_horn',
      state: ControlState.idle,
      layoutCfg: layout,
    );
    final activeResolved = resolveButtonCommand(
      buttonId: 'custom_horn',
      state: ControlState.slow,
      layoutCfg: layout,
    );

    expect(idleResolved.stateId, 'idle');
    expect(idleResolved.activeVariants, isEmpty);
    expect(activeResolved.stateId, 'active');
    expect(activeResolved.activeVariants, {PlcMapping.up});
  });
}
