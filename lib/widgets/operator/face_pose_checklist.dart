import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/face_enrollment_status.dart';

/// The guided-pose progress checklist (spec section 10): "✓ Front ✓ Left
/// ○ Right ○ Up" plus an "N / total" counter. Purely a rendering of
/// [poses] — all sequencing/acceptance logic lives in
/// `FaceEnrollmentService`.
class FacePoseChecklist extends StatelessWidget {
  const FacePoseChecklist({super.key, required this.poses});

  final List<PoseProgress> poses;

  @override
  Widget build(BuildContext context) {
    if (poses.isEmpty) return const SizedBox.shrink();
    final accepted = poses.where((p) => p.accepted).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(120),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final pose in poses) ...[
            _PoseChip(pose: pose),
            if (pose != poses.last) const SizedBox(width: 10),
          ],
          const SizedBox(width: 12),
          Text(
            '$accepted / ${poses.length}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PoseChip extends StatelessWidget {
  const _PoseChip({required this.pose});

  final PoseProgress pose;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    if (pose.accepted) {
      color = AppColors.brandSuccess;
      icon = Icons.check_circle_rounded;
    } else if (pose.isCurrent) {
      color = Colors.white;
      icon = Icons.radio_button_checked_rounded;
    } else {
      color = Colors.white.withAlpha(140);
      icon = Icons.radio_button_unchecked_rounded;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(
          pose.label,
          style: TextStyle(
            color: color,
            fontSize: 12.5,
            fontWeight: pose.isCurrent ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
