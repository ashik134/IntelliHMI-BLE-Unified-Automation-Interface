import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/catalog_preview_stage.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SettlingPreviewOverlay
//
// The brief, non-cancelable final leg of a catalogue placement
// (CustomizationInteractionMode.settlingWidget) OR an existing-widget move
// (CustomizationInteractionMode.settlingMovedWidget) — both flows share this
// one widget: tweens the SAME preview visual (CatalogPreviewStage — never a
// different-looking widget) from wherever the finger released ([startRect])
// into the validated grid rectangle LayoutEditController already found
// ([endRect]), animating both position AND size together so the widget
// never teleports. [config] is either the pending catalogue entry's preview
// config or the real ButtonConfig of the widget being moved — see
// CatalogPreviewStage's doc comment.
//
// Placed directly as a Stack child in the control screen (the same Stack
// PlacementCancelBar and EditModeToolbarHost already live in) rather than a
// manually-managed OverlayEntry — [startRect]/[endRect] are already in
// global/overlay coordinates (see LayoutEditController.handleCatalogueDrop/
// handleMoveDrop), and that Stack fills the whole screen from its own
// (0, 0), so global coordinates double as Positioned coordinates here
// exactly like PlacementCancelBar's own Positioned(top: 0, left: 0, ...)
// already assumes.
//
// [onSettled] — LayoutEditController.commitSettledPlacement or
// .commitMovedPlacement — adds/repositions the real ButtonConfig in the
// draft and flips interactionMode back to editing in the SAME
// notifyListeners() call that removes this widget from the tree, so there
// is no frame where neither the floating preview nor the real grid button
// is visible, and at most one frame where both are (at the identical final
// rectangle, so indistinguishable from a clean handoff).
// ─────────────────────────────────────────────────────────────────────────────

class SettlingPreviewOverlay extends StatefulWidget {
  const SettlingPreviewOverlay({
    super.key,
    required this.config,
    required this.previewSize,
    required this.startRect,
    required this.endRect,
    required this.onSettled,
  });

  final ButtonConfig config;
  final Size previewSize;
  final Rect startRect;
  final Rect endRect;
  final VoidCallback onSettled;

  @override
  State<SettlingPreviewOverlay> createState() =>
      _SettlingPreviewOverlayState();
}

class _SettlingPreviewOverlayState extends State<SettlingPreviewOverlay>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 220);

  late final AnimationController _controller;
  late final Animation<Rect?> _rect;
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
    _rect = RectTween(begin: widget.startRect, end: widget.endRect).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.addStatusListener(_handleStatus);
    _controller.forward();
  }

  void _handleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _settled) return;
    _settled = true;
    widget.onSettled();
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Positioned must stay the direct Stack child for its rect to take
    // effect, so IgnorePointer wraps only the content, not this widget.
    return AnimatedBuilder(
      animation: _controller,
      child: IgnorePointer(
        child: RepaintBoundary(
          child: CatalogPreviewStage(
            config: widget.config,
            previewSize: widget.previewSize,
          ),
        ),
      ),
      builder: (context, child) {
        final rect = _rect.value ?? widget.endRect;
        return Positioned.fromRect(rect: rect, child: child!);
      },
    );
  }
}
