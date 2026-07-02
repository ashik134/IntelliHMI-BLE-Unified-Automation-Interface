import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/widgets/buttons/push_control_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AxisTypePreview
//
// Static (non-interactive) preview of how an axis will render for a given
// ControlWidgetType. Used in ButtonEditSheet's Type tab so the operator can
// see the result before committing to a change. Generalizes the existing
// PushButtonPreview (push_control_button.dart) with slider/toggle mocks.
// ─────────────────────────────────────────────────────────────────────────────

class AxisTypePreview extends StatelessWidget {
  const AxisTypePreview({
    super.key,
    required this.widgetType,
    required this.wiringConfig,
    required this.primaryLabel,
    required this.secondaryLabel,
    this.primaryIcon = Icons.arrow_upward_rounded,
    this.secondaryIcon = Icons.arrow_downward_rounded,
    this.primaryColor = AppColors.upColor,
    this.primaryColorLight = AppColors.upColorLight,
    this.secondaryColor = AppColors.downColor,
    this.secondaryColorLight = AppColors.downColorLight,
  });

  final ControlWidgetType widgetType;
  final PushButtonWiringConfig wiringConfig;
  final String primaryLabel;
  final String secondaryLabel;
  final IconData primaryIcon;
  final IconData secondaryIcon;
  final Color primaryColor;
  final Color primaryColorLight;
  final Color secondaryColor;
  final Color secondaryColorLight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: IgnorePointer(
        child: switch (widgetType) {
          ControlWidgetType.pushButton => PushButtonPreview(
            wiringConfig: wiringConfig,
            upLabel: primaryLabel,
            downLabel: secondaryLabel,
          ),
          ControlWidgetType.toggle => Row(
            children: [
              Expanded(
                child: _TogglePreviewMock(
                  label: primaryLabel,
                  icon: primaryIcon,
                  color: primaryColor,
                  colorLight: primaryColorLight,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TogglePreviewMock(
                  label: secondaryLabel,
                  icon: secondaryIcon,
                  color: secondaryColor,
                  colorLight: secondaryColorLight,
                ),
              ),
            ],
          ),
          ControlWidgetType.joystick ||
          ControlWidgetType.rotary => const _ComingSoonMock(),
          ControlWidgetType.sliderButton => Row(
            children: [
              Expanded(
                child: _SliderPreviewMock(
                  label: primaryLabel,
                  icon: primaryIcon,
                  color: primaryColor,
                  colorLight: primaryColorLight,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SliderPreviewMock(
                  label: secondaryLabel,
                  icon: secondaryIcon,
                  color: secondaryColor,
                  colorLight: secondaryColorLight,
                ),
              ),
            ],
          ),
        },
      ),
    );
  }
}

class _SliderPreviewMock extends StatelessWidget {
  const _SliderPreviewMock({
    required this.label,
    required this.icon,
    required this.color,
    required this.colorLight,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color colorLight;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panelAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: colorLight, size: 26),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.darkText,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 28,
            height: 3,
            decoration: BoxDecoration(
              color: color.withAlpha(90),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'SLIDE',
            style: TextStyle(
              color: AppColors.darkTextMuted,
              fontSize: 7,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _TogglePreviewMock extends StatelessWidget {
  const _TogglePreviewMock({
    required this.label,
    required this.icon,
    required this.color,
    required this.colorLight,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color colorLight;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panelAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: colorLight, size: 24),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.darkText,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 32,
            height: 16,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: AppColors.darkBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.darkBorder),
            ),
            alignment: Alignment.centerLeft,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.darkTextSub,
                shape: BoxShape.circle,
              ),
              child: SizedBox(width: 12, height: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComingSoonMock extends StatelessWidget {
  const _ComingSoonMock();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panelAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: const Center(
        child: Text(
          'Coming soon',
          style: TextStyle(
            color: AppColors.darkTextMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
