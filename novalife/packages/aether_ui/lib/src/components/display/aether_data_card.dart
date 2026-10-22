import 'package:flutter/material.dart';

import '../../theme/aether_radii.dart';
import '../../theme/aether_spacing.dart';
import '../../utils/extensions.dart';

/// Key-value metadata pair displayed within an [AetherDataCard].
@immutable
class AetherDataCardField {
  /// Descriptive label for this data field (e.g., 'Status', 'Date', 'Type').
  final String label;

  /// Formatted string value of the field.
  final String value;

  /// Optional leading icon displayed before the label.
  final Widget? icon;

  const AetherDataCardField({
    required this.label,
    required this.value,
    this.icon,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AetherDataCardField &&
          runtimeType == other.runtimeType &&
          label == other.label &&
          value == other.value;

  @override
  int get hashCode => Object.hash(label, value);
}

/// A versatile, structured surface card for displaying records, diagnostic summaries,
/// reports, or entity overviews.
///
/// Features leading avatar/icon slot, title, subtitle, status badge, metadata key-value
/// fields grid, trailing actions, selection state, and tap interaction.
class AetherDataCard extends StatelessWidget {
  /// Primary headline text of the card.
  final String title;

  /// Optional secondary descriptive text under [title].
  final String? subtitle;

  /// Leading widget, typically an avatar, thumbnail, or icon.
  final Widget? leading;

  /// Optional status badge displayed in the top-right header area.
  final Widget? badge;

  /// Optional trailing widget displayed at the end of the header row.
  final Widget? trailing;

  /// Structured key-value fields displayed below the header.
  final List<AetherDataCardField>? fields;

  /// Action buttons or controls docked at the bottom of the card.
  final List<Widget>? actions;

  /// Tap callback triggered when the card is pressed.
  final VoidCallback? onTap;

  /// Whether this card is visually selected, showing a primary color highlight border.
  final bool isSelected;

  /// Custom padding within the card. Defaults to [AetherSpacing.lg] (16px).
  final EdgeInsetsGeometry? padding;

  /// Whether the card has shadow elevation instead of an outline border.
  final bool isElevated;

  const AetherDataCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.badge,
    this.trailing,
    this.fields,
    this.actions,
    this.onTap,
    this.isSelected = false,
    this.padding,
    this.isElevated = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;
    final typography = context.aetherTypography;

    final cardBorder = isSelected
        ? Border.all(color: colors.primary, width: 2.0)
        : (isElevated ? null : Border.all(color: colors.border, width: 1.0));

    final cardShadow = isElevated
        ? context.aetherShadows.md
        : (isSelected ? context.aetherShadows.sm : context.aetherShadows.none);

    final cardBackground = isElevated ? colors.surfaceElevated : colors.surface;

    Widget content = Padding(
      padding: padding ?? const EdgeInsets.all(AetherSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: AetherSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: typography.titleSmall.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: AetherSpacing.xxs),
                      Text(
                        subtitle!,
                        style: typography.bodySmall.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: AetherSpacing.sm),
                badge!,
              ],
              if (trailing != null) ...[
                const SizedBox(width: AetherSpacing.sm),
                trailing!,
              ],
            ],
          ),

          // Metadata Fields
          if (fields != null && fields!.isNotEmpty) ...[
            const SizedBox(height: AetherSpacing.md),
            ...fields!.map(
              (field) => Padding(
                padding: const EdgeInsets.symmetric(vertical: AetherSpacing.xxs),
                child: Row(
                  children: [
                    if (field.icon != null) ...[
                      field.icon!,
                      const SizedBox(width: AetherSpacing.xs),
                    ],
                    Text(
                      '${field.label}: ',
                      style: typography.labelSmall.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        field.value,
                        style: typography.bodySmall.copyWith(
                          color: colors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Footer Actions
          if (actions != null && actions!.isNotEmpty) ...[
            const SizedBox(height: AetherSpacing.md),
            Divider(height: 1, color: colors.borderSubtle),
            const SizedBox(height: AetherSpacing.sm),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AetherSpacing.sm,
              runSpacing: AetherSpacing.xs,
              children: actions!,
            ),
          ],
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: AetherRadii.md,
        border: cardBorder,
        boxShadow: cardShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: AetherRadii.md,
          onTap: onTap,
          child: content,
        ),
      ),
    );
  }
}
