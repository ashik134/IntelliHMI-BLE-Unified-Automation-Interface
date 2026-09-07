import 'package:shared_preferences/shared_preferences.dart';

/// Device-level lockout after repeated failed face-verification attempts —
/// mirrors [AdminAccessPinService]'s counter/lockout pattern exactly, but as
/// its own independent service: a failed face match never identifies who
/// attempted it, so this can only ever be a global per-device counter, not
/// a per-operator one. `SharedPreferences` (not secure storage) is the
/// right store here too — these are just counters, not secrets, same as
/// the PIN service's own lockout keys.
class FaceVerificationLockoutService {
  FaceVerificationLockoutService._();

  static const String _kFailedAttempts =
      'face_verification_failed_attempts';
  static const String _kLockedUntil =
      'face_verification_locked_until_epoch_ms';

  static const int maxFailedAttempts = 5;
  static const Duration lockoutDuration = Duration(minutes: 5);

  /// Seconds remaining until verification is allowed again, or 0.
  static Future<int> remainingLockoutSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final lockedUntil = prefs.getInt(_kLockedUntil);
    if (lockedUntil == null) return 0;
    final remainingMs = lockedUntil - DateTime.now().millisecondsSinceEpoch;
    return remainingMs > 0 ? (remainingMs / 1000).ceil() : 0;
  }

  static Future<int> failedAttemptCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kFailedAttempts) ?? 0;
  }

  /// Records one failed attempt and returns whether *this* call just
  /// tripped the lockout — lets the caller report "locked out" immediately
  /// on the attempt that crosses the threshold, rather than "failed" now
  /// and "locked out" only from the next call.
  static Future<bool> recordFailedAttempt() async {
    final prefs = await SharedPreferences.getInstance();
    final attempts = (prefs.getInt(_kFailedAttempts) ?? 0) + 1;
    await prefs.setInt(_kFailedAttempts, attempts);
    if (attempts >= maxFailedAttempts) {
      final until = DateTime.now()
          .add(lockoutDuration)
          .millisecondsSinceEpoch;
      await prefs.setInt(_kLockedUntil, until);
      return true;
    }
    return false;
  }

  /// Clears the failure counter and any active lockout — called on a
  /// successful verification.
  static Future<void> recordSuccess() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kFailedAttempts);
    await prefs.remove(_kLockedUntil);
  }

  /// Test-only: remove all stored lockout state.
  static Future<void> resetForTesting() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kFailedAttempts);
    await prefs.remove(_kLockedUntil);
  }
}
