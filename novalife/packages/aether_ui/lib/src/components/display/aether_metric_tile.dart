import 'package:flutter/material.dart';

import '../../theme/aether_radii.dart';
import '../../theme/aether_spacing.dart';
import '../../utils/extensions.dart';
import 'aether_status_badge.dart';

/// KPI / Metric card displaying prominent values, units, trend indicators, and icons.
class AetherMetricTile extends StatelessWidget {
  /// Category label or description of the metric (e.g. 'Recovery Rate', 'Hardware Cycles').
  final String label;

  /// Primary metric value string (e.g. '128', '100%', '0.42 s').
  final String value;

  /// Optional unit label displayed beside or beneath the value (e.g. 'bits', 'cycles', 'ms').
  final String? unit;

  /// Optional leading icon displayed beside the label.
  final Widget? icon;

  /// Formatted trend delta string (e.g. '+2.4%', '-0.12%').
  final String? trend;

  /// Whether the trend is positive (success tint) or negative (danger tint). Defaults to true.
  final bool isTrendPositive;

  /// Optional semantic state to tint the primary value text.
  final AetherStatusVariant? semantic;

  /// Optional footnote caption at the bottom of the tile.
  final String? caption;

  /// Tap callback triggered when the tile is pressed.
  final VoidCallback? onTap;

  /// Custom padding within the tile. Defaults to [AetherSpacing.lg] (16px).
  final EdgeInsetsGeometry? padding;

  const AetherMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
    this.trend,
    this.isTrendPositive = true,
    this.semantic,
    this.caption,
    this.onTap,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;
    final typography = context.aetherTypography;

    Color valueColor = colors.textPrimary;
    if (semantic != null) {
      switch (semantic!) {
        case AetherStatusVariant.success:
          valueColor = colors.success.base;
        case AetherStatusVariant.danger:
          valueColor = colors.danger.base;
        case AetherStatusVariant.warning:
          valueColor = colors.warning.base;
        case AetherStatusVariant.info:
          valueColor = colors.info.base;
        case AetherStatusVariant.neutral:
          valueColor = colors.neutral.base;
      }
    }

    Widget content = Padding(
      padding: padding ?? const EdgeInsets.all(AetherSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Row: Icon, Label, Trend
          Row(
            children: [
              if (icon != null) ...[
                icon!,
                const SizedBox(width: AetherSpacing.sm),
              ],
              Expanded(
                child: Text(
                  label,
                  style: typography.labelMedium.copyWith(
                    color: colors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trend != null)
                Text(
                  trend!,
                  style: TextStyle(
                    color: isTrendPositive ? colors.success.base : colors.danger.base,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.0,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AetherSpacing.sm),

          // Value and Unit Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: typography.displayMedium.copyWith(
                    color: valueColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (unit != null && unit!.isNotEmpty) ...[
                const SizedBox(width: AetherSpacing.xs),
                Text(
                  unit!,
                  style: typography.bodyMedium.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ],
          ),

          // Optional Footnote Caption
          if (caption != null && caption!.isNotEmpty) ...[
            const SizedBox(height: AetherSpacing.xs),
            Text(
              caption!,
              style: typography.bodySmall.copyWith(
                color: colors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AetherRadii.md,
        border: Border.all(color: colors.border),
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
