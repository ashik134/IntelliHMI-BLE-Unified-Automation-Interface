import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/widgets/industrial_spring_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ToggleControlGroup
//
// A pair of industrial toggle buttons (UP / DOWN) that replaces the slider
// button row on the control screen when widgetType == ControlWidgetType.toggle.
//
// Behaviour is governed by the [ToggleWiringConfig] in [ToggleControlConfig]:
//   • Spring-return  → active only while the button is held (Listener)
//   • Latched        → tap once to activate, tap again to deactivate
//   • Mutual exclusion enforced for latchedOffLatched config
//
// Sends [ControlState.slow] (no fast-ramp; use slider buttons for fast mode).
// ─────────────────────────────────────────────────────────────────────────────

class ToggleControlGroup extends StatefulWidget {
  const ToggleControlGroup({
    super.key,
    required this.toggleConfig,
    required this.upLabel,
    required this.downLabel,
    required this.isDisabled,
    required this.onUpChanged,
    required this.onDownChanged,
    required this.upActive,
    required this.downActive,
    this.height,
  });

  final ToggleControlConfig toggleConfig;
  final String upLabel;
  final String downLabel;
  final bool isDisabled;
  final ValueChanged<ControlState> onUpChanged;
  final ValueChanged<ControlState> onDownChanged;

  /// Reflects the live PLC-confirmed state (used for visual sync).
  final bool upActive;
  final bool downActive;
  final double? height;

  @override
  State<ToggleControlGroup> createState() => _ToggleControlGroupState();
}

class _ToggleControlGroupState extends State<ToggleControlGroup> {
  // Local UI latch states (for latched configs before PLC confirmation)
  bool _upLatched = false;
  bool _downLatched = false;

  bool get _upIsSpringReturn =>
      widget.toggleConfig.wiringConfig.upIsSpringReturn;
  bool get _downIsSpringReturn =>
      widget.toggleConfig.wiringConfig.downIsSpringReturn;
  bool get _mutuallyExclusive =>
      widget.toggleConfig.wiringConfig.isMutuallyExclusive;

  // ── Spring-return (pointer events) ───────────────────────────────────────

  void _onUpPointerDown() {
    if (widget.isDisabled || !_upIsSpringReturn) return;
    if (_mutuallyExclusive && _downLatched) _releaseDown();
    widget.onUpChanged(ControlState.slow);
  }

  void _onUpPointerUp() {
    if (_upIsSpringReturn) widget.onUpChanged(ControlState.idle);
  }

  void _onDownPointerDown() {
    if (widget.isDisabled || !_downIsSpringReturn) return;
    if (_mutuallyExclusive && _upLatched) _releaseUp();
    widget.onDownChanged(ControlState.slow);
  }

  void _onDownPointerUp() {
    if (_downIsSpringReturn) widget.onDownChanged(ControlState.idle);
  }

  // ── Latched (tap events) ──────────────────────────────────────────────────

  void _onUpTap() {
    if (widget.isDisabled || _upIsSpringReturn) return;
    if (_upLatched) {
      _releaseUp();
    } else {
      if (_mutuallyExclusive && _downLatched) _releaseDown();
      setState(() => _upLatched = true);
      widget.onUpChanged(ControlState.slow);
    }
  }

  void _onDownTap() {
    if (widget.isDisabled || _downIsSpringReturn) return;
    if (_downLatched) {
      _releaseDown();
    } else {
      if (_mutuallyExclusive && _upLatched) _releaseUp();
      setState(() => _downLatched = true);
      widget.onDownChanged(ControlState.slow);
    }
  }

  void _releaseUp() {
    setState(() => _upLatched = false);
    widget.onUpChanged(ControlState.idle);
  }

  void _releaseDown() {
    setState(() => _downLatched = false);
    widget.onDownChanged(ControlState.idle);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Visual active state: use PLC-confirmed state when available
    final upVisuallyActive =
        widget.upActive || (!_upIsSpringReturn && _upLatched);
    final downVisuallyActive =
        widget.downActive || (!_downIsSpringReturn && _downLatched);

    return Row(
      children: [
        Expanded(
          child: _ToggleButton(
            label: widget.upLabel,
            icon: Icons.arrow_upward_rounded,
            activeColor: AppColors.upColor,
            activeColorLight: AppColors.upColorLight,
            isActive: upVisuallyActive,
            isDisabled: widget.isDisabled,
            isSpringReturn: _upIsSpringReturn,
            isLatched: _upLatched,
            onPointerDown: _onUpPointerDown,
            onPointerUp: _onUpPointerUp,
            onTap: _onUpTap,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ToggleButton(
            label: widget.downLabel,
            icon: Icons.arrow_downward_rounded,
            activeColor: AppColors.downColor,
            activeColorLight: AppColors.downColorLight,
            isActive: downVisuallyActive,
            isDisabled: widget.isDisabled,
            isSpringReturn: _downIsSpringReturn,
            isLatched: _downLatched,
            onPointerDown: _onDownPointerDown,
            onPointerUp: _onDownPointerUp,
            onTap: _onDownTap,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ToggleButton  (single directional toggle)
// ─────────────────────────────────────────────────────────────────────────────

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.activeColorLight,
    required this.isActive,
    required this.isDisabled,
    required this.isSpringReturn,
    required this.isLatched,
    required this.onPointerDown,
    required this.onPointerUp,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color activeColor;
  final Color activeColorLight;
  final bool isActive;
  final bool isDisabled;
  final bool isSpringReturn;
  final bool isLatched;
  final VoidCallback onPointerDown;
  final VoidCallback onPointerUp;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = !isDisabled;

    return SizedBox.expand(
      child: IndustrialSpringButton(
        label: label,
        icon: icon,
        activeColor: activeColor,
        activeColorLight: activeColorLight,
        isActive: isActive && enabled,
        isSpringReturn: isSpringReturn,
        isLatched: isLatched,
        enabled: enabled,
        onPressed: isSpringReturn ? onPointerDown : null,
        onReleased: isSpringReturn ? onPointerUp : null,
        onTap: isSpringReturn ? null : onTap,
      ),
    );
  }
}

class ToggleButtonPreview extends StatelessWidget {
  const ToggleButtonPreview({
    super.key,
    required this.wiringConfig,
    this.upLabel = 'UP',
    this.downLabel = 'DOWN',
    this.scale = 1.0,
  });

  final ToggleWiringConfig wiringConfig;
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
            child: _PreviewToggle(
              label: upLabel,
              icon: Icons.arrow_upward_rounded,
              activeColor: AppColors.upColor,
              activeColorLight: AppColors.upColorLight,
              isSpringReturn: wiringConfig.upIsSpringReturn,
              isActive: false,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _PreviewToggle(
              label: downLabel,
              icon: Icons.arrow_downward_rounded,
              activeColor: AppColors.downColor,
              activeColorLight: AppColors.downColorLight,
              isSpringReturn: wiringConfig.downIsSpringReturn,
              isActive: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewToggle extends StatelessWidget {
  const _PreviewToggle({
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.activeColorLight,
    required this.isSpringReturn,
    required this.isActive,
  });

  final String label;
  final IconData icon;
  final Color activeColor;
  final Color activeColorLight;
  final bool isSpringReturn;
  final bool isActive;

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
          isActive: isActive,
          isSpringReturn: isSpringReturn,
          hapticFeedback: false,
        ),
      ),
    );
  }
}
