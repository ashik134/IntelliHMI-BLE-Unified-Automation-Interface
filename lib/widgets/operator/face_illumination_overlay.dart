import 'package:flutter/material.dart';

/// Uses the device screen itself as a front-facing light source during
/// face enrollment: paints an opaque white area over everything *outside*
/// the guide oval, while the oval itself is left fully transparent so the
/// live camera preview underneath stays visible there. Paired with a
/// temporarily raised screen brightness (see `FaceEnrollmentScreen`, which
/// owns that side of the effect), the white surround acts as a soft,
/// shadow-filling ring light in low-light conditions — the phone's own
/// display substitutes for a physical light source.
///
/// [ovalDiameter] must match the guide ring drawn by [FaceCaptureOverlay]
/// exactly (same value, same centering) — both are meant to line up as one
/// visual: illumination outside, live preview inside, guide ring on the
/// seam between them.
///
/// [active] drives an opacity fade rather than an instant show/hide, per
/// this feature's requirement that brightening the screen never reads as a
/// flash — see `FaceEnrollmentScreen`'s doc comment on when [active] flips.
class FaceIlluminationOverlay extends StatelessWidget {
  const FaceIlluminationOverlay({
    super.key,
    required this.active,
    required this.ovalDiameter,
  });

  final bool active;
  final double ovalDiameter;

  static const Duration _fadeDuration = Duration(milliseconds: 600);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: active ? 1.0 : 0.0,
        duration: _fadeDuration,
        curve: Curves.easeInOut,
        child: CustomPaint(
          painter: _IlluminationPainter(ovalDiameter: ovalDiameter),
        ),
      ),
    );
  }
}

/// Paints a full-bounds white fill with a circular hole cut out of its
/// center, via even-odd path difference rather than e.g. a radial gradient
/// or `BackdropFilter` — the hole must be exactly transparent (not merely
/// dim) so the requirement "the area inside the oval must remain fully
/// visible as the live camera preview" holds pixel-for-pixel, not just
/// approximately.
class _IlluminationPainter extends CustomPainter {
  _IlluminationPainter({required this.ovalDiameter});

  final double ovalDiameter;

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Offset.zero & size;
    final ovalRect = Rect.fromCenter(
      center: fullRect.center,
      width: ovalDiameter,
      height: ovalDiameter,
    );

    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(fullRect),
      Path()..addOval(ovalRect),
    );

    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _IlluminationPainter oldDelegate) =>
      oldDelegate.ovalDiameter != ovalDiameter;
}
