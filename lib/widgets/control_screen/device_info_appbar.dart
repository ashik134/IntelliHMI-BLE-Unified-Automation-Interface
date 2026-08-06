import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/ble_connection_state.dart';
import 'package:rev_crane_control_ops/models/ble_scan_device.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ControlAppBarGlow
//
// Soft violet radial bloom for the control-screen AppBar's flexibleSpace —
// barely visible but adds depth above the violet-tinted bar background.
// ─────────────────────────────────────────────────────────────────────────────

class ControlAppBarGlow extends StatelessWidget {
  const ControlAppBarGlow({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -1.8),
            radius: 1.6,
            colors: [
              AppColors.appBarGlow.withAlpha(31),
              AppColors.appBarGlow.withAlpha(0),
            ],
            stops: const [0.0, 0.7],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EditModeAppBarTitle
//
// Replaces DeviceInfoAppBarTitle in the AppBar while Customization/Edit Mode
// is active, so the title itself — not just a small icon — announces the
// mode change: an edit glyph plus "Customization Mode" and a one-line hint,
// in place of the tappable device/RSSI readout that isn't relevant while
// editing (outputs are blocked, so RSSI/connection detail is a distraction).
// ─────────────────────────────────────────────────────────────────────────────

class EditModeAppBarTitle extends StatelessWidget {
  const EditModeAppBarTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.selectionViolet.withAlpha(46),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.edit_rounded,
            size: 16,
            color: AppColors.selectionViolet,
          ),
        ),
        const SizedBox(width: 10),
        // Flexible so this shrinks to whatever width the AppBar's title slot
        // actually has left — e.g. narrower once Undo/Redo join the actions
        // row in Edit Mode (see EditModeUndoRedoActions) — letting the Texts'
        // own ellipsis do its job instead of the Row hard-overflowing.
        const Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Customization Mode',
                maxLines: 1,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.darkText,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Tap a widget to select or delete',
                maxLines: 1,
                overflow: TextOverflow.visible,
                style: TextStyle(fontSize: 10.5, color: AppColors.darkTextSub),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CustomizationModeBanner
//
// Replaces the AppBar's thin bottom accent line while Customization/Edit
// Mode is active. Deliberately louder than the normal-mode line (solid
// violet fill, bold uppercase text) so the AppBar's bottom edge alone makes
// the state obvious at a glance, and states the safety rule plainly — PLC
// outputs stay blocked for the whole edit session (see
// LayoutEditController.enter, which force-latches E-STOP on entry, and
// ControlCanvas/_CanvasSection.isDisabled, which disable every button while
// isEditing is true).
// ─────────────────────────────────────────────────────────────────────────────

/// Fixed-height AppBar footer for both control-screen modes.
///
/// Only its paint changes by mode. Its footprint stays constant so the
/// Scaffold body and the Expanded control canvas receive identical viewport
/// constraints before and after Edit Mode.
class ControlModeAppBarFooter extends StatelessWidget
    implements PreferredSizeWidget {
  const ControlModeAppBarFooter({super.key, required this.isEditing});

  final bool isEditing;

  static const double height = 28;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    if (isEditing) return const CustomizationModeBanner();

    return const SizedBox(
      height: height,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.appBarBanner,
            border: Border(
              bottom: BorderSide(color: AppColors.appBarBannerBorder),
            ),
          ),
          child: SizedBox(height: 3, width: double.infinity),
        ),
      ),
    );
  }
}

class CustomizationModeBanner extends StatelessWidget
    implements PreferredSizeWidget {
  const CustomizationModeBanner({super.key});

  @override
  Size get preferredSize =>
      const Size.fromHeight(ControlModeAppBarFooter.height);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: preferredSize.height,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.selectionVioletDeep,
        border: Border(
          bottom: BorderSide(color: AppColors.selectionViolet, width: 2),
        ),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline_rounded, size: 13, color: Colors.white),
          SizedBox(width: 6),
          Text(
            'OUTPUTS BLOCKED — LAYOUT EDITING ONLY',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EditModeUndoRedoActions
//
// AppBar-actions pair for Customization Mode: Undo/Redo over the in-progress
// draft (LayoutEditController.undo/redo — see that controller's history
// doc comment for what counts as one undo step). Each button watches only
// its own enabled flag via context.select, so a draft mutation elsewhere on
// the canvas only rebuilds this pair when Undo/Redo availability actually
// flips, not on every notifyListeners tick.
// ─────────────────────────────────────────────────────────────────────────────

class EditModeUndoRedoActions extends StatelessWidget {
  const EditModeUndoRedoActions({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [_UndoButton(), _RedoButton()],
    );
  }
}

class _UndoButton extends StatelessWidget {
  const _UndoButton();

  @override
  Widget build(BuildContext context) {
    final canUndo = context.select<LayoutEditController, bool>(
      (c) => c.canUndo,
    );
    return IconButton(
      icon: const Icon(Icons.undo, size: 20),
      color: AppColors.darkText,
      disabledColor: AppColors.darkTextMuted.withAlpha(90),
      tooltip: 'Undo',
      onPressed: canUndo
          ? () => context.read<LayoutEditController>().undo()
          : null,
    );
  }
}

class _RedoButton extends StatelessWidget {
  const _RedoButton();

  @override
  Widget build(BuildContext context) {
    final canRedo = context.select<LayoutEditController, bool>(
      (c) => c.canRedo,
    );
    return IconButton(
      icon: const Icon(Icons.redo, size: 20),
      color: AppColors.darkText,
      disabledColor: AppColors.darkTextMuted.withAlpha(90),
      tooltip: 'Redo',
      onPressed: canRedo
          ? () => context.read<LayoutEditController>().redo()
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DeviceInfoAppBarTitle
//
// Normal-mode AppBar title: device name + PLC type + live RSSI, tappable to
// open the connected-system details popup. RSSI is read straight off
// CraneController (already pushed live by BleService's 3s RSSI poll via
// connectionStream), so this widget updates on the same notifyListeners tick
// as the rest of the screen — no separate polling of its own.
// ─────────────────────────────────────────────────────────────────────────────

class DeviceInfoAppBarTitle extends StatelessWidget {
  const DeviceInfoAppBarTitle({
    super.key,
    required this.deviceName,
    required this.plcType,
    required this.rssi,
  });

  final String deviceName;
  final PlcType plcType;
  final int? rssi;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showDeviceInfoPopup(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              deviceName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.darkText,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    plcType.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.appBarGlow,
                    ),
                  ),
                ),
                if (rssi != null) ...[
                  const SizedBox(width: 6),
                  Icon(
                    _signalIcon(rssi!),
                    size: 12,
                    color: AppColors.darkTextSub,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '$rssi dBm',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.darkTextSub,
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                const Icon(
                  Icons.info_outline_rounded,
                  size: 12,
                  color: AppColors.darkTextSub,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static IconData _signalIcon(int rssi) {
    if (rssi >= -55) return Icons.signal_cellular_alt_rounded;
    if (rssi >= -68) return Icons.signal_cellular_alt_2_bar_rounded;
    if (rssi >= -80) return Icons.signal_cellular_alt_1_bar_rounded;
    return Icons.signal_cellular_0_bar_rounded;
  }
}

Future<void> showDeviceInfoPopup(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => const _DeviceInfoDialog(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _DeviceInfoDialog
//
// Read-only snapshot of the connected system, taken at open time. Deliberately
// not wrapped in a Consumer/listener — RSSI ticking mid-dialog would cause a
// distracting rebuild of a modal the operator is trying to read; they can
// reopen it for a fresh reading.
// ─────────────────────────────────────────────────────────────────────────────

class _DeviceInfoDialog extends StatelessWidget {
  const _DeviceInfoDialog();

  @override
  Widget build(BuildContext context) {
    final controller = context.read<CraneController>();
    final BleConnectionState connState = controller.connectionState;
    final BleScanDevice? device = connState.connectedDevice;
    final PlcType plcType = controller.connectedPlcType;
    final BluetoothDevice? bleDevice = device?.device;

    final rows = <_InfoRowData>[
      _InfoRowData(
        'Device name',
        device?.name ??
            controller.connectedDeviceName ??
            BLEConstants.deviceName,
      ),
      _InfoRowData('PLC type', plcType.displayName),
      _InfoRowData(
        'Device ID / MAC',
        bleDevice?.remoteId.str ?? device?.id ?? '—',
      ),
      _InfoRowData(
        'RSSI',
        device?.rssi != null
            ? '${device!.rssi} dBm  (${device.signalLabel})'
            : '—',
      ),
      _InfoRowData(
        'Connection status',
        _statusLabel(connState.status, controller.isConnected),
      ),
      _InfoRowData(
        'Bluetooth device state',
        bleDevice == null
            ? 'Unknown'
            : (bleDevice.isConnected ? 'Connected' : 'Disconnected'),
      ),
      const _InfoRowData(
        'Manufacturer data prefix',
        BLEConstants.manufacturerDataPrefix,
      ),
      _InfoRowData('Service UUID', _shortUuid(BLEConstants.serviceUuid)),
      _InfoRowData(
        'Characteristics',
        controller.isConnected ? 'Configured' : 'Not discovered',
      ),
      const _InfoRowData('Firmware / device info', 'Not reported by PLC'),
    ];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.panelStroke),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogHeader(plcType: plcType),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                  child: Column(
                    children: [for (final row in rows) _InfoRow(data: row)],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'CLOSE',
                      style: TextStyle(
                        color: AppColors.appBarGlow,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _statusLabel(BleConnectionStatus status, bool isConnected) {
    return switch (status) {
      BleConnectionStatus.disconnected => 'Disconnected',
      BleConnectionStatus.scanning => 'Scanning',
      BleConnectionStatus.connecting => 'Connecting',
      BleConnectionStatus.discoveringServices => 'Discovering services',
      BleConnectionStatus.configuringNotifications =>
        'Configuring notifications',
      BleConnectionStatus.initializingSafeState => 'Initializing safe state',
      BleConnectionStatus.connected => 'Connected',
      BleConnectionStatus.awaitingAuthentication => 'Awaiting authentication',
      BleConnectionStatus.authenticating => 'Authenticating',
      BleConnectionStatus.authenticated => 'Authenticated • Connected',
      BleConnectionStatus.error => 'Error',
    };
  }

  static String _shortUuid(String uuid) {
    if (uuid.length <= 13) return uuid;
    return '${uuid.substring(0, 8)}…${uuid.substring(uuid.length - 4)}';
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.plcType});

  final PlcType plcType;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
      decoration: const BoxDecoration(
        color: AppColors.appBarBanner,
        border: Border(bottom: BorderSide(color: AppColors.appBarBannerBorder)),
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.developer_board_rounded,
            size: 18,
            color: AppColors.appBarGlow,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Connected System Details',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.darkText,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AppColors.darkTextSub,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _InfoRowData {
  const _InfoRowData(this.label, this.value);
  final String label;
  final String value;
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.data});

  final _InfoRowData data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              data.label,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.darkTextSub,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              data.value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.darkText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
