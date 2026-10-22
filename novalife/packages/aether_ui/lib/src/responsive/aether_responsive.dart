import 'package:flutter/widgets.dart';

import '../theme/aether_spacing.dart';
import 'aether_breakpoint.dart';

/// Static utility functions for responsive layout evaluation, value selection,
/// and adaptive grid/gutter dimensions.
abstract final class AetherResponsive {
  /// Evaluates the current [AetherBreakpoint] from the [BuildContext]'s [MediaQueryData.size].
  static AetherBreakpoint of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return breakpointForWidth(width);
  }

  /// Maps a specific logical pixel [width] to its corresponding [AetherBreakpoint].
  static AetherBreakpoint breakpointForWidth(double width) {
    if (width <= kMobileMaxWidth) {
      return AetherBreakpoint.mobile;
    } else if (width <= kTabletMaxWidth) {
      return AetherBreakpoint.tablet;
    } else {
      return AetherBreakpoint.desktop;
    }
  }

  /// Selects a responsive value based on the current breakpoint in [context].
  ///
  /// - If [mobile], returns [mobile].
  /// - If [tablet], returns [tablet] (or [mobile] if [tablet] is null).
  /// - If [desktop], returns [desktop] (or [tablet] if non-null, else [mobile]).
  static T value<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    final bp = of(context);
    return valueForBreakpoint<T>(
      bp,
      mobile: mobile,
      tablet: tablet,
      desktop: desktop,
    );
  }

  /// Selects a responsive value directly from an [AetherBreakpoint] instance.
  static T valueForBreakpoint<T>(
    AetherBreakpoint breakpoint, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    switch (breakpoint) {
      case AetherBreakpoint.mobile:
        return mobile;
      case AetherBreakpoint.tablet:
        return tablet ?? mobile;
      case AetherBreakpoint.desktop:
        return desktop ?? tablet ?? mobile;
    }
  }

  /// Selects a responsive value based on a specific pixel [width].
  static T valueForWidth<T>(
    double width, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    final bp = breakpointForWidth(width);
    return valueForBreakpoint<T>(
      bp,
      mobile: mobile,
      tablet: tablet,
      desktop: desktop,
    );
  }

  /// Returns true if [context] currently resolves to [AetherBreakpoint.mobile].
  static bool isMobile(BuildContext context) => of(context).isMobile;

  /// Returns true if [context] currently resolves to [AetherBreakpoint.tablet].
  static bool isTablet(BuildContext context) => of(context).isTablet;

  /// Returns true if [context] currently resolves to [AetherBreakpoint.desktop].
  static bool isDesktop(BuildContext context) => of(context).isDesktop;

  /// Returns true if [context] resolves to either tablet or desktop.
  static bool isTabletOrDesktop(BuildContext context) =>
      of(context).isTabletOrDesktop;

  /// Returns recommended column count for a responsive grid:
  /// - Mobile: 1 column
  /// - Tablet: 2 columns
  /// - Desktop: 3 columns
  static int gridColumns(BuildContext context) {
    return value<int>(context, mobile: 1, tablet: 2, desktop: 3);
  }

  /// Returns recommended column count for a specific pixel [width].
  static int gridColumnsForWidth(double width) {
    return valueForWidth<int>(width, mobile: 1, tablet: 2, desktop: 3);
  }

  /// Returns recommended horizontal page gutter:
  /// - Mobile: [AetherSpacing.md] (12.0)
  /// - Tablet: [AetherSpacing.xl] (24.0)
  /// - Desktop: [AetherSpacing.xxl] (32.0)
  static double horizontalGutter(BuildContext context) {
    return value<double>(
      context,
      mobile: AetherSpacing.md,
      tablet: AetherSpacing.xl,
      desktop: AetherSpacing.xxl,
    );
  }
}
