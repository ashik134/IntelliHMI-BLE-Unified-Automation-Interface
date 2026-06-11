export 'package:rev_crane_control_ops/core/theme/app_colors.dart';
export 'package:rev_crane_control_ops/core/constants/app_constants.dart';
export 'package:rev_crane_control_ops/core/constants/ble_constants.dart';
export 'package:rev_crane_control_ops/core/constants/safety_constants.dart';

enum ControlState { idle, slow, fast }

const Map<ControlState, List<int>> plcOutputUp = {
  ControlState.idle: [0, 0, 0, 0],
  ControlState.slow: [0, 1, 0, 0],
  ControlState.fast: [0, 1, 0, 1],
};

const Map<ControlState, List<int>> plcOutputDown = {
  ControlState.idle: [0, 0, 0, 0],
  ControlState.slow: [0, 0, 1, 0],
  ControlState.fast: [0, 0, 1, 1],
};

const List<int> plcConflict = [0, 0, 0, 0];
