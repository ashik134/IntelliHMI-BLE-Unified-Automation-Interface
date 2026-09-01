import 'package:flutter_test/flutter_test.dart';
import 'package:rev_crane_control_ops/features/operator_auth/face/face_recognition_engine.dart';

void main() {
  group('FaceFrameAnalysis quality guidance', () {
    test('maps lighting failures to actionable guidance', () {
      const analysis = FaceFrameAnalysis(
        faces: [],
        processingTime: Duration(milliseconds: 10),
        qualityAccepted: false,
        qualityFailureCode: 'dynamic_range',
      );

      expect(analysis.qualityGuidance, 'Improve the lighting on your face');
    });

    test('maps pose failures to actionable guidance', () {
      const analysis = FaceFrameAnalysis(
        faces: [],
        processingTime: Duration(milliseconds: 10),
        qualityAccepted: false,
        qualityFailureCode: 'yaw',
      );

      expect(analysis.qualityGuidance, 'Look directly at the camera');
    });

    test('uses a safe generic message for an unknown SDK check', () {
      const analysis = FaceFrameAnalysis(
        faces: [],
        processingTime: Duration(milliseconds: 10),
        qualityAccepted: false,
        qualityFailureCode: 'future_sdk_check',
      );

      expect(
        analysis.qualityGuidance,
        'Improve face position, lighting, and image clarity',
      );
    });
  });

  test('face count is derived without retaining camera data', () {
    const analysis = FaceFrameAnalysis(
      faces: [
        NormalizedFaceBounds(left: 0.1, top: 0.2, right: 0.6, bottom: 0.8),
      ],
      processingTime: Duration(milliseconds: 20),
      qualityAccepted: true,
      liveness: FaceLivenessVerdict.real,
      livenessConfidence: 0.95,
    );

    expect(analysis.faceCount, 1);
    expect(analysis.liveness, FaceLivenessVerdict.real);
    expect(analysis.livenessConfidence, 0.95);
  });
}
