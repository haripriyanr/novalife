import 'package:flutter/material.dart';

import '../../theme/aether_colors.dart';
import '../../theme/aether_radii.dart';
import '../../theme/aether_spacing.dart';
import '../../utils/extensions.dart';

/// Semantic status categories for Aether UI status indicators and badges.
enum AetherStatusVariant {
  success,
  danger,
  warning,
  info,
  neutral;

  bool get isSuccess => this == AetherStatusVariant.success;
  bool get isDanger => this == AetherStatusVariant.danger;
  bool get isWarning => this == AetherStatusVariant.warning;
  bool get isInfo => this == AetherStatusVariant.info;
  bool get isNeutral => this == AetherStatusVariant.neutral;
}

/// Backwards-compatible type alias for existing test suites.
typedef AetherSemanticStatus = AetherStatusVariant;

/// Visual rendering styles for [AetherStatusBadge].
enum AetherStatusStyle {
  /// Soft tinted pastel/dark container background with high-contrast foreground text.
  subtle,

  /// Solid bold background with crisp high-contrast foreground text.
  solid,

  /// Transparent background with colored border and colored text.
  outline,
}

/// Backwards-compatible type alias for existing test suites.
typedef AetherBadgeStyle = AetherStatusStyle;

/// Pill-shaped status badge displaying semantic states with guaranteed WCAG AA contrast.
class AetherStatusBadge extends StatelessWidget {
  /// Text label displayed inside the badge.
  final String? text;

  /// Ergonomic alias for [text].
  final String? label;

  /// Semantic state of the badge.
  final AetherStatusVariant? status;

  /// Ergonomic alias for [status].
  final AetherStatusVariant? variant;

  /// Visual fill and border style. Defaults to [AetherStatusStyle.subtle].
  final AetherStatusStyle style;

  /// Optional icon displayed before the label.
  final Widget? icon;

  /// Whether to display a 6px status dot before the text.
  final bool showDot;

  /// Custom font size for the label. Defaults to 12.0.
  final double? fontSize;

  /// Custom padding around the content. Defaults to `horizontal: 8, vertical: 4`.
  final EdgeInsetsGeometry? padding;

  const AetherStatusBadge({
    super.key,
    this.text,
    this.label,
    this.status,
    this.variant,
    this.style = AetherStatusStyle.subtle,
    this.icon,
    this.showDot = false,
    this.fontSize,
    this.padding,
  }) : assert(text != null || label != null, 'Either text or label must be provided.');

  String get _displayText => text ?? label ?? '';
  AetherStatusVariant get _effectiveVariant => variant ?? status ?? AetherStatusVariant.neutral;

  AetherSemanticColor _resolveQuad(AetherColors colors) {
    switch (_effectiveVariant) {
      case AetherStatusVariant.success:
        return colors.success;
      case AetherStatusVariant.danger:
        return colors.danger;
      case AetherStatusVariant.warning:
        return colors.warning;
      case AetherStatusVariant.info:
        return colors.info;
      case AetherStatusVariant.neutral:
        return colors.neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;
    final typography = context.aetherTypography;
    final quad = _resolveQuad(colors);

    Color bg;
    Color fg;
    Border? border;

    switch (style) {
      case AetherStatusStyle.subtle:
        bg = quad.container;
        fg = quad.onContainer;
        border = null;
      case AetherStatusStyle.solid:
        bg = quad.base;
        fg = quad.onBase;
        border = null;
      case AetherStatusStyle.outline:
        bg = colors.surface.withAlpha(0);
        fg = quad.base;
        border = Border.all(color: quad.base, width: 1.0);
    }

    return Container(
      padding: padding ??
          const EdgeInsets.symmetric(
            horizontal: AetherSpacing.sm,
            vertical: AetherSpacing.xs,
          ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AetherRadii.full,
        border: border,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 6.0,
              height: 6.0,
              decoration: BoxDecoration(
                color: fg,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AetherSpacing.xs),
          ],
          if (icon != null) ...[
            icon!,
            const SizedBox(width: AetherSpacing.xs),
          ],
          Text(
            _displayText,
            style: typography.labelSmall.copyWith(
              color: fg,
              fontSize: fontSize ?? 12.0,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
