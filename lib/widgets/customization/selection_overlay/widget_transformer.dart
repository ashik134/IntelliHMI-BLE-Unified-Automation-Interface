import 'dart:math' as math;
import 'dart:ui';

/// Which resize handle is being dragged. Corner handles resize two edges at
/// once; edge handles resize a single axis.
enum ResizeHandlePosition {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  top,
  bottom,
  left,
  right,
}

/// A grid span expressed in whole cells, anchored at [x],[y] with size
/// [columns]x[rows] on a grid of [gridColumns]x[gridRows] cells.
class GridSpan {
  const GridSpan({
    required this.x,
    required this.y,
    required this.columns,
    required this.rows,
  });

  final int x;
  final int y;
  final int columns;
  final int rows;

  GridSpan copyWith({int? x, int? y, int? columns, int? rows}) => GridSpan(
    x: x ?? this.x,
    y: y ?? this.y,
    columns: columns ?? this.columns,
    rows: rows ?? this.rows,
  );

  @override
  bool operator ==(Object other) =>
      other is GridSpan &&
      other.x == x &&
      other.y == y &&
      other.columns == columns &&
      other.rows == rows;

  @override
  int get hashCode => Object.hash(x, y, columns, rows);
}

/// Pure geometry helper that converts pixel drag deltas into grid-cell
/// mutations, independent of any specific widget/button implementation.
///
/// Holds no state — every method is a pure function of its inputs — so it
/// can be shared by [ControlSelectionOverlay]'s move and resize gestures alike.
class WidgetTransformer {
  const WidgetTransformer({
    required this.cellWidth,
    required this.cellHeight,
    required this.spacing,
    required this.gridColumns,
    required this.gridRows,
  });

  final double cellWidth;
  final double cellHeight;
  final double spacing;
  final int gridColumns;
  final int gridRows;

  double get columnStride => cellWidth + spacing;
  double get rowStride => cellHeight + spacing;

  /// The pixel rect for a given [span] within the canvas.
  Rect rectFor(GridSpan span) {
    return Rect.fromLTWH(
      span.x * columnStride,
      span.y * rowStride,
      span.columns * cellWidth + (span.columns - 1) * spacing,
      span.rows * cellHeight + (span.rows - 1) * spacing,
    );
  }

  /// Rounds a pixel delta to the nearest whole number of grid cells.
  int _cellDelta(double pixelDelta, double stride) {
    if (stride <= 0) return 0;
    return (pixelDelta / stride).round();
  }

  /// Applies a raw pixel [delta] to [origin], snapping to whole grid cells
  /// and clamping so the span never leaves the canvas or goes below
  /// [minColumns]x[minRows]. Used for both move and resize previews.
  GridSpan resize({
    required GridSpan origin,
    required Offset delta,
    required ResizeHandlePosition handle,
    required int minColumns,
    required int minRows,
  }) {
    final dCols = _cellDelta(delta.dx, columnStride);
    final dRows = _cellDelta(delta.dy, rowStride);

    var x = origin.x;
    var y = origin.y;
    var columns = origin.columns;
    var rows = origin.rows;

    final growsRight = switch (handle) {
      ResizeHandlePosition.topRight ||
      ResizeHandlePosition.bottomRight ||
      ResizeHandlePosition.right => true,
      _ => false,
    };
    final growsLeft = switch (handle) {
      ResizeHandlePosition.topLeft ||
      ResizeHandlePosition.bottomLeft ||
      ResizeHandlePosition.left => true,
      _ => false,
    };
    final growsBottom = switch (handle) {
      ResizeHandlePosition.bottomLeft ||
      ResizeHandlePosition.bottomRight ||
      ResizeHandlePosition.bottom => true,
      _ => false,
    };
    final growsTop = switch (handle) {
      ResizeHandlePosition.topLeft ||
      ResizeHandlePosition.topRight ||
      ResizeHandlePosition.top => true,
      _ => false,
    };

    if (growsRight) {
      columns = (origin.columns + dCols).clamp(
        minColumns,
        gridColumns - origin.x,
      );
    } else if (growsLeft) {
      final maxGrowLeft = origin.x;
      final requested = -dCols;
      final grow = requested.clamp(-(origin.columns - minColumns), maxGrowLeft);
      columns = origin.columns + grow;
      x = origin.x - grow;
    }

    if (growsBottom) {
      rows = (origin.rows + dRows).clamp(minRows, gridRows - origin.y);
    } else if (growsTop) {
      final maxGrowTop = origin.y;
      final requested = -dRows;
      final grow = requested.clamp(-(origin.rows - minRows), maxGrowTop);
      rows = origin.rows + grow;
      y = origin.y - grow;
    }

    return GridSpan(x: x, y: y, columns: columns, rows: rows);
  }

  /// Applies a raw pixel [delta] as a move, snapping the anchor to whole
  /// grid cells and clamping so the span stays fully inside the canvas.
  GridSpan move({required GridSpan origin, required Offset delta}) {
    final dCols = _cellDelta(delta.dx, columnStride);
    final dRows = _cellDelta(delta.dy, rowStride);
    final maxX = math.max(0, gridColumns - origin.columns);
    final maxY = math.max(0, gridRows - origin.rows);
    final x = (origin.x + dCols).clamp(0, maxX);
    final y = (origin.y + dRows).clamp(0, maxY);
    return origin.copyWith(x: x, y: y);
  }
}
