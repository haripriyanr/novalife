import 'package:flutter/material.dart';

import '../../responsive/aether_responsive.dart';
import '../../theme/aether_radii.dart';
import '../../theme/aether_spacing.dart';
import '../../utils/extensions.dart';
import '../display/aether_status_badge.dart';
import 'aether_bottom_sheet.dart';

/// Styled action button within an [AetherAdaptiveDialog].
class AetherDialogAction extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool isDestructive;
  final Widget? icon;

  const AetherDialogAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
    this.isDestructive = false,
    this.icon,
  });

  const factory AetherDialogAction.primary({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    Widget? icon,
  }) = _AetherPrimaryDialogAction;

  const factory AetherDialogAction.destructive({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    Widget? icon,
  }) = _AetherDestructiveDialogAction;

  const factory AetherDialogAction.cancel({
    Key? key,
    String label,
    VoidCallback? onPressed,
  }) = _AetherCancelDialogAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;

    if (isDestructive) {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.danger.base,
          foregroundColor: colors.danger.onBase,
          shape: const RoundedRectangleBorder(borderRadius: AetherRadii.sm),
        ),
        onPressed: onPressed,
        child: Text(label),
      );
    }

    if (isPrimary) {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          shape: const RoundedRectangleBorder(borderRadius: AetherRadii.sm),
        ),
        onPressed: onPressed,
        child: Text(label),
      );
    }

    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: colors.textSecondary,
        shape: const RoundedRectangleBorder(borderRadius: AetherRadii.sm),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

class _AetherPrimaryDialogAction extends AetherDialogAction {
  const _AetherPrimaryDialogAction({
    super.key,
    required super.label,
    required super.onPressed,
    super.icon,
  }) : super(isPrimary: true);
}

class _AetherDestructiveDialogAction extends AetherDialogAction {
  const _AetherDestructiveDialogAction({
    super.key,
    required super.label,
    required super.onPressed,
    super.icon,
  }) : super(isDestructive: true);
}

class _AetherCancelDialogAction extends AetherDialogAction {
  const _AetherCancelDialogAction({
    super.key,
    super.label = 'Cancel',
    super.onPressed,
  });
}

/// Adaptive modal dialog that renders as a centered dialog on desktop/tablet viewports,
/// and automatically converts into a thumb-friendly bottom sheet on mobile viewports.
class AetherAdaptiveDialog extends StatelessWidget {
  /// Dialog title widget.
  final Widget title;

  /// Dialog body content widget.
  final Widget content;

  /// Action buttons at the bottom of the dialog.
  final List<Widget>? actions;

  /// Optional leading icon displayed beside or above the title.
  final Widget? leadingIcon;

  /// Optional semantic state to tint the leading icon or dialog header.
  final AetherStatusVariant? semantic;

  /// Maximum width of the dialog when rendered as a desktop modal. Defaults to 520.0.
  final double maxWidth;

  const AetherAdaptiveDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions,
    this.leadingIcon,
    this.semantic,
    this.maxWidth = 520.0,
  });

  /// Displays the adaptive dialog, automatically selecting between a centered modal
  /// and a modal bottom sheet based on the current screen width.
  static Future<T?> show<T>(
    BuildContext context, {
    required Widget title,
    required Widget content,
    List<Widget>? actions,
    Widget? leadingIcon,
    AetherStatusVariant? semantic,
    bool barrierDismissible = true,
    double maxWidth = 520.0,
    Color? barrierColor,
  }) {
    final bp = AetherResponsive.of(context);
    final colors = context.aetherColors;

    if (bp.isMobile) {
      return showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        backgroundColor: colors.surface.withAlpha(0),
        builder: (ctx) => AetherBottomSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leadingIcon != null) ...[
                leadingIcon,
                const SizedBox(height: AetherSpacing.md),
              ],
              DefaultTextStyle(
                style: ctx.aetherTypography.titleLarge,
                child: title,
              ),
              const SizedBox(height: AetherSpacing.md),
              DefaultTextStyle(
                style: ctx.aetherTypography.bodyMedium,
                child: content,
              ),
              if (actions != null && actions.isNotEmpty) ...[
                const SizedBox(height: AetherSpacing.xl),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AetherSpacing.sm,
                  runSpacing: AetherSpacing.xs,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor ?? colors.scrim.withAlpha(160),
      builder: (ctx) => AetherAdaptiveDialog(
        title: title,
        content: content,
        actions: actions,
        leadingIcon: leadingIcon,
        semantic: semantic,
        maxWidth: maxWidth,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;
    final typography = context.aetherTypography;

    return Dialog(
      backgroundColor: colors.surfaceElevated,
      shape: const RoundedRectangleBorder(borderRadius: AetherRadii.lg),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(AetherSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leadingIcon != null) ...[
                leadingIcon!,
                const SizedBox(height: AetherSpacing.md),
              ],
              DefaultTextStyle(
                style: typography.titleLarge.copyWith(
                  color: colors.textPrimary,
                ),
                child: title,
              ),
              const SizedBox(height: AetherSpacing.lg),
              DefaultTextStyle(
                style: typography.bodyMedium.copyWith(
                  color: colors.textSecondary,
                ),
                child: content,
              ),
              if (actions != null && actions!.isNotEmpty) ...[
                const SizedBox(height: AetherSpacing.xxl),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AetherSpacing.sm,
                  runSpacing: AetherSpacing.xs,
                  children: actions!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Top-level helper function to show an adaptive dialog.
Future<T?> showAetherDialog<T>(
  BuildContext context, {
  required Widget title,
  required Widget content,
  List<Widget>? actions,
  Widget? leadingIcon,
  AetherStatusVariant? semantic,
  bool barrierDismissible = true,
  double maxWidth = 520.0,
}) =>
    AetherAdaptiveDialog.show<T>(
      context,
      title: title,
      content: content,
      actions: actions,
      leadingIcon: leadingIcon,
      semantic: semantic,
      barrierDismissible: barrierDismissible,
      maxWidth: maxWidth,
    );
