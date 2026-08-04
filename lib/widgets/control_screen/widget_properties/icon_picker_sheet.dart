import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/button_icon_registry.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Icon picker
//
// Selects from the curated kButtonIconChoices registry only (never an
// arbitrary IconData) — see ButtonConfig.iconKey's doc comment for why: a
// curated, stably-keyed set is what makes the pick safely persist through
// save/reload, unlike a bare codePoint.
// ─────────────────────────────────────────────────────────────────────────────

/// Distinguishes "the sheet was dismissed with no change" (null return from
/// [showIconPickerSheet]) from "the operator explicitly cleared the icon"
/// ([IconPickResult] with a null [iconKey]).
class IconPickResult {
  const IconPickResult(this.iconKey);

  final String? iconKey;
}

Future<IconPickResult?> showIconPickerSheet(
  BuildContext context, {
  String? currentKey,
}) {
  return showModalBottomSheet<IconPickResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _IconPickerSheet(currentKey: currentKey),
  );
}

class _IconPickerSheet extends StatelessWidget {
  const _IconPickerSheet({this.currentKey});

  final String? currentKey;

  @override
  Widget build(BuildContext context) {
    final entries = kButtonIconChoices.entries.toList();
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        constraints: const BoxConstraints(maxHeight: 480),
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
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Choose Icon',
                  style: TextStyle(
                    color: AppColors.darkText,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(const IconPickResult(null)),
                  child: const Text(
                    'Clear',
                    style: TextStyle(color: AppColors.eStopColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final selected = entry.key == currentKey;
                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => Navigator.of(
                      context,
                    ).pop(IconPickResult(entry.key)),
                    child: Container(
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.selectionViolet.withAlpha(60)
                            : AppColors.darkBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? AppColors.selectionViolet
                              : AppColors.darkBorder,
                          width: selected ? 1.6 : 1,
                        ),
                      ),
                      child: Icon(
                        entry.value,
                        color: selected
                            ? AppColors.selectionViolet
                            : AppColors.darkTextSub,
                        size: 20,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
