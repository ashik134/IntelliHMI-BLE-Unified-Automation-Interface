import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';

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

  bool get _upIsSpringReturn => widget.toggleConfig.wiringConfig.upIsSpringReturn;
  bool get _downIsSpringReturn => widget.toggleConfig.wiringConfig.downIsSpringReturn;
  bool get _mutuallyExclusive => widget.toggleConfig.wiringConfig.isMutuallyExclusive;

  // ── Spring-return (pointer events) ───────────────────────────────────────

  void _onUpPointerDown() {
    if (widget.isDisabled || !_upIsSpringReturn) return;
    if (_mutuallyExclusive && _downLatched) _releaseDown();
    HapticFeedback.mediumImpact();
    widget.onUpChanged(ControlState.slow);
  }

  void _onUpPointerUp() {
    if (_upIsSpringReturn) widget.onUpChanged(ControlState.idle);
  }

  void _onDownPointerDown() {
    if (widget.isDisabled || !_downIsSpringReturn) return;
    if (_mutuallyExclusive && _upLatched) _releaseUp();
    HapticFeedback.mediumImpact();
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
      HapticFeedback.mediumImpact();
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
      HapticFeedback.mediumImpact();
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
    final upVisuallyActive = widget.upActive || (!_upIsSpringReturn && _upLatched);
    final downVisuallyActive = widget.downActive || (!_downIsSpringReturn && _downLatched);

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

class _ToggleButton extends StatefulWidget {
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
  State<_ToggleButton> createState() => _ToggleButtonState();
}

class _ToggleButtonState extends State<_ToggleButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 150),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _pressAnim, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _pressAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.isActive && !widget.isDisabled;
    final color = isActive ? widget.activeColor : AppColors.idleColor;
    final colorLight = isActive ? widget.activeColorLight : AppColors.darkTextSub;

    return Listener(
      onPointerDown: (_) {
        if (widget.isDisabled) return;
        _pressAnim.forward();
        widget.onPointerDown();
      },
      onPointerUp: (_) {
        _pressAnim.reverse();
        widget.onPointerUp();
      },
      onPointerCancel: (_) {
        _pressAnim.reverse();
        widget.onPointerUp();
      },
      child: GestureDetector(
        onTap: widget.isSpringReturn ? null : widget.onTap,
        child: AnimatedBuilder(
          animation: _scaleAnim,
          builder: (context, child) => Transform.scale(
            scale: _scaleAnim.value,
            child: child,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isActive
                  ? widget.activeColor.withAlpha(38)
                  : AppColors.panelAlt,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isActive ? widget.activeColor : AppColors.darkBorder,
                width: isActive ? 2.0 : 1.0,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: widget.activeColor.withAlpha(77),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Direction icon with glow
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: isActive
                          ? widget.activeColor.withAlpha(51)
                          : AppColors.panel,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: color,
                        width: isActive ? 2.0 : 1.0,
                      ),
                    ),
                    child: Icon(widget.icon, color: colorLight, size: 28),
                  ),
                  const SizedBox(height: 12),
                  // Label
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      color: isActive ? widget.activeColorLight : AppColors.darkTextSub,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                    child: Text(widget.label),
                  ),
                  const SizedBox(height: 6),
                  // Behaviour mode badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.panel,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.darkBorder),
                    ),
                    child: Text(
                      widget.isSpringReturn ? 'HOLD' : 'TAP',
                      style: const TextStyle(
                        color: AppColors.darkTextMuted,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  // Active indicator
                  const SizedBox(height: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isActive ? widget.activeColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ToggleButtonPreview  (static, non-interactive, used in settings previews)
// ─────────────────────────────────────────────────────────────────────────────

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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: isActive ? activeColor.withAlpha(38) : AppColors.panelAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? activeColor : AppColors.darkBorder,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.panel,
              shape: BoxShape.circle,
              border: Border.all(color: activeColor.withAlpha(100)),
            ),
            child: Icon(icon, color: activeColorLight, size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.darkText,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: Text(
              isSpringReturn ? 'HOLD' : 'TAP',
              style: const TextStyle(
                color: AppColors.darkTextMuted,
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
