import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// confirmDialog
//
// Shared Cancel/Confirm AlertDialog, extracted from
// EditableControlTile._confirmThenDelete so both that widget and the
// mutual-exclusion editor (button_edit_sheet.dart's BEHAVIOR tab) present the
// same styling instead of duplicating the boilerplate a third time.
// ─────────────────────────────────────────────────────────────────────────────

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'Confirm',
  Color confirmColor = AppColors.eStopColor,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.panel,
      title: Text(
        title,
        style: const TextStyle(color: AppColors.darkText, fontSize: 16),
      ),
      content: Text(
        body,
        style: const TextStyle(color: AppColors.darkTextSub, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: TextButton.styleFrom(foregroundColor: confirmColor),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}
