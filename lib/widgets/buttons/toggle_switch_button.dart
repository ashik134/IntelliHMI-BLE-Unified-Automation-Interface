import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ToggleSwitchButton
//
// Implements ControlWidgetType.toggle — previously a dead enum value with no
// rendering. Deliberately a standalone widget (not a wrapper around
// IndustrialSpringButton): a toggle should read as a rocker/slide switch,
// not a round illuminated pushbutton, so operators can tell the two control
// types apart at a glance.
//
// Reuses PushButtonWiringConfig (spring-return / latched) rather than the
// dead 5-variant ToggleWiringConfig enum — from the PLC's perspective a
// toggle drives the exact same two independently-controlled boolean outputs
// as a push button, just different chrome.
//
// Emits only ControlState.idle / ControlState.slow — never .fast, matching
// the product intent already documented (and now retired) in
// control_type_page.dart: "Toggle mode sends slow speed only. Use Slider
// mode to access fast speed."
//
// Unlike the push-button primitive, this widget honors the full
// ButtonStyleConfig (corner radius, icon size, label typography, show/hide
// label) since it's authored fresh rather than composed around a fixed
// custom-painted plate.
// ─────────────────────────────────────────────────────────────────────────────

class ToggleSwitchButton extends StatefulWidget {
  const ToggleSwitchButton({
    super.key,
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.activeColorLight,
    required this.isActive,
    required this.isDisabled,
    required this.isSpringReturn,
    required this.onCommandChanged,
    this.style = const ButtonStyleConfig(),
  });

  final String label;
  final IconData icon;

  /// Already-resolved colors (style.primaryColor/activeColor applied by the
  /// caller before construction, mirroring how the existing directional
  /// push-button wrappers receive their colors).
  final Color activeColor;
  final Color activeColorLight;

  final bool isActive;
  final bool isDisabled;
  final bool isSpringReturn;
  final ValueChanged<ControlState> onCommandChanged;
  final ButtonStyleConfig style;

  @override
  State<ToggleSwitchButton> createState() => _ToggleSwitchButtonState();
}

class _ToggleSwitchButtonState extends State<ToggleSwitchButton> {
  bool _pointerDown = false;

  bool get _enabled => !widget.isDisabled;
  bool get _on => widget.isActive && _enabled;

  void _handlePointerDown(PointerDownEvent _) {
    if (!_enabled || !widget.isSpringReturn || _pointerDown) return;
    _pointerDown = true;
    HapticFeedback.selectionClick();
    widget.onCommandChanged(ControlState.slow);
  }

  void _handlePointerUp(PointerUpEvent _) => _release();
  void _handlePointerCancel(PointerCancelEvent _) => _release();

  void _release() {
    if (!_pointerDown) return;
    _pointerDown = false;
    widget.onCommandChanged(ControlState.idle);
  }

  void _handleTap() {
    if (!_enabled || widget.isSpringReturn) return;
    HapticFeedback.selectionClick();
    widget.onCommandChanged(_on ? ControlState.idle : ControlState.slow);
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final cornerRadius = style.cornerRadius ?? 16.0;
    final iconSize = style.iconSize ?? 26.0;
    final labelFontSize = style.labelFontSize ?? 13.0;
    final labelFontWeight = style.labelFontWeight ?? FontWeight.w700;

    final trackColor = _on
        ? widget.activeColor.withAlpha(46)
        : AppColors.panelAlt;
    final borderColor = _on
        ? widget.activeColor
        : (_enabled ? AppColors.darkBorder : AppColors.disabled);
    final iconColor = _on ? widget.activeColorLight : AppColors.darkTextMuted;

    return Semantics(
      button: true,
      enabled: _enabled,
      toggled: _on,
      label: widget.label,
      child: Opacity(
        opacity: _enabled ? 1.0 : 0.5,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _handlePointerDown,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerCancel,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.isSpringReturn ? null : _handleTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              height: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: trackColor,
                borderRadius: BorderRadius.circular(cornerRadius),
                border: Border.all(color: borderColor, width: _on ? 2 : 1),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, size: iconSize, color: iconColor),
                  if (style.showLabel) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _on
                            ? widget.activeColorLight
                            : AppColors.darkText,
                        fontSize: labelFontSize,
                        fontWeight: labelFontWeight,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  // Rocker track
                  Container(
                    width: 44,
                    height: 24,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: AppColors.darkBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.darkBorder),
                    ),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeOut,
                      alignment: _on
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: _on
                              ? widget.activeColor
                              : AppColors.darkTextSub,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.isSpringReturn
                        ? 'HOLD'
                        : (_on ? 'ON · TAP' : 'OFF · TAP'),
                    style: const TextStyle(
                      color: AppColors.darkText,
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
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
