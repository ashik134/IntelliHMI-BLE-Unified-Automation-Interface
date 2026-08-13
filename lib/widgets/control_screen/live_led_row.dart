import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';

class LedSpec {
  const LedSpec({
    required this.label,
    required this.active,
    required this.color,
    this.inactiveColor,
    this.pulseWhenInactive = false,
    this.pulseDuration = const Duration(milliseconds: 1000),
    this.pin,
  });

  final String label;
  final bool active;
  final Color color;
  final Color? inactiveColor;
  final bool pulseWhenInactive;
  final Duration pulseDuration;
  final String? pin;
}

class LiveLedRow extends StatelessWidget {
  const LiveLedRow({super.key, required this.leds});

  final List<LedSpec> leds;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [for (final led in leds) _LedIndicator(spec: led)],
      ),
    );
  }
}

class _LedIndicator extends StatefulWidget {
  const _LedIndicator({required this.spec});

  final LedSpec spec;

  @override
  State<_LedIndicator> createState() => _LedIndicatorState();
}

class _LedIndicatorState extends State<_LedIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final CurvedAnimation _pulse;

  LedSpec get spec => widget.spec;

  bool get _shouldPulse =>
      !spec.active && spec.pulseWhenInactive && spec.inactiveColor != null;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: spec.pulseDuration);
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOutCubic);
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _LedIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spec.pulseDuration != spec.pulseDuration) {
      _pulseCtrl.duration = spec.pulseDuration;
    }
    _syncPulse();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _syncPulse() {
    if (_shouldPulse) {
      if (!_pulseCtrl.isAnimating) {
        _pulseCtrl.repeat(reverse: true);
      }
      return;
    }

    _pulseCtrl.stop();
    _pulseCtrl.value = 0.0;
  }

  Color _indicatorColor(double pulseValue) {
    if (spec.active) return spec.color;

    final readyColor = spec.inactiveColor;
    if (readyColor == null) return Colors.grey.shade600;

    return Color.lerp(readyColor.withAlpha(185), readyColor, pulseValue)!;
  }

  List<BoxShadow> _indicatorShadows({
    required double activeValue,
    required double pulseValue,
  }) {
    if (spec.active) {
      return [
        BoxShadow(
          color: spec.color.withAlpha(153),
          blurRadius: 4 * activeValue,
          spreadRadius: 1,
        ),
      ];
    }

    if (!_shouldPulse) return const <BoxShadow>[];

    final readyColor = spec.inactiveColor!;
    return [
      BoxShadow(
        color: readyColor.withAlpha((78 + (92 * pulseValue)).round()),
        blurRadius: 5 + (8 * pulseValue),
        spreadRadius: 0.5 + (1.5 * pulseValue),
      ),
      BoxShadow(
        color: readyColor.withAlpha((26 + (38 * pulseValue)).round()),
        blurRadius: 11 + (12 * pulseValue),
        spreadRadius: 1.5 + (2.5 * pulseValue),
      ),
    ];
  }

  Color get _labelColor {
    if (spec.active) return spec.color;
    if (_shouldPulse) return spec.inactiveColor!.withAlpha(210);
    return AppColors.darkTextMuted;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: spec.active ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 300),
          builder: (context, activeValue, _) {
            return AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (context, _) {
                final pulseValue = _shouldPulse ? _pulse.value : 0.0;

                return Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: _indicatorColor(pulseValue),
                    shape: BoxShape.circle,
                    boxShadow: _indicatorShadows(
                      activeValue: activeValue,
                      pulseValue: pulseValue,
                    ),
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(height: 4),
        // Text(
        //   spec.pin ?? '',
        //   style: const TextStyle(
        //     fontSize: 6,
        //     fontWeight: FontWeight.bold,
        //     color: AppColors.darkTextSub,
        //   ),
        // ),
        Text(
          spec.label,
          style: TextStyle(
            fontSize: 8,
            color: _labelColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
