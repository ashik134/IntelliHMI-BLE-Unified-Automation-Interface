import 'dart:async';

import 'package:flutter/foundation.dart';

/// Phases of the Control Screen inactivity-timeout state machine (see
/// [InactivityController]). [expired] is a terminal, one-shot signal meaning
/// "time to run the safe-disconnect flow" — the controller has no knowledge
/// of PLC/BLE and never performs the disconnect itself; it only reports the
/// phase transition via [ChangeNotifier.notifyListeners] for the owning
/// Control Screen to act on.
enum InactivityPhase { active, sleeping, expired }

// ─────────────────────────────────────────────────────────────────────────────
// InactivityController
//
// Centralized inactivity-timeout state machine for the Control Screen:
//   active --(sleepAfter of no activity)--> sleeping
//   sleeping --(disconnectAfterSleep more of no activity)--> expired
//
// A single Timer always represents "time until the next phase transition,"
// recomputed from a wall-clock DateTime rather than trusted purely on Timer
// firing — Dart Timers are not guaranteed to fire while the app is
// backgrounded/suspended by the OS, so reconcileAfterResume re-derives the
// correct phase from real elapsed time whenever the app returns to the
// foreground instead of trusting the timer to have caught up on its own.
//
// Deliberately has no knowledge of BLE/PLC/brightness/wakelock — it only
// tracks phase and notifies listeners; the owning screen decides what
// "sleeping" (dim + simulate sleep) and "expired" (run the safe-disconnect
// flow) actually do. This keeps the manager centralized and reusable rather
// than duplicating timers into individual controls.
// ─────────────────────────────────────────────────────────────────────────────

class InactivityController extends ChangeNotifier {
  InactivityController({
    this.sleepAfter = const Duration(minutes: 3),
    this.disconnectAfterSleep = const Duration(minutes: 2),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration sleepAfter;
  final Duration disconnectAfterSleep;
  final DateTime Function() _clock;

  InactivityPhase _phase = InactivityPhase.active;
  InactivityPhase get phase => _phase;
  bool get isSleeping => _phase == InactivityPhase.sleeping;

  Timer? _timer;
  DateTime? _lastActivityAt;
  bool _running = false;
  bool _disposed = false;

  /// Begins monitoring from "just active now." Call once per Control Screen
  /// session (from initState).
  void start() {
    if (_disposed) return;
    _running = true;
    _phase = InactivityPhase.active;
    _lastActivityAt = _clock();
    _reschedule();
  }

  /// Halts monitoring without disposing — used once the phase reaches
  /// [InactivityPhase.expired], or when the PLC disconnects for some other
  /// reason before the timeout fires (nothing left to time out toward).
  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Records a genuine user interaction. Always resets the clock back to
  /// "active, sleepAfter remaining" — waking the screen (and cancelling any
  /// pending auto-disconnect) if it had already gone to sleep.
  void registerActivity() {
    if (_disposed || !_running) return;
    final wasSleeping = _phase == InactivityPhase.sleeping;
    _lastActivityAt = _clock();
    _phase = InactivityPhase.active;
    _reschedule();
    if (wasSleeping) notifyListeners();
  }

  void _reschedule() {
    _timer?.cancel();
    final threshold = _phase == InactivityPhase.sleeping
        ? sleepAfter + disconnectAfterSleep
        : sleepAfter;
    final remaining = threshold - _clock().difference(_lastActivityAt!);
    if (remaining <= Duration.zero) {
      _advance();
      return;
    }
    _timer = Timer(remaining, _advance);
  }

  void _advance() {
    if (_disposed || !_running) return;
    if (_phase == InactivityPhase.active) {
      _phase = InactivityPhase.sleeping;
      notifyListeners();
      _reschedule();
    } else if (_phase == InactivityPhase.sleeping) {
      _phase = InactivityPhase.expired;
      _running = false;
      _timer = null;
      notifyListeners();
    }
  }

  /// Re-derives the phase from real elapsed wall-clock time rather than
  /// trusting that the Dart Timer fired on schedule — it may not have while
  /// the app was backgrounded/suspended. Call from didChangeAppLifecycleState
  /// on [AppLifecycleState.resumed].
  void reconcileAfterResume() {
    if (_disposed || !_running || _lastActivityAt == null) return;
    final elapsed = _clock().difference(_lastActivityAt!);
    if (elapsed >= sleepAfter + disconnectAfterSleep) {
      _phase = InactivityPhase.expired;
      _running = false;
      _timer?.cancel();
      _timer = null;
      notifyListeners();
    } else if (elapsed >= sleepAfter) {
      final wasActive = _phase == InactivityPhase.active;
      _phase = InactivityPhase.sleeping;
      _reschedule();
      if (wasActive) notifyListeners();
    } else {
      _reschedule();
    }
  }

  /// Cancels the live Timer while the app is backgrounded — Dart Timers may
  /// be suspended by the OS and are not a reliable clock while the process
  /// isn't actively running. [reconcileAfterResume] restores correct timing
  /// from wall-clock elapsed time once the app returns to the foreground.
  void pauseTimerForBackground() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
