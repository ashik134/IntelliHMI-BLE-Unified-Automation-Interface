import 'package:rev_crane_control_ops/models/app_enums.dart' show LayoutBucket;
import 'package:rev_crane_control_ops/models/button_behavior_config.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/button_state_output_mapping.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/grid_layout_option.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';

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
      description: 'Up/Down/Left/Right push buttons in a 2x2 grid.',
      build: _pushButtonPanel,
    ),
    LayoutTemplate(
      name: 'Large Touch Targets',
      description:
          'Up/Down/Left/Right push buttons in a 2x2 grid, scaled up for '
          'gloved operation.',
      build: _largeTouchTargets,
    ),
  ];

  static ControlLayoutConfig _factoryDefault(LayoutBucket bucket) =>
      ControlLayoutConfig.defaultForBucket(bucket);

  static ControlLayoutConfig _pushButtonPanel(LayoutBucket bucket) {
    final base = ControlLayoutConfig.defaultForBucket(bucket);
    return base.copyWith(
      buttons: {...base.resolvedButtons, ..._fourDirectionButtons()},
      gridLayout: GridLayoutOption.twoByTwo,
    );
  }

  static ControlLayoutConfig _largeTouchTargets(LayoutBucket bucket) {
    final base = ControlLayoutConfig.defaultForBucket(bucket);
    return base.copyWith(
      buttons: {
        ...base.resolvedButtons,
        ..._fourDirectionButtons(heightScale: 1.35),
      },
      gridLayout: GridLayoutOption.twoByTwo,
      sizeConfig: const ControlWidgetSizeConfig(estopButtonHeightScale: 1.25),
    );
  }

  /// Four independent, spring-return push buttons — Up/Down/Left/Right —
  /// placed at the four cells of a [GridLayoutOption.twoByTwo] page grid.
  /// Up/Down share row 0, Left/Right share row 1, matching how those same
  /// four directions were already grouped in the old fixed 2x3 six-slot
  /// grid (hoist axis in the first pair of slots, traverse axis in the
  /// second) — only the forward/reverse third axis's pair of slots is
  /// dropped, since these two templates only ever needed two axes of
  /// motion.
  static Map<String, ButtonConfig> _fourDirectionButtons({
    double heightScale = 1.0,
  }) {
    const wiring = PushButtonWiringConfig.offMomentary;

    ButtonConfig direction({
      required String id,
      required String label,
      required PlcOutputVariant plcMapping,
      required int gridX,
      required int gridY,
    }) {
      return ButtonConfig(
        id: id,
        type: ButtonType.pushButton,
        plcMapping: plcMapping,
        label: label,
        heightScale: heightScale,
        behavior: const ButtonBehaviorConfig(wiring: wiring),
        gridX: gridX,
        gridY: gridY,
        stateMappings: {
          'idle': const ButtonStateOutputMapping(stateId: 'idle'),
          'active': ButtonStateOutputMapping(
            stateId: 'active',
            activeVariants: {plcMapping},
          ),
        },
      );
    }

    return {
      'up': direction(
        id: 'up',
        label: 'Up',
        plcMapping: PlcOutputVariant.df2,
        gridX: 0,
        gridY: 0,
      ),
      'down': direction(
        id: 'down',
        label: 'Down',
        plcMapping: PlcOutputVariant.df3,
        gridX: 1,
        gridY: 0,
      ),
      'left': direction(
        id: 'left',
        label: 'Left',
        plcMapping: PlcOutputVariant.df5,
        gridX: 0,
        gridY: 1,
      ),
      'right': direction(
        id: 'right',
        label: 'Right',
        plcMapping: PlcOutputVariant.df6,
        gridX: 1,
        gridY: 1,
      ),
    };
  }
}
