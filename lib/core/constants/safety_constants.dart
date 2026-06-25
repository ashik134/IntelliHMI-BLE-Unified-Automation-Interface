class SafetyConstants {
  SafetyConstants._();

  static const Duration scanTimeout = Duration(seconds: 8);
  static const Duration authReplyTimeout = Duration(seconds: 6);
  static const Duration estopPulse = Duration(milliseconds: 300);
    static const Duration heartbeatInterval = Duration(milliseconds: 50);
}
