import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ScreenSleepOverlay
//
// The Control Screen's visible "asleep" state after the inactivity timeout —
// paired with dimming app brightness and releasing the wakelock (see the
// Control Screen's own inactivity wiring: _sleepScreen/_wakeScreen). Flutter
// cannot force a real hardware display sleep on either platform, so this
// stands in for it explicitly: a full-screen panel telling the operator
// IntelliHMI is deliberately sleeping — not frozen or crashed — with a
// gentle breathing icon so it still reads as "alive." Absorbs its first
// touch to wake rather than letting it fall through to whatever control
// happens to be underneath, so waking the screen can never also actuate
// motion the operator couldn't see to aim.
// ─────────────────────────────────────────────────────────────────────────────

class ScreenSleepOverlay extends StatefulWidget {
  const ScreenSleepOverlay({super.key, required this.onWake});

  final VoidCallback onWake;

  @override
  State<ScreenSleepOverlay> createState() => _ScreenSleepOverlayState();
}

class _ScreenSleepOverlayState extends State<ScreenSleepOverlay>
    with TickerProviderStateMixin {
  /// Slow, low-amplitude breathe — a deliberate "still alive" cue, not an
  /// attention-getter, so it reads as calm rather than a flashing alert.
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..forward();

  @override
  void dispose() {
    _breathe.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final breathe = CurvedAnimation(parent: _breathe, curve: Curves.easeInOut);
    final entrance = CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic);

    return Positioned.fill(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => widget.onWake(),
        child: FadeTransition(
          opacity: entrance,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              Center(
                child: AnimatedBuilder(
                  animation: breathe,
                  builder: (context, child) {
                    final t = breathe.value;
                    return Opacity(
                      opacity: 0.55 + 0.35 * t,
                      child: Transform.scale(scale: 0.96 + 0.05 * t, child: child),
                    );
                  },
                  child: const _SleepMessage(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SleepMessage extends StatelessWidget {
  const _SleepMessage();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.appBarGlow.withAlpha(26),
            border: Border.all(color: AppColors.appBarGlow.withAlpha(70)),
          ),
          child: const Icon(Icons.bedtime_rounded, color: AppColors.appBarGlow, size: 32),
        ),
        const SizedBox(height: 22),
        const Text(
          'Sleeping due to inactivity',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Touch anywhere to wake IntelliHMI',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withAlpha(130),
            fontSize: 12.5,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}
