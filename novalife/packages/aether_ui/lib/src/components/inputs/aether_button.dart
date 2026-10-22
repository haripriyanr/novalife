import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/aether_radii.dart';
import '../../theme/aether_spacing.dart';
import '../../utils/extensions.dart';

/// Semantic variants for [AetherButton].
enum AetherButtonVariant {
  primary,
  secondary,
  outline,
  text,
  danger,
  icon,
}

/// Sizing specification enforcing min touch targets on mobile.
enum AetherButtonSize {
  sm(height: 32.0, minTouchTarget: 48.0, iconSize: 16.0),
  md(height: 44.0, minTouchTarget: 48.0, iconSize: 18.0),
  lg(height: 52.0, minTouchTarget: 52.0, iconSize: 22.0);

  final double height;
  final double minTouchTarget;
  final double iconSize;

  const AetherButtonSize({
    required this.height,
    required this.minTouchTarget,
    required this.iconSize,
  });
}

/// Universal button supporting 5 variants, 3 sizes, loading state with spinner,
/// and mobile touch target enforcement (>= 48px).
class AetherButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget? label;
  final String? labelText;
  final Widget? icon;
  final AetherButtonVariant variant;
  final AetherButtonSize size;
  final bool isLoading;
  final bool isExpanded;
  final String? tooltip;

  const AetherButton({
    super.key,
    required this.onPressed,
    this.label,
    this.labelText,
    this.icon,
    this.variant = AetherButtonVariant.primary,
    this.size = AetherButtonSize.md,
    this.isLoading = false,
    this.isExpanded = false,
    this.tooltip,
  });

  const factory AetherButton.primary({
    Key? key,
    required VoidCallback? onPressed,
    Widget? label,
    String? labelText,
    Widget? icon,
    AetherButtonSize size,
    bool isLoading,
    bool isExpanded,
    String? tooltip,
  }) = _AetherPrimaryButton;

  const factory AetherButton.secondary({
    Key? key,
    required VoidCallback? onPressed,
    Widget? label,
    String? labelText,
    Widget? icon,
    AetherButtonSize size,
    bool isLoading,
    bool isExpanded,
    String? tooltip,
  }) = _AetherSecondaryButton;

  const factory AetherButton.outline({
    Key? key,
    required VoidCallback? onPressed,
    Widget? label,
    String? labelText,
    Widget? icon,
    AetherButtonSize size,
    bool isLoading,
    bool isExpanded,
    String? tooltip,
  }) = _AetherOutlineButton;

  const factory AetherButton.text({
    Key? key,
    required VoidCallback? onPressed,
    Widget? label,
    String? labelText,
    Widget? icon,
    AetherButtonSize size,
    bool isLoading,
    String? tooltip,
  }) = _AetherTextButton;

  const factory AetherButton.danger({
    Key? key,
    required VoidCallback? onPressed,
    Widget? label,
    String? labelText,
    Widget? icon,
    AetherButtonSize size,
    bool isLoading,
    bool isExpanded,
    String? tooltip,
  }) = _AetherDangerButton;

  const factory AetherButton.icon({
    Key? key,
    required VoidCallback? onPressed,
    required Widget icon,
    AetherButtonSize size,
    bool isLoading,
    String? tooltip,
  }) = _AetherIconButton;

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;
    final typography = context.aetherTypography;
    final isMobile = context.aetherIsMobile;
    final transparentColor = colors.surface.withAlpha(0);

    Color bg;
    Color fg;
    BorderSide? border;

    switch (variant) {
      case AetherButtonVariant.primary:
        bg = colors.primary;
        fg = colors.onPrimary;
      case AetherButtonVariant.secondary:
        bg = colors.surfaceSubtle;
        fg = colors.textPrimary;
      case AetherButtonVariant.outline:
        bg = transparentColor;
        fg = colors.primary;
        border = BorderSide(color: colors.primary);
      case AetherButtonVariant.text:
        bg = transparentColor;
        fg = colors.primary;
      case AetherButtonVariant.danger:
        bg = colors.danger.base;
        fg = colors.danger.onBase;
      case AetherButtonVariant.icon:
        bg = transparentColor;
        fg = colors.textPrimary;
    }

    if (onPressed == null) {
      bg = colors.surfaceSubtle;
      fg = colors.textMuted;
      border = null;
    }

    Widget content = Row(
      mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          SizedBox(
            width: size.iconSize,
            height: size.iconSize,
            child: CircularProgressIndicator(strokeWidth: 2.0, color: fg),
          ),
          if (labelText != null || label != null) const SizedBox(width: AetherSpacing.sm),
        ] else if (icon != null) ...[
          icon!,
          if (labelText != null || label != null) const SizedBox(width: AetherSpacing.sm),
        ],
        if (label != null)
          Flexible(child: label!)
        else if (labelText != null)
          Flexible(
            child: Text(
              labelText!,
              style: typography.labelLarge.copyWith(color: fg, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );

    Widget btn = ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        side: border,
        shape: const RoundedRectangleBorder(borderRadius: AetherRadii.sm),
        minimumSize: Size(
          isExpanded
              ? double.infinity
              : (variant == AetherButtonVariant.icon
                  ? (isMobile ? math.max(48.0, size.height) : size.height)
                  : (isMobile ? math.max(48.0, 64.0) : 64.0)),
          isMobile ? math.max(48.0, size.minTouchTarget) : size.height,
        ),
      ),
      onPressed: isLoading ? null : onPressed,
      child: content,
    );

    if (tooltip != null) {
      btn = Tooltip(message: tooltip!, child: btn);
    }

    return btn;
  }
}

class _AetherPrimaryButton extends AetherButton {
  const _AetherPrimaryButton({
    super.key,
    required super.onPressed,
    super.label,
    super.labelText,
    super.icon,
    super.size = AetherButtonSize.md,
    super.isLoading = false,
    super.isExpanded = false,
    super.tooltip,
  }) : super(variant: AetherButtonVariant.primary);
}

class _AetherSecondaryButton extends AetherButton {
  const _AetherSecondaryButton({
    super.key,
    required super.onPressed,
    super.label,
    super.labelText,
    super.icon,
    super.size = AetherButtonSize.md,
    super.isLoading = false,
    super.isExpanded = false,
    super.tooltip,
  }) : super(variant: AetherButtonVariant.secondary);
}

class _AetherOutlineButton extends AetherButton {
  const _AetherOutlineButton({
    super.key,
    required super.onPressed,
    super.label,
    super.labelText,
    super.icon,
    super.size = AetherButtonSize.md,
    super.isLoading = false,
    super.isExpanded = false,
    super.tooltip,
  }) : super(variant: AetherButtonVariant.outline);
}

class _AetherTextButton extends AetherButton {
  const _AetherTextButton({
    super.key,
    required super.onPressed,
    super.label,
    super.labelText,
    super.icon,
    super.size = AetherButtonSize.md,
    super.isLoading = false,
    super.tooltip,
  }) : super(variant: AetherButtonVariant.text);
}

class _AetherDangerButton extends AetherButton {
  const _AetherDangerButton({
    super.key,
    required super.onPressed,
    super.label,
    super.labelText,
    super.icon,
    super.size = AetherButtonSize.md,
    super.isLoading = false,
    super.isExpanded = false,
    super.tooltip,
  }) : super(variant: AetherButtonVariant.danger);
}

class _AetherIconButton extends AetherButton {
  const _AetherIconButton({
    super.key,
    required super.onPressed,
    required super.icon,
    super.size = AetherButtonSize.md,
    super.isLoading = false,
    super.tooltip,
  }) : super(variant: AetherButtonVariant.icon);
}
