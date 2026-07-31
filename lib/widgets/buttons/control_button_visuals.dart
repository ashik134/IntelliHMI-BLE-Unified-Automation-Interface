import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/button_rotation.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';

class ControlButtonVisualMetrics {
  const ControlButtonVisualMetrics._();

  static const double labelFontSize = 11.0;
  static const double minLabelFontSize = 8.0;
  static const FontWeight labelFontWeight = FontWeight.w700;
  static const double iconSize = 16.0;
  static const double minIconSize = 12.0;
  static const double iconLabelGap = 5.0;
  static const double rowHeight = 22.0;
  static const double minReadableLabelWidth = 28.0;

  static double labelSizeFor(Size size) {
    final shortest = math.min(size.width, size.height);
    final target = shortest < 18
        ? minLabelFontSize
        : shortest < 24
        ? 9.0
        : labelFontSize;
    return target.clamp(minLabelFontSize, labelFontSize).toDouble();
  }

  static double iconSizeFor(Size size) {
    final shortest = math.min(size.width, size.height);
    final target = shortest < 18
        ? minIconSize
        : shortest < 24
        ? 14.0
        : iconSize;
    return target.clamp(minIconSize, iconSize).toDouble();
  }

  static TextStyle labelTextStyle({
    required Color color,
    required Size bounds,
  }) {
    return TextStyle(
      color: color,
      fontSize: labelSizeFor(bounds),
      fontWeight: labelFontWeight,
      letterSpacing: 0,
    );
  }

  static TextSpan labelIconTextSpan({
    required String label,
    required IconData? icon,
    required Color color,
    required Size bounds,
    Color? iconColor,
    bool showIcon = true,
  }) {
    final textStyle = labelTextStyle(color: color, bounds: bounds);
    final resolvedIcon = showIcon ? icon : null;
    if (resolvedIcon == null) return TextSpan(text: label, style: textStyle);

    return TextSpan(
      children: [
        TextSpan(
          text: String.fromCharCode(resolvedIcon.codePoint),
          style: TextStyle(
            inherit: false,
            color: iconColor ?? color,
            fontSize: iconSizeFor(bounds),
            fontFamily: resolvedIcon.fontFamily,
            package: resolvedIcon.fontPackage,
          ),
        ),
        TextSpan(text: '  ', style: textStyle),
        TextSpan(text: label, style: textStyle),
      ],
    );
  }

  static double gapFor(Size size) {
    if (size.width < 52 || size.height < 18) return 3.0;
    return iconLabelGap;
  }

  static bool canShowText({
    required Size size,
    required bool hasIcon,
    required bool hasLabel,
  }) {
    if (!hasLabel) return false;
    if (!hasIcon) return size.width >= minReadableLabelWidth;
    final iconSize = iconSizeFor(size);
    return size.width >= iconSize + gapFor(size) + minReadableLabelWidth &&
        size.height >= minLabelFontSize + 2;
  }

  static void paintLabelIcon(
    Canvas canvas, {
    required Rect bounds,
    required String label,
    required IconData? icon,
    required Color color,
    Color? iconColor,
    bool showLabel = true,
    bool showIcon = true,
  }) {
    final boundsSize = bounds.size;
    final trimmedLabel = label.trim();
    final hasLabel = showLabel && trimmedLabel.isNotEmpty;
    final hasIcon = showIcon && icon != null;
    if (!hasLabel && !hasIcon) return;

    final iconSize = iconSizeFor(boundsSize);
    final labelFontSize = labelSizeFor(boundsSize);
    final gap = gapFor(boundsSize);
    final canDrawText = canShowText(
      size: boundsSize,
      hasIcon: hasIcon,
      hasLabel: hasLabel,
    );

    final TextPainter? iconPainter = hasIcon
        ? (TextPainter(
            text: TextSpan(
              text: String.fromCharCode(icon.codePoint),
              style: TextStyle(
                inherit: false,
                color: iconColor ?? color,
                fontSize: iconSize,
                fontFamily: icon.fontFamily,
                package: icon.fontPackage,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout())
        : null;

    final labelMaxWidth = math.max(
      0.0,
      bounds.width -
          (iconPainter == null || !canDrawText ? 0.0 : iconPainter.width + gap),
    );
    final TextPainter? labelPainter = canDrawText
        ? (TextPainter(
            text: TextSpan(
              text: trimmedLabel,
              style: TextStyle(
                color: color,
                fontSize: labelFontSize,
                fontWeight: labelFontWeight,
                letterSpacing: 0,
              ),
            ),
            maxLines: 1,
            ellipsis: '...',
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: labelMaxWidth))
        : null;

    final totalWidth =
        (iconPainter?.width ?? 0.0) +
        (iconPainter != null && labelPainter != null ? gap : 0.0) +
        (labelPainter?.width ?? 0.0);
    final contentHeight = math.max(
      iconPainter?.height ?? 0.0,
      labelPainter?.height ?? 0.0,
    );
    var dx = bounds.left + (bounds.width - totalWidth) / 2;
    final dy = bounds.top + (bounds.height - contentHeight) / 2;

    if (iconPainter != null) {
      iconPainter.paint(
        canvas,
        Offset(dx, dy + (contentHeight - iconPainter.height) / 2),
      );
      dx += iconPainter.width + (labelPainter != null ? gap : 0.0);
    }
    labelPainter?.paint(
      canvas,
      Offset(dx, dy + (contentHeight - labelPainter.height) / 2),
    );
  }
}

class ControlButtonLabelIcon extends StatelessWidget {
  const ControlButtonLabelIcon({
    super.key,
    required this.label,
    this.icon,
    required this.color,
    this.iconColor,
    this.style,
    this.showIcon = true,
    this.showLabel = true,
    this.alignment = MainAxisAlignment.center,
    this.rotation = ButtonRotation.none,
  });

  final String label;
  final IconData? icon;
  final Color color;
  final Color? iconColor;
  final ButtonStyleConfig? style;
  final bool showIcon;
  final bool showLabel;
  final MainAxisAlignment alignment;

  /// The button's own configured rotation (see ButtonConfig.rotation and
  /// ConfigurableButton's outer Transform.rotate, which rotates this
  /// widget along with everything else in the button). Counter-rotating by
  /// the same amount here keeps the label/icon upright and correctly
  /// measured no matter how the rest of the button is rotated. RotatedBox
  /// (unlike Transform.rotate) natively swaps layout constraints for a
  /// quarter turn, so no manual size bookkeeping is needed beyond computing
  /// [size] below with width/height swapped to match.
  final ButtonRotation rotation;

  @override
  Widget build(BuildContext context) {
    final wantsLabel = showLabel && (style?.showLabel ?? true);
    final trimmedLabel = label.trim();
    final hasLabel = wantsLabel && trimmedLabel.isNotEmpty;
    final hasIcon = showIcon && icon != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 160.0;
        final boxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : ControlButtonVisualMetrics.rowHeight;
        final quarterTurns = rotation.quarterTurns;
        final isSideways = quarterTurns.isOdd;
        // Once counter-rotated back to upright, the label's own available
        // space is this box with width/height swapped for a 90/270 turn.
        final size = isSideways
            ? Size(boxHeight, boxWidth)
            : Size(boxWidth, boxHeight);
        final iconSize = ControlButtonVisualMetrics.iconSizeFor(size);
        final gap = ControlButtonVisualMetrics.gapFor(size);
        final canShowText = ControlButtonVisualMetrics.canShowText(
          size: size,
          hasIcon: hasIcon,
          hasLabel: hasLabel,
        );

        final children = <Widget>[
          if (hasIcon) Icon(icon, size: iconSize, color: iconColor ?? color),
          if (hasIcon && canShowText) SizedBox(width: gap),
          if (canShowText)
            Flexible(
              child: Text(
                trimmedLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                textAlign: TextAlign.center,
                style: ControlButtonVisualMetrics.labelTextStyle(
                  color: color,
                  bounds: size,
                ),
              ),
            ),
        ];

        if (children.isEmpty) return const SizedBox.shrink();

        final row = SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Row(
            mainAxisAlignment: alignment,
            mainAxisSize: MainAxisSize.max,
            children: children,
          ),
        );

        if (quarterTurns == 0) return row;
        return RotatedBox(quarterTurns: -quarterTurns, child: row);
      },
    );
  }
}
