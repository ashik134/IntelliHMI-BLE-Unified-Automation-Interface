import 'package:flutter/foundation.dart';

/// Temporary diagnostic logger for the spring-return release-flicker
/// investigation. Traces every state-transition source in the shared button
/// pipeline (USER_DOWN/UP/CANCEL, SEND_ACTIVE/IDLE, PLC_STATUS_*,
/// VISUAL_ACTIVE/IDLE) so a stray source overriding local release state is
/// immediately visible in the debug console. Debug-only (stripped from
/// release builds by [kDebugMode]); safe to remove once the pipeline is
/// verified stable in the field.
class ButtonStateLog {
  const ButtonStateLog._();

  static void log(String message) {
    if (!kDebugMode) return;
    debugPrint('[BTN] $message');
  }
}
