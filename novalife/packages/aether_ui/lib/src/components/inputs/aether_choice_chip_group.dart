import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/aether_spacing.dart';
import '../../utils/extensions.dart';

/// Choice chip descriptor item.
class AetherChoiceChipItem<T> {
  final T value;
  final String label;
  final Widget? icon;
  final String? count;

  const AetherChoiceChipItem({
    required this.value,
    required this.label,
    this.icon,
    this.count,
  });
}

/// Backward-compatible alias for [AetherChoiceChipItem].
typedef AetherChoiceOption<T> = AetherChoiceChipItem<T>;

/// Responsive single or multi-selection chip group supporting wrap and horizontal scroll.
class AetherChoiceChipGroup<T> extends StatelessWidget {
  final List<AetherChoiceChipItem<T>> items;
  final T? selectedValue;
  final List<T>? selectedValues;
  final bool isMultiSelect;
  final ValueChanged<T>? onSelected;
  final ValueChanged<List<T>>? onMultiSelected;
  final WrapAlignment alignment;
  final double spacing;
  final double runSpacing;
  final bool isScrollable;

  const AetherChoiceChipGroup({
    super.key,
    required this.items,
    this.selectedValue,
    this.selectedValues,
    this.isMultiSelect = false,
    this.onSelected,
    this.onMultiSelected,
    this.alignment = WrapAlignment.start,
    this.spacing = AetherSpacing.sm,
    this.runSpacing = AetherSpacing.sm,
    this.isScrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;
    final typography = context.aetherTypography;

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    final chips = items.map((item) {
      final isSelected = isMultiSelect
          ? (selectedValues?.contains(item.value) ?? false)
          : item.value == selectedValue;

      return ChoiceChip(
        key: ValueKey('chip_${item.value}'),
        avatar: item.icon,
        label: Text(item.label),
        selected: isSelected,
        selectedColor: colors.primaryContainer,
        backgroundColor: colors.surface,
        side: BorderSide(color: isSelected ? colors.primary : colors.border),
        labelStyle: typography.labelMedium.copyWith(
          color: isSelected ? colors.primary : colors.textSecondary,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        ),
        onSelected: (_) {
          if (isMultiSelect) {
            final current = List<T>.from(selectedValues ?? []);
            if (current.contains(item.value)) {
              current.remove(item.value);
            } else {
              current.add(item.value);
            }
            onMultiSelected?.call(current);
          } else {
            onSelected?.call(item.value);
          }
        },
      );
    }).toList();

    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }

    if (isScrollable) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: chips
              .expand((chip) => [chip, SizedBox(width: spacing)])
              .take(math.max(0, chips.length * 2 - 1))
              .toList(),
        ),
      );
    }

    return Wrap(
      alignment: alignment,
      spacing: spacing,
      runSpacing: runSpacing,
      children: chips,
    );
  }
}
