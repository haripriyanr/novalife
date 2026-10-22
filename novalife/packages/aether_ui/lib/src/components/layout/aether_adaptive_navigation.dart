import 'package:flutter/material.dart';

import '../../theme/aether_radii.dart';
import '../../theme/aether_spacing.dart';
import '../../utils/extensions.dart';

/// Navigation destination model for [AetherAdaptiveNavigation].
class AetherNavigationItem {
  /// Unselected icon representation.
  final IconData icon;

  /// Optional active icon representation when selected.
  final IconData? activeIcon;

  /// Textual label displayed below or beside the icon.
  final String label;

  /// Optional badge text (e.g. unread count or status pill).
  final String? badgeText;

  /// Tooltip description for rail or compact display.
  final String? tooltip;

  const AetherNavigationItem({
    required this.icon,
    this.activeIcon,
    required this.label,
    this.badgeText,
    this.tooltip,
  });
}

/// Adaptive navigation component that automatically switches between:
/// - Mobile: Bottom Navigation Bar (height 64px, touch targets >= 48px).
/// - Tablet: Compact Navigation Rail (width 72px).
/// - Desktop: Full Expanded Navigation Sidebar (width 260px).
class AetherAdaptiveNavigation extends StatelessWidget {
  final List<AetherNavigationItem> items;
  final int currentIndex;
  final ValueChanged<int> onIndexChanged;
  final Widget? header;
  final Widget? footer;
  final bool isCollapsed;
  final VoidCallback? onToggleCollapse;

  const AetherAdaptiveNavigation({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onIndexChanged,
    this.header,
    this.footer,
    this.isCollapsed = false,
    this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final bp = context.aetherBreakpoint;
    final colors = context.aetherColors;
    final typography = context.aetherTypography;

    if (bp.isMobile) {
      return Container(
        height: 64.0,
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(items.length, (index) {
            final item = items[index];
            final isSelected = index == currentIndex;
            return InkWell(
              key: ValueKey('nav_item_$index'),
              onTap: () => onIndexChanged(index),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AetherSpacing.md,
                  vertical: AetherSpacing.sm,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          isSelected ? (item.activeIcon ?? item.icon) : item.icon,
                          color: isSelected ? colors.primary : colors.textSecondary,
                          size: 24.0,
                        ),
                        if (item.badgeText != null)
                          Positioned(
                            top: -4,
                            right: -8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AetherSpacing.xs,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: colors.danger.base,
                                borderRadius: AetherRadii.full,
                              ),
                              child: Text(
                                item.badgeText!,
                                style: typography.labelSmall.copyWith(
                                  fontSize: 10,
                                  color: colors.danger.onBase,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AetherSpacing.xxs),
                    Text(
                      item.label,
                      style: typography.labelSmall.copyWith(
                        fontSize: 11.0,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? colors.primary : colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      );
    } else if (bp.isTablet) {
      return Container(
        width: 72.0,
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(right: BorderSide(color: colors.border)),
        ),
        child: Column(
          children: [
            ?header,
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final isSelected = index == currentIndex;
                  return IconButton(
                    key: ValueKey('nav_item_$index'),
                    icon: Icon(
                      isSelected ? (item.activeIcon ?? item.icon) : item.icon,
                      color: isSelected ? colors.primary : colors.textSecondary,
                    ),
                    tooltip: item.tooltip ?? item.label,
                    onPressed: () => onIndexChanged(index),
                  );
                },
              ),
            ),
            ?footer,
          ],
        ),
      );
    } else {
      // Desktop full sidebar
      return Material(
        color: colors.surface,
        child: Container(
          width: 260.0,
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: colors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?header,
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(AetherSpacing.sm),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isSelected = index == currentIndex;
                    return ListTile(
                      key: ValueKey('nav_item_$index'),
                      selected: isSelected,
                      selectedTileColor: colors.primaryContainer,
                      shape: const RoundedRectangleBorder(borderRadius: AetherRadii.sm),
                      leading: Icon(
                        isSelected ? (item.activeIcon ?? item.icon) : item.icon,
                        color: isSelected ? colors.primary : colors.textSecondary,
                      ),
                      title: Text(
                        item.label,
                        style: typography.bodyMedium.copyWith(
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected ? colors.primary : colors.textPrimary,
                        ),
                      ),
                      trailing: item.badgeText != null
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: AetherSpacing.xxs,
                              ),
                              decoration: BoxDecoration(
                                color: colors.danger.base,
                                borderRadius: AetherRadii.full,
                              ),
                              child: Text(
                                item.badgeText!,
                                style: typography.labelSmall.copyWith(
                                  fontSize: 11,
                                  color: colors.danger.onBase,
                                ),
                              ),
                            )
                          : null,
                      onTap: () => onIndexChanged(index),
                    );
                  },
                ),
              ),
              ?footer,
            ],
          ),
        ),
      );
    }
  }
}
