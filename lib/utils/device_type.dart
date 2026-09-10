import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Utility for detecting the physical device form factor at runtime.
///
/// Detection is done once against the primary display's logical size, so it
/// is valid as early as [WidgetsFlutterBinding.ensureInitialized] has been
/// called — no [BuildContext] is required.
///
/// The 600 dp shortest-side threshold is the same boundary used by Android
/// resource qualifiers (`sw600dp`) and is the de-facto Flutter convention.
abstract final class DeviceType {
  /// Returns `true` when the shortest logical side of the primary display is
  /// at least 600 dp, which reliably identifies tablets and large foldables.
  static bool get isTablet {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final shortestSide = view.physicalSize.shortestSide / view.devicePixelRatio;
    return shortestSide >= 600;
  }

  /// Convenience inverse of [isTablet].
  static bool get isPhone => !isTablet;

  /// Orientations the app's baseline policy allows: phones are locked to
  /// portrait, tablets are left free to follow the sensor.
  static List<DeviceOrientation> get allowedOrientations => isTablet
      ? DeviceOrientation.values
      : const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown];

  /// Restores [allowedOrientations]. Screens that temporarily narrow the
  /// allowed orientations (e.g. locking to portrait for a camera capture
  /// flow) must call this on exit instead of re-enabling every orientation
  /// outright, or a phone would stay unlocked into landscape everywhere
  /// else in the app for the rest of the session.
  static Future<void> restoreDefaultOrientations() =>
      SystemChrome.setPreferredOrientations(allowedOrientations);
}
