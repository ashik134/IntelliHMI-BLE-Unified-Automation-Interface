import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/widgets/customization/selection_overlay/canvas_controller.dart';
import 'package:rev_crane_control_ops/widgets/customization/selection_overlay/resize_handle.dart';
import 'package:rev_crane_control_ops/widgets/customization/selection_overlay/selection_frame.dart';
import 'package:rev_crane_control_ops/widgets/customization/selection_overlay/widget_transformer.dart';

/// Figma/Canva-style selection layer drawn on top of a selected control
/// widget during customization mode.
///
/// This widget is intentionally ignorant of what it's wrapping — push
/// button, slider, toggle, joystick, gauge, indicator, whatever — it only
/// knows the widget's current [span] on the grid and reports proposed
/// spans back through [onResizeStart]/[onResizePreview]/[onResizeCommit]
/// and [onMoveStart]/[onMovePreview]/[onMoveCommit]. The caller (
/// [ControlSlotGrid]) owns translating a committed span into an actual
/// [ButtonConfig] mutation, so this component has zero PLC/model coupling.
class ControlSelectionOverlay extends StatefulWidget {
  const ControlSelectionOverlay({
    super.key,
    required this.span,
    required this.transformer,
    required this.canvasSize,
    required this.minColumns,
    required this.minRows,
    required this.borderRadius,
    this.showEdgeHandles = true,
    this.onResizeStart,
    required this.onResizePreview,
    required this.onResizeCommit,
    this.onResizeCancel,
    this.onMoveStart,
    this.onMovePreview,
    this.onMoveCommit,
    this.onMoveCancel,
  });

  /// The widget's current committed grid span (anchor + size).
  final GridSpan span;

  /// Pixel<->grid geometry for the canvas this widget lives on.
  final WidgetTransformer transformer;

  /// Pixel size of the canvas this widget is painted on, used to keep the
  /// frame/handles from being drawn (and therefore clipped or
  /// un-hit-testable) outside the canvas — see [_buildHandles].
  final Size canvasSize;

  final int minColumns;
  final int minRows;
  final double borderRadius;

  /// Whether to show the 4 edge midpoint handles in addition to corners.
  final bool showEdgeHandles;

  final VoidCallback? onResizeStart;

  /// Called continuously while a resize handle is dragged, with the
  /// candidate span snapped to grid cells (not yet committed).
  final ValueChanged<GridSpan> onResizePreview;

  /// Called once when the resize gesture ends with the final span.
  final ValueChanged<GridSpan> onResizeCommit;
  final VoidCallback? onResizeCancel;

  /// Move (drag-inside-frame) is optional — [ControlSlotGrid] already has
  /// its own LongPressDraggable slot-swap mechanism, so these are wired
  /// only where a lighter-weight in-place nudge is desired.
  final VoidCallback? onMoveStart;
  final ValueChanged<GridSpan>? onMovePreview;
  final ValueChanged<GridSpan>? onMoveCommit;
  final VoidCallback? onMoveCancel;

  @override
  State<ControlSelectionOverlay> createState() => _ControlSelectionOverlayState();
}

class _ControlSelectionOverlayState extends State<ControlSelectionOverlay> {
  final CanvasController _canvas = CanvasController();
  ResizeHandlePosition? _activeHandle;

  @override
  void dispose() {
    _canvas.dispose();
    super.dispose();
  }

  // Accumulates raw pointer deltas into a running pixel offset for the
  // life of one gesture, so the snap-to-cell math in WidgetTransformer
  // always sees the *total* drag distance from gesture start rather than
  // just the last frame's delta (which would under/over-shoot on rounding).
  Offset _accumulatedDelta = Offset.zero;

  void _handleResizeStart(ResizeHandlePosition handle) {
    _activeHandle = handle;
    _accumulatedDelta = Offset.zero;
    _canvas.beginGesture(widget.span);
    widget.onResizeStart?.call();
  }

  void _handleResizeUpdate(Offset delta) {
    final handle = _activeHandle;
    if (handle == null) return;
    _accumulatedDelta += delta;
    final next = widget.transformer.resize(
      origin: widget.span,
      delta: _accumulatedDelta,
      handle: handle,
      minColumns: widget.minColumns,
      minRows: widget.minRows,
    );
    _canvas.updatePreview(next);
    widget.onResizePreview(next);
  }

  void _handleResizeEnd() {
    final result = _canvas.livePreview;
    _accumulatedDelta = Offset.zero;
    _activeHandle = null;
    _canvas.endGesture();
    if (result != null) widget.onResizeCommit(result);
  }

  Offset _moveAccumulatedDelta = Offset.zero;

  void _handleMoveStart() {
    _moveAccumulatedDelta = Offset.zero;
    _canvas.beginGesture(widget.span);
    widget.onMoveStart?.call();
  }

  void _handleMoveUpdate(Offset delta) {
    _moveAccumulatedDelta += delta;
    final next = widget.transformer.move(
      origin: widget.span,
      delta: _moveAccumulatedDelta,
    );
    _canvas.updatePreview(next);
    widget.onMovePreview?.call(next);
  }

  void _handleMoveEnd() {
    final result = _canvas.livePreview;
    _moveAccumulatedDelta = Offset.zero;
    _canvas.endGesture();
    if (result != null) widget.onMoveCommit?.call(result);
  }

  static const double _frameMargin = 2;
  static const double _handleTouch = ResizeHandle.touchTarget;
  static const double _handleHalf = _handleTouch / 2;
  static const double _labelHeight = 24;
  static const double _labelGap = 6;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _canvas,
      builder: (context, _) {
        final isGesturing = _canvas.isGesturing;
        final liveSpan = _canvas.livePreview ?? widget.span;
        // While idle, the frame is drawn exactly on the widget's settled
        // rect. While gesturing, it snaps to the live preview rect instead
        // — the handles (built relative to this same Stack) move with it,
        // so there is only ever one rect to reason about.
        final settledRect = isGesturing
            ? widget.transformer.rectFor(liveSpan)
            : widget.transformer.rectFor(widget.span);

        // Clamp how far the frame/handles can sit outside the widget's own
        // edge so nothing is drawn (and therefore clipped or
        // un-hit-testable) beyond the canvas bounds — required for tiles
        // flush against a grid edge, e.g. row 0 or the last column.
        final insetLeft = math.min(_frameMargin, settledRect.left);
        final insetTop = math.min(_frameMargin, settledRect.top);
        final insetRight = math.min(
          _frameMargin,
          widget.canvasSize.width - settledRect.right,
        );
        final insetBottom = math.min(
          _frameMargin,
          widget.canvasSize.height - settledRect.bottom,
        );
        final displayRect = Rect.fromLTRB(
          settledRect.left - insetLeft,
          settledRect.top - insetTop,
          settledRect.right + insetRight,
          settledRect.bottom + insetBottom,
        );

        // The frame's visible border LINE is not flush with displayRect's
        // layout edge — strokeAlignOutside draws its centerline half a
        // stroke-width further out (see SelectionFrame.borderCenterOffset).
        // Handle centers must land on that line, not on the layout edge,
        // so a handle's box is offset by (touch-target half + line offset)
        // from displayRect, then clamped to the available canvas space so
        // the touch target itself never spills outside the SafeArea-safe
        // canvas this overlay was given.
        final lineOffset = SelectionFrame.borderCenterOffset(isGesturing);
        final target = _handleHalf + lineOffset;
        final handleLeft = math.min(target, displayRect.left + lineOffset);
        final handleTop = math.min(target, displayRect.top + lineOffset);
        final handleRight = math.min(
          target,
          widget.canvasSize.width - displayRect.right + lineOffset,
        );
        final handleBottom = math.min(
          target,
          widget.canvasSize.height - displayRect.bottom + lineOffset,
        );

        return Positioned.fromRect(
          rect: displayRect,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (widget.onMovePreview != null)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanStart: (_) => _handleMoveStart(),
                    onPanUpdate: (d) => _handleMoveUpdate(d.delta),
                    onPanEnd: (_) => _handleMoveEnd(),
                    onPanCancel: _handleMoveEnd,
                    child: SelectionFrame(
                      borderRadius: widget.borderRadius,
                      isGhost: isGesturing,
                    ),
                  ),
                )
              else
                Positioned.fill(
                  child: SelectionFrame(
                    borderRadius: widget.borderRadius,
                    isGhost: isGesturing,
                  ),
                ),
              Positioned(
                left: 0,
                top: math.max(0, -_labelHeight - _labelGap + insetTop),
                child: SelectionSizeLabel(
                  columns: liveSpan.columns,
                  rows: liveSpan.rows,
                ),
              ),
              ..._buildHandles(
                left: handleLeft,
                top: handleTop,
                right: handleRight,
                bottom: handleBottom,
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildHandles({
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) {
    return [
      Positioned(
        left: -left,
        top: -top,
        child: ResizeHandle(
          position: ResizeHandlePosition.topLeft,
          onDragStart: () => _handleResizeStart(ResizeHandlePosition.topLeft),
          onDragUpdate: _handleResizeUpdate,
          onDragEnd: _handleResizeEnd,
        ),
      ),
      Positioned(
        right: -right,
        top: -top,
        child: ResizeHandle(
          position: ResizeHandlePosition.topRight,
          onDragStart: () => _handleResizeStart(ResizeHandlePosition.topRight),
          onDragUpdate: _handleResizeUpdate,
          onDragEnd: _handleResizeEnd,
        ),
      ),
      Positioned(
        left: -left,
        bottom: -bottom,
        child: ResizeHandle(
          position: ResizeHandlePosition.bottomLeft,
          onDragStart: () =>
              _handleResizeStart(ResizeHandlePosition.bottomLeft),
          onDragUpdate: _handleResizeUpdate,
          onDragEnd: _handleResizeEnd,
        ),
      ),
      Positioned(
        right: -right,
        bottom: -bottom,
        child: ResizeHandle(
          position: ResizeHandlePosition.bottomRight,
          onDragStart: () =>
              _handleResizeStart(ResizeHandlePosition.bottomRight),
          onDragUpdate: _handleResizeUpdate,
          onDragEnd: _handleResizeEnd,
        ),
      ),
      if (widget.showEdgeHandles) ...[
        Positioned(
          left: 0,
          right: 0,
          top: -top,
          child: Center(
            child: ResizeHandle(
              position: ResizeHandlePosition.top,
              onDragStart: () => _handleResizeStart(ResizeHandlePosition.top),
              onDragUpdate: _handleResizeUpdate,
              onDragEnd: _handleResizeEnd,
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: -bottom,
          child: Center(
            child: ResizeHandle(
              position: ResizeHandlePosition.bottom,
              onDragStart: () =>
                  _handleResizeStart(ResizeHandlePosition.bottom),
              onDragUpdate: _handleResizeUpdate,
              onDragEnd: _handleResizeEnd,
            ),
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          left: -left,
          child: Center(
            child: ResizeHandle(
              position: ResizeHandlePosition.left,
              onDragStart: () => _handleResizeStart(ResizeHandlePosition.left),
              onDragUpdate: _handleResizeUpdate,
              onDragEnd: _handleResizeEnd,
            ),
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          right: -right,
          child: Center(
            child: ResizeHandle(
              position: ResizeHandlePosition.right,
              onDragStart: () =>
                  _handleResizeStart(ResizeHandlePosition.right),
              onDragUpdate: _handleResizeUpdate,
              onDragEnd: _handleResizeEnd,
            ),
          ),
        ),
      ],
    ];
  }
}
