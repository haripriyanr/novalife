import 'package:flutter/material.dart';

import '../../theme/aether_radii.dart';
import '../../theme/aether_spacing.dart';
import '../../utils/extensions.dart';

/// Structured grouping container card with title, subtitle, leading icon,
/// header actions, child content, and optional footer button row.
class AetherSectionCard extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? leadingIcon;
  final Widget? headerAction;
  final Widget child;
  final Widget? footer;
  final EdgeInsetsGeometry? padding;
  final bool isElevated;
  final VoidCallback? onTap;
  final Color? customBackgroundColor;

  const AetherSectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.leadingIcon,
    this.headerAction,
    required this.child,
    this.footer,
    this.padding,
    this.isElevated = false,
    this.onTap,
    this.customBackgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;
    final typography = context.aetherTypography;
    final shadows = context.aetherShadows;

    final bgColor = customBackgroundColor ??
        (isElevated ? colors.surfaceElevated : colors.surface);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: AetherRadii.md,
        border: isElevated ? null : Border.all(color: colors.border),
        boxShadow: isElevated ? shadows.md : shadows.none,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: AetherRadii.md,
          onTap: onTap,
          child: Padding(
            padding: padding ?? const EdgeInsets.all(AetherSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null || headerAction != null || leadingIcon != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AetherSpacing.md),
                    child: Row(
                      children: [
                        if (leadingIcon != null) ...[
                          leadingIcon!,
                          const SizedBox(width: AetherSpacing.sm),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (title != null) Text(title!, style: typography.titleSmall),
                              if (subtitle != null) Text(subtitle!, style: typography.bodySmall),
                            ],
                          ),
                        ),
                        ?headerAction,
                      ],
                    ),
                  ),
                child,
                if (footer != null) ...[
                  const SizedBox(height: AetherSpacing.md),
                  Divider(height: 1, color: colors.borderSubtle),
                  const SizedBox(height: AetherSpacing.sm),
                  footer!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
