import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rev_crane_control_ops/services/face_verification_lockout_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('remains allowed below the failure threshold', () async {
    for (var i = 0; i < FaceVerificationLockoutService.maxFailedAttempts - 1;
        i++) {
      final trippedLockout =
          await FaceVerificationLockoutService.recordFailedAttempt();
      expect(trippedLockout, isFalse);
    }

    expect(await FaceVerificationLockoutService.remainingLockoutSeconds(), 0);
    expect(
      await FaceVerificationLockoutService.failedAttemptCount(),
      FaceVerificationLockoutService.maxFailedAttempts - 1,
    );
  });

  test('locks out exactly at the failure threshold', () async {
    bool? trippedLockout;
    for (var i = 0; i < FaceVerificationLockoutService.maxFailedAttempts;
        i++) {
      trippedLockout =
          await FaceVerificationLockoutService.recordFailedAttempt();
    }

    expect(trippedLockout, isTrue);
    final remaining =
        await FaceVerificationLockoutService.remainingLockoutSeconds();
    expect(remaining, greaterThan(0));
    expect(
      remaining,
      lessThanOrEqualTo(FaceVerificationLockoutService.lockoutDuration.inSeconds),
    );
  });

  test('recordSuccess clears the failure counter and any lockout', () async {
    for (var i = 0; i < FaceVerificationLockoutService.maxFailedAttempts;
        i++) {
      await FaceVerificationLockoutService.recordFailedAttempt();
    }
    expect(
      await FaceVerificationLockoutService.remainingLockoutSeconds(),
      greaterThan(0),
    );

    await FaceVerificationLockoutService.recordSuccess();

    expect(await FaceVerificationLockoutService.remainingLockoutSeconds(), 0);
    expect(await FaceVerificationLockoutService.failedAttemptCount(), 0);
  });
}
