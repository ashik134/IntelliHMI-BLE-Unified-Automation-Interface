import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/widgets/buttons/industrial_spring_button.dart';

class DirectionalPushControlButton extends StatelessWidget {
  const DirectionalPushControlButton({
    super.key,
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.activeColorLight,
    required this.isActive,
    required this.isDisabled,
    required this.isSpringReturn,
    required this.onCommandChanged,
  });

  final String label;
  final IconData icon;
  final Color activeColor;
  final Color activeColorLight;
  final bool isActive;
  final bool isDisabled;
  final bool isSpringReturn;
  final ValueChanged<ControlState> onCommandChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = !isDisabled;
    final latched = !isSpringReturn && isActive;

    return SizedBox.expand(
      child: IndustrialSpringButton(
        label: label,
        icon: icon,
        activeColor: activeColor,
        activeColorLight: activeColorLight,
        isActive: isActive && enabled,
        isSpringReturn: isSpringReturn,
        isLatched: latched,
        enabled: enabled,
        onPressed: isSpringReturn
            ? () => onCommandChanged(ControlState.slow)
            : null,
        onReleased: isSpringReturn
            ? () => onCommandChanged(ControlState.idle)
            : null,
       
      ),
    );
  }
}

class UpPushControlButton extends StatelessWidget {
  const UpPushControlButton({
    super.key,
    required this.label,
    required this.isActive,
    required this.isDisabled,
    required this.isSpringReturn,
    required this.onCommandChanged,
    this.colorOverride,
    this.colorOverrideLight,
  });

  final String label;
  final bool isActive;
  final bool isDisabled;
  final bool isSpringReturn;
  final ValueChanged<ControlState> onCommandChanged;

  /// Optional per-role appearance override (from ButtonStyleConfig). Null
  /// keeps the role's default theme color.
  final Color? colorOverride;
  final Color? colorOverrideLight;

  @override
  Widget build(BuildContext context) {
    return DirectionalPushControlButton(
      label: label,
      icon: Icons.arrow_upward_rounded,
      activeColor: colorOverride ?? AppColors.upColor,
      activeColorLight: colorOverrideLight ?? AppColors.upColorLight,
      isActive: isActive,
      isDisabled: isDisabled,
      isSpringReturn: isSpringReturn,
      onCommandChanged: onCommandChanged,
    );
  }
}

class DownPushControlButton extends StatelessWidget {
  const DownPushControlButton({
    super.key,
    required this.label,
    required this.isActive,
    required this.isDisabled,
    required this.isSpringReturn,
    required this.onCommandChanged,
    this.colorOverride,
    this.colorOverrideLight,
  });

  final String label;
  final bool isActive;
  final bool isDisabled;
  final bool isSpringReturn;
  final ValueChanged<ControlState> onCommandChanged;
  final Color? colorOverride;
  final Color? colorOverrideLight;

  @override
  Widget build(BuildContext context) {
    return DirectionalPushControlButton(
      label: label,
      icon: Icons.arrow_downward_rounded,
      activeColor: colorOverride ?? AppColors.downColor,
      activeColorLight: colorOverrideLight ?? AppColors.downColorLight,
      isActive: isActive,
      isDisabled: isDisabled,
      isSpringReturn: isSpringReturn,
      onCommandChanged: onCommandChanged,
    );
  }
}

class LeftPushControlButton extends StatelessWidget {
  const LeftPushControlButton({
    super.key,
    required this.label,
    required this.isActive,
    required this.isDisabled,
    required this.isSpringReturn,
    required this.onCommandChanged,
    this.colorOverride,
    this.colorOverrideLight,
  });

  final String label;
  final bool isActive;
  final bool isDisabled;
  final bool isSpringReturn;
  final ValueChanged<ControlState> onCommandChanged;
  final Color? colorOverride;
  final Color? colorOverrideLight;

  @override
  Widget build(BuildContext context) {
    return DirectionalPushControlButton(
      label: label,
      icon: Icons.arrow_back_rounded,
      activeColor: colorOverride ?? AppColors.traverseColor,
      activeColorLight: colorOverrideLight ?? AppColors.traverseColorLight,
      isActive: isActive,
      isDisabled: isDisabled,
      isSpringReturn: isSpringReturn,
      onCommandChanged: onCommandChanged,
    );
  }
}

class RightPushControlButton extends StatelessWidget {
  const RightPushControlButton({
    super.key,
    required this.label,
    required this.isActive,
    required this.isDisabled,
    required this.isSpringReturn,
    required this.onCommandChanged,
    this.colorOverride,
    this.colorOverrideLight,
  });

  final String label;
  final bool isActive;
  final bool isDisabled;
  final bool isSpringReturn;
  final ValueChanged<ControlState> onCommandChanged;
  final Color? colorOverride;
  final Color? colorOverrideLight;

  @override
  Widget build(BuildContext context) {
    return DirectionalPushControlButton(
      label: label,
      icon: Icons.arrow_forward_rounded,
      activeColor: colorOverride ?? AppColors.traverseColor,
      activeColorLight: colorOverrideLight ?? AppColors.traverseColorLight,
      isActive: isActive,
      isDisabled: isDisabled,
      isSpringReturn: isSpringReturn,
      onCommandChanged: onCommandChanged,
    );
  }
}

class ForwardPushControlButton extends StatelessWidget {
  const ForwardPushControlButton({
    super.key,
    required this.label,
    required this.isActive,
    required this.isDisabled,
    required this.isSpringReturn,
    required this.onCommandChanged,
    this.colorOverride,
    this.colorOverrideLight,
  });

  final String label;
  final bool isActive;
  final bool isDisabled;
  final bool isSpringReturn;
  final ValueChanged<ControlState> onCommandChanged;
  final Color? colorOverride;
  final Color? colorOverrideLight;

  @override
  Widget build(BuildContext context) {
    return DirectionalPushControlButton(
      label: label,
      icon: Icons.north_rounded,
      activeColor: colorOverride ?? AppColors.travelColor,
      activeColorLight: colorOverrideLight ?? AppColors.travelColorLight,
      isActive: isActive,
      isDisabled: isDisabled,
      isSpringReturn: isSpringReturn,
      onCommandChanged: onCommandChanged,
    );
  }
}

class ReversePushControlButton extends StatelessWidget {
  const ReversePushControlButton({
    super.key,
    required this.label,
    required this.isActive,
    required this.isDisabled,
    required this.isSpringReturn,
    required this.onCommandChanged,
    this.colorOverride,
    this.colorOverrideLight,
  });

  final String label;
  final bool isActive;
  final bool isDisabled;
  final bool isSpringReturn;
  final ValueChanged<ControlState> onCommandChanged;
  final Color? colorOverride;
  final Color? colorOverrideLight;

  @override
  Widget build(BuildContext context) {
    return DirectionalPushControlButton(
      label: label,
      icon: Icons.south_rounded,
      activeColor: colorOverride ?? AppColors.travelColor,
      activeColorLight: colorOverrideLight ?? AppColors.travelColorLight,
      isActive: isActive,
      isDisabled: isDisabled,
      isSpringReturn: isSpringReturn,
      onCommandChanged: onCommandChanged,
    );
  }
}

class PushButtonPreview extends StatelessWidget {
  const PushButtonPreview({
    super.key,
    required this.wiringConfig,
    this.upLabel = 'UP',
    this.downLabel = 'DOWN',
    this.scale = 1.0,
  });

  final PushButtonWiringConfig wiringConfig;
  final String upLabel;
  final String downLabel;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: scale,
      alignment: Alignment.topCenter,
      child: Row(
        children: [
          Expanded(
            child: _PreviewButton(
              label: upLabel,
              icon: Icons.arrow_upward_rounded,
              activeColor: AppColors.upColor,
              activeColorLight: AppColors.upColorLight,
              isSpringReturn: wiringConfig.upIsSpringReturn,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _PreviewButton(
              label: downLabel,
              icon: Icons.arrow_downward_rounded,
              activeColor: AppColors.downColor,
              activeColorLight: AppColors.downColorLight,
              isSpringReturn: wiringConfig.downIsSpringReturn,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewButton extends StatelessWidget {
  const _PreviewButton({
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.activeColorLight,
    required this.isSpringReturn,
  });

  final String label;
  final IconData icon;
  final Color activeColor;
  final Color activeColorLight;
  final bool isSpringReturn;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: IgnorePointer(
        child: IndustrialSpringButton(
          label: label,
          icon: icon,
          activeColor: activeColor,
          activeColorLight: activeColorLight,
          isSpringReturn: isSpringReturn,
          hapticFeedback: false,
        ),
      ),
    );
  }
}
