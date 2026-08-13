import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/feedback_manager.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/alarm_indicator_config.dart'
    show AlarmSeverity;
import 'package:rev_crane_control_ops/models/feedback/alarm_feedback_config.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/feedback/feedback_palette.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FeedbackAlarmBanner
//
// The alarm overlay: a severity-coloured strip across the top of the control
// body whenever FeedbackManager resolves a non-normal severity. Tapping it
// acknowledges, which is LOCAL state only — the PLC is never told, so
// silencing the app can never be mistaken for clearing the plant condition
// (the banner keeps showing, dimmed, while the condition is still true).
// ─────────────────────────────────────────────────────────────────────────────

class FeedbackAlarmBanner extends StatelessWidget {
  const FeedbackAlarmBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<FeedbackManager>();
    final config = manager.config.alarm;
    final snapshot = manager.snapshot;

    // `severity` reads as muted once acknowledged, which is not an
    // annunciating rank — but an acknowledged alarm whose condition is still
    // true must stay on screen, so it is checked separately.
    final visible =
        config.bannerEnabled &&
        (snapshot.severity.isAnnunciating || snapshot.acknowledged);
    if (!visible) return const SizedBox.shrink();

    final severity = snapshot.acknowledged
        ? AlarmSeverity.muted
        : snapshot.severity;
    final color = FeedbackPalette.severity(severity, config: config);
    final canAcknowledge =
        config.acknowledgeEnabled && !snapshot.acknowledged;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _PulseWrapper(
        // A banner that keeps flashing after it has been acknowledged is just
        // noise — the acknowledgement is exactly the operator saying "seen".
        enabled: config.flashEnabled && !snapshot.acknowledged,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: canAcknowledge ? manager.acknowledge : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: color.withAlpha(34),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withAlpha(150)),
              ),
              child: Row(
                children: [
                  Icon(
                    snapshot.acknowledged
                        ? Icons.notifications_paused_rounded
                        : Icons.warning_amber_rounded,
                    color: color,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${config.label} — ${severity.displayLabel}'
                              .toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _detailFor(snapshot, config),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.darkTextMuted,
                            fontSize: 11,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (canAcknowledge) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: color.withAlpha(46),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: color.withAlpha(120)),
                      ),
                      child: Text(
                        'ACK',
                        style: TextStyle(
                          color: color,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Says whether the underlying condition is still true, which is the only
  /// thing an acknowledged or latched banner still has to communicate.
  String _detailFor(FeedbackSnapshot snapshot, AlarmFeedbackConfig config) {
    // An acknowledged episode ends the moment the raw condition clears (see
    // FeedbackManager._compute), so reaching here always means it is still
    // true — which is exactly what a silenced banner must keep saying.
    if (snapshot.acknowledged) {
      return 'Acknowledged — condition still active '
          '(${snapshot.rawSeverity.displayLabel}).';
    }
    if (config.latched && !snapshot.rawSeverity.isAnnunciating) {
      return 'Latched — the PLC condition has cleared. Acknowledge to reset.';
    }
    return 'Reported by the PLC. Feedback only — no command was sent.';
  }
}

/// Slow opacity breathe for an un-acknowledged alarm. A separate widget so the
/// animation controller only exists while something is actually annunciating.
class _PulseWrapper extends StatefulWidget {
  const _PulseWrapper({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<_PulseWrapper> createState() => _PulseWrapperState();
}

class _PulseWrapperState extends State<_PulseWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.enabled) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulseWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled == oldWidget.enabled) return;
    if (widget.enabled) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) =>
          Opacity(opacity: 0.62 + 0.38 * _controller.value, child: child),
      child: widget.child,
    );
  }
}
