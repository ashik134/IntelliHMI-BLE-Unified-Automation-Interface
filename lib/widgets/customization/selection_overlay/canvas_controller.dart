import 'package:flutter/foundation.dart';

import 'package:rev_crane_control_ops/widgets/customization/selection_overlay/widget_transformer.dart';

/// Ephemeral, per-canvas live-gesture state for the selection overlay.
///
/// This is deliberately separate from [CustomizationModeController]: that
/// controller owns the *committed-per-frame* draft layout (undo/redo, PLC
/// bucket, persistence). This controller only owns the transient preview
/// shown *while a finger is down* — the ghost frame position/size that
/// hasn't been committed to the draft yet. Keeping it separate means every
/// pixel of drag motion repaints only the overlay, not the whole grid.
class CanvasController extends ChangeNotifier {
  GridSpan? _livePreview;
  bool _isGesturing = false;

  /// The in-progress span while dragging/resizing, or null when idle.
  GridSpan? get livePreview => _livePreview;
  bool get isGesturing => _isGesturing;

  void beginGesture(GridSpan origin) {
    _isGesturing = true;
    _livePreview = origin;
    notifyListeners();
  }

  void updatePreview(GridSpan next) {
    if (next == _livePreview) return;
    _livePreview = next;
    notifyListeners();
  }

  void endGesture() {
    _isGesturing = false;
    _livePreview = null;
    notifyListeners();
  }
}
