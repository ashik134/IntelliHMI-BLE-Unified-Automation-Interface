import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'package:rev_crane_control_ops/models/detected_face.dart';
import 'package:rev_crane_control_ops/models/face_quality_result.dart';

/// Thin wrapper over `google_mlkit_face_detection`'s `FaceDetector`, plus
/// pure quality evaluation on its output (spec section 8).
///
/// [evaluateQuality] is deliberately independent of [detectFaces] itself
/// — it operates only on the already-converted [DetectedFace] data — so
/// it's unit-testable without ML Kit's real native detector, which needs
/// Android + Google Play Services and cannot run in this dev environment.
/// [detectFaces] itself can only be verified on an actual device.
///
/// Not checked here (scoped out of Stage 3, not an oversight): lighting
/// and blur. ML Kit's `Face` doesn't expose either, and a real check
/// needs the raw pixel buffer, which fits Stage 4's capture flow more
/// naturally (it already has the buffer in scope for cropping/embedding).
class FaceDetectionService {
  FaceDetectionService()
    : _detector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          enableTracking: true,
          enableLandmarks: true,
          performanceMode: FaceDetectorMode.accurate,
        ),
      );

  final FaceDetector _detector;

  /// Whether this platform's native ML Kit detector already rotates its
  /// results into the *upright* frame described by the `rotationDegrees`
  /// passed into `InputImageMetadata` (see
  /// `CameraFrameConverter.toInputImage`), as opposed to returning them in
  /// the raw, unrotated sensor-buffer frame `imageSize` describes.
  ///
  /// This is exactly backwards on the two platforms this app ships to, and
  /// getting it wrong silently corrupts every centering/size check for a
  /// 90°/270° rotation — i.e. almost every real capture, since a
  /// portrait-held phone with a landscape-mounted sensor is the ordinary
  /// case. Verified by reading the plugin's native glue directly (not just
  /// its Dart-side doc comments), because that's the only ground truth
  /// available without a physical device:
  ///
  /// - **Android** (`google_mlkit_commons`'
  ///   `InputImageConverter.handleBytesImage`, `google_mlkit_face_detection`'s
  ///   `FaceDetector.kt`): the raw byte array is handed to
  ///   `com.google.mlkit.vision.common.InputImage.fromByteArray(data, width,
  ///   height, rotationDegrees, format)` — the *original*, un-rotated
  ///   `width`/`height` plus a rotation hint. That factory exists
  ///   specifically so ML Kit can account for rotation internally without
  ///   the caller pre-rotating the pixel buffer, and its Android
  ///   implementation returns detection results already expressed in the
  ///   *rotated* (upright) frame — the standard ML Kit Android convention.
  /// - **iOS** (`google_mlkit_commons`'
  ///   `MLKVisionImage+FlutterPlugin.swift`, `bytesToVisionImage`): builds
  ///   the `VisionImage` straight from the raw `CVPixelBuffer` and never
  ///   reads or applies the `rotation` metadata field at all on this
  ///   camera-stream path — no `orientation` is set. Results stay in the
  ///   raw, unrotated sensor frame, so [uprightRect]/[uprightSize] are the
  ///   only place rotation gets applied on iOS.
  ///
  /// If this ever needs correcting for a newer plugin version, this is the
  /// one place to flip.
  static bool get _detectorPreRotatesResults =>
      defaultTargetPlatform != TargetPlatform.iOS;

  Future<List<DetectedFace>> detectFaces(
    InputImage image,
    Size imageSize, {
    int rotationDegrees = 0,
  }) async {
    final faces = await _detector.processImage(image);
    return faces
        .map((f) => _fromMlKitFace(f, imageSize, rotationDegrees))
        .toList();
  }

  Future<void> close() => _detector.close();

  static DetectedFace _fromMlKitFace(
    Face face,
    Size imageSize,
    int rotationDegrees,
  ) {
    var boundingBox = face.boundingBox;
    var leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
    var rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;

    // Normalize ML Kit's output back to the same raw, unrotated frame
    // `imageSize` and the RGB buffer (`CameraFrameConverter.toRgbImage`,
    // never rotated) are in — see `_detectorPreRotatesResults`. Without
    // this, `FaceAlignmentService`/`FrameQualityAnalyzer` crop the raw
    // buffer using coordinates from a different, rotated frame, and
    // `evaluateQuality`'s own upright-rotation below would double-rotate
    // an already-upright box.
    if (_detectorPreRotatesResults && rotationDegrees != 0) {
      boundingBox = downrightRect(boundingBox, imageSize, rotationDegrees);
      if (leftEye != null) {
        leftEye = _downrightPoint(leftEye, imageSize, rotationDegrees);
      }
      if (rightEye != null) {
        rightEye = _downrightPoint(rightEye, imageSize, rotationDegrees);
      }
    }

    return DetectedFace(
      boundingBox: boundingBox,
      imageSize: imageSize,
      headEulerAngleX: face.headEulerAngleX,
      headEulerAngleY: face.headEulerAngleY,
      headEulerAngleZ: face.headEulerAngleZ,
      leftEyeOpenProbability: face.leftEyeOpenProbability,
      rightEyeOpenProbability: face.rightEyeOpenProbability,
      smilingProbability: face.smilingProbability,
      leftEyePosition: leftEye,
      rightEyePosition: rightEye,
    );
  }

  // ── Quality evaluation — pure function, see class doc ───────────────────

  static const double minFaceWidthFraction = 0.25;
  static const double maxFaceWidthFraction = 0.85;
  static const double maxCenterOffsetFraction = 0.22;
  static const double maxPoseAngle = 20.0;

  /// [rotationDegrees] is the same rotation-compensation angle passed to
  /// ML Kit for detection (`CameraFrameConverter.rotationDegrees`/
  /// `toInputImage`). `DetectedFace.boundingBox`/[imageSize] are in raw,
  /// unrotated sensor space (e.g. landscape on a phone whose sensor is
  /// mounted landscape, even while the phone is held portrait) — every
  /// geometry check below needs to reason in the *upright*, on-screen
  /// orientation instead, or a 90°/270° rotation silently swaps the
  /// width/height and left-right/up-down axes against what the operator
  /// actually sees (and what the on-screen guide oval is measured
  /// against). Defaults to 0 (no-op) so existing unrotated callers/tests
  /// are unaffected.
  static FaceQualityResult evaluateQuality(
    List<DetectedFace> faces,
    Size imageSize, {
    int rotationDegrees = 0,
  }) {
    if (faces.isEmpty) {
      return const FaceQualityResult(
        passed: false,
        issues: [FaceQualityIssue.noFaceDetected],
      );
    }
    if (faces.length > 1) {
      return const FaceQualityResult(
        passed: false,
        issues: [FaceQualityIssue.multipleFacesDetected],
      );
    }

    final face = faces.single;
    final issues = <FaceQualityIssue>[];
    FaceOffsetDirection? offsetDirection;

    final uprightImageSize = uprightSize(imageSize, rotationDegrees);
    final uprightBox = uprightRect(
      face.boundingBox,
      imageSize,
      rotationDegrees,
    );

    final widthFraction = uprightBox.width / uprightImageSize.width;
    if (widthFraction < minFaceWidthFraction) {
      issues.add(FaceQualityIssue.faceTooSmall);
    } else if (widthFraction > maxFaceWidthFraction) {
      issues.add(FaceQualityIssue.faceTooLarge);
    }

    final faceCenter = uprightBox.center;
    final imageCenter = Offset(
      uprightImageSize.width / 2,
      uprightImageSize.height / 2,
    );
    final shortestSide = uprightImageSize.shortestSide == 0
        ? 1.0
        : uprightImageSize.shortestSide;
    final centerDelta = faceCenter - imageCenter;
    final offsetFraction = centerDelta.distance / shortestSide;
    if (offsetFraction > maxCenterOffsetFraction) {
      issues.add(FaceQualityIssue.offCenter);
      offsetDirection = centerDelta.dx.abs() >= centerDelta.dy.abs()
          ? (centerDelta.dx > 0
                ? FaceOffsetDirection.left
                : FaceOffsetDirection.right)
          : (centerDelta.dy > 0
                ? FaceOffsetDirection.up
                : FaceOffsetDirection.down);
    }

    final yaw = face.headEulerAngleY;
    final pitch = face.headEulerAngleX;
    if ((yaw != null && yaw.abs() > maxPoseAngle) ||
        (pitch != null && pitch.abs() > maxPoseAngle)) {
      issues.add(FaceQualityIssue.extremePose);
    }

    if (face.leftEyeOpenProbability == null ||
        face.rightEyeOpenProbability == null) {
      issues.add(FaceQualityIssue.eyesNotVisible);
    }

    return FaceQualityResult(
      passed: issues.isEmpty,
      issues: issues,
      offsetDirection: offsetDirection,
      centerOffsetFraction: offsetFraction,
      widthFraction: widthFraction,
    );
  }

  /// [imageSize] rotated into the upright orientation: a 90°/270°
  /// compensation swaps width and height (landscape sensor → portrait
  /// display); 0°/180° leaves them as-is.
  static Size uprightSize(Size imageSize, int rotationDegrees) {
    return rotationDegrees == 90 || rotationDegrees == 270
        ? Size(imageSize.height, imageSize.width)
        : imageSize;
  }

  /// Maps an axis-aligned [rect] in raw sensor space (sized [rawSize])
  /// into the axis-aligned rect it becomes once rotated clockwise by
  /// [rotationDegrees] to the upright orientation — the same convention
  /// `InputImageRotation`/`CameraFrameConverter.rotationDegrees` use.
  static Rect uprightRect(Rect rect, Size rawSize, int rotationDegrees) {
    switch (rotationDegrees) {
      case 90:
        return Rect.fromLTRB(
          rawSize.height - rect.bottom,
          rect.left,
          rawSize.height - rect.top,
          rect.right,
        );
      case 180:
        return Rect.fromLTRB(
          rawSize.width - rect.right,
          rawSize.height - rect.bottom,
          rawSize.width - rect.left,
          rawSize.height - rect.top,
        );
      case 270:
        return Rect.fromLTRB(
          rect.top,
          rawSize.width - rect.right,
          rect.bottom,
          rawSize.width - rect.left,
        );
      default:
        return rect;
    }
  }

  /// Inverse of [uprightRect]: maps a rect already expressed in the
  /// upright/on-screen frame back into the raw, unrotated sensor frame
  /// [DetectedFace.boundingBox] must be in for cropping the (never
  /// rotated) RGB buffer. Needed only on the platform(s) where the native
  /// detector already rotates its own results — see
  /// [_detectorPreRotatesResults].
  ///
  /// Derived algebraically from [uprightRect]: rotating raw→upright by
  /// `R` is undone by rotating upright→raw by `360-R`, applied to a rect
  /// already sized to the upright frame (`uprightSize(originalRawSize,
  /// R)`) rather than the original raw one. Round-trips exactly for all
  /// four rotations — see the unit tests.
  static Rect downrightRect(
    Rect rect,
    Size originalRawSize,
    int rotationDegrees,
  ) {
    final inverseRotation = (360 - rotationDegrees) % 360;
    final rectSpaceSize = uprightSize(originalRawSize, rotationDegrees);
    return uprightRect(rect, rectSpaceSize, inverseRotation);
  }

  /// Point counterpart of [downrightRect] — reuses it via a degenerate
  /// zero-size rect so the same tested rotation math applies to a single
  /// landmark coordinate (e.g. an eye position) instead of a bounding box.
  static math.Point<int> _downrightPoint(
    math.Point<int> point,
    Size originalRawSize,
    int rotationDegrees,
  ) {
    final asRect = Rect.fromLTWH(point.x.toDouble(), point.y.toDouble(), 0, 0);
    final transformed = downrightRect(asRect, originalRawSize, rotationDegrees);
    return math.Point<int>(transformed.left.round(), transformed.top.round());
  }

  /// The on-screen radius (in the same logical-pixel units as
  /// [screenSize]) that exactly matches [maxCenterOffsetFraction] once the
  /// upright camera frame is displayed via a `BoxFit.cover`-style
  /// transform (see `_CoverCameraPreview` in the enrollment/verify
  /// screens) into [screenSize] — i.e. the guide circle a screen should
  /// draw so "the face's center is inside this circle" and "the centering
  /// check passes" are the same statement, not two independently-chosen
  /// numbers that only coincidentally agree on any one device/orientation.
  ///
  /// [cameraAspectRatio] is `CameraController.value.aspectRatio` — the
  /// `camera` package always reports this as `previewSize.width /
  /// previewSize.height` in the camera's *raw* (typically landscape)
  /// sensor orientation, never swapped for display. `CameraPreview` itself
  /// (see its `build`/`_isLandscape()`) renders at the *inverse* of that
  /// ratio whenever the device orientation isn't landscape — which for
  /// this app is always, since both capture screens lock to
  /// `DeviceOrientation.portraitUp` in `initState`. Hence the inversion
  /// below is unconditional rather than re-deriving `_isLandscape()`.
  static double centerToleranceRadiusPx({
    required Size screenSize,
    required double cameraAspectRatio,
  }) {
    if (screenSize.isEmpty || cameraAspectRatio <= 0) return 0;

    final displayAspectRatio = 1 / cameraAspectRatio;

    // Standard BoxFit.cover closed form: the axis that would overflow
    // under BoxFit.contain is instead held exactly to the bound, and the
    // other is enlarged past it.
    final Size displayed;
    if (displayAspectRatio > screenSize.aspectRatio) {
      displayed = Size(
        screenSize.height * displayAspectRatio,
        screenSize.height,
      );
    } else {
      displayed = Size(
        screenSize.width,
        screenSize.width / displayAspectRatio,
      );
    }

    return maxCenterOffsetFraction * displayed.shortestSide;
  }
}
