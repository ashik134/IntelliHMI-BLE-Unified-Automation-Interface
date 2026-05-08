import 'package:permission_handler/permission_handler.dart';

class PermissionState {
  const PermissionState({
    required this.isGranted,
    required this.isPermanentlyDenied,
  });

  const PermissionState.initial()
    : isGranted = false,
      isPermanentlyDenied = false;

  final bool isGranted;
  final bool isPermanentlyDenied;
}

class PermissionService {
  static const List<Permission> requiredPermissions = [
    Permission.bluetooth,
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ];

  Future<PermissionState> requestPermissions() async {
    final statuses = await requiredPermissions.request();
    final isPermanentlyDenied = statuses.values.any(
      (status) => status.isPermanentlyDenied,
    );

    final isGranted =
        statuses[Permission.bluetoothScan]?.isGranted == true &&
        statuses[Permission.bluetoothConnect]?.isGranted == true;

    return PermissionState(
      isGranted: isGranted,
      isPermanentlyDenied: isPermanentlyDenied,
    );
  }

  Future<void> openSettings() async {
    await openAppSettings();
  }
}
