import 'package:flutter/material.dart';

import '../../theme/aether_colors.dart';
import '../../theme/aether_radii.dart';
import '../../theme/aether_spacing.dart';
import '../../utils/extensions.dart';
import '../display/aether_status_badge.dart';

/// Semantic notification banner displayed either inline within a layout or
/// floating as an active toast notification overlay.
class AetherToastBanner extends StatelessWidget {
  /// Message text content.
  final String message;

  /// Optional header title above [message].
  final String? title;

  /// Semantic state determining color quad and default icon. Defaults to [AetherStatusVariant.info].
  final AetherStatusVariant status;

  /// Dismiss callback triggered when close button is tapped.
  final VoidCallback? onDismiss;

  /// Optional custom action button (e.g. 'Retry', 'Undo').
  final Widget? action;

  /// Optional custom leading icon overriding the semantic default.
  final Widget? icon;

  /// Custom outer margin. Defaults to `margin: EdgeInsets.all(8.0)`.
  final EdgeInsetsGeometry? margin;

  const AetherToastBanner({
    super.key,
    required this.message,
    this.title,
    this.status = AetherStatusVariant.info,
    this.onDismiss,
    this.action,
    this.icon,
    this.margin,
  });

  /// Inline variant alias.
  const AetherToastBanner.inline({
    super.key,
    required this.message,
    this.title,
    this.status = AetherStatusVariant.info,
    this.onDismiss,
    this.action,
    this.icon,
    this.margin,
  });

  AetherSemanticColor _resolveQuad(AetherColors colors) {
    switch (status) {
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

  IconData _resolveIcon() {
    switch (status) {
      case AetherStatusVariant.success:
        return Icons.check_circle_outline;
      case AetherStatusVariant.danger:
        return Icons.error_outline;
      case AetherStatusVariant.warning:
        return Icons.warning_amber_outlined;
      case AetherStatusVariant.info:
        return Icons.info_outline;
      case AetherStatusVariant.neutral:
        return Icons.notifications_none;
    }
  }

  /// Displays the toast as a floating banner via [ScaffoldMessenger].
  static void show(
    BuildContext context, {
    required String message,
    String? title,
    AetherStatusVariant status = AetherStatusVariant.info,
    Duration duration = const Duration(seconds: 4),
    VoidCallback? onAction,
    String? actionLabel,
  }) {
    final colors = context.aetherColors;
    final quad = switch (status) {
      AetherStatusVariant.success => colors.success,
      AetherStatusVariant.danger => colors.danger,
      AetherStatusVariant.warning => colors.warning,
      AetherStatusVariant.info => colors.info,
      AetherStatusVariant.neutral => colors.neutral,
    };

    final messenger = ScaffoldMessenger.of(context);
    final typography = context.aetherTypography;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.surface.withAlpha(0),
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: AetherSpacing.lg, vertical: AetherSpacing.md),
        duration: duration,
        content: AetherToastBanner(
          title: title,
          message: message,
          status: status,
          action: (onAction != null && actionLabel != null)
              ? TextButton(
                  onPressed: () {
                    messenger.hideCurrentSnackBar();
                    onAction();
                  },
                  child: Text(
                    actionLabel,
                    style: typography.labelLarge.copyWith(
                      color: quad.onContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : null,
          onDismiss: () => messenger.hideCurrentSnackBar(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;
    final typography = context.aetherTypography;
    final isMobile = context.aetherIsMobile;
    final quad = _resolveQuad(colors);

    return Container(
      margin: margin ?? const EdgeInsets.all(AetherSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: AetherSpacing.lg, vertical: AetherSpacing.md),
      decoration: BoxDecoration(
        color: quad.container,
        borderRadius: AetherRadii.sm,
        border: Border.all(color: quad.base, width: 1.0),
        boxShadow: context.aetherShadows.sm,
      ),
      child: Row(
        crossAxisAlignment:
            title != null ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          icon ?? Icon(_resolveIcon(), color: quad.onContainer, size: 20),
          const SizedBox(width: AetherSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null && title!.isNotEmpty) ...[
                  Text(
                    title!,
                    style: typography.titleSmall.copyWith(
                      color: quad.onContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AetherSpacing.xxs),
                ],
                Text(
                  message,
                  style: typography.bodySmall.copyWith(
                    color: quad.onContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: AetherSpacing.sm),
            action!,
          ],
          if (onDismiss != null) ...[
            const SizedBox(width: AetherSpacing.xs),
            IconButton(
              icon: Icon(Icons.close, color: quad.onContainer, size: 16),
              tooltip: 'Dismiss',
              onPressed: onDismiss,
              splashRadius: isMobile ? 24 : 16,
              padding: isMobile ? const EdgeInsets.all(AetherSpacing.sm) : EdgeInsets.zero,
              constraints: isMobile
                  ? const BoxConstraints(minWidth: 48, minHeight: 48)
                  : const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
          ],
        ],
      ),
    );
  }
}

/// Top-level helper function to show an AetherToastBanner.
void showAetherToast(
  BuildContext context, {
  required String message,
  String? title,
  AetherStatusVariant status = AetherStatusVariant.info,
  Duration duration = const Duration(seconds: 4),
  VoidCallback? onAction,
  String? actionLabel,
}) =>
    AetherToastBanner.show(
      context,
      message: message,
      title: title,
      status: status,
      duration: duration,
      onAction: onAction,
      actionLabel: actionLabel,
    );
