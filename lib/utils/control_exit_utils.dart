import 'package:flutter/material.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';

/// Shows a confirmation dialog before leaving a PLC control screen.
///
/// Returns `true` if the operator confirmed disconnect, `false` otherwise.
/// Both PLC14 and PLC38 control screens use this shared dialog to ensure
/// consistent behaviour without duplicating dialog code.
Future<bool> showControlExitDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.logout_rounded, color: AppColors.darkTextSub, size: 20),
          SizedBox(width: 10),
          Text(
            'Leave Control Screen?',
            style: TextStyle(color: AppColors.darkText, fontSize: 16),
          ),
        ],
      ),
      content: const Text(
        'All motion has been stopped.\n'
        'Disconnect and return to the scan screen?',
        style: TextStyle(color: AppColors.darkTextSub, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text(
            'Stay',
            style: TextStyle(color: AppColors.darkTextSub),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.eStopColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text('Disconnect'),
        ),
      ],
    ),
  );
  return result ?? false;
}
