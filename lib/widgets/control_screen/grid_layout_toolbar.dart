import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/grid_layout_option.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GridLayoutToolbar
//
// The "Layout" tool's palette: an in-place replacement for the normal
// Customization Toolbar row (see CustomizationToolbar, which swaps between
// the two via AnimatedSwitcher — never a route/sheet/dialog, so the current
// edit session's selection/draft state is untouched). Presents every
// GridLayoutOption as a horizontally scrollable, one-tap-selectable card;
// selecting a card only stages [selected] locally in the parent — the
// active grid only actually changes when [onApply] fires. [onCancel]
// discards the staged selection and returns to the normal toolbar.
// ─────────────────────────────────────────────────────────────────────────────

const double _kSlotWidth = 74;
const double _kCircleDiameter = 52;
const double _kCardWidth = 72;

class GridLayoutToolbar extends StatelessWidget {
  const GridLayoutToolbar({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onCancel,
    required this.onApply,
  });

  final GridLayoutOption selected;
  final ValueChanged<GridLayoutOption> onSelect;
  final VoidCallback onCancel;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 96,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: _GridPanelCircleButton(
                icon: Icons.arrow_back_rounded,
                label: 'Back',
                background: AppColors.toolbarCircleBg,
                iconColor: AppColors.darkText,
                onTap: onCancel,
              ),
            ),
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: GridLayoutOption.values.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final option = GridLayoutOption.values[i];
                    return _GridLayoutCard(
                      option: option,
                      isSelected: option == selected,
                      onTap: () => onSelect(option),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: _GridPanelCircleButton(
                icon: Icons.check_rounded,
                label: 'Apply',
                background: AppColors.selectionViolet,
                iconColor: Colors.white,
                glow: true,
                onTap: onApply,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _GridLayoutCard
// ─────────────────────────────────────────────────────────────────────────────

class _GridLayoutCard extends StatelessWidget {
  const _GridLayoutCard({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final GridLayoutOption option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final previewColor = isSelected
        ? AppColors.selectionViolet
        : AppColors.darkTextSub;
    final labelColor = isSelected
        ? AppColors.selectionViolet
        : AppColors.darkTextSub;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        width: _kCardWidth,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.toolbarCircleBgSelected
              : AppColors.toolbarCircleBg,
          borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          border: Border.all(
            color: isSelected ? AppColors.selectionViolet : AppColors.darkBorder,
            width: isSelected ? 1.6 : 1,
          ),
          boxShadow: isSelected
              ? const [
                  BoxShadow(
                    color: AppColors.selectionGlow,
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            _MiniGridPreview(option: option, color: previewColor),
            const SizedBox(height: 7),
            Text(
              option.label,
              style: TextStyle(
                decoration: TextDecoration.none,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: labelColor,
              ),
            ),
            if (option.isDefault) ...[
              const SizedBox(height: 1),
              const Text(
                'Default',
                style: TextStyle(
                  decoration: TextDecoration.none,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkTextMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MiniGridPreview
// ─────────────────────────────────────────────────────────────────────────────

class _MiniGridPreview extends StatelessWidget {
  const _MiniGridPreview({required this.option, required this.color});

  final GridLayoutOption option;
  final Color color;

  static const double _cell = 7;
  static const double _gap = 2;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < option.rows; r++) ...[
          if (r > 0) const SizedBox(height: _gap),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var c = 0; c < option.columns; c++) ...[
                if (c > 0) const SizedBox(width: _gap),
                Container(
                  width: _cell,
                  height: _cell,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _GridPanelCircleButton
// ─────────────────────────────────────────────────────────────────────────────

class _GridPanelCircleButton extends StatefulWidget {
  const _GridPanelCircleButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.iconColor,
    required this.onTap,
    this.glow = false,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color iconColor;
  final bool glow;
  final VoidCallback onTap;

  @override
  State<_GridPanelCircleButton> createState() =>
      _GridPanelCircleButtonState();
}

class _GridPanelCircleButtonState extends State<_GridPanelCircleButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: widget.onTap,
      child: SizedBox(
        width: _kSlotWidth,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: _pressed ? 0.96 : 1.0,
              duration: Duration(milliseconds: _pressed ? 90 : 120),
              curve: Curves.easeOut,
              child: Container(
                width: _kCircleDiameter,
                height: _kCircleDiameter,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: widget.background,
                  shape: BoxShape.circle,
                  boxShadow: widget.glow
                      ? const [
                          BoxShadow(
                            color: AppColors.selectionGlow,
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Icon(widget.icon, size: 23, color: widget.iconColor),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.label,
              style: TextStyle(
                decoration: TextDecoration.none,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: widget.glow ? Colors.white : AppColors.darkTextSub,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
