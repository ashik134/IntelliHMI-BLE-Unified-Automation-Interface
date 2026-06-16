import 'dart:async';

import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';

typedef StartupProgressCallback = void Function(String message);

class AppStartupInitializer {
  AppStartupInitializer({required CraneController controller})
    : _controller = controller;

  final CraneController _controller;

  Future<void> initialize({StartupProgressCallback? onProgress}) async {
    onProgress?.call('Applying runtime policies');
    await _safeTask(() async {
      await WakelockPlus.enable();
    });

    onProgress?.call('Preparing BLE and safety services');
    await _controller.initialize();

    onProgress?.call('Startup checks complete');
  }

  Future<void> _safeTask(Future<void> Function() task) async {
    try {
      await task();
    } catch (_) {
      // Non-fatal startup tasks should never crash the app launch.
    }
  }
}
