import 'package:flutter/material.dart';

/// The Control Screen's simulated "asleep" state: a full-screen black
/// overlay standing in for a real hardware display sleep (which Flutter
/// cannot force on either platform) once paired with dimming app brightness
/// and releasing the wakelock — see the Control Screen's own inactivity
/// wiring. Absorbs its first touch to wake rather than letting it fall
/// through to whatever control happens to be underneath, so waking the
/// screen can never also actuate motion the operator couldn't see to aim.
class ScreenSleepOverlay extends StatelessWidget {
  const ScreenSleepOverlay({super.key, required this.onWake});

  final VoidCallback onWake;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => onWake(),
        child: const ColoredBox(color: Colors.black),
      ),
    );
  }
}
