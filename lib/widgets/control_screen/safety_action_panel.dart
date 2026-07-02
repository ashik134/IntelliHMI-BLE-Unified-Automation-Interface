import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/widgets/buttons/estop_swipe_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SafetyActionPanel
//
// Extracted verbatim from the near-byte-identical _buildSafetyActionPanel /
// _buildEStopButton / _buildResetSection methods that existed independently
// in plc14_control_screen.dart and plc38_control_screen.dart — pure
// presentational de-dup, no behavior change.
//
// Deliberately never wrapped in EditableControlTile by callers: E-Stop must
// remain live and tappable at all times, including while Customization Mode
// is active.
// ─────────────────────────────────────────────────────────────────────────────

class SafetyActionPanel extends StatelessWidget {
  const SafetyActionPanel({
    super.key,
    required this.estopLatched,
    required this.compact,
    required this.height,
    required this.instructionLabel,
    required this.resetLabel,
    required this.onEStopTap,
    required this.onResetActivated,
  });

  final bool estopLatched;
  final bool compact;
  final double height;
  final String instructionLabel;
  final String resetLabel;
  final VoidCallback onEStopTap;
  final VoidCallback onResetActivated;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      width: double.infinity,
      child: estopLatched
          ? _ResetSection(resetLabel: resetLabel, compact: compact, onResetActivated: onResetActivated)
          : _EStopButton(
              compact: compact,
              height: height,
              instructionLabel: instructionLabel,
              onTap: onEStopTap,
            ),
    );
  }
}

class _EStopButton extends StatelessWidget {
  const _EStopButton({
    required this.height,
    required this.compact,
    required this.instructionLabel,
    required this.onTap,
  });

  final double height;
  final bool compact;
  final String instructionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: Colors.white.withAlpha(50),
        highlightColor: Colors.white.withAlpha(20),
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: compact ? 100 : 100),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6B0000), AppColors.eStopColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.eStopColor.withAlpha(100),
                blurRadius: 14,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: compact ? 32 : 34,
                height: compact ? 32 : 34,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(31),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withAlpha(64), width: 2),
                ),
                child: const Icon(Icons.power_settings_new, color: Colors.white, size: 18),
              ),
              SizedBox(width: compact ? 10 : 12),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'STOP',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  Text(
                    'Tap to stop all crane operations',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white60, fontSize: compact ? 9 : 10),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResetSection extends StatelessWidget {
  const _ResetSection({
    required this.resetLabel,
    required this.onResetActivated,
    this.compact = false,
  });

  final String resetLabel;
  final bool compact;
  final VoidCallback onResetActivated;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(compact ? 8 : 10),
          decoration: BoxDecoration(
            color: AppColors.eStopColor.withAlpha(31),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.eStopColor.withAlpha(153), width: 2),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: compact ? 13 : 16,
                backgroundColor: AppColors.eStopColor,
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: compact ? 15 : 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EMERGENCY STOP ACTIVE',
                      style: TextStyle(
                        color: AppColors.eStopColorLight,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      'All crane controls are locked',
                      style: TextStyle(color: AppColors.darkTextSub, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: compact ? 6 : 8),
        EStopSwipeButton(
          onActivated: onResetActivated,
          instructionLabel: 'SWIPE TO RESET E-STOP',
          instructionSubtitle: 'Slide right to clear emergency lockout',
        ),
      ],
    );
  }
}
