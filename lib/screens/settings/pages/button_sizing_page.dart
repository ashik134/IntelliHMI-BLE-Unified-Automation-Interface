import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev6_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev6_crane_control_ops/models/control_layout_config.dart';
import 'package:rev6_crane_control_ops/utils/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ButtonSizingPage
// ─────────────────────────────────────────────────────────────────────────────

class ButtonSizingPage extends StatelessWidget {
  const ButtonSizingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.connBg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.connText,
        elevation: 0,
        titleSpacing: 0,
        title: const Text(
          'Button Sizing',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.divider),
        ),
      ),
      body: const _ButtonSizingBody(),
    );
  }
}

class _ButtonSizingBody extends StatefulWidget {
  const _ButtonSizingBody();

  @override
  State<_ButtonSizingBody> createState() => _ButtonSizingBodyState();
}

class _ButtonSizingBodyState extends State<_ButtonSizingBody> {
  late double _hoistScale;
  late double _estopScale;
  String? _errorMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cfg = context.read<LayoutSettingsController>().config.sizeConfig;
    _hoistScale = cfg.hoistButtonHeightScale;
    _estopScale = cfg.estopButtonHeightScale;
  }

  void _apply(BuildContext context) {
    final proposed = ControlWidgetSizeConfig(
      hoistButtonHeightScale: _hoistScale,
      estopButtonHeightScale: _estopScale,
    );
    final result =
        context.read<LayoutSettingsController>().updateSizeConfig(proposed);
    setState(() {
      _errorMessage = result.isValid ? null : result.errors.join('\n');
    });
    if (result.isValid && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Button sizes saved.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final savedCfg =
        context.watch<LayoutSettingsController>().config.sizeConfig;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // ── Sizing controls
        _PageCard(
          title: 'SCALE CONFIGURATION',
          icon: Icons.open_in_full_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _InfoBanner(
                message:
                    'Scale factors are validated against the minimum touch '
                    'target requirement (≥ 48 px) before being saved.',
              ),
              const SizedBox(height: 16),
              _ScaleSlider(
                label: 'Hoist Buttons Height',
                description: 'UP / DOWN control button area',
                value: _hoistScale,
                savedValue: savedCfg.hoistButtonHeightScale,
                resolvedPx:
                    ControlWidgetSizeConfig.baseHoistButtonHeight * _hoistScale,
                onChanged: (v) => setState(() => _hoistScale = v),
              ),
              const SizedBox(height: 16),
              _ScaleSlider(
                label: 'E-Stop Button Height',
                description: 'Emergency stop swipe button',
                value: _estopScale,
                savedValue: savedCfg.estopButtonHeightScale,
                resolvedPx:
                    ControlWidgetSizeConfig.baseEstopButtonHeight * _estopScale,
                onChanged: (v) => setState(() => _estopScale = v),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: _errorMessage!),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton.icon(
                  onPressed: () => _apply(context),
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('Apply Sizes'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.connPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Preview
        _PageCard(
          title: 'PREVIEW',
          icon: Icons.preview_rounded,
          child: _SizingPreview(
            hoistScale: _hoistScale,
            estopScale: _estopScale,
            savedHoistScale: savedCfg.hoistButtonHeightScale,
            savedEstopScale: savedCfg.estopButtonHeightScale,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ScaleSlider
// ─────────────────────────────────────────────────────────────────────────────

class _ScaleSlider extends StatelessWidget {
  const _ScaleSlider({
    required this.label,
    required this.description,
    required this.value,
    required this.savedValue,
    required this.resolvedPx,
    required this.onChanged,
  });

  final String label;
  final String description;
  final double value;
  final double savedValue;
  final double resolvedPx;
  final ValueChanged<double> onChanged;

  bool get _isSaved => (value - savedValue).abs() < 0.005;
  bool get _belowMin =>
      resolvedPx < ControlWidgetSizeConfig.minTouchTargetPx;

  @override
  Widget build(BuildContext context) {
    final indicatorColor = _belowMin ? AppColors.error : AppColors.connected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: AppColors.connText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!_isSaved) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.connWarning.withAlpha(30),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Unsaved',
                            style: TextStyle(
                              color: AppColors.connWarning,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    description,
                    style: const TextStyle(
                      color: AppColors.connTextMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${resolvedPx.toStringAsFixed(0)} px',
                  style: TextStyle(
                    color: indicatorColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  '×${value.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: AppColors.connTextMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor:
                _belowMin ? AppColors.error : AppColors.connPrimary,
            thumbColor: _belowMin ? AppColors.error : AppColors.connPrimary,
            inactiveTrackColor: AppColors.neutralBg,
          ),
          child: Slider(
            value: value,
            min: ControlWidgetSizeConfig.minHeightScale,
            max: ControlWidgetSizeConfig.maxHeightScale,
            divisions: 16,
            onChanged: onChanged,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '×${ControlWidgetSizeConfig.minHeightScale.toStringAsFixed(1)}  min',
              style:
                  const TextStyle(color: AppColors.connTextMuted, fontSize: 9),
            ),
            Text(
              '×${ControlWidgetSizeConfig.maxHeightScale.toStringAsFixed(1)}  max',
              style:
                  const TextStyle(color: AppColors.connTextMuted, fontSize: 9),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SizingPreview
// ─────────────────────────────────────────────────────────────────────────────

class _SizingPreview extends StatelessWidget {
  const _SizingPreview({
    required this.hoistScale,
    required this.estopScale,
    required this.savedHoistScale,
    required this.savedEstopScale,
  });

  final double hoistScale;
  final double estopScale;
  final double savedHoistScale;
  final double savedEstopScale;

  static const double _previewHoistBase = 100.0;
  static const double _previewEstopBase = 36.0;

  @override
  Widget build(BuildContext context) {
    final hoistH = _previewHoistBase * hoistScale;
    final estopH = _previewEstopBase * estopScale;
    final savedHoistH = _previewHoistBase * savedHoistScale;
    final savedEstopH = _previewEstopBase * savedEstopScale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Live preview of button proportions. Unsaved changes shown in blue.',
          style: TextStyle(
            color: AppColors.connTextMuted,
            fontSize: 11,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.darkBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // E-Stop bar
              Row(
                children: [
                  Expanded(
                    child: _PreviewBar(
                      label: 'E-STOP',
                      height: estopH,
                      color: AppColors.eStopColor,
                      hasUnsaved:
                          (estopScale - savedEstopScale).abs() > 0.005,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Hoist buttons
              Row(
                children: [
                  Expanded(
                    child: _PreviewBar(
                      label: 'UP',
                      height: hoistH,
                      color: AppColors.upColor,
                      hasUnsaved:
                          (hoistScale - savedHoistScale).abs() > 0.005,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PreviewBar(
                      label: 'DOWN',
                      height: hoistH,
                      color: AppColors.downColor,
                      hasUnsaved:
                          (hoistScale - savedHoistScale).abs() > 0.005,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Legend
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.connPrimary.withAlpha(60),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                          color: AppColors.connPrimary.withAlpha(120)),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Unsaved change',
                    style: TextStyle(
                        color: AppColors.connTextMuted, fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PreviewBar extends StatelessWidget {
  const _PreviewBar({
    required this.label,
    required this.height,
    required this.color,
    required this.hasUnsaved,
  });

  final String label;
  final double height;
  final Color color;
  final bool hasUnsaved;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: height.clamp(20.0, 200.0),
      decoration: BoxDecoration(
        color: hasUnsaved
            ? AppColors.connPrimary.withAlpha(30)
            : color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasUnsaved
              ? AppColors.connPrimary.withAlpha(100)
              : color.withAlpha(80),
          width: hasUnsaved ? 1.5 : 1.0,
        ),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: hasUnsaved ? AppColors.connPrimary : color,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared atoms
// ─────────────────────────────────────────────────────────────────────────────

class _PageCard extends StatelessWidget {
  const _PageCard({
    required this.title,
    required this.icon,
    required this.child,
  });
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.connBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(8),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              color: AppColors.connSurfaceAlt,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 15, color: AppColors.connTextMuted),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.connTextMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.scanning.withAlpha(14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.scanningBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 14, color: AppColors.scanning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  color: AppColors.connTextSub, fontSize: 11, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withAlpha(14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.errorBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 14, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  color: AppColors.error, fontSize: 11, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
