import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/aether_spacing.dart';
import '../../utils/extensions.dart';

/// Responsive master-detail dual-pane layout.
/// Collapses to single-pane drilldown on mobile and side-by-side split on tablet/desktop.
class AetherSplitView extends StatelessWidget {
  final Widget master;
  final Widget? detail;
  final double? masterWidth;
  final double? masterRatio;
  final bool showDetailOnMobile;
  final VoidCallback? onBackToMaster;
  final Widget? emptyDetailPlaceholder;
  final bool showDivider;

  const AetherSplitView({
    super.key,
    required this.master,
    this.detail,
    this.masterWidth,
    this.masterRatio,
    this.showDetailOnMobile = false,
    this.onBackToMaster,
    this.emptyDetailPlaceholder,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final bp = context.aetherBreakpoint;
    final colors = context.aetherColors;
    final typography = context.aetherTypography;

    final effectiveDetail = detail ?? emptyDetailPlaceholder ?? const SizedBox.shrink();

    if (bp.isMobile) {
      if (showDetailOnMobile) {
        return Column(
          children: [
            if (onBackToMaster != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AetherSpacing.sm,
                  vertical: AetherSpacing.xs,
                ),
                color: colors.surface,
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('split_view_back_btn'),
                      icon: const Icon(Icons.arrow_back),
                      color: colors.textPrimary,
                      onPressed: onBackToMaster,
                    ),
                    Text(
                      'Back to List',
                      style: typography.bodyMedium.copyWith(color: colors.textPrimary),
                    ),
                  ],
                ),
              ),
            Expanded(child: effectiveDetail),
          ],
        );
      }
      return master;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxMaster = math.max(200.0, constraints.maxWidth - 200.0);
        final effectiveMasterWidth = masterWidth ??
            (constraints.maxWidth * (masterRatio ?? 0.35)).clamp(200.0, maxMaster);

        return Row(
          children: [
            SizedBox(
              width: effectiveMasterWidth,
              child: master,
            ),
            if (showDivider)
              VerticalDivider(width: 1, thickness: 1, color: colors.border),
            Expanded(child: effectiveDetail),
          ],
        );
      },
    );
  }
}
