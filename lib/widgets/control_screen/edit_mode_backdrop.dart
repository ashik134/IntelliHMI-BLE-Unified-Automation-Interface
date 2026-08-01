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
