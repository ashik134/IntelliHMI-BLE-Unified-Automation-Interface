import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/customization_interaction_mode.dart';
import 'package:rev_crane_control_ops/models/widget_catalog.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/catalog_preview_stage.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/device_info_appbar.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WidgetCatalogScreen
//
// Reached from the customization toolbar's "Widgets" action — rendered as a
// sliding overlay INSIDE the control screen's own Stack (see
// CatalogueOverlayHost), never pushed as its own Navigator route (see
// _DraggableCatalogCard's doc comment for why that distinction matters).
// Browsing is pure reference — cards are visually inert (see
// CatalogPreviewStage) — but a long press on a card begins the full
// placement flow: the preview lifts (_LiftingCataloguePreview), the
// catalogue overlay slides away to reveal the control screen beneath it
// (see LayoutEditController.beginCatalogueLift / confirmPlacementStarted),
// the SAME preview keeps following the finger there, and releasing it hands
// off to LayoutEditController.handleCatalogueDrop, which finds a
// collision-free grid rectangle and animates the widget into it (see
// SettlingPreviewOverlay).
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
  late final ScrollController _scrollController;
  LayoutEditController? _editCtrl;

  @override
  void initState() {
    super.initState();
    final editCtrl = context.read<LayoutEditController>();
    _editCtrl = editCtrl;
    // Resume from wherever the operator last left off — see
    // LayoutEditController.catalogueScrollOffset's doc comment.
    _scrollController = ScrollController(
      initialScrollOffset: editCtrl.catalogueScrollOffset,
    )..addListener(_persistScrollOffset);
  }

  void _persistScrollOffset() {
    if (!_scrollController.hasClients) return;
    _editCtrl?.updateCatalogueScrollOffset(_scrollController.offset);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_persistScrollOffset);
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
    // Exactly matches the outer CatalogPreviewStage rendered inside the
    // card, so the lifted/floating preview's first frame is pixel-identical
    // to what was on the card, never a visible resize.
    final previewStageSize = Size(
      cardWidth - _kCardPadding * 2,
      _kPreviewHeight,
    );

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Column(
        children: [
          _WidgetsAppBar(
            onBack: () =>
                context.read<LayoutEditController>().closeCatalogueBrowsing(),
          ),
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
                          previewStageSize: previewStageSize,
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
    required Size previewStageSize,
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
                (context, index) => _DraggableCatalogCard(
                  entry: group.value[index],
                  previewStageSize: previewStageSize,
                ),
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
// _DraggableCatalogCard
//
// Wraps a plain _CatalogCard with long-press-to-lift. LongPressDraggable is
// deliberately reused rather than hand-rolled: its DelayedMultiDragGesture-
// Recognizer already arbitrates correctly against the ancestor
// CustomScrollView (vertical movement before recognition hands the gesture
// to scrolling, exactly like any other long-press-draggable list item), its
// haptic-on-recognize is the same HapticFeedback.selectionClick() convention
// already used elsewhere in this app (see main.dart's bottom nav), and —
// critically — its avatar/recognizer are explicitly designed to survive the
// Draggable being removed from the widget tree mid-drag (see
// _DraggableState's own doc comment in the framework source, drag_target.
// dart), which is exactly what "reverse the transition when placement
// begins" needs: the operator must be able to keep dragging after the
// catalogue slides away underneath.
//
// That tree-removal survival is real, but it is NOT sufficient by itself —
// this is the one thing about this widget that is not optional to
// understand before touching it. NavigatorState.pop()/push() unconditionally
// cancels every pointer the Navigator has ever seen go down
// (_afterNavigation -> _cancelActivePointers, in navigator.dart), which
// dispatches a synthetic PointerCancelEvent to this drag's own pointer the
// instant a route changes — regardless of whether the Draggable itself
// stays mounted. An earlier version of this screen was pushed as its own
// Navigator route and popped (from _handleLiftComplete, right after the
// lift animation) to reveal the control screen underneath; that pop silently
// canceled the in-progress drag within the same frame, landing the widget
// at whatever the release-point search resolved to from wherever the finger
// happened to be at that instant — i.e. auto-placement, visually
// indistinguishable from a real carry-and-drop since both end with "a widget
// appears in the grid." The catalogue is now rendered as a sliding overlay
// within the SAME route instead (see CatalogueOverlayHost) — closing it is
// an ordinary rebuild, never a Navigator transition — which is the only way
// this drag actually survives from catalogue to release. Do not reintroduce
// a pushed/popped route for the catalogue without re-solving this.
// ─────────────────────────────────────────────────────────────────────────────

const Duration _kLongPressDelay = Duration(milliseconds: 400);

class _DraggableCatalogCard extends StatefulWidget {
  const _DraggableCatalogCard({
    required this.entry,
    required this.previewStageSize,
  });

  final CatalogEntry entry;
  final Size previewStageSize;

  @override
  State<_DraggableCatalogCard> createState() => _DraggableCatalogCardState();
}

class _DraggableCatalogCardState extends State<_DraggableCatalogCard> {
  late LayoutEditController _editCtrl;
  Offset? _dragAnchor;
  bool _dragFinishHandled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _editCtrl = context.read<LayoutEditController>();
  }

  /// Maps the point the operator touched into the preview stage's coordinate
  /// space. The anchor may sit outside the preview when the touch begins on
  /// the card text; preserving that offset avoids a visible handoff jump.
  Offset _grabAnchor(
    Draggable<Object> draggable,
    BuildContext context,
    Offset position,
  ) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      final fallback = widget.previewStageSize.center(Offset.zero);
      _dragAnchor = fallback;
      return fallback;
    }
    final local = renderBox.globalToLocal(position);
    final anchor = local - const Offset(_kCardPadding, _kCardPadding);
    _dragAnchor = anchor;
    return anchor;
  }

  void _handleDragStarted() {
    if (_editCtrl.interactionMode !=
        CustomizationInteractionMode.browsingCatalogue) {
      return;
    }
    _dragFinishHandled = false;
    HapticFeedback.selectionClick();
    _editCtrl.beginCatalogueLift(widget.entry);
  }

  /// Advances liftingCatalogueWidget -> placingWidget once the preview's own
  /// lift-off animation finishes. That mode change is the ENTIRE mechanism
  /// behind "reveal the control screen behind it" — CatalogueOverlayHost
  /// watches interactionMode and slides the whole catalogue away in
  /// response — so this deliberately does nothing else. In particular: no
  /// Navigator call belongs here (see _DraggableCatalogCard's doc comment
  /// for exactly what goes wrong if one is added back).
  void _handleLiftComplete() {
    if (_editCtrl.interactionMode !=
        CustomizationInteractionMode.liftingCatalogueWidget) {
      return;
    }
    _editCtrl.confirmPlacementStarted();
  }

  /// Handles the end of the drag, from wherever the finger actually was.
  /// This State may already be unmounted by this point — the catalogue
  /// overlay stops being built once interactionMode moves past
  /// placingWidget (see CatalogueOverlayHost) — so this deliberately touches
  /// only [_editCtrl] (a reference to the long-lived controller, captured
  /// while mounted, not this State's own BuildContext) and never
  /// `context`/`mounted`-gated UI.
  ///
  /// [wasAccepted] mirrors `DraggableDetails.wasAccepted`: true only when a
  /// DragTarget (PlacementCancelBar) accepted the drop, which already
  /// canceled the session itself via its own onAcceptWithDetails — this
  /// method has nothing further to do in that case. Both onDragEnd and
  /// onDraggableCanceled can fire for the same gesture (Flutter calls
  /// onDraggableCanceled in addition to onDragEnd when not accepted); the
  /// guard below makes whichever fires first authoritative.
  void _handleDragEnd(bool wasAccepted, Offset offset) {
    if (_dragFinishHandled) return;
    _dragFinishHandled = true;

    if (_editCtrl.interactionMode ==
        CustomizationInteractionMode.liftingCatalogueWidget) {
      // Released before the lift animation even finished separating the
      // preview from its card — never reached the control screen at all.
      _editCtrl.cancelCataloguePlacement(returnToCatalogueBrowsing: true);
      return;
    }
    if (wasAccepted) return;
    _editCtrl.handleCatalogueDrop(
      globalDropOffset: offset,
      previewSize: widget.previewStageSize,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LongPressDraggable<CatalogEntry>(
      data: widget.entry,
      delay: _kLongPressDelay,
      hapticFeedbackOnStart: false,
      dragAnchorStrategy: _grabAnchor,
      feedback: _LiftingCataloguePreview(
        entry: widget.entry,
        size: widget.previewStageSize,
        dragAnchor: () => _dragAnchor,
        onLiftComplete: _handleLiftComplete,
      ),
      childWhenDragging: const _CatalogCardPlaceholder(),
      onDragStarted: _handleDragStarted,
      onDragEnd: (details) => _handleDragEnd(details.wasAccepted, details.offset),
      onDraggableCanceled: (_, offset) => _handleDragEnd(false, offset),
      child: _CatalogCard(entry: widget.entry),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LiftingCataloguePreview
//
// The floating "preview" — exactly the same CatalogPreviewStage content,
// at exactly the size it rendered at on the card, so nothing is destroyed
// and recreated at a different size. It plays a small one-shot lift
// animation on its own entrance (scale + soft shadow, ~160ms, easeOutCubic)
// and then reports completion so the controller can advance
// liftingCatalogueWidget -> placingWidget; the catalogue-overlay slide-away
// reveal happens reactively from that same mode change (see
// CatalogueOverlayHost), after the preview has visually separated from its
// catalogue card.
//
// Watches LayoutEditController.interactionMode so a Cancel tap elsewhere
// (the control screen's Cancel bar) can make this preview vanish
// immediately, even though Draggable's own avatar keeps silently tracking
// the still-down finger in the background until it actually lifts (see
// LayoutEditController.cancelCataloguePlacement's doc comment).
// ─────────────────────────────────────────────────────────────────────────────

class _LiftingCataloguePreview extends StatefulWidget {
  const _LiftingCataloguePreview({
    required this.entry,
    required this.size,
    required this.dragAnchor,
    required this.onLiftComplete,
  });

  final CatalogEntry entry;
  final Size size;
  final Offset? Function() dragAnchor;
  final VoidCallback onLiftComplete;

  @override
  State<_LiftingCataloguePreview> createState() =>
      _LiftingCataloguePreviewState();
}

class _LiftingCataloguePreviewState extends State<_LiftingCataloguePreview>
    with SingleTickerProviderStateMixin {
  static const _liftDuration = Duration(milliseconds: 160);

  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<int> _shadowAlpha;
  late final Animation<double> _shadowBlur;
  late final Animation<double> _shadowDy;
  late final Alignment _scaleAlignment;
  bool _liftReported = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _liftDuration);
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _scale = Tween<double>(begin: 1.0, end: 1.03).animate(curved);
    _shadowAlpha = IntTween(begin: 0, end: 56).animate(curved);
    _shadowBlur = Tween<double>(begin: 0, end: 10).animate(curved);
    _shadowDy = Tween<double>(begin: 0, end: 3).animate(curved);
    _scaleAlignment = _scaleAlignmentFor(widget.dragAnchor());
    _controller.addStatusListener(_handleStatus);
    _controller.forward();
  }

  void _handleStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _liftReported) return;
    _liftReported = true;
    widget.onLiftComplete();
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatus);
    _controller.dispose();
    super.dispose();
  }

  Alignment _scaleAlignmentFor(Offset? anchor) {
    final effectiveAnchor = anchor ?? widget.size.center(Offset.zero);
    final x = widget.size.width <= 0
        ? 0.0
        : (effectiveAnchor.dx / widget.size.width) * 2 - 1;
    final y = widget.size.height <= 0
        ? 0.0
        : (effectiveAnchor.dy / widget.size.height) * 2 - 1;
    return Alignment(x, y);
  }

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<LayoutEditController>().interactionMode;
    final isLive =
        mode == CustomizationInteractionMode.liftingCatalogueWidget ||
        mode == CustomizationInteractionMode.placingWidget;

    final stage = SizedBox(
      width: widget.size.width,
      height: widget.size.height,
      child: CatalogPreviewStage(entry: widget.entry),
    );

    return Material(
      type: MaterialType.transparency,
      child: !isLive
          ? const SizedBox.shrink()
          : AnimatedBuilder(
              animation: _controller,
              builder: (context, child) => Transform.scale(
                alignment: _scaleAlignment,
                scale: _scale.value,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(_shadowAlpha.value),
                        blurRadius: _shadowBlur.value,
                        spreadRadius: -1,
                        offset: Offset(0, _shadowDy.value),
                      ),
                    ],
                  ),
                  child: child,
                ),
              ),
              child: stage,
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

class _CatalogCardPlaceholder extends StatelessWidget {
  const _CatalogCardPlaceholder();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.panel.withAlpha(120),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.panelStroke.withAlpha(120)),
      ),
      child: const SizedBox.expand(),
    );
  }
}

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
              child: CatalogPreviewStage(entry: entry),
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

// CatalogPreviewStage (the actual inert control preview) now lives in
// lib/widgets/control_screen/catalog_preview_stage.dart, shared with the
// dragged feedback avatar above and SettlingPreviewOverlay's grid-settle
// animation — all three must render the identical visual.
