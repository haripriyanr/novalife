import 'package:flutter/material.dart';

import '../../theme/aether_spacing.dart';
import '../../utils/extensions.dart';

/// Top application header bar implementing [PreferredSizeWidget].
/// Provides title, subtitle, leading action, trailing actions, and integrated search slot.
class AetherHeaderBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final String? titleText;
  final Widget? subtitle;
  final String? subtitleText;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final List<Widget>? actions;
  final Widget? searchSlot;
  final PreferredSizeWidget? bottom;
  final bool hasBorder;
  final double height;
  final Color? backgroundColor;

  const AetherHeaderBar({
    super.key,
    this.title,
    this.titleText,
    this.subtitle,
    this.subtitleText,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.actions,
    this.searchSlot,
    this.bottom,
    this.hasBorder = true,
    this.height = 64.0,
    this.backgroundColor,
  });

  @override
  Size get preferredSize => Size.fromHeight(height + (bottom?.preferredSize.height ?? 0.0));

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;
    final typography = context.aetherTypography;

    Widget? effectiveLeading = leading;
    if (effectiveLeading == null && automaticallyImplyLeading) {
      final ModalRoute<dynamic>? parentRoute = ModalRoute.of(context);
      final bool canPop = parentRoute?.canPop ?? false;
      if (canPop) {
        effectiveLeading = IconButton(
          icon: const Icon(Icons.arrow_back),
          color: colors.textPrimary,
          onPressed: () => Navigator.of(context).maybePop(),
        );
      }
    }

    return Container(
      height: preferredSize.height,
      padding: const EdgeInsets.symmetric(horizontal: AetherSpacing.lg),
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.surface,
        border: hasBorder ? Border(bottom: BorderSide(color: colors.border)) : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              children: [
                if (effectiveLeading != null) ...[
                  effectiveLeading,
                  const SizedBox(width: AetherSpacing.sm),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title ?? Text(titleText ?? '', style: typography.titleMedium),
                      if (subtitle != null || subtitleText != null)
                        subtitle ?? Text(subtitleText ?? '', style: typography.bodySmall),
                    ],
                  ),
                ),
                if (searchSlot != null) ...[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360.0),
                    child: searchSlot!,
                  ),
                  const SizedBox(width: AetherSpacing.sm),
                ],
                ...?actions,
              ],
            ),
          ),
          ?bottom,
        ],
      ),
    );
  }
}
