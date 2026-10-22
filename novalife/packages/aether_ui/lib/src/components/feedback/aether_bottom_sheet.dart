import 'package:flutter/material.dart';

import '../../theme/aether_radii.dart';
import '../../theme/aether_spacing.dart';
import '../../utils/extensions.dart';

/// Draggable modal bottom sheet container with rounded top corners, top drag handle,
/// header title, and maximum height constraints.
class AetherBottomSheet extends StatelessWidget {
  /// Optional title header for the bottom sheet.
  final String? title;

  /// Main content widget inside the sheet.
  final Widget child;

  /// Optional trailing header action button.
  final Widget? action;

  /// Whether to render the 36x4 drag handle pill at the top. Defaults to true.
  final bool showDragHandle;

  /// Maximum height fraction of the screen height. Defaults to 0.85.
  final double maxHeightFraction;

  /// Padding around the content. Defaults to [AetherSpacing.lg].
  final EdgeInsetsGeometry? padding;

  const AetherBottomSheet({
    super.key,
    this.title,
    required this.child,
    this.action,
    this.showDragHandle = true,
    this.maxHeightFraction = 0.85,
    this.padding,
  });

  /// Displays the bottom sheet via [showModalBottomSheet].
  static Future<T?> show<T>(
    BuildContext context, {
    required Widget child,
    String? title,
    Widget? action,
    bool isDismissible = true,
    bool enableDrag = true,
    double maxHeightFraction = 0.85,
    bool isScrollControlled = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      isScrollControlled: isScrollControlled,
      backgroundColor: context.aetherColors.surface.withAlpha(0),
      builder: (ctx) => AetherBottomSheet(
        title: title,
        action: action,
        maxHeightFraction: maxHeightFraction,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;
    final typography = context.aetherTypography;
    final maxHeight = MediaQuery.sizeOf(context).height * maxHeightFraction;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: const BorderRadius.vertical(top: AetherRadii.radiusLg),
        boxShadow: context.aetherShadows.lg,
      ),
      padding: padding ?? const EdgeInsets.all(AetherSpacing.lg),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Drag Handle
            if (showDragHandle)
              Center(
                child: Container(
                  width: 36.0,
                  height: 4.0,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: AetherRadii.full,
                  ),
                ),
              ),

            // Header Title & Action
            if (title != null) ...[
              const SizedBox(height: AetherSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: typography.titleMedium.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ?action,
                ],
              ),
            ],

            const SizedBox(height: AetherSpacing.lg),

            // Child Content
            Flexible(
              child: SingleChildScrollView(
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Top-level helper function to show an AetherBottomSheet.
Future<T?> showAetherBottomSheet<T>(
  BuildContext context, {
  required Widget child,
  String? title,
  Widget? action,
  bool isDismissible = true,
  bool enableDrag = true,
  double maxHeightFraction = 0.85,
}) =>
    AetherBottomSheet.show<T>(
      context,
      child: child,
      title: title,
      action: action,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      maxHeightFraction: maxHeightFraction,
    );
