import 'package:flutter/material.dart';

import '../../utils/extensions.dart';

/// Clean toggle switch tile with title, subtitle, leading icon, and disabled state.
class AetherSwitchTile extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool enabled;
  final EdgeInsetsGeometry? contentPadding;

  const AetherSwitchTile({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
    this.leading,
    this.enabled = true,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;
    final typography = context.aetherTypography;

    return SwitchListTile(
      value: value,
      onChanged: enabled ? onChanged : null,
      contentPadding: contentPadding,
      activeThumbColor: colors.primary,
      activeTrackColor: colors.primaryContainer,
      inactiveThumbColor: colors.surface,
      inactiveTrackColor: colors.border,
      title: Text(
        title,
        style: typography.titleSmall.copyWith(
          color: enabled ? colors.textPrimary : colors.textDisabled,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: typography.bodySmall.copyWith(
                color: enabled ? colors.textSecondary : colors.textDisabled,
              ),
            )
          : null,
      secondary: leading,
    );
  }
}
