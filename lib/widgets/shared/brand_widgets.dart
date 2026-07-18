import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';

// ═══════════════════════════════════════════════════════════════════════
// Shared design-system primitives for the Home, Scan and Authentication
// screens. Everything here leans on AppColors' "brand*" tokens so the
// three screens visually belong to one product, with the violet accent
// tying back to the Control Screen.
// ═══════════════════════════════════════════════════════════════════════

/// Small uppercase eyebrow label used above section groups
/// ("QUICK ACTIONS", "NEARBY DEVICES", etc).
class BrandSectionLabel extends StatelessWidget {
  const BrandSectionLabel({super.key, required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppColors.brandTextMuted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
          ),
        ),
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
  }
}

/// Standard elevated content card used across all three screens.
class BrandCard extends StatelessWidget {
  const BrandCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppMetrics.spaceLg),
    this.color = AppColors.brandSurface,
    this.borderColor = AppColors.brandBorder,
    this.radius = AppMetrics.radiusLg,
    this.boxShadow = AppMetrics.shadowSm,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;
  final double radius;
  final List<BoxShadow> boxShadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
        boxShadow: boxShadow,
      ),
      child: child,
    );
  }
}

/// Status tone used by pills/badges/banners across the three screens.
enum BrandTone { neutral, violet, success, warning, danger, info }

class _ToneColors {
  const _ToneColors(this.fg, this.bg, this.border);
  final Color fg;
  final Color bg;
  final Color border;
}

_ToneColors _resolveBrandTone(BrandTone tone) {
  switch (tone) {
    case BrandTone.violet:
      return const _ToneColors(
        AppColors.brandVioletDeep,
        AppColors.brandVioletSoft,
        Color(0x338B5CF6),
      );
    case BrandTone.success:
      return const _ToneColors(
        AppColors.brandSuccess,
        AppColors.brandSuccessSoft,
        Color(0x3312B76A),
      );
    case BrandTone.warning:
      return const _ToneColors(
        AppColors.brandWarning,
        AppColors.brandWarningSoft,
        Color(0x33F79009),
      );
    case BrandTone.danger:
      return const _ToneColors(
        AppColors.brandDanger,
        AppColors.brandDangerSoft,
        Color(0x33F04438),
      );
    case BrandTone.info:
      return const _ToneColors(
        AppColors.brandInfo,
        AppColors.brandInfoSoft,
        Color(0x333B82F6),
      );
    case BrandTone.neutral:
      return const _ToneColors(
        AppColors.brandTextSub,
        AppColors.brandSurfaceAlt,
        AppColors.brandBorder,
      );
  }
}

/// Compact pill badge, e.g. "SCANNING", "3 FOUND", "READY".
class BrandBadge extends StatelessWidget {
  const BrandBadge({
    super.key,
    required this.label,
    this.tone = BrandTone.neutral,
    this.icon,
    this.dense = false,
  });

  final String label;
  final BrandTone tone;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = _resolveBrandTone(tone);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(AppMetrics.radiusPill),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 10 : 12, color: colors.fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: colors.fg,
              fontSize: dense ? 9.5 : 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width status banner: icon + title + message, optional trailing
/// action row and busy indicator. Used for hero status on scan/auth.
class BrandStatusBanner extends StatelessWidget {
  const BrandStatusBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.tone = BrandTone.neutral,
    this.busy = false,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String message;
  final BrandTone tone;
  final bool busy;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = _resolveBrandTone(tone);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: const EdgeInsets.all(AppMetrics.spaceLg),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.fg.withAlpha(28),
                  borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
                ),
                child: busy
                    ? Padding(
                        padding: const EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: colors.fg,
                        ),
                      )
                    : Icon(icon, color: colors.fg, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: colors.fg,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      message,
                      style: const TextStyle(
                        color: AppColors.brandTextSub,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
    );
  }
}

/// Primary CTA — solid violet-brand action button with icon, used for the
/// main call-to-action on each of the three screens.
class BrandPrimaryButton extends StatelessWidget {
  const BrandPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.height = 52,
    this.color = AppColors.brandViolet,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final double height;
  final Color color;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = SizedBox(
      height: height,
      width: expand ? double.infinity : null,
      child: FilledButton.icon(
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : (icon != null ? Icon(icon, size: 18) : const SizedBox.shrink()),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.6),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.brandTextMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          ),
        ),
      ),
    );
    return child;
  }
}

/// Secondary/outlined button, e.g. "Back to Scan".
class BrandSecondaryButton extends StatelessWidget {
  const BrandSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 48,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon != null ? Icon(icon, size: 16) : const SizedBox.shrink(),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.brandTextSub,
          side: const BorderSide(color: AppColors.brandBorderStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
          ),
        ),
      ),
    );
  }
}

/// Shared text-field decoration builder so Home/Scan/Auth forms match.
InputDecoration brandInputDecoration({
  required String label,
  String? hint,
  required IconData icon,
  Widget? suffix,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.brandTextMuted),
    labelStyle: const TextStyle(color: AppColors.brandTextSub),
    prefixIcon: Icon(icon, color: AppColors.brandTextMuted, size: 20),
    suffixIcon: suffix,
    filled: true,
    fillColor: AppColors.brandSurfaceAlt,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
      borderSide: const BorderSide(color: AppColors.brandBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
      borderSide: const BorderSide(color: AppColors.brandBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
      borderSide: const BorderSide(color: AppColors.brandViolet, width: 1.6),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
      borderSide: const BorderSide(color: AppColors.brandDanger),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
      borderSide: const BorderSide(color: AppColors.brandDanger, width: 1.6),
    ),
  );
}

/// Small circular icon button used in headers/app bars (back, settings...).
class BrandIconButton extends StatelessWidget {
  const BrandIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.dark = false,
    this.size = 40,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool dark;
  final double size;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: dark ? Colors.white.withAlpha(20) : AppColors.brandSurface,
            shape: BoxShape.circle,
            border: Border.all(
              color: dark ? Colors.white.withAlpha(40) : AppColors.brandBorder,
            ),
          ),
          child: Icon(
            icon,
            size: size * 0.5,
            color: dark ? AppColors.brandOnDark : AppColors.brandTextSub,
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// Shared app identity mark (rounded logo tile) used on Home header and
/// the Auth context panel so branding is consistent everywhere.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 44, this.dark = false});

  final double size;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.06),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withAlpha(24) : AppColors.brandVioletSoft,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(
          color: dark
              ? Colors.white.withAlpha(40)
              : AppColors.brandViolet.withAlpha(50),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.2),
        child: Image.asset(
          'assets/images/intellicontrol-icon-1024x1024 (6).png',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
