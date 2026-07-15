import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/widgets/customization/selection_overlay/widget_transformer.dart';

/// A single Figma-style resize handle: a small white/violet dot with a
/// generous invisible touch target, positioned by its parent [Stack] so
/// its visual center lands exactly on the selection frame's border line.
///
/// Edge (midpoint) handles are drawn slightly larger than corner handles —
/// they're harder to grab since there's no corner geometry to aim for —
/// but both share the same 28x28 hit-testable area so they stay
/// finger-friendly regardless of the dot's visual size.
class ResizeHandle extends StatefulWidget {
  const ResizeHandle({
    super.key,
    required this.position,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final ResizeHandlePosition position;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  static const double touchTarget = 28;
  static const double cornerSize = 9;
  static const double edgeSize = 11;

  static bool isCorner(ResizeHandlePosition position) => switch (position) {
    ResizeHandlePosition.topLeft ||
    ResizeHandlePosition.topRight ||
    ResizeHandlePosition.bottomLeft ||
    ResizeHandlePosition.bottomRight => true,
    _ => false,
  };

  @override
  State<ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<ResizeHandle> {
  bool _pressed = false;

  bool get _isCorner => ResizeHandle.isCorner(widget.position);

  MouseCursor get _cursor => switch (widget.position) {
    ResizeHandlePosition.topLeft ||
    ResizeHandlePosition.bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
    ResizeHandlePosition.topRight ||
    ResizeHandlePosition.bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
    ResizeHandlePosition.left ||
    ResizeHandlePosition.right => SystemMouseCursors.resizeLeftRight,
    ResizeHandlePosition.top ||
    ResizeHandlePosition.bottom => SystemMouseCursors.resizeUpDown,
  };

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final baseSize = _isCorner ? ResizeHandle.cornerSize : ResizeHandle.edgeSize;
    final size = _pressed ? baseSize + 2 : baseSize;
    return MouseRegion(
      cursor: _cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) {
          _setPressed(true);
          widget.onDragStart();
        },
        onPanUpdate: (details) => widget.onDragUpdate(details.delta),
        onPanEnd: (_) {
          _setPressed(false);
          widget.onDragEnd();
        },
        onPanCancel: () {
          _setPressed(false);
          widget.onDragEnd();
        },
        child: SizedBox(
          width: ResizeHandle.touchTarget,
          height: ResizeHandle.touchTarget,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: _pressed
                    ? AppColors.selectionViolet
                    : AppColors.selectionHandleFill,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.selectionViolet,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x40000000),
                    blurRadius: _pressed ? 6 : 3,
                    offset: const Offset(0, 1),
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
