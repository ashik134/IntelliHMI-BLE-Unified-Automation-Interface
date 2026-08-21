import 'package:rev_crane_control_ops/models/analog_wire_config.dart'
    show analogOutputChannelOf;
import 'package:rev_crane_control_ops/models/button_behavior_config.dart';
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

    _checkLabel('Legacy slot 1 label', config.legacySlot1Label, errors);
    _checkLabel('Legacy slot 2 label', config.legacySlot2Label, errors);
    _checkLabel('Legacy slot 3 label', config.legacySlot3Label, errors);
    _checkLabel('Legacy slot 4 label', config.legacySlot4Label, errors);
    _checkLabel('Legacy slot 5 label', config.legacySlot5Label, errors);
    _checkLabel('Legacy slot 6 label', config.legacySlot6Label, errors);
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

    final buttons = config.resolvedButtons;
    final grid = config.gridLayout;
    for (final entry in buttons.entries) {
      final buttonResult = validateButtonConfig(
        entry.value,
        buttons,
        columns: grid.columns,
        rows: grid.rows,
        slotCount: grid.slotCount,
      );
      if (!buttonResult.isValid) errors.addAll(buttonResult.errors);
    }

    final slotResult = validateButtonSlots(
      buttons,
      columns: grid.columns,
      rows: grid.rows,
      slotCount: grid.slotCount,
    );
    if (!slotResult.isValid) errors.addAll(slotResult.errors);

    return errors.isEmpty
        ? const ValidationResult.valid()
        : ValidationResult.invalid(errors);
  }

  ValidationResult validateButtonSlots(
    Map<String, ButtonConfig> buttons, {
    int columns = ButtonConfig.controlGridColumns,
    int rows = ButtonConfig.controlGridRows,
    int slotCount = ButtonConfig.controlSlotCount,
  }) {
    final errors = validateGridOccupancy(
      buttons,
      slotCount: slotCount,
      columns: columns,
      rows: rows,
    );

    for (final button in buttons.values) {
      // Safety-role buttons (estop/resetEstop) never occupy a grid slot;
      // only generic (roleless) visible buttons need one.
      if (button.role != null || !button.visible) continue;

      final slot = button.slotIndex;
      final name = button.label.isEmpty ? button.id : button.label;
      if (slot == null) {
        errors.add('$name must have a control slot.');
        continue;
      }
      final maxSlotIndex = slotCount - 1;
      if (slot < ButtonConfig.minSlotIndex || slot > maxSlotIndex) {
        errors.add(
          '$name slot must be between ${ButtonConfig.minSlotIndex} and '
          '$maxSlotIndex (got $slot).',
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
    Map<String, ButtonConfig> allButtons, {
    int columns = ButtonConfig.controlGridColumns,
    int rows = ButtonConfig.controlGridRows,
    int slotCount = ButtonConfig.controlSlotCount,
  }) {
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

    final ownChannel = analogOutputChannelOf(config);
    if (ownChannel != null) {
      for (final other in allButtons.values) {
        if (other.id == config.id) continue;
        if (analogOutputChannelOf(other) != ownChannel) continue;
        final otherName = other.label.isEmpty ? other.id : other.label;
        errors.add(
          '$name and $otherName both write to analog channel '
          '${ownChannel.token} — assign each to a different channel.',
        );
      }
    }

    _checkIntRange(
      '$name debounce',
      config.behavior.debounceMs,
      ButtonBehaviorConfig.minDebounceMs,
      ButtonBehaviorConfig.maxDebounceMs,
      errors,
    );
    _checkIntRange(
      '$name long-press duration',
      config.behavior.longPressRequiredMs,
      ButtonBehaviorConfig.minLongPressRequiredMs,
      ButtonBehaviorConfig.maxLongPressRequiredMs,
      errors,
    );
    _checkRange(
      '$name press animation strength',
      config.behavior.pressAnimationStrength,
      ButtonBehaviorConfig.minPressAnimationStrength,
      ButtonBehaviorConfig.maxPressAnimationStrength,
      errors,
    );
    // An invisible button occupies no grid cell — its stored gridX/gridY/
    // slotIndex are stale placement data rather than a live conflict, so
    // placement geometry is never checked for it. Mirrors the same
    // visible-only assumption validateGridOccupancy and
    // buildControlGridPages already make via _isPageControl.
    final skipPlacementValidation = !config.visible;
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
    if (config.columnSpan < 1 || config.columnSpan > columns) {
      errors.add(
        '$name column span must be between 1 and '
        '$columns (got ${config.columnSpan}).',
      );
    }
    if (!skipPlacementValidation && config.pageIndex < 0) {
      errors.add('$name page index must be zero or greater.');
    }
    if (!skipPlacementValidation &&
        (config.gridX < 0 || config.gridX + config.gridColumnSpan > columns)) {
      errors.add('$name gridX must keep the widget inside $columns columns.');
    }
    if (!skipPlacementValidation &&
        (config.gridY < 0 || config.gridY + config.gridRowSpan > rows)) {
      errors.add('$name gridY must keep the widget inside $rows rows.');
    }
    _checkMinTouchTarget(name, config.resolvedHeight, errors);
    _checkUnitRange('$name canvasX', config.canvasX, errors);
    _checkUnitRange('$name canvasY', config.canvasY, errors);
    // Safety-role buttons (estop/resetEstop) never occupy a grid slot; only
    // generic (roleless) buttons need one.
    if (!skipPlacementValidation && config.role == null) {
      final slot = config.slotIndex;
      final maxSlotIndex = slotCount - 1;
      if (slot == null) {
        errors.add('$name must have a control slot.');
      } else if (slot < ButtonConfig.minSlotIndex || slot > maxSlotIndex) {
        errors.add(
          '$name slot must be between ${ButtonConfig.minSlotIndex} and '
          '$maxSlotIndex (got $slot).',
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

  /// Same contract as [_checkRange] but for an int field with non-nullable
  /// bounds (unlike the nullable cosmetic style fields, every
  /// ButtonBehaviorConfig field always has a concrete value).
  void _checkIntRange(
    String name,
    int value,
    int min,
    int max,
    List<String> errors,
  ) {
    if (value < min || value > max) {
      errors.add('$name $value must be between $min and $max.');
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
