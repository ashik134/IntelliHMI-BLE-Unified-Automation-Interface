import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button/estop_swipe_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SafetyActionPanel
//
// Extracted verbatim from the near-byte-identical _buildSafetyActionPanel /
// _buildEStopButton / _buildResetSection methods that existed independently
// in plc14_control_screen.dart and plc38_control_screen.dart — pure
// presentational de-dup, no behavior change.
//
// E-Stop must remain structurally separate from layout editing chrome — the
// [resetEnabled] flag exists so a future editing/customization workflow can
// disable reset interaction without touching this widget's internals.
// ─────────────────────────────────────────────────────────────────────────────

class SafetyActionPanel extends StatelessWidget {
  const SafetyActionPanel({
    super.key,
    required this.estopLatched,
    required this.compact,
    required this.height,
    this.width,
    required this.instructionLabel,
    required this.resetLabel,
    this.resetEnabled = true,
    required this.onEStopTap,
    required this.onResetActivated,
  });

  final bool estopLatched;
  final bool compact;
  final double height;

  /// Operator-configured E-Stop button width (Safety Size customization).
  /// `null` (the factory default) stretches the button to fill the panel,
  /// matching prior behavior. [_ResetSection] never reads this — its width
  /// is always `double.infinity`, independent of E-Stop sizing.
  final double? width;
  final String instructionLabel;
  final String resetLabel;
  final bool resetEnabled;
  final VoidCallback onEStopTap;
  final VoidCallback onResetActivated;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      width: double.infinity,
      child: estopLatched
          ? _ResetSection(
              resetLabel: resetLabel,
              compact: compact,
              enabled: resetEnabled,
              onResetActivated: onResetActivated,
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                // Cap the operator-configured width to whatever the panel
                // actually has available, so a wide Safety Size setting can
                // never overflow onto a narrower screen than it was tuned on.
                final resolvedWidth = width?.clamp(0.0, constraints.maxWidth);
                return Center(
                  child: _EStopButton(
                    compact: compact,
                    height: height,
                    width: resolvedWidth,
                    instructionLabel: instructionLabel,
                    onTap: onEStopTap,
                  ),
                );
              },
            ),
    );
  }
}

class _EStopButton extends StatelessWidget {
  const _EStopButton({
    required this.height,
    this.width,
    required this.compact,
    required this.instructionLabel,
    required this.onTap,
  });

  final double height;
  final double? width;
  final bool compact;
  final String instructionLabel;
  final VoidCallback onTap;

  /// Below this rendered width there isn't room for the title/subtitle
  /// column without truncation or overflow — collapse to icon-only instead.
  static const double _iconOnlyWidthThreshold = 150.0;

  /// Below this rendered height the subtitle is dropped first (title stays,
  /// scaled down) to avoid squeezing two lines of text into a short button.
  static const double _subtitleMinHeight = 64.0;

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
          width: width ?? double.infinity,
          constraints: BoxConstraints(
            minHeight: height,
            maxHeight: height,
            minWidth: ControlWidgetSizeConfig.minTouchTargetPx,
          ),
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final renderedWidth = constraints.maxWidth;
              final iconOnly = renderedWidth < _iconOnlyWidthThreshold;
              final showSubtitle = !iconOnly && height >= _subtitleMinHeight;

              // Icon and title scale down gently on very short/narrow
              // buttons rather than clipping or overflowing.
              final iconBoxSize = compact ? 32.0 : 34.0;
              final iconSize = compact ? 18.0 : 19.0;
              final titleFontSize = height < 56
                  ? 12.0
                  : (compact ? 14.0 : 15.0);

              if (iconOnly) {
                return Center(
                  child: Container(
                    width: iconBoxSize,
                    height: iconBoxSize,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(31),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withAlpha(64),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.power_settings_new,
                      color: Colors.white,
                      size: iconSize,
                    ),
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: iconBoxSize,
                      height: iconBoxSize,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(31),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withAlpha(64),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.power_settings_new,
                        color: Colors.white,
                        size: iconSize,
                      ),
                    ),
                    SizedBox(width: compact ? 10 : 12),
                    Flexible(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'STOP',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: titleFontSize,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                          if (showSubtitle)
                            Text(
                              'Tap to stop all crane operations',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: compact ? 9 : 10,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
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
    this.enabled = true,
  });

  final String resetLabel;
  final bool compact;
  final bool enabled;
  final VoidCallback onResetActivated;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
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
                      fontSize: 10,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Text(
                    'All crane controls are locked',
                    style: TextStyle(
                      color: AppColors.darkTextSub,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 6 : 8),
        AbsorbPointer(
          absorbing: !enabled,
          child: Opacity(
            opacity: enabled ? 1.0 : 0.45,
            child: EStopSwipeButton(
              onActivated: onResetActivated,
              instructionLabel: enabled
                  ? 'SWIPE TO RESET E-STOP'
                  : 'EXIT EDIT MODE TO RESET',
              instructionSubtitle: enabled
                  ? 'Slide right to clear emergency lockout'
                  : 'Return to normal mode before clearing E-Stop',
            ),
          ),
        ),
      ],
    );
  }
}
