import 'package:flutter/material.dart';
import 'package:rev6_crane_control_ops/utils/constants.dart';

class EStopSwipeButton extends StatefulWidget {
  final VoidCallback onActivated;
  final String instructionTitle;
  final String instructionSubtitle;

  const EStopSwipeButton({
    super.key,
    required this.onActivated,
    this.instructionTitle = 'SWIPE TO EMERGENCY STOP',
    this.instructionSubtitle = 'Slide right to stop all crane operations',
  });

  @override
  State<EStopSwipeButton> createState() => _EStopSwipeButtonState();
}

class _EStopSwipeButtonState extends State<EStopSwipeButton>
    with SingleTickerProviderStateMixin {
  static const double _thumbSize = 66.0;
  static const double _buttonHeight = 74.0;
  static const double _activationThreshold = 1.0;

  // ── drag state ──────────────────────────────────────────────────────────────
  double _trackWidth = 0.0;
  double _thumbOffsetPx = 0.0;
  bool _isDragging = false;

  double get _maxTravel =>
      (_trackWidth - _thumbSize).clamp(0.0, double.infinity);
  double get _progress =>
      _maxTravel > 0 ? (_thumbOffsetPx / _maxTravel).clamp(0.0, 1.0) : 0.0;

  // ── snap animation ──────────────────────────────────────────────────────────
  late AnimationController _snapController;
  double _snapStartPx = 0.0;
  bool _isSnapping = false;

  double get _displayOffset {
    if (_isSnapping) {
      return _snapStartPx * (1.0 - _snapController.value);
    }
    return _thumbOffsetPx;
  }

  double get _displayProgress {
    if (_isSnapping) {
      return _maxTravel > 0
          ? (_displayOffset / _maxTravel).clamp(0.0, 1.0)
          : 0.0;
    }
    return _progress;
  }

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _snapController.addListener(() {
      if (mounted) setState(() {});
    });
    _snapController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {
          _isSnapping = false;
          _thumbOffsetPx = 0.0;
        });
      }
    });
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  // ── gesture handlers ────────────────────────────────────────────────────────

  void _onDragStart(DragStartDetails details) {
    if (_isSnapping) {
      _snapController.stop();
      _isSnapping = false;
    }
    setState(() {
      _isDragging = true;
      _thumbOffsetPx = 0.0;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    setState(() {
      _thumbOffsetPx = (_thumbOffsetPx + details.delta.dx).clamp(
        0.0,
        _maxTravel,
      );
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    setState(() => _isDragging = false);

    if (_progress >= _activationThreshold) {
      setState(() => _thumbOffsetPx = _maxTravel);
      widget.onActivated();
    } else {
      _snapStartPx = _thumbOffsetPx;
      _isSnapping = true;
      _snapController.forward(from: 0.0);
    }
  }

  // ── build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _trackWidth = constraints.maxWidth;
        final thumbLeft = _displayOffset;
        final progress = _displayProgress;

        return GestureDetector(
          // Only horizontal drag triggers the swipe; incidental taps are ignored.
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          child: SizedBox(
            width: double.infinity,
            height: _buttonHeight,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF2A0000),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.eStopColor.withAlpha(170),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.eStopColor.withAlpha(
                      (70 + (progress * 80).round()),
                    ),
                    blurRadius: 12 + progress * 8,
                    spreadRadius: 1,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14.5),
                child: Stack(
                  children: [
                    // ── track tick marks (decorative, industrial look) ──────
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _TrackTickPainter(
                          thumbEnd: thumbLeft + _thumbSize,
                          color: Colors.white.withAlpha(18),
                        ),
                      ),
                    ),

                    // ── progress fill ───────────────────────────────────────
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: (thumbLeft + _thumbSize).clamp(
                        0.0,
                        constraints.maxWidth,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(
                                0xFF6B0000,
                              ).withAlpha((160 + progress * 95).round()),
                              AppColors.eStopColor.withAlpha(
                                (140 + progress * 115).round(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // ── instruction label ───────────────────────────────────
                    Positioned.fill(
                      child: Opacity(
                        opacity: (1.0 - progress * 1.5).clamp(0.0, 1.0),
                        child: Padding(
                          padding: const EdgeInsets.only(
                            left: _thumbSize * 0.5,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (int i = 0; i < 3; i++)
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.white.withAlpha(55 + i * 35),
                                  size: 18,
                                ),
                              const SizedBox(width: 4),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.instructionTitle,
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  Text(
                                    widget.instructionSubtitle,
                                    style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 9.5,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // ── thumb handle ────────────────────────────────────────
                    Positioned(
                      left: thumbLeft,
                      top: 0,
                      bottom: 0,
                      width: _thumbSize,
                      child: Container(
                        margin: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE74C3C), Color(0xFF8B1A1A)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withAlpha(60),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(130),
                              blurRadius: 6,
                              offset: const Offset(2, 2),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.power_settings_new,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paints evenly-spaced vertical tick marks on the track to reinforce the
/// directional / industrial look without being distracting.
class _TrackTickPainter extends CustomPainter {
  final double thumbEnd;
  final Color color;

  const _TrackTickPainter({required this.thumbEnd, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    const spacing = 12.0;
    final count = (size.width / spacing).floor();
    for (int i = 1; i < count; i++) {
      final x = i * spacing;
      if (x < thumbEnd) continue; // hide ticks under the fill
      canvas.drawLine(
        Offset(x, size.height * 0.3),
        Offset(x, size.height * 0.7),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TrackTickPainter old) =>
      old.thumbEnd != thumbEnd || old.color != color;
}
