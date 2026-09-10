import 'dart:typed_data' show Uint8List;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// Bridges the `camera` package's [CameraImage] stream to the two formats
/// the enrollment pipeline needs: an ML Kit [InputImage] (detection) and
/// an `image`-package [img.Image] (alignment/quality analysis/embedding).
///
/// This is the only place camera pixel-format details (NV21/BGRA8888,
/// plane layout, YUV-to-RGB conversion) are handled — kept separate from
/// any on-screen display transform (mirroring, aspect-fit scaling), so
/// the ML-processing coordinate space and the camera-display transform
/// never mix, per the enrollment screen's requirements.
class CameraFrameConverter {
  CameraFrameConverter._();

  /// The image format to request from [CameraController]. Both platforms
  /// resolve to a single flat plane (no multi-plane YUV_420_888 row/pixel
  /// stride handling needed): CameraX (`camera_android_camerax`) converts
  /// to a tightly-packed NV21 buffer natively when this is requested,
  /// verified against its source (`ImageProxyUtils.getNv21Buffer`,
  /// `bytesPerRow: imageProxy.width`); iOS's `camera_avfoundation`
  /// likewise delivers BGRA8888 as one interleaved plane.
  static ImageFormatGroup get preferredFormatGroup =>
      defaultTargetPlatform == TargetPlatform.iOS
      ? ImageFormatGroup.bgra8888
      : ImageFormatGroup.nv21;

  /// Converts one camera frame to an ML Kit [InputImage].
  ///
  /// Rotation compensation follows the standard formula for this plugin
  /// (matching what `CameraPreview` itself uses internally, via the same
  /// [CameraController.value.deviceOrientation] — so ML-processing
  /// rotation and on-screen preview rotation can never disagree): on
  /// Android, combine the camera's fixed [CameraDescription.sensorOrientation]
  /// with the live device orientation the `camera` plugin already tracks
  /// (added for the front camera, subtracted for the back camera);
  /// [InputImageMetadata.rotation] is unused on iOS per
  /// `google_mlkit_commons`' own doc comment, so the sensor orientation
  /// alone is passed there.
  static InputImage toInputImage(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) {
    final rawRotation = rotationDegrees(camera, deviceOrientation);
    final rotation =
        InputImageRotationValue.fromRawValue(rawRotation) ??
        InputImageRotation.rotation0deg;

    final format = image.format.group == ImageFormatGroup.bgra8888
        ? InputImageFormat.bgra8888
        : InputImageFormat.nv21;

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  /// Decodes [image] into an `image`-package RGB buffer, unmirrored and
  /// in the camera's native pixel orientation (no rotation applied — the
  /// detector already works in this same unrotated space via
  /// [toInputImage]/[sensorOrientation], so `DetectedFace.boundingBox`
  /// lines up with this image directly).
  ///
  /// This is a plain-Dart pixel conversion, not a cheap operation — only
  /// call it for frames worth the cost (i.e. once detection has already
  /// found exactly one face).
  static img.Image toRgbImage(CameraImage image) {
    final plane = image.planes.first;
    return decodePlane(
      bytes: plane.bytes,
      bytesPerRow: plane.bytesPerRow,
      width: image.width,
      height: image.height,
      formatGroup: image.format.group,
    );
  }

  /// Same conversion as [toRgbImage], factored out to take one plane's raw
  /// fields directly instead of a `camera`-package [CameraImage] — needed
  /// once decoding runs inside `FaceEnrollmentWorker`'s isolate, where only
  /// the plane bytes/metadata (plain, isolate-sendable data) have crossed
  /// the boundary, not a [CameraImage] itself ([CameraImage] and [Plane]
  /// only expose private constructors outside this package, so one can't be
  /// reconstructed on the other side regardless).
  static img.Image decodePlane({
    required Uint8List bytes,
    required int bytesPerRow,
    required int width,
    required int height,
    required ImageFormatGroup formatGroup,
  }) {
    return formatGroup == ImageFormatGroup.bgra8888
        ? _bgra8888ToImage(
            bytes: bytes,
            bytesPerRow: bytesPerRow,
            width: width,
            height: height,
          )
        : _nv21ToImage(bytes: bytes, width: width, height: height);
  }

  /// The same rotation-compensation angle applied to [toInputImage]'s
  /// metadata (and, on Android, to `CameraPreview`'s own on-screen
  /// rotation) — exposed so callers can reproduce it to reason about
  /// ML Kit's coordinate space (e.g. mapping a raw-sensor-space
  /// [DetectedFace.boundingBox] into the upright/on-screen orientation
  /// for a center/size check), without duplicating the platform-specific
  /// formula.
  static int rotationDegrees(
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) {
    return defaultTargetPlatform == TargetPlatform.iOS
        ? camera.sensorOrientation
        : _androidRotationCompensation(camera, deviceOrientation);
  }

  static int _androidRotationCompensation(
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) {
    final deviceDegrees = switch (deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };

    if (camera.lensDirection == CameraLensDirection.front) {
      return (camera.sensorOrientation + deviceDegrees) % 360;
    }
    return (camera.sensorOrientation - deviceDegrees + 360) % 360;
  }

  static img.Image _bgra8888ToImage({
    required Uint8List bytes,
    required int bytesPerRow,
    required int width,
    required int height,
  }) {
    return img.Image.fromBytes(
      width: width,
      height: height,
      bytes: bytes.buffer,
      bytesOffset: bytes.offsetInBytes,
      rowStride: bytesPerRow,
      order: img.ChannelOrder.bgra,
    );
  }

  /// NV21: a full-resolution Y plane (row-major, one byte per pixel)
  /// followed by a half-resolution, 2x2-subsampled chroma plane storing
  /// interleaved V,U byte pairs (V before U — that ordering is what
  /// distinguishes NV21 from NV12). Standard, fixed layout for this
  /// format — not something specific to this codebase.
  static img.Image _nv21ToImage({
    required Uint8List bytes,
    required int width,
    required int height,
  }) {
    final ySize = width * height;

    final out = img.Image(width: width, height: height);

    for (var y = 0; y < height; y++) {
      final rowStart = y * width;
      final uvRow = y ~/ 2;
      for (var x = 0; x < width; x++) {
        final yValue = bytes[rowStart + x].toDouble();
        final uvCol = x ~/ 2;
        final uvIndex = ySize + uvRow * width + uvCol * 2;
        final vValue = bytes[uvIndex].toDouble() - 128.0;
        final uValue = bytes[uvIndex + 1].toDouble() - 128.0;

        final r = (yValue + 1.402 * vValue).round().clamp(0, 255);
        final g = (yValue - 0.344136 * uValue - 0.714136 * vValue)
            .round()
            .clamp(0, 255);
        final b = (yValue + 1.772 * uValue).round().clamp(0, 255);

        out.setPixelRgb(x, y, r, g, b);
      }
    }

    return out;
  }
}
