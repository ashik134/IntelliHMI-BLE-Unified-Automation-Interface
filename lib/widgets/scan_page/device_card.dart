import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/ble_scan_device.dart';
import 'package:rev_crane_control_ops/widgets/circular_progress_indicator.dart';

class AvailableDeviceCard extends StatelessWidget {
  const AvailableDeviceCard({
    super.key,
    required this.device,
    required this.connecting,
    required this.onConnect,
  });

  final BleScanDevice device;
  final bool connecting;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final staleStatus = device.staleStatus;
    final isStale = staleStatus != DeviceStaleStatus.active;
    final isExpired = staleStatus == DeviceStaleStatus.expired;

    // Dimmer when another device is connecting
    final double opacity = connecting ? 0.45 : (isExpired ? 0.70 : 1.0);

    final Color borderColor = connecting
        ? AppColors.connBorder.withAlpha(120)
        : isStale
        ? AppColors.warningBorder
        : AppColors.connBorder;

    final Color cardBg = isStale
        ? AppColors.warningBg.withAlpha(90)
        : AppColors.connSurfaceAlt;

    return AnimatedOpacity(
      opacity: opacity,
      duration: const Duration(milliseconds: 300),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isStale ? AppColors.warningBg : AppColors.primarySoft,
              ),
              child: Image.asset(
                'assets/icons/Connector.png',
                color: isStale ? AppColors.connWarning : AppColors.connPrimary,
                width: 20,
                height: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        device.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isStale
                              ? AppColors.connTextSub
                              : AppColors.connText,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (isStale) _StaleIndicatorRow(isExpired: isExpired),
                    ],
                  ),
                  const SizedBox(height: 3),
                  _PlcTypeBadge(plcType: device.plcType, compact: true),
                  const SizedBox(height: 3),
                  Text(
                    device.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.connTextMuted,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 6),
                  _SignalPill(rssi: device.rssi, label: device.signalLabel),
                ],
              ),
            ),
            // Hide the connect button while another device is connecting or device is stale.
            if (!connecting && !isStale) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 92,
                child: FilledButton(
                  onPressed: onConnect,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.connPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  child: const Text('CONNECT'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Stale Indicator Row
// ═══════════════════════════════════════════════════════════
class _StaleIndicatorRow extends StatelessWidget {
  const _StaleIndicatorRow({required this.isExpired});

  final bool isExpired;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.warningBorder),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.signal_wifi_statusbar_connected_no_internet_4_rounded,
            size: 10,
            color: AppColors.connWarning,
          ),
          SizedBox(width: 4),
          Flexible(
            child: Text(
              'STALE',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: AppColors.connWarning,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalPill extends StatelessWidget {
  const _SignalPill({required this.rssi, required this.label});

  final int rssi;
  final String label;

  @override
  Widget build(BuildContext context) {
    final Color tone = rssi >= -68
        ? AppColors.connected
        : rssi >= -80
        ? AppColors.connWarning
        : AppColors.error;

    return Row(
      children: [
        Icon(Icons.signal_cellular_alt_rounded, size: 12, color: tone),
        const SizedBox(width: 5),
        Text(
          '$rssi dBm',
          style: TextStyle(
            color: tone,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Connected Device Card
// ═══════════════════════════════════════════════════════════

class ConnectedDeviceCard extends StatelessWidget {
  const ConnectedDeviceCard({
    super.key,
    required this.device,
    required this.onCancel,
    this.isCancelling = false,
  });

  final BleScanDevice device;
  final VoidCallback onCancel;
  final bool isCancelling;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 234, 241, 249),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color.fromARGB(255, 163, 192, 223)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: const Color.fromARGB(
                        255,
                        163,
                        192,
                        223,
                      ).withAlpha(30),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/icons/Connector.png',
                  color: AppColors.connPrimary,
                  width: 20,
                  height: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          device.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.connText,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(width: 4),
                        _PlcTypeBadge(plcType: device.plcType, compact: true),
                      ],
                    ),

                    const SizedBox(height: 3),
                    Text(
                      device.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.connTextMuted,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(
                width: 30,
                height: 30,
                child: CustomCircularStepProgressIndicator(
                  totalSteps: 20,
                  currentStep: 12,
                  stepSize: 20,
                  selectedColor: Colors.red,
                  unselectedColor: const Color.fromARGB(255, 71, 100, 188),
                  padding: math.pi / 80,
                  width: 30,
                  height: 30,
                  startingAngle: -math.pi * 2 / 3,
                  arcSize: math.pi * 2 / 3 * 2,
                  gradientColor: const LinearGradient(
                    colors: [
                      Color.fromARGB(255, 54, 184, 244),
                      Color.fromARGB(255, 111, 152, 224),
                    ],
                  ),
                  // rotating during cancellation to signal the abort
                  isAnimating: !isCancelling,
                ),
              ),
            ],
          ),

          // const SizedBox(height: 0),

          // ///////////////////////////
          // // _RSSIBar(rssi: device.rssi),

          // const SizedBox(height: 0),

          ///////////////////////////
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isCancelling ? null : onCancel,
              icon: isCancelling
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.connTextSub,
                      ),
                    )
                  : const Icon(Icons.close_rounded, size: 16),
              label: Text(isCancelling ? 'CANCELLING...' : 'CANCEL'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.connTextSub,
                side: BorderSide(
                  color: isCancelling
                      ? AppColors.connBorder.withAlpha(80)
                      : AppColors.connBorder,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
                backgroundColor: AppColors.connSurfaceAlt,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// PLC Type Badge
// ═══════════════════════════════════════════════════════════

class _PlcTypeBadge extends StatelessWidget {
  const _PlcTypeBadge({required this.plcType, this.compact = true});

  final PlcType plcType;
  final bool compact;

  bool get _isKnown => plcType != PlcType.unknown;
  @override
  Widget build(BuildContext context) {
    final Color bg = _isKnown
        ? AppColors.connPrimary.withAlpha(20)
        : AppColors.connSurfaceAlt;
    final Color border = _isKnown
        ? AppColors.connPrimary.withAlpha(70)
        : AppColors.connBorder;
    final Color textColor = _isKnown
        ? AppColors.connPrimary
        : AppColors.connTextMuted;
    final double fontSize = compact ? 9.5 : 11.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            plcType.displayName,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: textColor,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// RSSI Bar
// ═══════════════════════════════════════════════════════════

// class _RSSIBar extends StatelessWidget {
//   const _RSSIBar({required this.rssi});

//   final int rssi;

//   double get _signalStrength => ((rssi + 100) / 70).clamp(0.0, 1.0);

//   Color get _signalColor {
//     if (_signalStrength >= 0.65) return AppColors.connTextSub;
//     if (_signalStrength >= 0.35) return AppColors.connWarning;
//     return AppColors.error;
//   }

//   @override
//   Widget build(BuildContext context) {
//     return LayoutBuilder(
//       builder: (context, constraints) {
//         final w = constraints.maxWidth;
//         final iconSize = (w * 0.07).clamp(14.0, 22.0);
//         final containerSize = (w * 0.11).clamp(20.0, 30.0);
//         final fontSize = (w * 0.028).clamp(8.0, 10.0);

//         return Container(
//           padding: EdgeInsets.symmetric(
//             horizontal: (w * 0.02).clamp(6.0, 10.0),
//             vertical: (w * 0.015).clamp(4.0, 8.0),
//           ),
//           decoration: BoxDecoration(
//             color: Colors.white,
//             borderRadius: BorderRadius.circular(10),
//           ),
//           child: Row(
//             children: [
//               Container(
//                 width: containerSize,
//                 height: containerSize,
//                 decoration: BoxDecoration(
//                   color: _signalColor.withAlpha(20),
//                   borderRadius: BorderRadius.circular(containerSize * 0.28),
//                 ),
//                 child: Icon(
//                   Icons.signal_cellular_alt_rounded,
//                   color: _signalColor,
//                   size: iconSize,
//                 ),
//               ),

//               SizedBox(width: (w * 0.015).clamp(4.0, 8.0)),
//               Flexible(
//                 child: Text(
//                   '$rssi dBm',
//                   overflow: TextOverflow.ellipsis,
//                   style: TextStyle(
//                     color: _signalColor,
//                     fontSize: fontSize,
//                     fontWeight: FontWeight.w700,
//                     fontFamily: 'monospace',
//                   ),
//                 ),
//               ),
//               // Expanded(child: SizedBox(width: (w * 0.015).clamp(4.0, 8.0))),
//               // Signal percentage badge
//               // Container(
//               //   padding: EdgeInsets.symmetric(
//               //     horizontal: (w * 0.015).clamp(4.0, 7.0),
//               //     vertical: 2,
//               //   ),
//               //   decoration: BoxDecoration(
//               //     color: _signalColor.withAlpha(20),
//               //     borderRadius: BorderRadius.circular(6),
//               //   ),
//               //   child: Text(
//               //     '${(_signalStrength * 100).toInt()}%',
//               //     style: TextStyle(
//               //       color: _signalColor,
//               //       fontSize: fontSize,
//               //       fontWeight: FontWeight.w800,
//               //       fontFamily: 'monospace',
//               //     ),
//               //   ),
//               // ),
//             ],
//           ),
//         );
//       },
//     );
//   }
// }
