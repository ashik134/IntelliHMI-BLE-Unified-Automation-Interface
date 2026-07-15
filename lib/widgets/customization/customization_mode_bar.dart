import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/customization_mode_controller.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/services/layout_template_service.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CustomizationModeBar
//
// Floating pill shown while Customization Mode is active. Nothing in this
// bar touches LayoutSettingsController directly except commit() — every
// other action mutates the draft via CustomizationModeController, so it
// stays fully undoable/discardable until Apply is tapped.
// ─────────────────────────────────────────────────────────────────────────────

class DraggableCustomizationModeBar extends StatefulWidget {
  const DraggableCustomizationModeBar({super.key, required this.minTop});

  final double minTop;

  @override
  State<DraggableCustomizationModeBar> createState() =>
      _DraggableCustomizationModeBarState();
}

class _DraggableCustomizationModeBarState
    extends State<DraggableCustomizationModeBar> {
  static const double _margin = 12.0;
  static const Size _fallbackBarSize = Size(340, 56);

  final GlobalKey _barKey = GlobalKey();
  Offset? _position;
  Offset? _longPressStartGlobalPosition;
  Offset? _longPressStartBarPosition;
  Size _barSize = _fallbackBarSize;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.paddingOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        if (!maxWidth.isFinite || !maxHeight.isFinite) {
          return const SizedBox.shrink();
        }

        final resolvedWidth = math.max(
          0.0,
          math.min(maxWidth - _margin * 2, 348.0),
        );
        final start =
            _position ??
            _defaultPosition(
              maxWidth: maxWidth,
              maxHeight: maxHeight,
              barWidth: resolvedWidth,
              safePadding: safePadding,
            );
        final clamped = _clampPosition(
          start,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          barWidth: resolvedWidth,
          safePadding: safePadding,
        );

        if (_position != clamped) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _position = clamped);
          });
        }
        WidgetsBinding.instance.addPostFrameCallback((_) => _syncBarSize());

        return Stack(
          children: [
            Positioned(
              left: clamped.dx,
              top: clamped.dy,
              width: resolvedWidth,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPressStart: (details) {
                  HapticFeedback.mediumImpact();
                  _longPressStartGlobalPosition = details.globalPosition;
                  _longPressStartBarPosition = clamped;
                  setState(() => _dragging = true);
                },
                onLongPressMoveUpdate: (details) {
                  final startGlobal = _longPressStartGlobalPosition;
                  final startPosition = _longPressStartBarPosition;
                  if (startGlobal == null || startPosition == null) return;

                  setState(() {
                    _position = _clampPosition(
                      startPosition + details.globalPosition - startGlobal,
                      maxWidth: maxWidth,
                      maxHeight: maxHeight,
                      barWidth: resolvedWidth,
                      safePadding: safePadding,
                    );
                  });
                },
                onLongPressEnd: (_) => _clearLongPressDrag(),
                onLongPressCancel: _clearLongPressDrag,
                child: AnimatedScale(
                  scale: _dragging ? 1.03 : 1.0,
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _dragging
                          ? [
                              BoxShadow(
                                color: Colors.black.withAlpha(140),
                                blurRadius: 22,
                                offset: const Offset(0, 10),
                              ),
                            ]
                          : const [],
                    ),
                    child: KeyedSubtree(
                      key: _barKey,
                      child: CustomizationModeBar(
                        onDragStart: () {
                          HapticFeedback.mediumImpact();
                          setState(() => _dragging = true);
                        },
                        onDragUpdate: (details) {
                          setState(() {
                            _position = _clampPosition(
                              clamped + details.delta,
                              maxWidth: maxWidth,
                              maxHeight: maxHeight,
                              barWidth: resolvedWidth,
                              safePadding: safePadding,
                            );
                          });
                        },
                        onDragEnd: () => setState(() => _dragging = false),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _clearLongPressDrag() {
    _longPressStartGlobalPosition = null;
    _longPressStartBarPosition = null;
    if (mounted) setState(() => _dragging = false);
  }

  Offset _defaultPosition({
    required double maxWidth,
    required double maxHeight,
    required double barWidth,
    required EdgeInsets safePadding,
  }) {
    return Offset(
      maxWidth - barWidth - _margin,
      maxHeight - _barSize.height - safePadding.bottom - _margin,
    );
  }

  Offset _clampPosition(
    Offset position, {
    required double maxWidth,
    required double maxHeight,
    required double barWidth,
    required EdgeInsets safePadding,
  }) {
    const minLeft = _margin;
    final maxLeft = math.max(minLeft, maxWidth - barWidth - _margin);
    final minTop = math.max(widget.minTop + _margin, safePadding.top + _margin);
    final maxTop = math.max(
      minTop,
      maxHeight - _barSize.height - safePadding.bottom - _margin,
    );

    return Offset(
      position.dx.clamp(minLeft, maxLeft).toDouble(),
      position.dy.clamp(minTop, maxTop).toDouble(),
    );
  }

  void _syncBarSize() {
    final context = _barKey.currentContext;
    if (context == null) return;
    final size = context.size;
    if (size == null || size == _barSize) return;
    if (mounted) setState(() => _barSize = size);
  }
}

class CustomizationModeBar extends StatelessWidget {
  const CustomizationModeBar({
    super.key,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
  });

  final VoidCallback? onDragStart;
  final ValueChanged<DragUpdateDetails>? onDragUpdate;
  final VoidCallback? onDragEnd;

  Future<void> _confirmDiscard(BuildContext context) async {
    final customCtrl = context.read<CustomizationModeController>();
    if (!customCtrl.hasUnsavedChanges) {
      customCtrl.discard();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text(
          'Discard changes?',
          style: TextStyle(color: AppColors.darkText),
        ),
        content: const Text(
          'All unapplied edits made in this session will be lost.',
          style: TextStyle(color: AppColors.darkTextSub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.eStopColor),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed == true) customCtrl.discard();
  }

  Future<void> _apply(BuildContext context) async {
    final customCtrl = context.read<CustomizationModeController>();
    final result = await customCtrl.commit();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.isValid ? 'Layout applied.' : result.firstError),
        backgroundColor: result.isValid
            ? AppColors.darkSuccess
            : AppColors.eStopColor,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customCtrl = context.watch<CustomizationModeController>();
    final validation = customCtrl.lastValidation;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!validation.isValid)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.eStopColor.withAlpha(230),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 15,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    validation.firstError,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.panel.withAlpha(245),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.darkBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(80),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // _ToolbarDragHandle(
              //   onDragStart: onDragStart,
              //   onDragUpdate: onDragUpdate,
              //   onDragEnd: onDragEnd,
              // ),
              const SizedBox(width: 4),
              _BarIconButton(
                icon: Icons.undo_rounded,
                tooltip: 'Undo',
                onTap: customCtrl.canUndo ? customCtrl.undo : null,
              ),
              _BarIconButton(
                icon: Icons.redo_rounded,
                tooltip: 'Redo',
                onTap: customCtrl.canRedo ? customCtrl.redo : null,
              ),
              _BarIconButton(
                icon: Icons.more_horiz_rounded,
                tooltip: 'More',
                onTap: () => _showOverflowMenu(context),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _confirmDiscard(context),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.darkTextSub,
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Discard', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: () => _apply(context),
                icon: const Icon(Icons.check_rounded, size: 17),
                label: const Text('Apply', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.darkSuccess,
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showOverflowMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _OverflowMenu(hostContext: context),
    );
  }
}

class _BarIconButton extends StatelessWidget {
  const _BarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      color: onTap == null ? AppColors.disabled : AppColors.darkText,
      onPressed: onTap,
    );
  }
}

// class _ToolbarDragHandle extends StatelessWidget {
//   const _ToolbarDragHandle({
//     required this.onDragUpdate,
//   }) : onDragStart = null : onDragEnd;

//   final VoidCallback? onDragStart;
//   final ValueChanged<DragUpdateDetails>? onDragUpdate;
//   final VoidCallback? onDragEnd;

//   @override
//   Widget build(BuildContext context) {
//     return MouseRegion(
//       cursor: SystemMouseCursors.move,
//       child: GestureDetector(
//         behavior: HitTestBehavior.opaque,
//         onPanStart: onDragStart == null ? null : (_) => onDragStart!(),
//         onPanUpdate: onDragUpdate,
//         onPanEnd: onDragEnd == null ? null : (_) => onDragEnd!(),
//         onPanCancel: onDragEnd,
//         child: Container(
//           width: 42,
//           height: 34,
//           alignment: Alignment.center,
//           decoration: BoxDecoration(
//             color: AppColors.darkBg.withAlpha(140),
//             borderRadius: BorderRadius.circular(8),
//             border: Border.all(color: AppColors.darkBorder.withAlpha(190)),
//           ),
//           child: const Icon(
//             Icons.drag_indicator_rounded,
//             size: 22,
//             color: AppColors.darkTextSub,
//           ),
//         ),
//       ),
//     );
//   }
// }

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({required this.hostContext});
  final BuildContext hostContext;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            _MenuTile(
              icon: Icons.dashboard_rounded,
              label: 'Layout Elements',
              onTap: () {
                Navigator.of(context).pop();
                _showLayoutElementsDialog(hostContext);
              },
            ),
            _MenuTile(
              icon: Icons.warning_amber_rounded,
              label: 'Safety Labels',
              onTap: () {
                Navigator.of(context).pop();
                _showSafetyLabelsDialog(hostContext);
              },
            ),
            _MenuTile(
              icon: Icons.aspect_ratio_rounded,
              label: 'Safety Size',
              onTap: () {
                Navigator.of(context).pop();
                _showSafetySizeDialog(hostContext);
              },
            ),
            _MenuTile(
              icon: Icons.copy_rounded,
              label: 'Export Layout (copy JSON)',
              onTap: () {
                Navigator.of(context).pop();
                _exportLayout(hostContext);
              },
            ),
            _MenuTile(
              icon: Icons.paste_rounded,
              label: 'Import Layout (paste JSON)',
              onTap: () {
                Navigator.of(context).pop();
                _importLayout(hostContext);
              },
            ),
            _MenuTile(
              icon: Icons.dashboard_customize_rounded,
              label: 'Load Template',
              onTap: () {
                Navigator.of(context).pop();
                _showTemplatesDialog(hostContext);
              },
            ),
            _MenuTile(
              icon: Icons.restore_rounded,
              label: 'Reset to Factory Defaults',
              iconColor: AppColors.eStopColor,
              onTap: () {
                Navigator.of(context).pop();
                _confirmResetToDefaults(hostContext);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _exportLayout(BuildContext context) {
    final draft = context.read<CustomizationModeController>().draft;
    Clipboard.setData(ClipboardData(text: draft.toJsonString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Layout copied to clipboard.')),
    );
  }

  Future<void> _importLayout(BuildContext context) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) return;
    final text = data?.text;
    if (text == null || text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Clipboard is empty.')));
      return;
    }
    final customCtrl = context.read<CustomizationModeController>();
    final parsed = ControlLayoutConfig.fromJsonString(text);
    customCtrl.applyDraftChange(parsed);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Layout imported. Review, then Apply to save.'),
      ),
    );
  }

  void _showTemplatesDialog(BuildContext context) {
    const service = LayoutTemplateService();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text(
          'Load Template',
          style: TextStyle(color: AppColors.darkText),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final template in service.templates)
                ListTile(
                  title: Text(
                    template.name,
                    style: const TextStyle(color: AppColors.darkText),
                  ),
                  subtitle: Text(
                    template.description,
                    style: const TextStyle(
                      color: AppColors.darkTextSub,
                      fontSize: 11,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    context
                        .read<CustomizationModeController>()
                        .applyTemplate(template);
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmResetToDefaults(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text(
          'Reset to factory defaults?',
          style: TextStyle(color: AppColors.darkText),
        ),
        content: const Text(
          'This restores every control on this screen to its factory layout. '
          'Nothing is saved until you tap Apply.',
          style: TextStyle(color: AppColors.darkTextSub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.eStopColor),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<CustomizationModeController>().resetDraftToFactoryDefaults();
    }
  }

  void _showLayoutElementsDialog(BuildContext context) {
    final customCtrl = context.read<CustomizationModeController>();

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final arrangement = customCtrl.draft.arrangementConfig;

          void update(ControlArrangementConfig next) {
            final draft = customCtrl.draft;
            customCtrl.applyDraftChange(
              draft.copyWith(arrangementConfig: next),
            );
            setDialogState(() {});
          }

          return AlertDialog(
            backgroundColor: AppColors.panel,
            title: const Text(
              'Layout Elements',
              style: TextStyle(color: AppColors.darkText),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text(
                    'Sensor row',
                    style: TextStyle(color: AppColors.darkText, fontSize: 13),
                  ),
                  activeThumbColor: AppColors.accent,
                  value: arrangement.showSensorRow,
                  onChanged: (v) =>
                      update(arrangement.copyWith(showSensorRow: v)),
                ),
                SwitchListTile(
                  title: const Text(
                    'Live LED row',
                    style: TextStyle(color: AppColors.darkText, fontSize: 13),
                  ),
                  activeThumbColor: AppColors.accent,
                  value: arrangement.showLiveLEDs,
                  onChanged: (v) =>
                      update(arrangement.copyWith(showLiveLEDs: v)),
                ),
                SwitchListTile(
                  title: const Text(
                    'Connection subtitle',
                    style: TextStyle(color: AppColors.darkText, fontSize: 13),
                  ),
                  activeThumbColor: AppColors.accent,
                  value: arrangement.showConnectionSubtitle,
                  onChanged: (v) =>
                      update(arrangement.copyWith(showConnectionSubtitle: v)),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSafetyLabelsDialog(BuildContext context) {
    final customCtrl = context.read<CustomizationModeController>();
    final labels = customCtrl.draft.labelConfig;
    final estopController = TextEditingController(
      text: labels.estopSwipeInstruction,
    );
    final resetController = TextEditingController(text: labels.resetEstopLabel);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text(
          'Safety Labels',
          style: TextStyle(color: AppColors.darkText),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: estopController,
              maxLength: ControlLabelConfig.maxInstructionLength,
              style: const TextStyle(color: AppColors.darkText),
              decoration: const InputDecoration(
                labelText: 'E-Stop instruction',
              ),
            ),
            TextField(
              controller: resetController,
              maxLength: ControlLabelConfig.maxLabelLength,
              style: const TextStyle(color: AppColors.darkText),
              decoration: const InputDecoration(
                labelText: 'Reset E-Stop label',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final draft = customCtrl.draft;
              customCtrl.applyDraftChange(
                draft.copyWith(
                  labelConfig: draft.labelConfig.copyWith(
                    estopSwipeInstruction: estopController.text.trim(),
                    resetEstopLabel: resetController.text.trim(),
                  ),
                ),
              );
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Safety Size dialog is deliberately separate from the per-button
  // ButtonEditSheet: E-Stop is never wrapped in EditableControlTile (it must
  // stay live and tappable during Customization Mode), so it has no pencil
  // badge / per-button sheet entry point of its own — this overflow-menu
  // entry is its only sizing UI. Every change flows through
  // applyDraftChange, so Discard reverts it like any other draft edit.
  void _showSafetySizeDialog(BuildContext context) {
    final customCtrl = context.read<CustomizationModeController>();

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final sizing = customCtrl.draft.sizeConfig;
          final heightScale = sizing.estopButtonHeightScale;
          final widthScale = sizing.estopButtonWidthScale;
          final resolvedHeight = sizing.resolvedEstopHeight;
          final resolvedWidth = sizing.resolvedEstopWidth;
          final heightBelowMin =
              resolvedHeight < ControlWidgetSizeConfig.minTouchTargetPx;
          final widthBelowMin =
              resolvedWidth < ControlWidgetSizeConfig.minTouchTargetPx;

          void update(ControlWidgetSizeConfig next) {
            customCtrl.applyDraftChange(
              customCtrl.draft.copyWith(sizeConfig: next),
            );
            setDialogState(() {});
          }

          return AlertDialog(
            backgroundColor: AppColors.panel,
            title: const Text(
              'Safety Size',
              style: TextStyle(color: AppColors.darkText),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'E-STOP BUTTON HEIGHT',
                      style: TextStyle(
                        color: AppColors.darkTextMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${resolvedHeight.toStringAsFixed(0)} px',
                          style: TextStyle(
                            color: heightBelowMin
                                ? AppColors.eStopColor
                                : AppColors.darkSuccess,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '×${heightScale.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: AppColors.darkTextMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: heightBelowMin
                            ? AppColors.eStopColor
                            : AppColors.accent,
                        thumbColor: heightBelowMin
                            ? AppColors.eStopColor
                            : AppColors.accent,
                        inactiveTrackColor: AppColors.darkBorder,
                      ),
                      child: Slider(
                        value: heightScale,
                        min: ControlWidgetSizeConfig.minHeightScale,
                        max: ControlWidgetSizeConfig.maxHeightScale,
                        divisions: 16,
                        onChanged: (v) =>
                            update(sizing.copyWith(estopButtonHeightScale: v)),
                      ),
                    ),
                    if (heightBelowMin)
                      const _InfoNote(
                        message:
                            'Below the 48px minimum industrial touch target. '
                            'Increase the scale before applying.',
                        color: AppColors.eStopColor,
                      ),
                    const SizedBox(height: 12),
                    const Text(
                      'E-STOP BUTTON WIDTH',
                      style: TextStyle(
                        color: AppColors.darkTextMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${resolvedWidth.toStringAsFixed(0)} px',
                          style: TextStyle(
                            color: widthBelowMin
                                ? AppColors.eStopColor
                                : AppColors.darkSuccess,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '×${widthScale.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: AppColors.darkTextMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: widthBelowMin
                            ? AppColors.eStopColor
                            : AppColors.accent,
                        thumbColor: widthBelowMin
                            ? AppColors.eStopColor
                            : AppColors.accent,
                        inactiveTrackColor: AppColors.darkBorder,
                      ),
                      child: Slider(
                        value: widthScale,
                        min: ControlWidgetSizeConfig.minWidthScale,
                        max: ControlWidgetSizeConfig.maxWidthScale,
                        divisions: 16,
                        onChanged: (v) =>
                            update(sizing.copyWith(estopButtonWidthScale: v)),
                      ),
                    ),
                    if (widthBelowMin)
                      const _InfoNote(
                        message:
                            'Below the 48px minimum industrial touch target. '
                            'Increase the scale before applying.',
                        color: AppColors.eStopColor,
                      ),
                    const SizedBox(height: 4),
                    const Text(
                      'Resizing E-Stop does not affect the Reset section, '
                      'which always stays full width.',
                      style: TextStyle(
                        color: AppColors.darkTextSub,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => update(const ControlWidgetSizeConfig()),
                child: const Text('Reset'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InfoNote extends StatelessWidget {
  const _InfoNote({required this.message, this.color = AppColors.darkInfo});
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 13, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontSize: 11, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor = AppColors.darkTextSub,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(
        label,
        style: const TextStyle(color: AppColors.darkText, fontSize: 13),
      ),
      onTap: onTap,
    );
  }
}
