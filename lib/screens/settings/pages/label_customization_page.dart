import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev6_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev6_crane_control_ops/models/control_layout_config.dart';
import 'package:rev6_crane_control_ops/utils/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LabelCustomizationPage
// ─────────────────────────────────────────────────────────────────────────────

class LabelCustomizationPage extends StatelessWidget {
  const LabelCustomizationPage({super.key});

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
          'Label Customization',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.divider),
        ),
      ),
      body: const _LabelCustomizationBody(),
    );
  }
}

class _LabelCustomizationBody extends StatefulWidget {
  const _LabelCustomizationBody();

  @override
  State<_LabelCustomizationBody> createState() =>
      _LabelCustomizationBodyState();
}

class _LabelCustomizationBodyState
    extends State<_LabelCustomizationBody> {
  late final TextEditingController _upCtrl;
  late final TextEditingController _downCtrl;
  late final TextEditingController _estopCtrl;
  late final TextEditingController _resetEstopCtrl;
  late final TextEditingController _screenTitleCtrl;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final cfg =
        context.read<LayoutSettingsController>().config.labelConfig;
    _upCtrl = TextEditingController(text: cfg.upLabel);
    _downCtrl = TextEditingController(text: cfg.downLabel);
    _estopCtrl = TextEditingController(text: cfg.estopSwipeInstruction);
    _resetEstopCtrl = TextEditingController(text: cfg.resetEstopLabel);
    _screenTitleCtrl = TextEditingController(text: cfg.screenTitle);
  }

  @override
  void dispose() {
    _upCtrl.dispose();
    _downCtrl.dispose();
    _estopCtrl.dispose();
    _resetEstopCtrl.dispose();
    _screenTitleCtrl.dispose();
    super.dispose();
  }

  void _apply(BuildContext context) {
    final proposed = ControlLabelConfig(
      upLabel: _upCtrl.text.trim(),
      downLabel: _downCtrl.text.trim(),
      estopSwipeInstruction: _estopCtrl.text.trim(),
      resetEstopLabel: _resetEstopCtrl.text.trim(),
      screenTitle: _screenTitleCtrl.text.trim(),
    );
    final result =
        context.read<LayoutSettingsController>().updateLabelConfig(proposed);
    setState(() {
      _errorMessage = result.isValid ? null : result.errors.join('\n');
    });
    if (result.isValid && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Labels saved.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved =
        context.watch<LayoutSettingsController>().config.labelConfig;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // ── Controls
        _PageCard(
          title: 'BUTTON LABELS',
          icon: Icons.label_outline_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _InfoBanner(
                message:
                    'Labels must be 1–18 characters. '
                    'They appear on buttons and the E-Stop control.',
              ),
              const SizedBox(height: 16),
              _LabelField(
                controller: _upCtrl,
                label: 'Up Button Label',
                hint: 'UP',
                icon: Icons.arrow_upward_rounded,
                savedValue: saved.upLabel,
                maxLength: ControlLabelConfig.maxLabelLength,
              ),
              const SizedBox(height: 12),
              _LabelField(
                controller: _downCtrl,
                label: 'Down Button Label',
                hint: 'DOWN',
                icon: Icons.arrow_downward_rounded,
                savedValue: saved.downLabel,
                maxLength: ControlLabelConfig.maxLabelLength,
              ),
            ],
          ),
        ),

        _PageCard(
          title: 'E-STOP LABELS',
          icon: Icons.warning_amber_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LabelField(
                controller: _estopCtrl,
                label: 'Swipe Instruction',
                hint: 'SWIPE TO EMERGENCY STOP',
                icon: Icons.swipe_rounded,
                savedValue: saved.estopSwipeInstruction,
                maxLength: ControlLabelConfig.maxLabelLength,
              ),
              const SizedBox(height: 12),
              _LabelField(
                controller: _resetEstopCtrl,
                label: 'Reset E-Stop Label',
                hint: 'RESET E-STOP',
                icon: Icons.restart_alt_rounded,
                savedValue: saved.resetEstopLabel,
                maxLength: ControlLabelConfig.maxLabelLength,
              ),
            ],
          ),
        ),

        _PageCard(
          title: 'SCREEN TITLE',
          icon: Icons.title_rounded,
          child: _LabelField(
            controller: _screenTitleCtrl,
            label: 'Screen Title',
            hint: 'CRANE CONTROL',
            icon: Icons.text_fields_rounded,
            savedValue: saved.screenTitle,
            maxLength: ControlLabelConfig.maxLabelLength,
          ),
        ),

        // ── Error + apply button
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            children: [
              if (_errorMessage != null) ...[
                _ErrorBanner(message: _errorMessage!),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton.icon(
                  onPressed: () => _apply(context),
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('Apply Labels'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.connPrimary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
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
          child: _LabelPreview(
            upLabel: _upCtrl.text,
            downLabel: _downCtrl.text,
            estopInstruction: _estopCtrl.text,
            resetLabel: _resetEstopCtrl.text,
            screenTitle: _screenTitleCtrl.text,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LabelField
// ─────────────────────────────────────────────────────────────────────────────

class _LabelField extends StatefulWidget {
  const _LabelField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.savedValue,
    required this.maxLength,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final String savedValue;
  final int maxLength;

  @override
  State<_LabelField> createState() => _LabelFieldState();
}

class _LabelFieldState extends State<_LabelField> {
  bool get _hasUnsaved =>
      widget.controller.text.trim() != widget.savedValue;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(widget.icon, size: 14, color: AppColors.connTextMuted),
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: const TextStyle(
                color: AppColors.connText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_hasUnsaved) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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
        const SizedBox(height: 6),
        TextField(
          controller: widget.controller,
          maxLength: widget.maxLength,
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle:
                const TextStyle(color: AppColors.connTextMuted, fontSize: 13),
            filled: true,
            fillColor: AppColors.connBg,
            counterStyle: const TextStyle(
                color: AppColors.connTextMuted, fontSize: 10),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: AppColors.connBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: AppColors.connBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                  color: AppColors.connPrimary, width: 1.5),
            ),
          ),
          style: const TextStyle(
              color: AppColors.connText,
              fontSize: 13,
              fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LabelPreview
// ─────────────────────────────────────────────────────────────────────────────

class _LabelPreview extends StatelessWidget {
  const _LabelPreview({
    required this.upLabel,
    required this.downLabel,
    required this.estopInstruction,
    required this.resetLabel,
    required this.screenTitle,
  });

  final String upLabel;
  final String downLabel;
  final String estopInstruction;
  final String resetLabel;
  final String screenTitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Labels update live as you type.',
          style: TextStyle(
              color: AppColors.connTextMuted, fontSize: 11, height: 1.4),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.darkBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Screen title
              Center(
                child: Text(
                  screenTitle.isEmpty ? '—' : screenTitle.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.darkText,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.0,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // E-Stop bar
              Container(
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.eStopColor.withAlpha(38),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.eStopColor.withAlpha(80)),
                ),
                child: Center(
                  child: Text(
                    estopInstruction.isEmpty
                        ? '—'
                        : '▶▶  ${estopInstruction.toUpperCase()}',
                    style: const TextStyle(
                      color: AppColors.eStopColorLight,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Reset E-Stop bar (shown when E-Stop is active)
              Container(
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.idleColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.idleColor.withAlpha(60)),
                ),
                child: Center(
                  child: Text(
                    resetLabel.isEmpty ? '—' : resetLabel.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.darkTextSub,
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Hoist buttons
              Row(
                children: [
                  Expanded(
                      child: _HoistMock(
                    label: upLabel.isEmpty ? '—' : upLabel,
                    isUp: true,
                  )),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _HoistMock(
                    label: downLabel.isEmpty ? '—' : downLabel,
                    isUp: false,
                  )),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HoistMock extends StatelessWidget {
  const _HoistMock({required this.label, required this.isUp});
  final String label;
  final bool isUp;

  @override
  Widget build(BuildContext context) {
    final color = isUp ? AppColors.upColor : AppColors.downColor;
    final colorLight = isUp ? AppColors.upColorLight : AppColors.downColorLight;
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: AppColors.panelAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            color: colorLight,
            size: 20,
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: AppColors.darkText,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Container(
            width: 24,
            height: 2,
            margin: const EdgeInsets.only(top: 3),
            decoration: BoxDecoration(
              color: color.withAlpha(80),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
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
