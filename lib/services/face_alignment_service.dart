import 'dart:math' as math;

import 'package:image/image.dart' as img;

import 'package:rev_crane_control_ops/models/detected_face.dart';

/// Produces an aligned, cropped face image ready for
/// `FaceEmbeddingService.embed` (which only resizes to 112x112 and
/// normalizes — it does no alignment of its own; see its `cropToFace`,
/// which is axis-aligned crop only).
///
/// Alignment corrects in-plane head roll (ear-toward-shoulder tilt) by
/// rotating a padded crop around its own center so the eye line becomes
/// horizontal, using the eye landmark positions ML Kit reports (see
/// `DetectedFace.leftEyePosition`/`rightEyePosition`). Rotating a small
/// crop around its own center — rather than the full camera frame — means
/// the face's position relative to the crop never needs to be
/// recalculated after rotating: `image`'s `copyRotate` always keeps the
/// source center at the destination center and only grows the canvas, so
/// a plain center-crop afterward is always valid.
///
/// This only runs on samples that already passed
/// `FaceDetectionService.evaluateQuality` (which requires both eyes
/// visible), so landmark positions should reliably be present; if they
/// aren't (edge case), this falls back to an unrotated center crop rather
/// than rejecting the sample outright.
class FaceAlignmentService {
  FaceAlignmentService._();

  /// The padded crop's side length, as a multiple of the detected face
  /// box's larger dimension. Must be at least `sqrt(2)` times
  /// [_finalCropFactor] so the final square's corners never sample
  /// outside the padded crop after rotation (rotation preserves distance
  /// from center, so this is a fixed geometric requirement, not a guess).
  static const double _paddingFactor = 2.0;

  /// The final aligned crop's side length, as a multiple of the face
  /// box's larger dimension — a little looser than the raw box so the
  /// embedding sees some context around the face, matching the intent of
  /// `FaceEmbeddingService.cropToFace`'s fixed-pixel padding.
  static const double _finalCropFactor = 1.3;

  static img.Image align({
    required img.Image sourceImage,
    required DetectedFace face,
  }) {
    final box = face.boundingBox;
    final faceSize = math.max(box.width, box.height);
    final paddedSide = faceSize * _paddingFactor;
    final centerX = box.center.dx;
    final centerY = box.center.dy;

    final left = (centerX - paddedSide / 2)
        .clamp(0, sourceImage.width - 1)
        .round();
    final top = (centerY - paddedSide / 2)
        .clamp(0, sourceImage.height - 1)
        .round();
    final right = (centerX + paddedSide / 2)
        .clamp(left + 1, sourceImage.width)
        .round();
    final bottom = (centerY + paddedSide / 2)
        .clamp(top + 1, sourceImage.height)
        .round();

    final padded = img.copyCrop(
      sourceImage,
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );

    final leftEye = face.leftEyePosition;
    final rightEye = face.rightEyePosition;
    if (leftEye == null || rightEye == null) {
      return _centerSquareCrop(padded, faceSize);
    }

    // ML Kit's landmark naming is subject-relative: in a normal, level,
    // unmirrored frame, the subject's own left eye sits at a *larger* x
    // than their right eye (it's on the viewer's right). So the vector
    // that points along +x for a level face is (leftEye - rightEye), not
    // the other way around — using (rightEye - leftEye) here would treat
    // an already-level face as tilted ~180° and rotate it upside down.
    //
    // atan2(dy, dx) on that vector, in pixel (y-down) coordinates, gives
    // the eye line's clockwise tilt from horizontal; `image`'s
    // copyRotate(angle: θ) rotates content clockwise by θ (verified
    // against its orthogonal-angle fast path: a 90° rotate moves the
    // top-left source pixel to the top-right of the destination, i.e.
    // clockwise). Rotating by the negative of the measured tilt therefore
    // levels the eye line.
    final dx = (leftEye.x - rightEye.x).toDouble();
    final dy = (leftEye.y - rightEye.y).toDouble();
    final rollDegrees = math.atan2(dy, dx) * 180 / math.pi;

    final rotated = img.copyRotate(
      padded,
      angle: -rollDegrees,
      interpolation: img.Interpolation.linear,
    );

    return _centerSquareCrop(rotated, faceSize);
  }

  static img.Image _centerSquareCrop(img.Image image, double faceSize) {
    final maxAvailable = math.min(image.width, image.height).toDouble();
    final size = math.min(faceSize * _finalCropFactor, maxAvailable).round();
    final left = ((image.width - size) / 2).round();
    final top = ((image.height - size) / 2).round();
    return img.copyCrop(image, x: left, y: top, width: size, height: size);
  }
}
