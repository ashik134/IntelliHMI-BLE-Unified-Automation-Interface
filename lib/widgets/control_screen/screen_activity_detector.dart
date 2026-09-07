import 'dart:async';

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ScreenActivityDetector
//
// Wraps [child] with centralized touch-activity detection for the whole
// subtree beneath it — button presses, joystick/slider drags, toggles, and
// plain screen touches all surface as raw pointer events here regardless of
// which descendant GestureDetector ultimately claims the gesture (Flutter
// routes pointer events to every Listener along the hit-test path
// independently of gesture-arena results), so a single instance of this
// widget can watch an entire screen without instrumenting each control
// individually.
//
// Also treats a continuous, motionless hold (e.g. an operator holding a
// joystick still through a long, slow hoist lift) as ongoing activity: a
// held pointer alone produces no further onPointerMove events, so without
// this a "last pointer-event time" check would incorrectly treat the
// operator as inactive mid-operation.
// ─────────────────────────────────────────────────────────────────────────────

class ScreenActivityDetector extends StatefulWidget {
  const ScreenActivityDetector({
    super.key,
    required this.onActivity,
    required this.child,
  });

  final VoidCallback onActivity;
  final Widget child;

  @override
  State<ScreenActivityDetector> createState() =>
      _ScreenActivityDetectorState();
}

class _ScreenActivityDetectorState extends State<ScreenActivityDetector> {
  static const _holdPingInterval = Duration(seconds: 30);

  int _activePointers = 0;
  Timer? _holdTicker;

  void _onPointerDown(PointerDownEvent event) {
    _activePointers++;
    widget.onActivity();
    _holdTicker ??= Timer.periodic(_holdPingInterval, (_) {
      if (_activePointers > 0) widget.onActivity();
    });
  }

  void _onPointerMove(PointerMoveEvent event) => widget.onActivity();

  void _onPointerEnd(PointerEvent event) {
    if (_activePointers > 0) _activePointers--;
    if (_activePointers == 0) {
      _holdTicker?.cancel();
      _holdTicker = null;
    }
  }

  @override
  void dispose() {
    _holdTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: widget.child,
    );
  }
}
