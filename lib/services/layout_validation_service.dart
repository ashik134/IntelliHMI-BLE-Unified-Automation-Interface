import 'package:rev_crane_control_ops/models/control_layout_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ValidationResult
// ─────────────────────────────────────────────────────────────────────────────

class ValidationResult {
  const ValidationResult.valid()
    : isValid = true,
      errors = const [];

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
      'Hoist button height',
      config.hoistButtonHeightScale,
      errors,
    );
    _checkScaleBounds(
      'E-Stop button height',
      config.estopButtonHeightScale,
      errors,
    );

    _checkMinTouchTarget(
      'Hoist button',
      config.resolvedHoistHeight,
      errors,
    );
    _checkMinTouchTarget(
      'E-Stop button',
      config.resolvedEstopHeight,
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
    _checkLabel('E-Stop instruction', config.estopSwipeInstruction, errors);
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

  void _checkLabel(String name, String value, List<String> errors) {
    if (value.trim().isEmpty) {
      errors.add('$name must not be empty.');
    } else if (value.length > ControlLabelConfig.maxLabelLength) {
      errors.add(
        '$name exceeds the maximum ${ControlLabelConfig.maxLabelLength} '
        'characters.',
      );
    }
  }

  void _checkLabelMaxOnly(String name, String value, List<String> errors) {
    if (value.length > ControlLabelConfig.maxLabelLength) {
      errors.add(
        '$name exceeds the maximum ${ControlLabelConfig.maxLabelLength} '
        'characters.',
      );
    }
  }
}
