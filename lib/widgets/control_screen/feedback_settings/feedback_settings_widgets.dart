import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/plc_condition_config.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/property_field_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared chrome for the Feedback Settings sheets
//
// Every feedback area is a sheet with the same shape — grab handle, a title
// row that can go back to the hub, a scrolling body and a single closing
// action — so the hub and its five panels read as one place rather than five
// unrelated dialogs. Pure presentation: nothing here touches a config, and
// nothing here can reach a PLC command path.
// ─────────────────────────────────────────────────────────────────────────────

/// All variants a feedback condition may watch. DF1/E-STOP is deliberately
/// absent: it already has dedicated, protected indication everywhere in the
/// app, and PlcConditionConfig strips it anyway (see its doc comment).
final List<PlcOutputVariant> kFeedbackConditionVariants = PlcOutputVariant
    .values
    .where((variant) => variant.isUserConfigurable)
    .toList(growable: false);

class FeedbackSheetScaffold extends StatelessWidget {
  const FeedbackSheetScaffold({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.onBack,
    this.closeLabel = 'Done',
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  /// When set, the title row gets a back affordance and the closing button
  /// reads as returning to the hub rather than leaving customization.
  final VoidCallback? onBack;

  final String closeLabel;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.darkBorder),
              boxShadow: AppMetrics.shadowMd,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.panelStroke,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (onBack != null) ...[
                      _RoundIconButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Back to Feedback Settings',
                        onTap: onBack!,
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: AppColors.darkText,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              subtitle!,
                              style: const TextStyle(
                                color: AppColors.darkTextMuted,
                                fontSize: 11.5,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 10),
                      trailing!,
                    ],
                  ],
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: children,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.selectionViolet,
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(closeLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.darkBg,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: AppColors.darkText),
        ),
      ),
    );
  }
}

/// Hub row: one feedback area, with a live one-line summary of how it is
/// currently configured so the operator can see the state of every area
/// without opening each one.
class FeedbackNavTile extends StatelessWidget {
  const FeedbackNavTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.summary,
    required this.onTap,
    this.accent,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String summary;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppColors.selectionViolet;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            color: AppColors.darkBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: color.withAlpha(70)),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.darkText,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.darkTextMuted,
                        fontSize: 11.5,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.darkTextMuted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Trigger-condition editor shared by every PLC-status-driven feedback area:
/// which reported fields are watched, and whether any-of or all-of them must
/// be ON. Reads status only — this widget has no notion of an output.
class PlcConditionEditor extends StatelessWidget {
  const PlcConditionEditor({
    super.key,
    required this.title,
    required this.condition,
    required this.onChanged,
    this.emptyWarning,
  });

  final String title;
  final PlcConditionConfig condition;
  final ValueChanged<PlcConditionConfig> onChanged;

  /// Shown when nothing is selected. Null means an unconfigured condition is
  /// a normal, expected state for this area (e.g. an alarm severity a site
  /// simply does not use).
  final String? emptyWarning;

  @override
  Widget build(BuildContext context) {
    final selectedKeys = condition.watchedFields
        .map((variant) => variant.storageKey)
        .toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.darkText,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: () => onChanged(
                condition.copyWith(
                  watchedFields: kFeedbackConditionVariants.toSet(),
                ),
              ),
              child: const Text('All'),
            ),
            TextButton(
              onPressed: () =>
                  onChanged(condition.copyWith(watchedFields: const {})),
              child: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        PropertyMultiSelect(
          options: [
            for (final variant in kFeedbackConditionVariants)
              (variant.storageKey, variant.genericLabel),
          ],
          selectedKeys: selectedKeys,
          onToggle: (key) {
            final variant = PlcOutputVariant.fromStorageKey(key);
            if (variant == null) return;
            onChanged(condition.toggleField(variant));
          },
        ),
        const SizedBox(height: 10),
        PropertySegmented<PlcConditionCombinator>(
          options: const [
            (PlcConditionCombinator.any, 'Any selected is ON'),
            (PlcConditionCombinator.all, 'All selected are ON'),
          ],
          selected: condition.combinator,
          onChanged: (value) => onChanged(condition.copyWith(combinator: value)),
        ),
        if (!condition.hasCondition && emptyWarning != null) ...[
          const SizedBox(height: 10),
          PropertyInfoBanner(text: emptyWarning!, isWarning: true),
        ],
      ],
    );
  }
}

/// Numeric field for calibration/scaling values. Commits on every edit so the
/// draft (and therefore the live preview behind the sheet) tracks typing —
/// the whole sheet visit is one undo entry, so keystroke-level writes are
/// intentional here.
class FeedbackNumberField extends StatelessWidget {
  const FeedbackNumberField({
    super.key,
    required this.controller,
    required this.label,
    required this.onChanged,
    this.suffix,
    this.allowNegative = true,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<double> onChanged;
  final String? suffix;
  final bool allowNegative;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(
        decimal: true,
        signed: allowNegative,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          allowNegative ? RegExp(r'[0-9.\-]') : RegExp(r'[0-9.]'),
        ),
      ],
      style: const TextStyle(color: AppColors.darkText, fontSize: 13.5),
      // A half-typed number ("-", "1.") parses to null; leaving the config
      // untouched until it is valid again keeps the field editable instead of
      // fighting the operator's cursor.
      onChanged: (raw) {
        final parsed = double.tryParse(raw.trim());
        if (parsed != null) onChanged(parsed);
      },
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        suffixStyle: const TextStyle(
          color: AppColors.darkTextMuted,
          fontSize: 12,
        ),
        labelStyle: const TextStyle(color: AppColors.darkTextMuted),
        isDense: true,
        filled: true,
        fillColor: AppColors.darkBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
    );
  }
}

/// Small live chip used by the hub's status strip — shows what the Feedback
/// Manager is resolving right now, so the settings screen and the running
/// annunciation never have to be compared by eye.
class FeedbackStatusChip extends StatelessWidget {
  const FeedbackStatusChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
