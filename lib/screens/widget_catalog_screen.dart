import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/button_catalog_entry.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/widgets/shared/brand_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WidgetCatalogScreen
//
// Reached from the customization toolbar's "Widgets" action. Shows every
// IntelliHMI component grouped into 4 categories (see button_catalog_entry.
// dart). Tapping a card adds that widget to the draft layout at the next
// open grid slot (or flips a System Widgets arrangement toggle) and pops
// back to the editable canvas. LayoutEditController lives at the app's root
// Provider scope, so a plain Navigator.pop() here preserves the draft with
// no special handling — see LayoutEditController's own doc comment.
// ─────────────────────────────────────────────────────────────────────────────

class WidgetCatalogScreen extends StatelessWidget {
  const WidgetCatalogScreen({super.key});

  void _onTapEntry(BuildContext context, ButtonCatalogEntry entry) {
    final editCtrl = context.read<LayoutEditController>();
    if (entry.buttonType != null) {
      final config = ButtonConfig(
        id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
        type: entry.buttonType!,
        // Placeholder mapping — this widget is inert (drives no PLC output)
        // until a future per-button property editor lets the operator
        // configure real stateMappings, matching the existing "empty
        // stateMappings = inert until configured" convention (see
        // ButtonConfig.stateMappings doc comment).
        plcMapping: PlcOutputVariant.df2,
        label: entry.displayName,
      );
      final result = editCtrl.addButton(config);
      if (!result.isValid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message ?? 'Could not place this widget.'),
          ),
        );
        return;
      }
    } else {
      editCtrl.toggleArrangement(entry.arrangementToggle!);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final byCategory = <ButtonCatalogCategory, List<ButtonCatalogEntry>>{
      for (final category in ButtonCatalogCategory.values) category: [],
    };
    for (final entry in kButtonCatalog) {
      byCategory[entry.category]!.add(entry);
    }

    return Scaffold(
      backgroundColor: AppColors.brandBg,
      body: Column(
        children: [
          _CatalogHeader(onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.all(AppMetrics.spaceLg),
                children: [
                  for (final category in ButtonCatalogCategory.values)
                    if (byCategory[category]!.isNotEmpty) ...[
                      BrandSectionLabel(label: category.displayName),
                      const SizedBox(height: AppMetrics.spaceMd),
                      _CatalogGrid(
                        entries: byCategory[category]!,
                        onTap: (entry) => _onTapEntry(context, entry),
                      ),
                      const SizedBox(height: AppMetrics.space2xl),
                    ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogHeader extends StatelessWidget {
  const _CatalogHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 16),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.brandInk, AppColors.brandInkAlt],
          ),
        ),
        child: Row(
          children: [
            BrandIconButton(
              icon: Icons.arrow_back_rounded,
              dark: true,
              tooltip: 'Back',
              onTap: onBack,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Widget Catalog',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandOnDark,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogGrid extends StatelessWidget {
  const _CatalogGrid({required this.entries, required this.onTap});

  final List<ButtonCatalogEntry> entries;
  final ValueChanged<ButtonCatalogEntry> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = constraints.maxWidth > 560;
        return GridView.count(
          crossAxisCount: isTablet ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: isTablet ? 1.0 : 0.95,
          children: [
            for (final entry in entries)
              _CatalogCard(entry: entry, onTap: () => onTap(entry)),
          ],
        );
      },
    );
  }
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({required this.entry, required this.onTap});

  final ButtonCatalogEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final buttonType = entry.buttonType;
    final (cols, rows) = buttonType != null
        ? catalogGridSizeFor(buttonType)
        : (1, 1);
    final isResizable = buttonType != null && catalogIsResizableFor(buttonType);

    return InkWell(
      borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
      onTap: onTap,
      child: BrandCard(
        padding: const EdgeInsets.all(AppMetrics.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.brandViolet.withAlpha(24),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(entry.icon, color: AppColors.brandViolet, size: 19),
            ),
            const SizedBox(height: 10),
            Text(
              entry.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.brandText,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Expanded(
              child: Text(
                entry.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.brandTextMuted,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (buttonType != null) ...[
                  BrandBadge(label: '$cols×$rows', dense: true),
                  BrandBadge(
                    label: isResizable ? 'Resizable' : 'Fixed size',
                    tone: isResizable ? BrandTone.info : BrandTone.neutral,
                    dense: true,
                  ),
                ] else
                  const BrandBadge(
                    label: 'Toggle',
                    tone: BrandTone.violet,
                    dense: true,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
