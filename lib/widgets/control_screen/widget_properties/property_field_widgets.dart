import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared small building blocks used by every widget_properties/*_tab.dart
// file, so the 5 tabs read as one consistent design system instead of each
// reinventing section headers/sliders/switches. Pure presentation — every
// piece here is stateless and takes its value/onChanged from the caller,
// which always sources it from ButtonConfig and writes back via
// LayoutEditController.updateButton.
// ─────────────────────────────────────────────────────────────────────────────

class PropertySectionHeader extends StatelessWidget {
  const PropertySectionHeader(this.title, {super.key, this.padTop = 18});

  final String title;
  final double padTop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: padTop, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.selectionViolet,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class PropertyLabeledSlider extends StatelessWidget {
  const PropertyLabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.valueLabel,
    required this.onChanged,
    this.divisions,
    this.enabled = true,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String valueLabel;
  final int? divisions;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.darkText,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                valueLabel,
                style: const TextStyle(
                  color: AppColors.darkTextMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: AppColors.selectionViolet,
              inactiveTrackColor: AppColors.darkBorder,
              thumbColor: AppColors.selectionViolet,
              overlayColor: AppColors.selectionGlow,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ],
      ),
    );
  }
}

class PropertySwitchTile extends StatelessWidget {
  const PropertySwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      activeThumbColor: AppColors.selectionViolet,
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.darkText,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(
                color: AppColors.darkTextMuted,
                fontSize: 11.5,
              ),
            ),
      value: value,
      onChanged: onChanged,
    );
  }
}

class PropertyTextField extends StatelessWidget {
  const PropertyTextField({
    super.key,
    required this.controller,
    required this.label,
    this.onChanged,
    this.keyboardType,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        enabled: enabled,
        onChanged: onChanged,
        keyboardType: keyboardType,
        style: const TextStyle(color: AppColors.darkText, fontSize: 13.5),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.darkTextMuted),
          filled: true,
          fillColor: AppColors.darkBg,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.darkBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.darkBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
              color: AppColors.selectionViolet,
              width: 1.6,
            ),
          ),
        ),
      ),
    );
  }
}

/// A single-select row of pill choices — used for rotation, orientation,
/// wiring mode, etc. `T` must have stable `==`.
class PropertySegmented<T> extends StatelessWidget {
  const PropertySegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<(T value, String label)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          _Pill(
            label: option.$2,
            selected: option.$1 == selected,
            onTap: () => onChanged(option.$1),
          ),
      ],
    );
  }
}

/// Same visual as [PropertySegmented] but allows any number of options
/// (including zero) to be active at once — used for PLC-output-variant
/// mapping and mutual-exclusion picking.
class PropertyMultiSelect extends StatelessWidget {
  const PropertyMultiSelect({
    super.key,
    required this.options,
    required this.selectedKeys,
    required this.onToggle,
    this.disabledKeys = const {},
  });

  final List<(String key, String label)> options;
  final Set<String> selectedKeys;
  final Set<String> disabledKeys;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return const Text(
        'No other widgets on this layout.',
        style: TextStyle(color: AppColors.darkTextMuted, fontSize: 12),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          _Pill(
            label: option.$2,
            selected: selectedKeys.contains(option.$1),
            onTap: disabledKeys.contains(option.$1)
                ? null
                : () => onToggle(option.$1),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.selectionViolet
              : AppColors.darkBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppColors.selectionViolet
                : AppColors.darkBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: disabled
                ? AppColors.darkTextMuted
                : selected
                ? Colors.white
                : AppColors.darkText,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Non-interactive info banner — used for validation warnings and for the
/// analog Output tab's "no PLC output-variant mapping" note.
class PropertyInfoBanner extends StatelessWidget {
  const PropertyInfoBanner({
    super.key,
    required this.text,
    this.isWarning = false,
  });

  final String text;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final color = isWarning ? AppColors.eStopColor : AppColors.darkInfo;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isWarning ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 12, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
