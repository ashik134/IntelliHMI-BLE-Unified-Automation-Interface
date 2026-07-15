import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ValidationResult
// ─────────────────────────────────────────────────────────────────────────────

class ValidationResult {
  const ValidationResult.valid() : isValid = true, errors = const [];

  const ValidationResult.invalid(this.errors) : isValid = false;

  final bool isValid;
  final List<String> errors;

  String get firstError => errors.isNotEmpty ? errors.first : '';
}

// ─────────────────────────────────────────────────────────────────────────────
// LayoutValidationService
// ─────────────────────────────────────────────────────────────────────────────

class LayoutValidationService {
  const LayoutValidationService();

  // ── Public API ─────────────────────────────────────────────────────────────

  ValidationResult validateSizeConfig(ControlWidgetSizeConfig config) {
    final errors = <String>[];

    _checkScaleBounds(
      'E-Stop button height',
      config.estopButtonHeightScale,
      errors,
    );
    _checkScaleBoundsGeneric(
      'E-Stop button width',
      config.estopButtonWidthScale,
      ControlWidgetSizeConfig.minWidthScale,
      ControlWidgetSizeConfig.maxWidthScale,
      errors,
    );

    _checkMinTouchTarget('E-Stop button', config.resolvedEstopHeight, errors);
    _checkMinTouchTarget(
      'E-Stop button width',
      config.resolvedEstopWidth,
      errors,
    );

    return errors.isEmpty
        ? const ValidationResult.valid()
        : ValidationResult.invalid(errors);
  }

  ValidationResult validateLabelConfig(ControlLabelConfig config) {
    final errors = <String>[];

    _checkLabel('UP button label', config.upLabel, errors);
    _checkLabel('DOWN button label', config.downLabel, errors);
    _checkLabel('LEFT button label', config.leftLabel, errors);
    _checkLabel('RIGHT button label', config.rightLabel, errors);
    _checkLabel('FORWARD button label', config.forwardLabel, errors);
    _checkLabel('REVERSE button label', config.reverseLabel, errors);
    _checkLabel(
      'E-Stop instruction',
      config.estopSwipeInstruction,
      errors,
      max: ControlLabelConfig.maxInstructionLength,
    );
    _checkLabel('Reset E-Stop label', config.resetEstopLabel, errors);

    if (config.screenTitle.isNotEmpty) {
      _checkLabelMaxOnly('Screen title', config.screenTitle, errors);
    }

    return errors.isEmpty
        ? const ValidationResult.valid()
        : ValidationResult.invalid(errors);
  }

  ValidationResult validateFullConfig(ControlLayoutConfig config) {
    final errors = <String>[];

    final sizeResult = validateSizeConfig(config.sizeConfig);
    if (!sizeResult.isValid) errors.addAll(sizeResult.errors);

    final labelResult = validateLabelConfig(config.labelConfig);
    if (!labelResult.isValid) errors.addAll(labelResult.errors);

    for (final axis in AxisKind.values) {
      final axisResult = validateAxisConfig(
        axis,
        config.axisConfigs.forAxis(axis),
      );
      if (!axisResult.isValid) errors.addAll(axisResult.errors);
    }

    for (final role in ControlRole.values) {
      if (role == ControlRole.estop) continue; // no style exists for E-Stop
      final styleResult = validateRoleStyle(
        role,
        config.roleStyles.forRole(role),
      );
      if (!styleResult.isValid) errors.addAll(styleResult.errors);
    }

    final orderResult = validateAxisOrder(config.axisOrder);
    if (!orderResult.isValid) errors.addAll(orderResult.errors);

    final buttons = config.resolvedButtons;
    for (final entry in buttons.entries) {
      final buttonResult = validateButtonConfig(entry.value, buttons);
      if (!buttonResult.isValid) errors.addAll(buttonResult.errors);
    }

    final slotResult = validateButtonSlots(buttons);
    if (!slotResult.isValid) errors.addAll(slotResult.errors);

    return errors.isEmpty
        ? const ValidationResult.valid()
        : ValidationResult.invalid(errors);
  }

  ValidationResult validateButtonSlots(Map<String, ButtonConfig> buttons) {
    final errors = validateGridOccupancy(buttons);

    for (final button in buttons.values) {
      final role = button.role;
      if (role == null || !role.isMotionControl || !button.visible) continue;
      if (isRedundantCrossTravelConfig(button, buttons)) continue;

      final slot = button.slotIndex;
      final name = button.label.isEmpty ? button.id : button.label;
      if (slot == null) {
        errors.add('$name must have a control slot.');
        continue;
      }
      if (slot < ButtonConfig.minSlotIndex ||
          slot > ButtonConfig.maxSlotIndex) {
        errors.add(
          '$name slot must be between ${ButtonConfig.minSlotIndex} and '
          '${ButtonConfig.maxSlotIndex} (got $slot).',
        );
        continue;
      }
    }

    return errors.isEmpty
        ? const ValidationResult.valid()
        : ValidationResult.invalid(errors);
  }

  /// Validates a single button's mutual-exclusion configuration against the
  /// full button set — "validate and reject configurations the PLC protocol
  /// cannot support, with a clear explanation." Rejects self-exclusion and
  /// exclusions referencing a nonexistent button id; flags asymmetric
  /// exclusion pairs (A excludes B but B doesn't exclude A) as an error so
  /// the operator can't accidentally leave a one-directional interlock.
  ValidationResult validateButtonConfig(
    ButtonConfig config,
    Map<String, ButtonConfig> allButtons,
  ) {
    final errors = <String>[];

    if (config.mutualExclusion.excludedButtonIds.contains(config.id)) {
      errors.add(
        '${config.label.isEmpty ? config.id : config.label} cannot exclude itself.',
      );
    }

    for (final excludedId in config.mutualExclusion.excludedButtonIds) {
      final excludedButton = allButtons[excludedId];
      if (excludedButton == null) {
        errors.add(
          '${config.label.isEmpty ? config.id : config.label} excludes '
          'unknown button "$excludedId".',
        );
        continue;
      }
      if (!excludedButton.mutualExclusion.excludedButtonIds.contains(
        config.id,
      )) {
        errors.add(
          '${config.label.isEmpty ? config.id : config.label} excludes '
          '${excludedButton.label.isEmpty ? excludedButton.id : excludedButton.label}, '
          'but not the reverse — mutual exclusion must be symmetric.',
        );
      }
    }

    final name = config.label.isEmpty ? config.id : config.label;
    // An invisible button occupies no grid cell — its stored gridX/gridY/
    // slotIndex are stale placement data (e.g. a hoist-only layout's hidden
    // traverseRight, still carrying its crossTravel-span-2 default position)
    // rather than a live conflict, so placement geometry is never checked
    // for it. Mirrors the same visible-only assumption validateGridOccupancy
    // and buildControlGridPages already make via _isPageControl.
    final skipPlacementValidation =
        !config.visible ||
        isRedundantCrossTravelConfig(config, allButtons);
    _checkScaleBoundsGeneric(
      '$name height',
      config.heightScale,
      ButtonConfig.minHeightScale,
      ButtonConfig.maxHeightScale,
      errors,
    );
    _checkScaleBoundsGeneric(
      '$name width',
      config.widthScale,
      ButtonConfig.minWidthScale,
      ButtonConfig.maxWidthScale,
      errors,
    );
    if (config.columnSpan < 1 ||
        config.columnSpan > ButtonConfig.controlGridColumns) {
      errors.add(
        '$name column span must be between 1 and '
        '${ButtonConfig.controlGridColumns} (got ${config.columnSpan}).',
      );
    }
    if (!skipPlacementValidation && config.pageIndex < 0) {
      errors.add('$name page index must be zero or greater.');
    }
    if (!skipPlacementValidation &&
        (config.gridX < 0 ||
            config.gridX + config.gridColumnSpan >
                ButtonConfig.controlGridColumns)) {
      errors.add(
        '$name gridX must keep the widget inside '
        '${ButtonConfig.controlGridColumns} columns.',
      );
    }
    if (!skipPlacementValidation &&
        (config.gridY < 0 ||
            config.gridY + config.gridRowSpan > ButtonConfig.controlGridRows)) {
      errors.add(
        '$name gridY must keep the widget inside '
        '${ButtonConfig.controlGridRows} rows.',
      );
    }
    _checkMinTouchTarget(name, config.resolvedHeight, errors);
    _checkUnitRange('$name canvasX', config.canvasX, errors);
    _checkUnitRange('$name canvasY', config.canvasY, errors);
    final role = config.role;
    if (!skipPlacementValidation && role != null && role.isMotionControl) {
      final slot = config.slotIndex;
      if (slot == null) {
        errors.add('$name must have a control slot.');
      } else if (slot < ButtonConfig.minSlotIndex ||
          slot > ButtonConfig.maxSlotIndex) {
        errors.add(
          '$name slot must be between ${ButtonConfig.minSlotIndex} and '
          '${ButtonConfig.maxSlotIndex} (got $slot).',
        );
      }
    }

    return errors.isEmpty
        ? const ValidationResult.valid()
        : ValidationResult.invalid(errors);
  }

  void _checkUnitRange(String name, double value, List<String> errors) {
    if (value < 0.0 || value > 1.0) {
      errors.add(
        '$name must be between 0.0 and 1.0 (got ${value.toStringAsFixed(2)}).',
      );
    }
  }

  /// Validates a single axis's control type / wiring / height scale.
  ValidationResult validateAxisConfig(AxisKind axis, AxisControlConfig config) {
    final errors = <String>[];

    _checkScaleBoundsGeneric(
      '${axis.displayName} button height',
      config.heightScale,
      AxisControlConfig.minHeightScale,
      AxisControlConfig.maxHeightScale,
      errors,
    );
    _checkMinTouchTarget(
      '${axis.displayName} button',
      config.resolvedHeight,
      errors,
    );

    return errors.isEmpty
        ? const ValidationResult.valid()
        : ValidationResult.invalid(errors);
  }

  /// Validates a single role's cosmetic style overrides.
  ///
  /// [ControlRole.estop] always fails — E-Stop's appearance is not
  /// customizable, and [RoleStyleConfig] has no field to hold one anyway,
  /// but this stays as a defensive check for any caller that bypasses that
  /// structural guarantee.
  ValidationResult validateRoleStyle(
    ControlRole role,
    ButtonStyleConfig style,
  ) {
    final errors = <String>[];

    if (role == ControlRole.estop) {
      errors.add('E-Stop appearance cannot be customized.');
    }

    _checkRange(
      '${role.name} corner radius',
      style.cornerRadius,
      ButtonStyleConfig.minCornerRadius,
      ButtonStyleConfig.maxCornerRadius,
      errors,
    );
    _checkRange(
      '${role.name} elevation',
      style.elevation,
      ButtonStyleConfig.minElevation,
      ButtonStyleConfig.maxElevation,
      errors,
    );
    _checkRange(
      '${role.name} icon size',
      style.iconSize,
      ButtonStyleConfig.minIconSize,
      ButtonStyleConfig.maxIconSize,
      errors,
    );
    _checkRange(
      '${role.name} label font size',
      style.labelFontSize,
      ButtonStyleConfig.minLabelFontSize,
      ButtonStyleConfig.maxLabelFontSize,
      errors,
    );

    return errors.isEmpty
        ? const ValidationResult.valid()
        : ValidationResult.invalid(errors);
  }

  /// Validates that [order] is a valid permutation of the three axis kinds.
  ValidationResult validateAxisOrder(List<AxisKind> order) {
    final errors = <String>[];
    if (order.length != 3 || order.toSet().length != 3) {
      errors.add(
        'Axis order must contain HOIST, TRAVERSE, and TRAVEL exactly once each.',
      );
    }
    return errors.isEmpty
        ? const ValidationResult.valid()
        : ValidationResult.invalid(errors);
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  void _checkScaleBounds(String name, double value, List<String> errors) {
    if (value < ControlWidgetSizeConfig.minHeightScale) {
      errors.add(
        '$name scale ${value.toStringAsFixed(2)} is below the minimum '
        '${ControlWidgetSizeConfig.minHeightScale.toStringAsFixed(2)}.',
      );
    } else if (value > ControlWidgetSizeConfig.maxHeightScale) {
      errors.add(
        '$name scale ${value.toStringAsFixed(2)} exceeds the maximum '
        '${ControlWidgetSizeConfig.maxHeightScale.toStringAsFixed(2)}.',
      );
    }
  }

  void _checkScaleBoundsGeneric(
    String name,
    double value,
    double min,
    double max,
    List<String> errors,
  ) {
    if (value < min) {
      errors.add(
        '$name scale ${value.toStringAsFixed(2)} is below the minimum '
        '${min.toStringAsFixed(2)}.',
      );
    } else if (value > max) {
      errors.add(
        '$name scale ${value.toStringAsFixed(2)} exceeds the maximum '
        '${max.toStringAsFixed(2)}.',
      );
    }
  }

  /// Generic bounds check for nullable cosmetic style fields. A null value
  /// means "use the theme default" and is always valid — only an explicit
  /// out-of-range override is rejected.
  void _checkRange(
    String name,
    double? value,
    double min,
    double max,
    List<String> errors,
  ) {
    if (value == null) return;
    if (value < min || value > max) {
      errors.add(
        '$name ${value.toStringAsFixed(1)} must be between '
        '${min.toStringAsFixed(1)} and ${max.toStringAsFixed(1)}.',
      );
    }
  }

  void _checkMinTouchTarget(
    String name,
    double resolvedPx,
    List<String> errors,
  ) {
    if (resolvedPx < ControlWidgetSizeConfig.minTouchTargetPx) {
      errors.add(
        '$name resolved height ${resolvedPx.toStringAsFixed(1)} px is below '
        'the minimum touch target of '
        '${ControlWidgetSizeConfig.minTouchTargetPx.toStringAsFixed(0)} px. '
        'Increase the scale factor.',
      );
    }
  }

  void _checkLabel(String name, String value, List<String> errors, {int? max}) {
    final limit = max ?? ControlLabelConfig.maxLabelLength;
    if (value.trim().isEmpty) {
      errors.add('$name must not be empty.');
    } else if (value.length > limit) {
      errors.add('$name exceeds the maximum $limit characters.');
    }
  }

  void _checkLabelMaxOnly(String name, String value, List<String> errors) {
    if (value.length > ControlLabelConfig.maxInstructionLength) {
      errors.add(
        '$name exceeds the maximum ${ControlLabelConfig.maxInstructionLength} '
        'characters.',
      );
    }
  }
}
