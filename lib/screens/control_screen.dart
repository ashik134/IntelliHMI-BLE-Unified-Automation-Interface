import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rev6_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev6_crane_control_ops/controllers/hmi_layout_controller.dart';
import 'package:rev6_crane_control_ops/models/hmi_layout_models.dart';
import 'package:rev6_crane_control_ops/screens/hmi_configuration_screen.dart';
import 'package:rev6_crane_control_ops/utils/constants.dart';
import 'package:rev6_crane_control_ops/widgets/hmi/hmi_runtime_widget.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  CraneController? _craneController;
  String? _lastDisconnectMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<CraneController>();
    if (_craneController != controller) {
      _craneController?.removeListener(_onCraneControllerChanged);
      _craneController = controller;
      _craneController?.addListener(_onCraneControllerChanged);
    }
  }

  @override
  void dispose() {
    _craneController?.removeListener(_onCraneControllerChanged);
    super.dispose();
  }

  void _onCraneControllerChanged() {
    if (!mounted || _craneController == null) {
      return;
    }
    final controller = _craneController!;
    if (controller.isDisconnected) {
      final message = controller.errorMessage ?? 'Disconnected from PLC';
      if (_lastDisconnectMessage == message) {
        return;
      }
      _lastDisconnectMessage = message;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 3),
            backgroundColor: AppColors.eStopColor,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<CraneController, HmiLayoutController>(
      builder: (context, craneController, hmiController, _) {
        final profile = hmiController.activeProfile;
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  craneController.connectedDeviceName ??
                      BLEConstants.deviceName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Row(
                  children: [
                    const Icon(
                      Icons.circle,
                      size: 8,
                      color: AppColors.upColorLight,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      hmiController.editMode ? 'Edit Mode' : 'Run Mode',
                      style: TextStyle(
                        color: hmiController.editMode
                            ? AppColors.fastColor
                            : AppColors.upColorLight,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: hmiController.editMode
                    ? 'Exit drag/resize mode'
                    : 'Enable drag/resize mode',
                icon: Icon(
                  hmiController.editMode
                      ? Icons.edit_location_alt_rounded
                      : Icons.edit_location_alt_outlined,
                  color: hmiController.editMode
                      ? AppColors.fastColor
                      : AppColors.textSecondary,
                ),
                onPressed: () =>
                    hmiController.setEditMode(!hmiController.editMode),
              ),
              IconButton(
                tooltip: 'Open configuration',
                icon: const Icon(
                  Icons.tune_rounded,
                  color: AppColors.textSecondary,
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const HmiConfigurationScreen(),
                    ),
                  );
                },
              ),
              IconButton(
                tooltip: 'Disconnect',
                icon: const Icon(
                  Icons.bluetooth_disabled_rounded,
                  color: AppColors.textSecondary,
                ),
                onPressed: craneController.disconnect,
              ),
            ],
          ),
          body: SafeArea(
            maintainBottomViewPadding: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                children: [
                  _LayoutInfoBanner(
                    profile: profile,
                    issueCount: hmiController.layoutIssues.length,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: profile == null
                        ? const _EmptyRuntimeState()
                        : _RuntimeCanvas(
                            profile: profile,
                            craneController: craneController,
                            hmiController: hmiController,
                          ),
                  ),
                  const SizedBox(height: 8),
                  _LiveStatusStrip(
                    craneController: craneController,
                    hmiController: hmiController,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LayoutInfoBanner extends StatelessWidget {
  const _LayoutInfoBanner({required this.profile, required this.issueCount});

  final HmiLayoutProfile? profile;
  final int issueCount;

  @override
  Widget build(BuildContext context) {
    if (profile == null) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Profile: ${profile!.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${profile!.widgets.length} widgets',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            issueCount == 0 ? 'Validated' : '$issueCount issue(s)',
            style: TextStyle(
              color: issueCount == 0
                  ? AppColors.upColorLight
                  : AppColors.fastColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RuntimeCanvas extends StatelessWidget {
  const _RuntimeCanvas({
    required this.profile,
    required this.craneController,
    required this.hmiController,
  });

  final HmiLayoutProfile profile;
  final CraneController craneController;
  final HmiLayoutController hmiController;

  @override
  Widget build(BuildContext context) {
    final widgets = profile.widgets.where((widget) => widget.visible).toList();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.panelAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
          if (widgets.isEmpty) {
            return const _EmptyRuntimeState();
          }
          return Stack(
            children: [
              for (final widget in widgets)
                Positioned(
                  left: widget.layout.x * constraints.maxWidth,
                  top: widget.layout.y * constraints.maxHeight,
                  width: widget.layout.width * constraints.maxWidth,
                  height: widget.layout.height * constraints.maxHeight,
                  child: HmiRuntimeWidget(
                    config: widget,
                    craneController: craneController,
                    hmiController: hmiController,
                    editMode: hmiController.editMode,
                    selected: widget.id == hmiController.selectedWidgetId,
                    onTap: () => hmiController.selectWidget(widget.id),
                    onDragUpdate: (details) {
                      hmiController.moveWidgetByPixels(
                        widgetId: widget.id,
                        deltaPixels: details.delta,
                        canvasSize: canvasSize,
                      );
                    },
                    onDragEnd: hmiController.finalizeLayoutGesture,
                    onResizeUpdate: (details) {
                      hmiController.resizeWidgetByPixels(
                        widgetId: widget.id,
                        deltaPixels: details.delta,
                        canvasSize: canvasSize,
                      );
                    },
                    onResizeEnd: hmiController.finalizeLayoutGesture,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _LiveStatusStrip extends StatelessWidget {
  const _LiveStatusStrip({
    required this.craneController,
    required this.hmiController,
  });

  final CraneController craneController;
  final HmiLayoutController hmiController;

  @override
  Widget build(BuildContext context) {
    final statusColor = craneController.estopLatched
        ? AppColors.eStopColor
        : switch (craneController.hoistState) {
            HoistState.idle => AppColors.idleColor,
            HoistState.upSlow => AppColors.upColor,
            HoistState.upFast => AppColors.fastColor,
            HoistState.downSlow => AppColors.downColor,
            HoistState.downFast => AppColors.fastColor,
          };

    final analogKeys = craneController.analogValues.keys.toList()..sort();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withValues(alpha: 0.75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle, size: 9, color: statusColor),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  craneController.statusLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final key in analogKeys)
                _AnalogChip(
                  label: key,
                  value: hmiController.getAnalogValue(key).toStringAsFixed(0),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnalogChip extends StatelessWidget {
  const _AnalogChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.panelAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRuntimeState extends StatelessWidget {
  const _EmptyRuntimeState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'No widgets configured. Open configuration and add controls.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
    );
  }
}
