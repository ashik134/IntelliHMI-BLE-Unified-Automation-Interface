import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/widget_catalog.dart';
import 'package:rev_crane_control_ops/widgets/buttons/configurable_button.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/device_info_appbar.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WidgetCatalogScreen
//
// Reached from the customization toolbar's "Widgets" action. A pure browsing
// / reference catalogue: every control family IntelliHMI supports, grouped
// Category -> Subgroup -> two-column preview grid (see widget_catalog.dart
// for the registry driving this). Cards render a real, live-fidelity miniature
// of the control (via ConfigurableButton — the same widget the control
// screen itself uses) wrapped in IgnorePointer so it is strictly non-
// interactive; nothing here can place a widget, write BLE, or touch the
// saved layout. That lands in a later stage (see the long-press note on
// _CatalogPreviewStage).
// ─────────────────────────────────────────────────────────────────────────────

const double _kPagePadding = 18;
const double _kColumnGap = 14;
const double _kRowGap = 18;
const double _kCategoryTopSpacing = 28;
const double _kSubgroupTopSpacing = 18;
const double _kSubgroupHeadingGap = 10;

const double _kPreviewHeight = 148;
const double _kCardPadding = 14;
const double _kGapAfterPreview = 10;
const double _kNameHeight = 38;
const double _kGapAfterName = 4;
const double _kNotationHeight = 20;
const double _kGapAfterNotation = 8;
const double _kMetaHeight = 26;
const double _kGapAfterMeta = 8;
const double _kDescriptionHeight = 48;

// Fixed content-region budget -> every card renders at exactly this height,
// regardless of column count, so "metadata positions [stay] consistent
// between cards" without measuring text at build time.
const double _kCardHeight =
    _kCardPadding * 2 +
    _kPreviewHeight +
    _kGapAfterPreview +
    _kNameHeight +
    _kGapAfterName +
    _kNotationHeight +
    _kGapAfterNotation +
    _kMetaHeight +
    _kGapAfterMeta +
    _kDescriptionHeight;

int _columnsForWidth(double width) {
  if (width < 360) return 1;
  if (width < 720) return 2;
  if (width < 1024) return 3;
  return 4;
}

class WidgetCatalogScreen extends StatefulWidget {
  const WidgetCatalogScreen({super.key});

  @override
  State<WidgetCatalogScreen> createState() => _WidgetCatalogScreenState();
}

class _WidgetCatalogScreenState extends State<WidgetCatalogScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grouped = groupCatalog(kWidgetCatalog);
    final width = MediaQuery.sizeOf(context).width;
    final columns = _columnsForWidth(width);
    final cardWidth =
        (width - _kPagePadding * 2 - _kColumnGap * (columns - 1)) / columns;
    final aspectRatio = cardWidth / _kCardHeight;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Column(
        children: [
          _WidgetsAppBar(onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: SafeArea(
              top: false,
              child: RawScrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                thickness: 3,
                radius: const Radius.circular(8),
                thumbColor: AppColors.darkTextSub.withAlpha(140),
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  slivers: [
                    for (final category in CatalogCategory.values)
                      if (grouped[category] != null)
                        ..._categorySlivers(
                          category: category,
                          groups: grouped[category]!,
                          columns: columns,
                          aspectRatio: aspectRatio,
                        ),
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _categorySlivers({
    required CatalogCategory category,
    required Map<String, List<CatalogEntry>> groups,
    required int columns,
    required double aspectRatio,
  }) {
    final slivers = <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          _kPagePadding,
          _kCategoryTopSpacing,
          _kPagePadding,
          0,
        ),
        sliver: SliverToBoxAdapter(
          child: _CategoryHeading(title: category.displayName),
        ),
      ),
    ];
    for (final group in groups.entries) {
      slivers
        ..add(
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              _kPagePadding,
              _kSubgroupTopSpacing,
              _kPagePadding,
              _kSubgroupHeadingGap,
            ),
            sliver: SliverToBoxAdapter(
              child: _SubgroupHeading(title: group.key),
            ),
          ),
        )
        ..add(
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: _kPagePadding),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: _kRowGap,
                crossAxisSpacing: _kColumnGap,
                childAspectRatio: aspectRatio,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _CatalogCard(entry: group.value[index]),
                childCount: group.value.length,
              ),
            ),
          ),
        );
    }
    return slivers;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _WidgetsAppBar extends StatelessWidget {
  const _WidgetsAppBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: kToolbarHeight + 12,
        child: DecoratedBox(
          decoration: const BoxDecoration(color: AppColors.appBarEditingBg),
          child: Stack(
            children: [
              const Positioned.fill(child: ControlAppBarGlow()),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.darkText,
                    ),
                    tooltip: 'Back',
                    onPressed: onBack,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Widgets',
                    style: TextStyle(
                      color: AppColors.darkText,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Headings
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryHeading extends StatelessWidget {
  const _CategoryHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: AppColors.darkText,
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }
}

class _SubgroupHeading extends StatelessWidget {
  const _SubgroupHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.darkTextSub,
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CatalogCard
//
// Every region below the preview stage occupies a fixed height slot
// (populated or blank) so cards line up row-to-row regardless of which
// entry has a notation or how many tags it carries.
// ─────────────────────────────────────────────────────────────────────────────

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({required this.entry});

  final CatalogEntry entry;

  @override
  Widget build(BuildContext context) {
    final (cols, rows) = entry.gridSize;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.panelStroke),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_kCardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _kPreviewHeight,
              child: _CatalogPreviewStage(entry: entry),
            ),
            const SizedBox(height: _kGapAfterPreview),
            SizedBox(
              height: _kNameHeight,
              child: Center(
                child: Text(
                  entry.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.darkText,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ),
            ),
            const SizedBox(height: _kGapAfterName),
            SizedBox(
              height: _kNotationHeight,
              child: entry.notation == null
                  ? null
                  : Center(
                      child: Text(
                        entry.notation!,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: _kGapAfterNotation),
            SizedBox(
              height: _kMetaHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MetaChip(label: '$cols × $rows'),
                      for (final tag in entry.tags) ...[
                        const SizedBox(width: 6),
                        _MetaChip(label: tag, isGridSize: false),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: _kGapAfterMeta),
            SizedBox(
              height: _kDescriptionHeight,
              child: Text(
                entry.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.darkTextSub,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, this.isGridSize = true});

  final String label;
  final bool isGridSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isGridSize ? AppColors.accentSoft : Colors.white.withAlpha(14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isGridSize
              ? AppColors.accent.withAlpha(90)
              : Colors.white.withAlpha(30),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isGridSize ? AppColors.accent : AppColors.darkTextSub,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CatalogPreviewStage
//
// Renders the real control widget via ConfigurableButton — the exact same
// entry point the live control screens use — so the preview is genuinely
// the control, not a lookalike icon. Layered safety, per the "non-
// interactive preview" requirement:
//   1. IgnorePointer blocks every touch before it reaches the control, so
//      no gesture handler (and therefore no haptic/BLE-triggering callback)
//      can ever fire.
//   2. The callbacks passed to ConfigurableButton are no-ops anyway, so
//      even a hypothetical gesture leak writes nothing.
//   3. The ButtonConfig backing the preview is thrown away every rebuild —
//      never read from or written to the saved layout.
// A future stage may turn this stage into a long-press placement target;
// the control drawn inside it must stay non-interactive regardless.
// ─────────────────────────────────────────────────────────────────────────────

class _CatalogPreviewStage extends StatelessWidget {
  const _CatalogPreviewStage({required this.entry});

  final CatalogEntry entry;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: RepaintBoundary(
            child: ExcludeSemantics(
              child: IgnorePointer(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: entry.previewSize.width,
                    height: entry.previewSize.height,
                    child: ConfigurableButton(
                      config: entry.buildPreviewConfig(),
                      activeState: ControlState.idle,
                      isDisabled: false,
                      height: entry.previewSize.height,
                      onCommand: _noOpCommand,
                      onStateIdCommand: _noOpStateIdCommand,
                      onAnalogCommand: _noOpAnalogCommand,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _noOpCommand(String buttonId, ControlState state) {}

void _noOpStateIdCommand(String buttonId, String stateId) {}

void _noOpAnalogCommand(ButtonConfig config, double value) {}
