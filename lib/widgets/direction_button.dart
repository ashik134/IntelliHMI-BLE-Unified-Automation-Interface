import 'package:flutter/material.dart';
import 'package:rev6_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev6_crane_control_ops/utils/constants.dart';

class TriStateHoistButton extends StatelessWidget {
  const TriStateHoistButton({
    super.key,
    required this.isUp,
    required this.hoistState,
    required this.disabled,
    required this.onTap,
  });

  final bool isUp;
  final HoistState hoistState;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isActive = isUp
        ? (hoistState == HoistState.upSlow || hoistState == HoistState.upFast)
        : (hoistState == HoistState.downSlow ||
            hoistState == HoistState.downFast);
    final bool isFast = isUp
        ? hoistState == HoistState.upFast
        : hoistState == HoistState.downFast;

    final Color baseColor =
        isUp ? AppColors.upColor : AppColors.downColor;
    final Color activeColor = isFast ? AppColors.fastColor : baseColor;
    final Color displayColor = isActive ? activeColor : AppColors.textSecondary;

    final String stateLabel = !isActive
        ? 'TAP TO ACTIVATE'
        : isFast
            ? 'FAST \u2014 TAP TO STOP'
            : 'SLOW \u2014 TAP FOR FAST';

    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withAlpha(31)
              : AppColors.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? activeColor : AppColors.border,
            width: isActive ? 2 : 1,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: activeColor.withAlpha(77),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Opacity(
          opacity: disabled ? 0.38 : 1.0,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isUp
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: displayColor,
                size: 44,
              ),
              const SizedBox(height: 8),
              Text(
                isUp ? 'HOIST UP' : 'HOIST DOWN',
                style: TextStyle(
                  color: isActive ? activeColor : AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                stateLabel,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
