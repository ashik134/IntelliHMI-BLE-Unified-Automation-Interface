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
          ControlWidgetType.joystick => const _JoystickPreviewMock(),
          ControlWidgetType.rotary => const _RotaryPreviewMock(),
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

class _JoystickPreviewMock extends StatelessWidget {
  const _JoystickPreviewMock();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panelAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Center(
        child: SizedBox(
          width: 108,
          height: 108,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Dished bezel, matching the analog-gimbal plate treatment.
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    center: Alignment(-0.36, -0.5),
                    radius: 1.2,
                    colors: [
                      Color(0xFF2C3B4C),
                      Color(0xFF17222E),
                      Color(0xFF080D13),
                    ],
                    stops: [0.0, 0.55, 1.0],
                  ),
                  border: Border.all(color: Colors.white.withAlpha(28)),
                ),
              ),
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.darkTextMuted.withAlpha(70),
                  ),
                ),
              ),
              // Faint travel crosshair — continuous-field cue, no gate lines.
              Container(
                width: 66,
                height: 1,
                color: Colors.white.withAlpha(22),
              ),
              Container(
                width: 1,
                height: 66,
                color: Colors.white.withAlpha(22),
              ),
              Transform.translate(
                offset: const Offset(14, -16),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(-0.35, -0.45),
                      colors: [
                        AppColors.accent.withAlpha(255),
                        Color.alphaBlend(
                          Colors.black.withAlpha(90),
                          AppColors.accent,
                        ),
                      ],
                    ),
                    border: Border.all(color: Colors.white.withAlpha(60)),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withAlpha(100),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RotaryPreviewMock extends StatelessWidget {
  const _RotaryPreviewMock();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panelAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Center(
        child: SizedBox(
          width: 108,
          height: 108,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    center: Alignment(-0.32, -0.42),
                    radius: 1.2,
                    colors: [
                      Color(0xFF394A59),
                      Color(0xFF17232D),
                      Color(0xFF071018),
                    ],
                    stops: [0.0, 0.58, 1.0],
                  ),
                  border: Border.all(color: Colors.white.withAlpha(32)),
                ),
              ),
              const SizedBox(
                width: 82,
                height: 82,
                child: CircularProgressIndicator(
                  value: 0.62,
                  strokeWidth: 7,
                  color: AppColors.accent,
                  backgroundColor: AppColors.darkBg,
                ),
              ),
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    center: Alignment(-0.36, -0.45),
                    colors: [
                      Color(0xFFE5EBF0),
                      Color(0xFF7E8B96),
                      Color(0xFF2A333B),
                    ],
                    stops: [0.0, 0.48, 1.0],
                  ),
                  border: Border.all(color: Colors.black.withAlpha(120)),
                ),
              ),
              Transform.rotate(
                angle: 0.75,
                child: Container(
                  width: 7,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
