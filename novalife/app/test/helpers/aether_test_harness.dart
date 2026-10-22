// Aether UI Opaque-Box Test Harness & Contract Definitions
//
// This file provides pure Flutter SDK implementations of the Aether UI
// design system contracts per PROJECT.md and ORIGINAL_REQUEST.md.
// It enables the E2E test suite to execute opaque-box interface and
// behavioral verifications across all 4 tiers without external UI dependencies.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';

// ============================================================================
// 1. RESPONSIVE BREAKPOINTS & FRAMEWORK
// ============================================================================

enum AetherBreakpoint {
  mobile,
  tablet,
  desktop;

  bool get isMobile => this == AetherBreakpoint.mobile;
  bool get isTablet => this == AetherBreakpoint.tablet;
  bool get isDesktop => this == AetherBreakpoint.desktop;
  bool get isTabletOrDesktop => isTablet || isDesktop;
}

class AetherBreakpoints {
  static const double kMobileMaxWidth = 600.0;
  static const double kTabletMaxWidth = 1024.0;
  static const double kDesktopMaxWidth = 1920.0;
  static const double kMaxContentWidth = 1440.0;
}

class AetherResponsive {
  static AetherBreakpoint of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width <= AetherBreakpoints.kMobileMaxWidth) {
      return AetherBreakpoint.mobile;
    }
    if (width <= AetherBreakpoints.kTabletMaxWidth) {
      return AetherBreakpoint.tablet;
    }
    return AetherBreakpoint.desktop;
  }

  static T value<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    final bp = of(context);
    switch (bp) {
      case AetherBreakpoint.mobile:
        return mobile;
      case AetherBreakpoint.tablet:
        return tablet ?? mobile;
      case AetherBreakpoint.desktop:
        return desktop ?? tablet ?? mobile;
    }
  }

  static int gridColumns(BuildContext context) {
    return value<int>(context, mobile: 1, tablet: 2, desktop: 3);
  }

  static double horizontalGutter(BuildContext context) {
    return value<double>(
      context,
      mobile: AetherSpacing.md,
      tablet: AetherSpacing.xl,
      desktop: AetherSpacing.xxl,
    );
  }
}

typedef AetherResponsiveWidgetBuilder = Widget Function(
  BuildContext context,
  AetherBreakpoint breakpoint,
  BoxConstraints constraints,
);

class AetherResponsiveBuilder extends StatelessWidget {
  final AetherResponsiveWidgetBuilder builder;

  const AetherResponsiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final bp = width <= AetherBreakpoints.kMobileMaxWidth
            ? AetherBreakpoint.mobile
            : (width <= AetherBreakpoints.kTabletMaxWidth
                ? AetherBreakpoint.tablet
                : AetherBreakpoint.desktop);
        return builder(context, bp, constraints);
      },
    );
  }
}

// ============================================================================
// 2. DESIGN TOKENS (COLORS, TYPOGRAPHY, SPACING, RADII, SHADOWS)
// ============================================================================

class AetherSpacing {
  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double xxxl = 48.0;
}

class AetherRadii {
  static const BorderRadius none = BorderRadius.zero;
  static const BorderRadius xs = BorderRadius.all(Radius.circular(4.0));
  static const BorderRadius sm = BorderRadius.all(Radius.circular(8.0));
  static const BorderRadius md = BorderRadius.all(Radius.circular(12.0));
  static const BorderRadius lg = BorderRadius.all(Radius.circular(16.0));
  static const BorderRadius xl = BorderRadius.all(Radius.circular(24.0));
  static const BorderRadius full = BorderRadius.all(Radius.circular(999.0));
}

class AetherShadows {
  static const List<BoxShadow> none = [];
  static const List<BoxShadow> sm = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> md = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 4)),
  ];
  static const List<BoxShadow> lg = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 20, offset: Offset(0, 8)),
  ];
}

class AetherSemanticColor {
  final Color base;
  final Color container;
  final Color onBase;
  final Color onContainer;

  const AetherSemanticColor({
    required this.base,
    required this.container,
    required this.onBase,
    required this.onContainer,
  });
}

class AetherColors {
  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceSubtle;
  final Color primary;
  final Color primaryHover;
  final Color primaryContainer;
  final Color onPrimary;
  final Color onPrimaryContainer;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color border;
  final Color borderSubtle;

  final AetherSemanticColor success;
  final AetherSemanticColor danger;
  final AetherSemanticColor warning;
  final AetherSemanticColor info;
  final AetherSemanticColor neutral;

  const AetherColors({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceSubtle,
    required this.primary,
    required this.primaryHover,
    required this.primaryContainer,
    required this.onPrimary,
    required this.onPrimaryContainer,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.borderSubtle,
    required this.success,
    required this.danger,
    required this.warning,
    required this.info,
    required this.neutral,
  });

  factory AetherColors.light() {
    return const AetherColors(
      background: Color(0xFFF8FAFC),
      surface: Color(0xFFFFFFFF),
      surfaceElevated: Color(0xFFFFFFFF),
      surfaceSubtle: Color(0xFFF1F5F9),
      primary: Color(0xFF2563EB),
      primaryHover: Color(0xFF1D4ED8),
      primaryContainer: Color(0xFFEFF6FF),
      onPrimary: Color(0xFFFFFFFF),
      onPrimaryContainer: Color(0xFF1E40AF),
      textPrimary: Color(0xFF0F172A),
      textSecondary: Color(0xFF475569),
      textMuted: Color(0xFF94A3B8),
      border: Color(0xFFE2E8F0),
      borderSubtle: Color(0xFFF1F5F9),
      success: AetherSemanticColor(
        base: Color(0xFF16A34A),
        container: Color(0xFFDCFCE7),
        onBase: Color(0xFFFFFFFF),
        onContainer: Color(0xFF14532D),
      ),
      danger: AetherSemanticColor(
        base: Color(0xFFDC2626),
        container: Color(0xFFFEE2E2),
        onBase: Color(0xFFFFFFFF),
        onContainer: Color(0xFF7F1D1D),
      ),
      warning: AetherSemanticColor(
        base: Color(0xFFD97706),
        container: Color(0xFFFEF3C7),
        onBase: Color(0xFFFFFFFF),
        onContainer: Color(0xFF78350F),
      ),
      info: AetherSemanticColor(
        base: Color(0xFF0284C7),
        container: Color(0xFFE0F2FE),
        onBase: Color(0xFFFFFFFF),
        onContainer: Color(0xFF0C4A6E),
      ),
      neutral: AetherSemanticColor(
        base: Color(0xFF64748B),
        container: Color(0xFFF1F5F9),
        onBase: Color(0xFFFFFFFF),
        onContainer: Color(0xFF1E293B),
      ),
    );
  }

  factory AetherColors.dark() {
    return const AetherColors(
      background: Color(0xFF0F172A),
      surface: Color(0xFF1E293B),
      surfaceElevated: Color(0xFF334155),
      surfaceSubtle: Color(0xFF182234),
      primary: Color(0xFF3B82F6),
      primaryHover: Color(0xFF60A5FA),
      primaryContainer: Color(0xFF1E3A8A),
      onPrimary: Color(0xFFFFFFFF),
      onPrimaryContainer: Color(0xFFDBEAFE),
      textPrimary: Color(0xFFF8FAFC),
      textSecondary: Color(0xFF94A3B8),
      textMuted: Color(0xFF64748B),
      border: Color(0xFF334155),
      borderSubtle: Color(0xFF1E293B),
      success: AetherSemanticColor(
        base: Color(0xFF22C55E),
        container: Color(0xFF052E16),
        onBase: Color(0xFF052E16),
        onContainer: Color(0xFF86EFAC),
      ),
      danger: AetherSemanticColor(
        base: Color(0xFFEF4444),
        container: Color(0xFF450A0A),
        onBase: Color(0xFFFFFFFF),
        onContainer: Color(0xFFFCA5A5),
      ),
      warning: AetherSemanticColor(
        base: Color(0xFFF59E0B),
        container: Color(0xFF451A03),
        onBase: Color(0xFF451A03),
        onContainer: Color(0xFFFDE68A),
      ),
      info: AetherSemanticColor(
        base: Color(0xFF38BDF8),
        container: Color(0xFF082F49),
        onBase: Color(0xFF082F49),
        onContainer: Color(0xFFBAE6FD),
      ),
      neutral: AetherSemanticColor(
        base: Color(0xFF94A3B8),
        container: Color(0xFF1E293B),
        onBase: Color(0xFF0F172A),
        onContainer: Color(0xFFE2E8F0),
      ),
    );
  }
}

class AetherTypography {
  final TextStyle displayLarge;
  final TextStyle displayMedium;
  final TextStyle titleLarge;
  final TextStyle titleMedium;
  final TextStyle titleSmall;
  final TextStyle bodyLarge;
  final TextStyle bodyMedium;
  final TextStyle bodySmall;
  final TextStyle labelLarge;
  final TextStyle labelMedium;
  final TextStyle labelSmall;
  final TextStyle code;

  const AetherTypography({
    required this.displayLarge,
    required this.displayMedium,
    required this.titleLarge,
    required this.titleMedium,
    required this.titleSmall,
    required this.bodyLarge,
    required this.bodyMedium,
    required this.bodySmall,
    required this.labelLarge,
    required this.labelMedium,
    required this.labelSmall,
    required this.code,
  });

  factory AetherTypography.fromColors(AetherColors colors) {
    return AetherTypography(
      displayLarge: TextStyle(
        fontSize: 32.0,
        fontWeight: FontWeight.w700,
        height: 1.25,
        color: colors.textPrimary,
      ),
      displayMedium: TextStyle(
        fontSize: 26.0,
        fontWeight: FontWeight.w700,
        height: 1.30,
        color: colors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: 20.0,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: colors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 17.0,
        fontWeight: FontWeight.w600,
        height: 1.40,
        color: colors.textPrimary,
      ),
      titleSmall: TextStyle(
        fontSize: 15.0,
        fontWeight: FontWeight.w600,
        height: 1.40,
        color: colors.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: 16.0,
        fontWeight: FontWeight.w400,
        height: 1.50,
        color: colors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14.0,
        fontWeight: FontWeight.w400,
        height: 1.50,
        color: colors.textSecondary,
      ),
      bodySmall: TextStyle(
        fontSize: 12.0,
        fontWeight: FontWeight.w400,
        height: 1.40,
        color: colors.textMuted,
      ),
      labelLarge: TextStyle(
        fontSize: 14.0,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: colors.textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: 12.0,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
        color: colors.textSecondary,
      ),
      labelSmall: TextStyle(
        fontSize: 10.0,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        color: colors.textMuted,
      ),
      code: TextStyle(
        fontSize: 13.0,
        fontWeight: FontWeight.w500,
        fontFamily: 'monospace',
        color: colors.textPrimary,
      ),
    );
  }
}

class AetherThemeData {
  final Brightness brightness;
  final AetherColors colors;
  final AetherTypography typography;

  bool get isDark => brightness == Brightness.dark;
  bool get isLight => brightness == Brightness.light;

  const AetherThemeData({
    required this.brightness,
    required this.colors,
    required this.typography,
  });

  factory AetherThemeData.light() {
    final colors = AetherColors.light();
    return AetherThemeData(
      brightness: Brightness.light,
      colors: colors,
      typography: AetherTypography.fromColors(colors),
    );
  }

  factory AetherThemeData.dark() {
    final colors = AetherColors.dark();
    return AetherThemeData(
      brightness: Brightness.dark,
      colors: colors,
      typography: AetherTypography.fromColors(colors),
    );
  }
}

class AetherTheme extends InheritedWidget {
  final AetherThemeData data;

  const AetherTheme({
    super.key,
    required this.data,
    required super.child,
  });

  static AetherThemeData of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<AetherTheme>();
    if (theme != null) return theme.data;
    // Fallback: safe graceful degradation based on system brightness
    final platformBrightness = Theme.of(context).brightness;
    return platformBrightness == Brightness.dark
        ? AetherThemeData.dark()
        : AetherThemeData.light();
  }

  @override
  bool updateShouldNotify(AetherTheme oldWidget) => data != oldWidget.data;
}

extension AetherContextExtension on BuildContext {
  AetherThemeData get aetherTheme => AetherTheme.of(this);
  AetherColors get aetherColors => aetherTheme.colors;
  AetherTypography get aetherTypography => aetherTheme.typography;
}

// ============================================================================
// 3. WCAG AA CONTRAST EVALUATOR
// ============================================================================

class ContrastChecker {
  static double relativeLuminance(Color color) {
    double transform(double val) {
      return (val <= 0.04045)
          ? val / 12.92
          : math.pow((val + 0.055) / 1.055, 2.4).toDouble();
    }

    final r = transform(color.r);
    final g = transform(color.g);
    final b = transform(color.b);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  static double contrastRatio(Color foreground, Color background) {
    final l1 = relativeLuminance(foreground);
    final l2 = relativeLuminance(background);
    final lighter = math.max(l1, l2);
    final darker = math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  static bool isWcagAaNormalText(Color fg, Color bg) =>
      contrastRatio(fg, bg) >= 4.5;

  static bool isWcagAaLargeTextOrUi(Color fg, Color bg) =>
      contrastRatio(fg, bg) >= 3.0;
}

// ============================================================================
// 4. COMPONENTS: LAYOUT & STRUCTURE
// ============================================================================

class AetherNavigationItem {
  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final String? badgeText;
  final String? tooltip;

  const AetherNavigationItem({
    required this.icon,
    this.activeIcon,
    required this.label,
    this.badgeText,
    this.tooltip,
  });
}

class AetherAdaptiveNavigation extends StatelessWidget {
  final List<AetherNavigationItem> items;
  final int currentIndex;
  final ValueChanged<int> onIndexChanged;
  final Widget? header;
  final Widget? footer;

  const AetherAdaptiveNavigation({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onIndexChanged,
    this.header,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final bp = AetherResponsive.of(context);
    final colors = context.aetherColors;

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
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
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
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: colors.danger.base,
                                borderRadius: AetherRadii.full,
                              ),
                              child: Text(
                                item.badgeText!,
                                style: const TextStyle(fontSize: 10, color: Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      item.label,
                      style: TextStyle(
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
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
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
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected ? colors.primary : colors.textPrimary,
                      ),
                    ),
                    trailing: item.badgeText != null
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: colors.danger.base,
                              borderRadius: AetherRadii.full,
                            ),
                            child: Text(
                              item.badgeText!,
                              style: const TextStyle(fontSize: 11, color: Colors.white),
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

class AetherResponsiveScaffold extends StatelessWidget {
  final Widget body;
  final PreferredSizeWidget? header;
  final List<AetherNavigationItem>? navigationItems;
  final int currentIndex;
  final ValueChanged<int>? onNavigationChanged;
  final Widget? floatingActionButton;
  final Widget? sidePanel;
  final bool showNavigation;
  final Color? backgroundColor;

  const AetherResponsiveScaffold({
    super.key,
    required this.body,
    this.header,
    this.navigationItems,
    this.currentIndex = 0,
    this.onNavigationChanged,
    this.floatingActionButton,
    this.sidePanel,
    this.showNavigation = true,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final bp = AetherResponsive.of(context);
    final colors = context.aetherColors;

    final navWidget = (showNavigation && navigationItems != null && onNavigationChanged != null)
        ? AetherAdaptiveNavigation(
            items: navigationItems!,
            currentIndex: currentIndex,
            onIndexChanged: onNavigationChanged!,
          )
        : null;

    if (bp.isMobile) {
      return Scaffold(
        backgroundColor: backgroundColor ?? colors.background,
        appBar: header,
        body: SafeArea(child: body),
        bottomNavigationBar: navWidget,
        floatingActionButton: floatingActionButton,
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor ?? colors.background,
      appBar: header,
      floatingActionButton: floatingActionButton,
      body: Row(
        children: [
          ?navWidget,
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: AetherBreakpoints.kMaxContentWidth),
                child: body,
              ),
            ),
          ),
          if (sidePanel != null && bp.isDesktop)
            SizedBox(
              width: 320.0,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: colors.border)),
                ),
                child: sidePanel!,
              ),
            ),
        ],
      ),
    );
  }
}

class AetherHeaderBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? title;
  final String? titleText;
  final Widget? subtitle;
  final String? subtitleText;
  final Widget? leading;
  final List<Widget>? actions;
  final Widget? searchSlot;
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
    this.actions,
    this.searchSlot,
    this.hasBorder = true,
    this.height = 64.0,
    this.backgroundColor,
  });

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;
    final typography = context.aetherTypography;

    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.surface,
        border: hasBorder ? Border(bottom: BorderSide(color: colors.border)) : null,
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8.0)],
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
            const SizedBox(width: 8.0),
          ],
          ...?actions,
        ],
      ),
    );
  }
}

class AetherSectionCard extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? leadingIcon;
  final Widget? headerAction;
  final Widget child;
  final Widget? footer;
  final EdgeInsetsGeometry? padding;
  final bool isElevated;
  final VoidCallback? onTap;

  const AetherSectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.leadingIcon,
    this.headerAction,
    required this.child,
    this.footer,
    this.padding,
    this.isElevated = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;
    final typography = context.aetherTypography;

    return Container(
      decoration: BoxDecoration(
        color: isElevated ? colors.surfaceElevated : colors.surface,
        borderRadius: AetherRadii.md,
        border: isElevated ? null : Border.all(color: colors.border),
        boxShadow: isElevated ? AetherShadows.md : AetherShadows.none,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AetherRadii.md,
          onTap: onTap,
          child: Padding(
            padding: padding ?? const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null || headerAction != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(
                      children: [
                        if (leadingIcon != null) ...[leadingIcon!, const SizedBox(width: 8.0)],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title ?? '', style: typography.titleSmall),
                              if (subtitle != null) Text(subtitle!, style: typography.bodySmall),
                            ],
                          ),
                        ),
                        ?headerAction,
                      ],
                    ),
                  ),
                child,
                if (footer != null) ...[
                  const SizedBox(height: 12.0),
                  const Divider(height: 1),
                  const SizedBox(height: 8.0),
                  footer!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AetherSplitView extends StatelessWidget {
  final Widget master;
  final Widget detail;
  final double masterWidth;
  final bool showDetailOnMobile;
  final VoidCallback? onBackToMaster;

  const AetherSplitView({
    super.key,
    required this.master,
    required this.detail,
    this.masterWidth = 380.0,
    this.showDetailOnMobile = false,
    this.onBackToMaster,
  });

  @override
  Widget build(BuildContext context) {
    final bp = AetherResponsive.of(context);
    final colors = context.aetherColors;

    if (bp.isMobile) {
      if (showDetailOnMobile) {
        return Column(
          children: [
            if (onBackToMaster != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                color: colors.surface,
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('split_view_back_btn'),
                      icon: const Icon(Icons.arrow_back),
                      onPressed: onBackToMaster,
                    ),
                    const Text('Back to List'),
                  ],
                ),
              ),
            Expanded(child: detail),
          ],
        );
      }
      return master;
    }

    return Row(
      children: [
        SizedBox(
          width: masterWidth,
          child: master,
        ),
        VerticalDivider(width: 1, thickness: 1, color: colors.border),
        Expanded(child: detail),
      ],
    );
  }
}

// ============================================================================
// 5. COMPONENTS: INPUTS & CONTROLS
// ============================================================================

class AetherTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hintText;
  final String? errorText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool isPassword;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  const AetherTextField({
    super.key,
    this.controller,
    this.label,
    this.hintText,
    this.errorText,
    this.prefixIcon,
    this.suffixIcon,
    this.isPassword = false,
    this.enabled = true,
    this.onChanged,
  });

  @override
  State<AetherTextField> createState() => _AetherTextFieldState();
}

class _AetherTextFieldState extends State<AetherTextField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;
    final typography = context.aetherTypography;

    Widget? effectiveSuffix = widget.suffixIcon;
    if (widget.isPassword) {
      effectiveSuffix = IconButton(
        key: const Key('aether_password_visibility_btn'),
        icon: Icon(_obscured ? Icons.visibility_off : Icons.visibility),
        onPressed: () => setState(() => _obscured = !_obscured),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Text(
              widget.label!,
              style: typography.labelMedium.copyWith(color: colors.textPrimary),
            ),
          ),
        TextField(
          controller: widget.controller,
          enabled: widget.enabled,
          obscureText: widget.isPassword ? _obscured : false,
          onChanged: widget.onChanged,
          decoration: InputDecoration(
            hintText: widget.hintText,
            errorText: widget.errorText,
            prefixIcon: widget.prefixIcon,
            suffixIcon: effectiveSuffix,
            filled: true,
            fillColor: widget.enabled ? colors.surface : colors.surfaceSubtle,
            enabledBorder: OutlineInputBorder(
              borderRadius: AetherRadii.sm,
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AetherRadii.sm,
              borderSide: BorderSide(color: colors.primary, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: AetherRadii.sm,
              borderSide: BorderSide(color: colors.danger.base),
            ),
          ),
        ),
      ],
    );
  }
}

class AetherSearchInput extends StatefulWidget {
  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final VoidCallback? onFilterTap;
  final Duration debounceDuration;

  const AetherSearchInput({
    super.key,
    this.controller,
    this.hintText = 'Search…',
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.onFilterTap,
    this.debounceDuration = const Duration(milliseconds: 300),
  });

  @override
  State<AetherSearchInput> createState() => _AetherSearchInputState();
}

class _AetherSearchInputState extends State<AetherSearchInput> {
  late final TextEditingController _ctrl;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller ?? TextEditingController();
  }

  void _onTextChange(String text) {
    _timer?.cancel();
    _timer = Timer(widget.debounceDuration, () {
      widget.onChanged?.call(text);
    });
    setState(() {});
  }

  void _clear() {
    _ctrl.clear();
    widget.onClear?.call();
    widget.onChanged?.call('');
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (widget.controller == null) _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;

    return TextField(
      controller: _ctrl,
      onChanged: _onTextChange,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_ctrl.text.isNotEmpty)
              IconButton(
                key: const Key('aether_search_clear_btn'),
                icon: const Icon(Icons.clear, size: 18),
                onPressed: _clear,
              ),
            if (widget.onFilterTap != null)
              IconButton(
                key: const Key('aether_search_filter_btn'),
                icon: const Icon(Icons.filter_list, size: 18),
                onPressed: widget.onFilterTap,
              ),
          ],
        ),
        filled: true,
        fillColor: colors.surface,
        border: const OutlineInputBorder(borderRadius: AetherRadii.sm),
      ),
    );
  }
}

class AetherChoiceChipItem<T> {
  final T value;
  final String label;
  final Widget? icon;

  const AetherChoiceChipItem({
    required this.value,
    required this.label,
    this.icon,
  });
}

class AetherChoiceChipGroup<T> extends StatelessWidget {
  final List<AetherChoiceChipItem<T>> items;
  final T? selectedValue;
  final ValueChanged<T>? onSelected;

  const AetherChoiceChipGroup({
    super.key,
    required this.items,
    this.selectedValue,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;

    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      children: items.map((item) {
        final isSelected = item.value == selectedValue;
        return ChoiceChip(
          key: ValueKey('chip_${item.value}'),
          avatar: item.icon,
          label: Text(item.label),
          selected: isSelected,
          selectedColor: colors.primaryContainer,
          backgroundColor: colors.surface,
          labelStyle: TextStyle(
            color: isSelected ? colors.primary : colors.textSecondary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
          onSelected: (_) => onSelected?.call(item.value),
        );
      }).toList(),
    );
  }
}

enum AetherButtonVariant {
  primary,
  secondary,
  outline,
  text,
  danger,
}

enum AetherButtonSize {
  sm(height: 32.0, minTouchTarget: 36.0),
  md(height: 44.0, minTouchTarget: 48.0),
  lg(height: 52.0, minTouchTarget: 52.0);

  final double height;
  final double minTouchTarget;

  const AetherButtonSize({
    required this.height,
    required this.minTouchTarget,
  });
}

class AetherButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String? labelText;
  final Widget? icon;
  final AetherButtonVariant variant;
  final AetherButtonSize size;
  final bool isLoading;
  final bool isExpanded;

  const AetherButton({
    super.key,
    required this.onPressed,
    this.labelText,
    this.icon,
    this.variant = AetherButtonVariant.primary,
    this.size = AetherButtonSize.md,
    this.isLoading = false,
    this.isExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;
    final bp = AetherResponsive.of(context);
    final isMobile = bp.isMobile;

    Color bg;
    Color fg;
    BorderSide? border;

    switch (variant) {
      case AetherButtonVariant.primary:
        bg = colors.primary;
        fg = colors.onPrimary;
      case AetherButtonVariant.secondary:
        bg = colors.surfaceSubtle;
        fg = colors.textPrimary;
      case AetherButtonVariant.outline:
        bg = Colors.transparent;
        fg = colors.primary;
        border = BorderSide(color: colors.primary);
      case AetherButtonVariant.text:
        bg = Colors.transparent;
        fg = colors.primary;
      case AetherButtonVariant.danger:
        bg = colors.danger.base;
        fg = colors.danger.onBase;
    }

    if (onPressed == null) {
      bg = colors.surfaceSubtle;
      fg = colors.textMuted;
      border = null;
    }

    Widget content = Row(
      mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          SizedBox(
            width: 16.0,
            height: 16.0,
            child: CircularProgressIndicator(strokeWidth: 2.0, color: fg),
          ),
          if (labelText != null) const SizedBox(width: 8.0),
        ] else if (icon != null) ...[
          icon!,
          if (labelText != null) const SizedBox(width: 8.0),
        ],
        if (labelText != null)
          Flexible(
            child: Text(
              labelText!,
              style: TextStyle(color: fg, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );

    Widget btn = ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        side: border,
        shape: const RoundedRectangleBorder(borderRadius: AetherRadii.sm),
        minimumSize: Size(
          isExpanded ? double.infinity : 64.0,
          isMobile ? size.minTouchTarget : size.height,
        ),
      ),
      onPressed: isLoading ? null : onPressed,
      child: content,
    );

    return btn;
  }
}

class AetherSwitchTile extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool enabled;

  const AetherSwitchTile({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
    this.leading,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: enabled ? onChanged : null,
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      secondary: leading,
    );
  }
}

// ============================================================================
// 6. COMPONENTS: DATA DISPLAY & STATUS
// ============================================================================

enum AetherSemanticStatus {
  success,
  danger,
  warning,
  info,
  neutral;

  bool get isSuccess => this == AetherSemanticStatus.success;
  bool get isDanger => this == AetherSemanticStatus.danger;
  bool get isWarning => this == AetherSemanticStatus.warning;
  bool get isInfo => this == AetherSemanticStatus.info;
  bool get isNeutral => this == AetherSemanticStatus.neutral;
}

enum AetherBadgeStyle {
  subtle,
  solid,
  outline,
}

class AetherStatusBadge extends StatelessWidget {
  final String text;
  final AetherSemanticStatus status;
  final AetherBadgeStyle style;
  final Widget? icon;
  final bool showDot;

  const AetherStatusBadge({
    super.key,
    required this.text,
    this.status = AetherSemanticStatus.neutral,
    this.style = AetherBadgeStyle.subtle,
    this.icon,
    this.showDot = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;
    AetherSemanticColor c;
    switch (status) {
      case AetherSemanticStatus.success:
        c = colors.success;
      case AetherSemanticStatus.danger:
        c = colors.danger;
      case AetherSemanticStatus.warning:
        c = colors.warning;
      case AetherSemanticStatus.info:
        c = colors.info;
      case AetherSemanticStatus.neutral:
        c = colors.neutral;
    }

    Color bg;
    Color fg;
    Border? border;

    switch (style) {
      case AetherBadgeStyle.subtle:
        bg = c.container;
        fg = c.onContainer;
      case AetherBadgeStyle.solid:
        bg = c.base;
        fg = c.onBase;
      case AetherBadgeStyle.outline:
        bg = Colors.transparent;
        fg = c.base;
        border = Border.all(color: c.base);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AetherRadii.full,
        border: border,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 6.0,
              height: 6.0,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4.0),
          ],
          if (icon != null) ...[icon!, const SizedBox(width: 4.0)],
          Text(
            text,
            style: TextStyle(color: fg, fontSize: 12.0, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class AetherDataCardField {
  final String label;
  final String value;

  const AetherDataCardField({required this.label, required this.value});
}

class AetherDataCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final AetherStatusBadge? badge;
  final List<AetherDataCardField>? fields;
  final VoidCallback? onTap;
  final bool isSelected;

  const AetherDataCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.badge,
    this.fields,
    this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;
    final typography = context.aetherTypography;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AetherRadii.md,
        border: Border.all(
          color: isSelected ? colors.primary : colors.border,
          width: isSelected ? 2.0 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AetherRadii.md,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (leading != null) ...[leading!, const SizedBox(width: 12.0)],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: typography.titleSmall),
                          if (subtitle != null) Text(subtitle!, style: typography.bodySmall),
                        ],
                      ),
                    ),
                    ?badge,
                  ],
                ),
                if (fields != null && fields!.isNotEmpty) ...[
                  const SizedBox(height: 12.0),
                  ...fields!.map((f) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Row(
                          children: [
                            Text('${f.label}: ', style: typography.labelSmall),
                            Expanded(child: Text(f.value, style: typography.bodySmall)),
                          ],
                        ),
                      )),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AetherMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final Widget? icon;
  final String? trend;
  final bool isTrendPositive;
  final AetherSemanticStatus? semantic;
  final VoidCallback? onTap;

  const AetherMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
    this.trend,
    this.isTrendPositive = true,
    this.semantic,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;
    final typography = context.aetherTypography;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AetherRadii.md,
        border: Border.all(color: colors.border),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (icon != null) ...[icon!, const SizedBox(width: 8.0)],
                Expanded(child: Text(label, style: typography.labelMedium)),
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
            const SizedBox(height: 8.0),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: typography.displayMedium),
                if (unit != null) ...[
                  const SizedBox(width: 4.0),
                  Text(unit!, style: typography.bodyMedium),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AetherAvatarBadge extends StatelessWidget {
  final String? name;
  final double size;
  final AetherSemanticStatus? statusDot;

  const AetherAvatarBadge({
    super.key,
    this.name,
    this.size = 40.0,
    this.statusDot,
  });

  String _initials() {
    if (name == null || name!.isEmpty) return '??';
    final parts = name!.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0].substring(0, math.min(2, parts[0].length)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: size / 2,
            backgroundColor: colors.primaryContainer,
            child: Text(
              _initials(),
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.w600,
                fontSize: size * 0.38,
              ),
            ),
          ),
          if (statusDot != null)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: size * 0.28,
                height: size * 0.28,
                decoration: BoxDecoration(
                  color: statusDot == AetherSemanticStatus.success
                      ? colors.success.base
                      : colors.danger.base,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// 7. COMPONENTS: FEEDBACK & OVERLAYS
// ============================================================================

class AetherAdaptiveDialog extends StatelessWidget {
  final Widget title;
  final Widget content;
  final List<Widget>? actions;

  const AetherAdaptiveDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions,
  });

  static Future<T?> show<T>(
    BuildContext context, {
    required Widget title,
    required Widget content,
    List<Widget>? actions,
  }) {
    final bp = AetherResponsive.of(context);
    if (bp.isMobile) {
      return showModalBottomSheet<T>(
        context: context,
        builder: (ctx) => AetherBottomSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 12.0),
              content,
              if (actions != null) ...[
                const SizedBox(height: 16.0),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
              ],
            ],
          ),
        ),
      );
    }

    return showDialog<T>(
      context: context,
      builder: (ctx) => AetherAdaptiveDialog(
        title: title,
        content: content,
        actions: actions,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;

    return Dialog(
      backgroundColor: colors.surfaceElevated,
      shape: const RoundedRectangleBorder(borderRadius: AetherRadii.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520.0),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DefaultTextStyle(
                style: context.aetherTypography.titleLarge,
                child: title,
              ),
              const SizedBox(height: 16.0),
              DefaultTextStyle(
                style: context.aetherTypography.bodyMedium,
                child: content,
              ),
              if (actions != null) ...[
                const SizedBox(height: 24.0),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: actions!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AetherBottomSheet extends StatelessWidget {
  final String? title;
  final Widget child;

  const AetherBottomSheet({super.key, this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;

    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          if (title != null) ...[
            const SizedBox(height: 12.0),
            Text(title!, style: context.aetherTypography.titleMedium),
          ],
          const SizedBox(height: 16.0),
          child,
        ],
      ),
    );
  }
}

class AetherImageViewer extends StatefulWidget {
  final Widget child;
  final TransformationController? controller;

  const AetherImageViewer({
    super.key,
    required this.child,
    this.controller,
  });

  @override
  State<AetherImageViewer> createState() => AetherImageViewerState();
}

class AetherImageViewerState extends State<AetherImageViewer> {
  late final TransformationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TransformationController();
  }

  void zoomIn() {
    _controller.value = _controller.value.clone()..scaleByDouble(1.25, 1.25, 1.0, 1.0);
    setState(() {});
  }

  void zoomOut() {
    _controller.value = _controller.value.clone()..scaleByDouble(0.8, 0.8, 1.0, 1.0);
    setState(() {});
  }

  void resetZoom() {
    _controller.value = Matrix4.identity();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InteractiveViewer(
          transformationController: _controller,
          minScale: 0.5,
          maxScale: 8.0,
          child: Center(child: widget.child),
        ),
        Positioned(
          bottom: 16.0,
          right: 16.0,
          child: Container(
            decoration: BoxDecoration(
              color: context.aetherColors.surface.withAlpha(220),
              borderRadius: AetherRadii.md,
              border: Border.all(color: context.aetherColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key('zoom_out_btn'),
                  icon: const Icon(Icons.zoom_out),
                  onPressed: zoomOut,
                ),
                IconButton(
                  key: const Key('zoom_reset_btn'),
                  icon: const Icon(Icons.refresh),
                  onPressed: resetZoom,
                ),
                IconButton(
                  key: const Key('zoom_in_btn'),
                  icon: const Icon(Icons.zoom_in),
                  onPressed: zoomIn,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class AetherToastBanner extends StatelessWidget {
  final String message;
  final AetherSemanticStatus status;
  final VoidCallback? onDismiss;

  const AetherToastBanner({
    super.key,
    required this.message,
    this.status = AetherSemanticStatus.info,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.aetherColors;
    AetherSemanticColor c;
    switch (status) {
      case AetherSemanticStatus.success:
        c = colors.success;
      case AetherSemanticStatus.danger:
        c = colors.danger;
      case AetherSemanticStatus.warning:
        c = colors.warning;
      case AetherSemanticStatus.info:
        c = colors.info;
      case AetherSemanticStatus.neutral:
        c = colors.neutral;
    }

    return Container(
      margin: const EdgeInsets.all(8.0),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: c.container,
        borderRadius: AetherRadii.sm,
        border: Border.all(color: c.base),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: c.onContainer, size: 20),
          const SizedBox(width: 12.0),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: c.onContainer, fontWeight: FontWeight.w500),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              icon: Icon(Icons.close, color: c.onContainer, size: 16),
              onPressed: onDismiss,
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// 8. STATIC AUDIT UTILITIES
// ============================================================================

class ColorAuditViolation {
  final String filePath;
  final int lineNumber;
  final String matchedToken;
  final String lineContent;

  const ColorAuditViolation({
    required this.filePath,
    required this.lineNumber,
    required this.matchedToken,
    required this.lineContent,
  });

  @override
  String toString() => '$filePath:$lineNumber: [$matchedToken] $lineContent';
}

class ColorAuditResult {
  final int filesScanned;
  final List<ColorAuditViolation> violations;

  const ColorAuditResult({
    required this.filesScanned,
    required this.violations,
  });

  int get totalViolations => violations.length;
}

class ColorAuditScanner {
  static final RegExp _colorLiteralRegex = RegExp(
    r'(?<!//.*)(?:\bColors\.[a-zA-Z0-9_]+|\bColor\(0x[0-9a-fA-F]+\))',
  );

  static ColorAuditResult scanDirectory(String dirPath) {
    // import 'dart:io' dynamically or via file check
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      return const ColorAuditResult(filesScanned: 0, violations: []);
    }

    final violations = <ColorAuditViolation>[];
    int filesCount = 0;

    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        filesCount++;
        final lines = entity.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trim();
          if (trimmed.startsWith('//') || trimmed.startsWith('/*')) continue;

          final matches = _colorLiteralRegex.allMatches(line);
          for (final match in matches) {
            violations.add(ColorAuditViolation(
              filePath: entity.path,
              lineNumber: i + 1,
              matchedToken: match.group(0) ?? '',
              lineContent: trimmed,
            ));
          }
        }
      }
    }

    return ColorAuditResult(filesScanned: filesCount, violations: violations);
  }

  static ColorAuditResult scanSourceString(String source, {String filePath = 'in_memory.dart'}) {
    final violations = <ColorAuditViolation>[];
    final lines = source.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.startsWith('//') || trimmed.startsWith('/*')) continue;

      final matches = _colorLiteralRegex.allMatches(line);
      for (final match in matches) {
        violations.add(ColorAuditViolation(
          filePath: filePath,
          lineNumber: i + 1,
          matchedToken: match.group(0) ?? '',
          lineContent: trimmed,
        ));
      }
    }
    return ColorAuditResult(filesScanned: 1, violations: violations);
  }
}

