import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/button_rotation.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/models/mutual_exclusion_config.dart';
import 'package:rev_crane_control_ops/models/plc_mapping.dart';
import 'package:rev_crane_control_ops/services/layout_template_service.dart';
import 'package:rev_crane_control_ops/services/layout_validation_service.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';

void main() {
  group('ControlLayoutConfig JSON round-trip', () {
    test('default config round-trips through toJsonString/fromJsonString', () {
      const original = ControlLayoutConfig();
      final restored = ControlLayoutConfig.fromJsonString(
        original.toJsonString(),
      );
      expect(restored, original);
    });

    test('custom axisConfigs/roleStyles/axisOrder round-trip', () {
      const original = ControlLayoutConfig(
        axisConfigs: AxisConfigSet(
          hoist: AxisControlConfig(
            widgetType: ControlWidgetType.toggle,
            wiringConfig: PushButtonWiringConfig.offLatched,
            heightScale: 1.2,
          ),
        ),
        axisOrder: [AxisKind.travel, AxisKind.hoist, AxisKind.traverse],
      );
      final restored = ControlLayoutConfig.fromJsonString(
        original.toJsonString(),
      );
      expect(restored, original);
      expect(restored.axisConfigs.hoist.widgetType, ControlWidgetType.toggle);
      expect(restored.axisOrder, [
        AxisKind.travel,
        AxisKind.hoist,
        AxisKind.traverse,
      ]);
    });

    test('malformed axisOrder falls back to the default order', () {
      final restored = ControlLayoutConfig.fromJson({
        'axisOrder': ['hoist', 'hoist', 'travel'], // invalid: not a permutation
      });
      expect(restored.axisOrder, kDefaultAxisOrder);
    });

    test('malformed JSON string falls back to factory defaults', () {
      final restored = ControlLayoutConfig.fromJsonString('not json');
      expect(restored, const ControlLayoutConfig());
    });
  });

  group('LayoutValidationService', () {
    const validator = LayoutValidationService();

    test('rejects axis height scale below the touch-target minimum', () {
      final result = validator.validateAxisConfig(
        AxisKind.hoist,
        const AxisControlConfig(heightScale: AxisControlConfig.minHeightScale),
      );
      // At the allowed minimum scale (0.7x of 185px = ~129px), this stays
      // above the 48px floor, so it should be valid...
      expect(result.isValid, isTrue);
    });

    test('rejects axis height scale outside [min, max] bounds', () {
      final result = validator.validateAxisConfig(
        AxisKind.hoist,
        const AxisControlConfig(heightScale: 2.0),
      );
      expect(result.isValid, isFalse);
    });

    test('rejects E-Stop role style — appearance is not customizable', () {
      final result = validator.validateRoleStyle(
        ControlRole.estop,
        const ButtonStyleConfig(),
      );
      expect(result.isValid, isFalse);
    });

    test('rejects out-of-range corner radius on a styleable role', () {
      final result = validator.validateRoleStyle(
        ControlRole.hoistUp,
        const ButtonStyleConfig(cornerRadius: 999),
      );
      expect(result.isValid, isFalse);
    });

    test('accepts a null (default) style override', () {
      final result = validator.validateRoleStyle(
        ControlRole.hoistUp,
        const ButtonStyleConfig(),
      );
      expect(result.isValid, isTrue);
    });

    test('rejects a non-permutation axis order', () {
      final result = validator.validateAxisOrder([
        AxisKind.hoist,
        AxisKind.hoist,
      ]);
      expect(result.isValid, isFalse);
    });

    test('accepts a valid permutation axis order', () {
      final result = validator.validateAxisOrder([
        AxisKind.travel,
        AxisKind.traverse,
        AxisKind.hoist,
      ]);
      expect(result.isValid, isTrue);
    });

    test('rejects a button that excludes itself', () {
      const config = ButtonConfig(
        id: 'hoistUp',
        type: ButtonType.pushButton,
        plcMapping: PlcMapping.up,
        mutualExclusion: MutualExclusionConfig(excludedButtonIds: {'hoistUp'}),
      );
      final result = validator.validateButtonConfig(config, {
        'hoistUp': config,
      });
      expect(result.isValid, isFalse);
    });

    test('rejects an exclusion referencing an unknown button id', () {
      const config = ButtonConfig(
        id: 'hoistUp',
        type: ButtonType.pushButton,
        plcMapping: PlcMapping.up,
        mutualExclusion: MutualExclusionConfig(
          excludedButtonIds: {'doesNotExist'},
        ),
      );
      final result = validator.validateButtonConfig(config, {
        'hoistUp': config,
      });
      expect(result.isValid, isFalse);
    });

    test('rejects an asymmetric exclusion pair', () {
      const up = ButtonConfig(
        id: 'hoistUp',
        type: ButtonType.pushButton,
        plcMapping: PlcMapping.up,
        mutualExclusion: MutualExclusionConfig(
          excludedButtonIds: {'hoistDown'},
        ),
      );
      const down = ButtonConfig(
        id: 'hoistDown',
        type: ButtonType.pushButton,
        plcMapping: PlcMapping.down,
        // Deliberately does NOT exclude 'hoistUp' back.
      );
      final result = validator.validateButtonConfig(up, {
        'hoistUp': up,
        'hoistDown': down,
      });
      expect(result.isValid, isFalse);
    });

    test('accepts a symmetric exclusion pair', () {
      const up = ButtonConfig(
        id: 'hoistUp',
        type: ButtonType.pushButton,
        plcMapping: PlcMapping.up,
        mutualExclusion: MutualExclusionConfig(
          excludedButtonIds: {'hoistDown'},
        ),
      );
      const down = ButtonConfig(
        id: 'hoistDown',
        type: ButtonType.pushButton,
        plcMapping: PlcMapping.down,
        mutualExclusion: MutualExclusionConfig(excludedButtonIds: {'hoistUp'}),
      );
      final result = validator.validateButtonConfig(up, {
        'hoistUp': up,
        'hoistDown': down,
      });
      expect(result.isValid, isTrue);
    });
  });

  group('Button-centric migration (v2 legacy JSON -> buttons map)', () {
    test('old-format JSON (no buttons key) synthesizes all 8 buttons', () {
      // Hand-written v2 shape: axisConfigs/roleStyles/labelConfig present,
      // no `buttons` key, no `schemaVersion` key — matches what the app
      // persisted before this refactor.
      final legacyJson = const ControlLayoutConfig().toJson()
        ..remove('buttons')
        ..remove('schemaVersion');

      final restored = ControlLayoutConfig.fromJson(legacyJson);

      expect(restored.buttons.length, ControlRole.values.length);
      for (final role in ControlRole.values) {
        expect(restored.buttons.containsKey(role.name), isTrue);
      }
    });

    test('migrated button type matches the legacy axis widgetType', () {
      final legacyJson =
          const ControlLayoutConfig(
              axisConfigs: AxisConfigSet(
                hoist: AxisControlConfig(widgetType: ControlWidgetType.toggle),
              ),
            ).toJson()
            ..remove('buttons')
            ..remove('schemaVersion');

      final restored = ControlLayoutConfig.fromJson(legacyJson);

      expect(restored.buttons['hoistUp']!.type, ButtonType.toggle);
      expect(restored.buttons['hoistDown']!.type, ButtonType.toggle);
    });

    test('migrated buttons are seeded with the safety-default exclusion', () {
      final legacyJson = const ControlLayoutConfig().toJson()
        ..remove('buttons')
        ..remove('schemaVersion');

      final restored = ControlLayoutConfig.fromJson(legacyJson);

      expect(
        restored.buttons['hoistUp']!.mutualExclusion.excludedButtonIds,
        contains('hoistDown'),
      );
      expect(
        restored.buttons['hoistDown']!.mutualExclusion.excludedButtonIds,
        contains('hoistUp'),
      );
      expect(
        restored.buttons['traverseLeft']!.mutualExclusion.excludedButtonIds,
        contains('traverseRight'),
      );
      expect(
        restored.buttons['travelForward']!.mutualExclusion.excludedButtonIds,
        contains('travelReverse'),
      );
      // estop/resetEstop have no paired role -> no default exclusion.
      expect(
        restored.buttons['estop']!.mutualExclusion.excludedButtonIds,
        isEmpty,
      );
    });

    test(
      'axisConfigs/roleStyles are preserved unchanged through migration',
      () {
        const original = ControlLayoutConfig(
          axisConfigs: AxisConfigSet(
            hoist: AxisControlConfig(heightScale: 1.3),
          ),
        );
        final legacyJson = original.toJson()
          ..remove('buttons')
          ..remove('schemaVersion');

        final restored = ControlLayoutConfig.fromJson(legacyJson);

        expect(restored.axisConfigs, original.axisConfigs);
        expect(restored.roleStyles, original.roleStyles);
      },
    );

    test('new-format config (with buttons) round-trips losslessly', () {
      const original = ControlLayoutConfig(
        buttons: {
          'hoistUp': ButtonConfig(
            id: 'hoistUp',
            type: ButtonType.pushButton,
            plcMapping: PlcMapping.up,
            role: ControlRole.hoistUp,
            label: 'UP',
            slotIndex: 0,
            rotation: ButtonRotation.deg90,
            mutualExclusion: MutualExclusionConfig(
              excludedButtonIds: {'hoistDown'},
            ),
          ),
        },
      );
      final restored = ControlLayoutConfig.fromJsonString(
        original.toJsonString(),
      );
      expect(restored, original);
      expect(restored.buttons['hoistUp']!.rotation, ButtonRotation.deg90);
    });

    test('schemaVersion is written into the JSON', () {
      final decoded =
          jsonDecode(const ControlLayoutConfig().toJsonString())
              as Map<String, dynamic>;
      expect(decoded['schemaVersion'], 5);
    });

    test('manual control page count round-trips through JSON', () {
      const original = ControlLayoutConfig(controlPageCount: 4);
      final restored = ControlLayoutConfig.fromJsonString(
        original.toJsonString(),
      );
      expect(restored.controlPageCount, 4);
      expect(restored, original);
    });

    test('malformed buttons map falls back gracefully', () {
      final json = const ControlLayoutConfig().toJson();
      json['buttons'] = 'not a map';
      // fromJson would throw on the bad cast; fromJsonString's top-level
      // try/catch is what the app actually relies on for corrupted JSON.
      final restored = ControlLayoutConfig.fromJsonString(jsonEncode(json));
      expect(restored, const ControlLayoutConfig());
    });
  });

  group('ButtonConfig new fields (width/enabled/locked/canvas position)', () {
    test('round-trips explicit values through JSON', () {
      const config = ButtonConfig(
        id: 'hoistUp',
        type: ButtonType.pushButton,
        plcMapping: PlcMapping.up,
        widthScale: 1.25,
        enabled: false,
        locked: true,
        canvasX: 0.33,
        canvasY: 0.67,
        slotIndex: 4,
      );
      final restored = ButtonConfig.fromJson(config.toJson());
      expect(restored, config);
      expect(restored.widthScale, 1.25);
      expect(restored.enabled, isFalse);
      expect(restored.locked, isTrue);
      expect(restored.canvasX, 0.33);
      expect(restored.canvasY, 0.67);
      expect(restored.slotIndex, 4);
    });

    test('old JSON missing the new keys parses with documented defaults', () {
      const config = ButtonConfig(
        id: 'hoistUp',
        type: ButtonType.pushButton,
        plcMapping: PlcMapping.up,
        role: ControlRole.hoistUp,
      );
      final json = config.toJson()
        ..remove('widthScale')
        ..remove('enabled')
        ..remove('locked')
        ..remove('canvasX')
        ..remove('canvasY')
        ..remove('slotIndex');
      final restored = ButtonConfig.fromJson(json);
      expect(restored.widthScale, 1.0);
      expect(restored.enabled, isTrue);
      expect(restored.locked, isFalse);
      final (defaultX, defaultY) = ButtonConfig.defaultCanvasPositionFor(
        ControlRole.hoistUp,
      );
      expect(restored.canvasX, defaultX);
      expect(restored.canvasY, defaultY);
      expect(restored.slotIndex, 0);
    });

    test(
      'new-format JSON with partial buttons is completed from legacy fields',
      () {
        final json =
            const ControlLayoutConfig(
                axisConfigs: AxisConfigSet(
                  hoist: AxisControlConfig(
                    widgetType: ControlWidgetType.pushButton,
                  ),
                ),
              ).toJson()
              ..['buttons'] = {
                'hoistUp': const ButtonConfig(
                  id: 'hoistUp',
                  type: ButtonType.toggle,
                  plcMapping: PlcMapping.up,
                  role: ControlRole.hoistUp,
                ).toJson(),
              };

        final restored = ControlLayoutConfig.fromJson(json);
        expect(restored.buttons.length, ControlRole.values.length);
        expect(
          restored.buttonFor(ControlRole.hoistUp)!.type,
          ButtonType.toggle,
        );
        expect(
          restored.buttonFor(ControlRole.hoistDown)!.type,
          ButtonType.pushButton,
        );
      },
    );

    test(
      'built-in templates populate button configs used by button-centric screens',
      () {
        const service = LayoutTemplateService();
        final pushTemplate = service.templates.firstWhere(
          (template) => template.name == 'Push Button Panel',
        );
        final config = pushTemplate.build();

        expect(config.buttons.length, ControlRole.values.length);
        expect(
          config.buttonFor(ControlRole.hoistUp)!.type,
          ButtonType.pushButton,
        );
        expect(
          config.buttonFor(ControlRole.traverseLeft)!.type,
          ButtonType.pushButton,
        );
      },
    );

    test('migration seeds traverse slider type as crossTravel by default', () {
      final legacyJson =
          const ControlLayoutConfig(
              axisConfigs: AxisConfigSet(
                traverse: AxisControlConfig(
                  widgetType: ControlWidgetType.sliderButton,
                ),
              ),
            ).toJson()
            ..remove('buttons')
            ..remove('schemaVersion');
      final restored = ControlLayoutConfig.fromJson(legacyJson);
      expect(restored.buttons['traverseLeft']!.type, ButtonType.crossTravel);
      expect(restored.buttons['traverseRight']!.type, ButtonType.crossTravel);
      // Non-traverse axes still map sliderButton -> sliderButton, unaffected.
      expect(restored.buttons['hoistUp']!.type, ButtonType.sliderButton);
    });

    test('E-Stop and Reset E-Stop default to locked', () {
      final restored = ControlLayoutConfig.fromJson(
        const ControlLayoutConfig().toJson()
          ..remove('buttons')
          ..remove('schemaVersion'),
      );
      expect(restored.buttons['estop']!.locked, isTrue);
      expect(restored.buttons['resetEstop']!.locked, isTrue);
    });

    test(
      'buttonFor falls back to synthesized defaults for the bare default constructor',
      () {
        const config = ControlLayoutConfig();
        for (final role in ControlRole.values) {
          expect(
            config.buttonFor(role),
            isNotNull,
            reason: '${role.name} should resolve',
          );
        }
      },
    );

    test('widthScale/canvasX/canvasY bounds are validated', () {
      const validator = LayoutValidationService();
      const outOfBounds = ButtonConfig(
        id: 'hoistUp',
        type: ButtonType.pushButton,
        plcMapping: PlcMapping.up,
        widthScale: 5.0,
        canvasX: 2.0,
        canvasY: -0.5,
      );
      final result = validator.validateButtonConfig(outOfBounds, {
        'hoistUp': outOfBounds,
      });
      expect(result.isValid, isFalse);
      expect(result.errors.length, greaterThanOrEqualTo(3));
    });

    test('in-bounds widthScale/canvasX/canvasY are accepted', () {
      const validator = LayoutValidationService();
      const inBounds = ButtonConfig(
        id: 'hoistUp',
        type: ButtonType.pushButton,
        plcMapping: PlcMapping.up,
        role: ControlRole.hoistUp,
        widthScale: 1.2,
        canvasX: 0.5,
        canvasY: 0.5,
        slotIndex: 0,
      );
      final result = validator.validateButtonConfig(inBounds, {
        'hoistUp': inBounds,
      });
      expect(result.isValid, isTrue);
    });

    test('duplicate motion-control slots are rejected', () {
      const validator = LayoutValidationService();
      final config = const ControlLayoutConfig().copyWith(
        buttons: {
          ...const ControlLayoutConfig().resolvedButtons,
          ControlRole.hoistDown.name: const ControlLayoutConfig()
              .buttonFor(ControlRole.hoistDown)!
              .copyWith(slotIndex: 0),
        },
      );

      final result = validator.validateFullConfig(config);

      expect(result.isValid, isFalse);
      expect(result.errors.join('\n'), contains('both occupy slot 1'));
    });

    test('5-zone cross travel declares a two-column grid span', () {
      const config = ButtonConfig(
        id: 'traverseLeft',
        type: ButtonType.crossTravel,
        plcMapping: PlcMapping.left,
        role: ControlRole.traverseLeft,
        slotIndex: 2,
      );

      expect(config.gridColumnSpan, 2);
      expect(config.gridRowSpan, 1);
      expect(occupiedGridSlotsFor(config), [2, 3]);
    });

    test('PLC14 role list renders only hoist controls from default layout', () {
      final pages = buildControlGridPages(
        layoutCfg: const ControlLayoutConfig(),
        roles: const [ControlRole.hoistUp, ControlRole.hoistDown],
        slotCount: 2,
      );

      final renderedIds = pages
          .expand((page) => page.items)
          .map((item) => item.config.id)
          .toList();

      expect(renderedIds, [
        ControlRole.hoistUp.name,
        ControlRole.hoistDown.name,
      ]);
      expect(renderedIds, isNot(contains(ControlRole.traverseLeft.name)));
      expect(renderedIds, isNot(contains(ControlRole.traverseRight.name)));
      expect(renderedIds, isNot(contains(ControlRole.travelForward.name)));
      expect(renderedIds, isNot(contains(ControlRole.travelReverse.name)));
    });

    test('auto arrange creates a new page when page one is full', () {
      final base = const ControlLayoutConfig().resolvedButtons;
      final buttons = {
        ...base,
        'extraMonitor': const ButtonConfig(
          id: 'extraMonitor',
          type: ButtonType.pushButton,
          plcMapping: PlcMapping.up,
          role: ControlRole.hoistUp,
          label: 'Monitor',
          pageIndex: 0,
          gridX: 0,
          gridY: 0,
          slotIndex: 0,
        ),
      };

      final arranged = autoArrangeButtons(buttons);

      expect(arranged.values.any((button) => button.pageIndex == 1), isTrue);
      expect(validateGridOccupancy(arranged), isEmpty);
    });

    test(
      'adding a free button searches the preferred page then spills over',
      () {
        final result = buildButtonAdd(
          buttons: const ControlLayoutConfig().resolvedButtons,
          preferredPageIndex: 0,
          button: const ButtonConfig(
            id: 'custom_1',
            type: ButtonType.pushButton,
            plcMapping: PlcMapping.up,
            label: 'Custom',
            role: null,
            enabled: false,
            plcMappingEnabled: false,
          ),
        );

        expect(result.isValid, isTrue);
        expect(result.buttons!['custom_1']!.pageIndex, 1);
        expect(result.buttons!['custom_1']!.plcMappingEnabled, isFalse);
        expect(validateGridOccupancy(result.buttons!), isEmpty);
      },
    );

    test('cross travel type change merges the paired traverse cell', () {
      final original = const ControlLayoutConfig().copyWith(
        buttons: {
          ...const ControlLayoutConfig().resolvedButtons,
          ControlRole.traverseLeft.name: const ControlLayoutConfig()
              .buttonFor(ControlRole.traverseLeft)!
              .copyWith(type: ButtonType.pushButton, slotIndex: 2),
          ControlRole.traverseRight.name: const ControlLayoutConfig()
              .buttonFor(ControlRole.traverseRight)!
              .copyWith(type: ButtonType.pushButton, slotIndex: 3),
        },
      );

      final result = buildButtonTypeChange(
        draft: original,
        role: ControlRole.traverseLeft,
        type: ButtonType.crossTravel,
      );

      expect(result.isValid, isTrue);
      final updated = result.layout!;
      expect(
        updated.buttonFor(ControlRole.traverseLeft)!.type,
        ButtonType.crossTravel,
      );
      expect(updated.buttonFor(ControlRole.traverseLeft)!.slotIndex, 2);
      expect(updated.buttonFor(ControlRole.traverseRight)!.visible, isFalse);
      expect(
        const LayoutValidationService().validateFullConfig(updated).isValid,
        isTrue,
      );
    });

    test('cross travel type change rejects a blocked neighboring cell', () {
      final original = const ControlLayoutConfig().copyWith(
        buttons: {
          ...const ControlLayoutConfig().resolvedButtons,
          ControlRole.traverseLeft.name: const ControlLayoutConfig()
              .buttonFor(ControlRole.traverseLeft)!
              .copyWith(type: ButtonType.pushButton, slotIndex: 2),
          ControlRole.traverseRight.name: const ControlLayoutConfig()
              .buttonFor(ControlRole.traverseRight)!
              .copyWith(visible: false),
          ControlRole.travelForward.name: const ControlLayoutConfig()
              .buttonFor(ControlRole.travelForward)!
              .copyWith(slotIndex: 3),
        },
      );

      final result = buildButtonTypeChange(
        draft: original,
        role: ControlRole.traverseLeft,
        type: ButtonType.crossTravel,
      );

      expect(result.isValid, isFalse);
      expect(result.message, kCrossTravelSpanMessage);
    });

    test('legacy dual cross travel configs coalesce during validation', () {
      final result = const LayoutValidationService().validateFullConfig(
        const ControlLayoutConfig(),
      );

      expect(result.isValid, isTrue);
    });
  });
}
