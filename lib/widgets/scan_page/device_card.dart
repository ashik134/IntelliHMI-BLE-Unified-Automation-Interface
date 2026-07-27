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
                color: AppColors.connPrimary,
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
                      _SignalPill(rssi: device.rssi, label: device.signalLabel),
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
        color: AppColors.brandWarningSoft,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: const Color.fromARGB(127, 248, 24, 16).withAlpha(80),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning, size: 10, color: Color.fromARGB(255, 247, 57, 9)),
          SizedBox(width: 4),
          Flexible(
            child: Text(
              'STALE',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: Color.fromARGB(255, 247, 57, 9),
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
        ? AppColors.brandSuccess
        : rssi >= -80
        ? AppColors.brandWarning
        : AppColors.brandDanger;

    return Row(
      children: [
        // Icon(Icons.signal_cellular_alt_rounded, size: 13, color: tone),
        // const SizedBox(width: 5),
        Text(
          '$rssi dBm',
          style: TextStyle(
            color: tone,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(width: 6),
        Container(
          width: 3,
          height: 3,
          decoration: const BoxDecoration(
            color: AppColors.brandTextMuted,
            shape: BoxShape.circle,
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.brandVioletSoft,
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        border: Border.all(color: AppColors.brandViolet.withAlpha(70)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brandViolet.withAlpha(50),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.developer_board_rounded,
                  color: AppColors.brandViolet,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            device.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.brandText,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _PlcTypeBadge(plcType: device.plcType, compact: true),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      device.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.brandTextMuted,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 32,
                height: 32,
                child: CustomCircularStepProgressIndicator(
                  totalSteps: 20,
                  currentStep: 12,
                  stepSize: 20,
                  selectedColor: AppColors.brandDanger,
                  unselectedColor: AppColors.brandViolet.withAlpha(70),
                  padding: math.pi / 80,
                  width: 32,
                  height: 32,
                  startingAngle: -math.pi * 2 / 3,
                  arcSize: math.pi * 2 / 3 * 2,
                  gradientColor: const LinearGradient(
                    colors: [AppColors.brandViolet, AppColors.brandVioletDeep],
                  ),
                  // rotating during cancellation to signal the abort
                  isAnimating: !isCancelling,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
                        color: AppColors.brandTextSub,
                      ),
                    )
                  : const Icon(Icons.close_rounded, size: 16),
              label: Text(isCancelling ? 'CANCELLING...' : 'CANCEL'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brandTextSub,
                side: BorderSide(
                  color: isCancelling
                      ? AppColors.brandBorder.withAlpha(80)
                      : AppColors.brandBorderStrong,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                ),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
                backgroundColor: Colors.white,
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
        ? AppColors.brandViolet.withAlpha(20)
        : AppColors.brandSurfaceAlt;
    final Color border = _isKnown
        ? AppColors.brandViolet.withAlpha(70)
        : AppColors.brandBorder;
    final Color textColor = _isKnown
        ? AppColors.brandVioletDeep
        : AppColors.brandTextMuted;
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
      child: Text(
        plcType.displayName,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          color: textColor,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
