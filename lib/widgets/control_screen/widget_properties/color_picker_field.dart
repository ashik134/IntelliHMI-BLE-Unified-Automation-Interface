import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Color picker
//
// A curated swatch grid (this app's own role/status colors plus a standard
// spread) with a hex field for anything else, and a "Use theme default"
// clear option — null always means "use the role/type default," matching
// ButtonStyleConfig.primaryColor/.activeColor's existing nullable contract.
// ─────────────────────────────────────────────────────────────────────────────

const List<Color> kCuratedButtonColors = [
  AppColors.accent,
  AppColors.upColor,
  AppColors.downColor,
  AppColors.fastColor,
  AppColors.traverseColor,
  AppColors.travelColor,
  AppColors.darkInfo,
  AppColors.darkSuccess,
  AppColors.eStopColor,
  AppColors.selectionViolet,
  Color(0xFFEF4444),
  Color(0xFFF97316),
  Color(0xFFEAB308),
  Color(0xFF84CC16),
  Color(0xFF22C55E),
  Color(0xFF14B8A6),
  Color(0xFF06B6D4),
  Color(0xFF3B82F6),
  Color(0xFF6366F1),
  Color(0xFFA855F7),
  Color(0xFFEC4899),
  Color(0xFF78716C),
  Color(0xFF94A3B8),
  Color(0xFFFFFFFF),
];

/// Inline field: a labeled swatch preview that opens the picker sheet on
/// tap. [value] null renders as "Default" (the role/type fallback color).
class PropertyColorField extends StatelessWidget {
  const PropertyColorField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final Color? value;
  final ValueChanged<Color?> onChanged;

  Future<void> _open(BuildContext context) async {
    final result = await showModalBottomSheet<_ColorPickResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ColorPickerSheet(current: value),
    );
    if (result != null) onChanged(result.color);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _open(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.darkBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.darkText,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                value == null ? 'Default' : '#${_hex(value!)}',
                style: const TextStyle(
                  color: AppColors.darkTextMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: value ?? AppColors.darkBg,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: value == null
                        ? AppColors.darkTextMuted
                        : Colors.white.withAlpha(80),
                    width: value == null ? 1.4 : 1,
                    style: value == null
                        ? BorderStyle.solid
                        : BorderStyle.solid,
                  ),
                ),
                child: value == null
                    ? const Icon(
                        Icons.block_rounded,
                        size: 12,
                        color: AppColors.darkTextMuted,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorPickResult {
  const _ColorPickResult(this.color);

  final Color? color;
}

String _hex(Color color) =>
    color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();

class _ColorPickerSheet extends StatefulWidget {
  const _ColorPickerSheet({this.current});

  final Color? current;

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late final TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _hexController = TextEditingController(
      text: widget.current == null ? '' : _hex(widget.current!),
    );
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _applyHex() {
    final raw = _hexController.text.trim().replaceFirst('#', '');
    if (raw.length != 6 && raw.length != 8) return;
    final parsed = int.tryParse(raw.length == 6 ? 'FF$raw' : raw, radix: 16);
    if (parsed == null) return;
    Navigator.of(context).pop(_ColorPickResult(Color(parsed)));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.darkBorder),
          boxShadow: AppMetrics.shadowMd,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.panelStroke,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Choose Color',
                  style: TextStyle(
                    color: AppColors.darkText,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(const _ColorPickResult(null)),
                  child: const Text(
                    'Use default',
                    style: TextStyle(color: AppColors.eStopColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final color in kCuratedButtonColors)
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () =>
                        Navigator.of(context).pop(_ColorPickResult(color)),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: widget.current == color
                              ? AppColors.selectionViolet
                              : Colors.white.withAlpha(60),
                          width: widget.current == color ? 2.4 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _hexController,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F#]')),
                    ],
                    style: const TextStyle(
                      color: AppColors.darkText,
                      fontSize: 13.5,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Hex (RRGGBB)',
                      labelStyle: const TextStyle(
                        color: AppColors.darkTextMuted,
                      ),
                      filled: true,
                      fillColor: AppColors.darkBg,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.darkBorder,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _applyHex(),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _applyHex,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.selectionViolet,
                  ),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
