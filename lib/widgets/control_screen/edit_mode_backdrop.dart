import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EditModeBackdrop
//
// Full-screen visual cue that Customization/Edit Mode is active. Layered as
// a Positioned.fill over the *entire* body — safety panel, sensor/LED rows,
// canvas, status chip — so the "this isn't normal operation" signal isn't
// confined to the AppBar alone: a violet vignette wash plus a persistent
// frame border around the whole screen.
//
// Always IgnorePointer: this widget only paints, it never intercepts touches.
// Blocking control interaction is ControlCanvas's job (AbsorbPointer on every
// occupied cell) and CraneController's job (estopLatched forced true for the
// whole edit session by LayoutEditController.enter) — this is purely visual.
// ─────────────────────────────────────────────────────────────────────────────

class EditModeBackdrop extends StatelessWidget {
  const EditModeBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.9),
            radius: 1.6,
            colors: [
              AppColors.selectionViolet.withAlpha(23),
              AppColors.selectionViolet.withAlpha(0),
            ],
            stops: const [0.0, 0.75],
          ),
          border: Border.all(
            color: AppColors.selectionViolet.withAlpha(90),
            width: 2,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BottomActionsRecede
//
// Fades and nudges [child] downward when [recede] is true, coordinated with
// EditModeToolbarHost's own 280ms/easeOutCubic entrance so the normal-mode
// bottom content (the status chip, sitting where CustomizationToolbar docks)
// visually gets out of the way as the toolbar rises, instead of the two
// abruptly overlapping.
// ─────────────────────────────────────────────────────────────────────────────

class BottomActionsRecede extends StatelessWidget {
  const BottomActionsRecede({
    super.key,
    required this.recede,
    required this.child,
  });

  final bool recede;
  final Widget child;

  static const Duration _duration = Duration(milliseconds: 280);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: recede,
      child: AnimatedSlide(
        duration: _duration,
        curve: Curves.easeOutCubic,
        offset: recede ? const Offset(0, 0.6) : Offset.zero,
        child: AnimatedOpacity(
          duration: _duration,
          curve: Curves.easeOutCubic,
          opacity: recede ? 0.0 : 1.0,
          child: child,
        ),
      ),
    );
  }
}
