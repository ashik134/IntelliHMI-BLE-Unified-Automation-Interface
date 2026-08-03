import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/widget_catalog.dart';
import 'package:rev_crane_control_ops/widgets/buttons/configurable_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CatalogPreviewStage
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
//
// Shared by three call sites that must render the IDENTICAL visual so the
// widget never appears to change mid-interaction: the catalogue card
// (WidgetCatalogScreen), the lifted/dragged feedback avatar, and
// SettlingPreviewOverlay's grid-settle animation.
// ─────────────────────────────────────────────────────────────────────────────

/// Inner padding around the control inside its preview stage — shared by
/// every call site so the preview stays pixel-identical (never a visible
/// resize) as it moves from catalogue card to floating feedback to settling
/// into its final grid rectangle.
const double kCatalogPreviewInnerPadding = 10;

class CatalogPreviewStage extends StatelessWidget {
  const CatalogPreviewStage({super.key, required this.entry});

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
          padding: const EdgeInsets.all(kCatalogPreviewInnerPadding),
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
