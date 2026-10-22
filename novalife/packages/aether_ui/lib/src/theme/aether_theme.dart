import 'package:flutter/material.dart';

import 'aether_colors.dart';
import 'aether_radii.dart';
import 'aether_shadows.dart';
import 'aether_typography.dart';

/// Complete immutable theme data bundle for Aether UI.
@immutable
class AetherThemeData {
  final Brightness brightness;
  final AetherColors colors;
  final AetherTypography typography;
  final AetherShadows shadows;

  const AetherThemeData({
    required this.brightness,
    required this.colors,
    required this.typography,
    required this.shadows,
  });

  bool get isDark => brightness == Brightness.dark;
  bool get isLight => brightness == Brightness.light;

  /// Constructs a complete Light theme configuration.
  factory AetherThemeData.light({
    AetherColors? colors,
    AetherTypography? typography,
    AetherShadows? shadows,
  }) {
    final effectiveColors = colors ?? AetherColors.light();
    final effectiveTypography = typography ??
        AetherTypography.fromColors(
          textPrimary: effectiveColors.textPrimary,
          textSecondary: effectiveColors.textSecondary,
          textMuted: effectiveColors.textMuted,
          textDisabled: effectiveColors.textDisabled,
        );
    final effectiveShadows = shadows ?? AetherShadows.light();

    return AetherThemeData(
      brightness: Brightness.light,
      colors: effectiveColors,
      typography: effectiveTypography,
      shadows: effectiveShadows,
    );
  }

  /// Constructs a complete Dark theme configuration.
  factory AetherThemeData.dark({
    AetherColors? colors,
    AetherTypography? typography,
    AetherShadows? shadows,
  }) {
    final effectiveColors = colors ?? AetherColors.dark();
    final effectiveTypography = typography ??
        AetherTypography.fromColors(
          textPrimary: effectiveColors.textPrimary,
          textSecondary: effectiveColors.textSecondary,
          textMuted: effectiveColors.textMuted,
          textDisabled: effectiveColors.textDisabled,
        );
    final effectiveShadows = shadows ?? AetherShadows.dark();

    return AetherThemeData(
      brightness: Brightness.dark,
      colors: effectiveColors,
      typography: effectiveTypography,
      shadows: effectiveShadows,
    );
  }

  AetherThemeData copyWith({
    Brightness? brightness,
    AetherColors? colors,
    AetherTypography? typography,
    AetherShadows? shadows,
  }) {
    return AetherThemeData(
      brightness: brightness ?? this.brightness,
      colors: colors ?? this.colors,
      typography: typography ?? this.typography,
      shadows: shadows ?? this.shadows,
    );
  }

  /// Converts this [AetherThemeData] into a standard Flutter Material 3 [ThemeData].
  ThemeData toThemeData() {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      cardColor: colors.surface,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: colors.primary,
        onPrimary: colors.onPrimary,
        primaryContainer: colors.primaryContainer,
        onPrimaryContainer: colors.textPrimary,
        secondary: colors.primaryHover,
        onSecondary: colors.onPrimary,
        surface: colors.surface,
        onSurface: colors.textPrimary,
        error: colors.danger.base,
        onError: colors.danger.onBase,
        errorContainer: colors.danger.container,
        onErrorContainer: colors.danger.onContainer,
        outline: colors.border,
        outlineVariant: colors.borderSubtle,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: typography.titleLarge.copyWith(color: colors.textPrimary),
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AetherRadii.md,
          side: BorderSide(color: colors.border, width: 1.0),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(
        color: colors.borderSubtle,
        thickness: 1.0,
        space: 1.0,
      ),
      textTheme: TextTheme(
        displayLarge: typography.displayLarge,
        displayMedium: typography.displayMedium,
        titleLarge: typography.titleLarge,
        titleMedium: typography.titleMedium,
        titleSmall: typography.titleSmall,
        bodyLarge: typography.bodyLarge,
        bodyMedium: typography.bodyMedium,
        bodySmall: typography.bodySmall,
        labelLarge: typography.labelLarge,
        labelMedium: typography.labelMedium,
        labelSmall: typography.labelSmall,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AetherThemeData &&
          runtimeType == other.runtimeType &&
          brightness == other.brightness &&
          colors == other.colors &&
          typography == other.typography &&
          shadows == other.shadows;

  @override
  int get hashCode => Object.hash(brightness, colors, typography, shadows);
}

/// Root InheritedWidget providing [AetherThemeData] to its subtree.
class AetherTheme extends InheritedWidget {
  final AetherThemeData data;

  const AetherTheme({
    super.key,
    required this.data,
    required super.child,
  });

  @override
  bool updateShouldNotify(AetherTheme oldWidget) => data != oldWidget.data;

  /// Retrieves the ambient [AetherThemeData] from the closest ancestor.
  ///
  /// **Resilience Guarantee**: If invoked in an unmounted context or outside an
  /// [AetherTheme] scope, it safely inspects [Theme.of(context).brightness] to
  /// return [AetherThemeData.light()] or [AetherThemeData.dark()] without crashing.
  static AetherThemeData of(BuildContext context) {
    if (!context.mounted) {
      return AetherThemeData.light();
    }

    try {
      final inherited = context.dependOnInheritedWidgetOfExactType<AetherTheme>();
      if (inherited != null) {
        return inherited.data;
      }

      final brightness = Theme.of(context).brightness;
      return brightness == Brightness.dark
          ? AetherThemeData.dark()
          : AetherThemeData.light();
    } catch (_) {
      return AetherThemeData.light();
    }
  }

  /// Nullable query for [AetherThemeData] without automatic fallback.
  static AetherThemeData? maybeOf(BuildContext context) {
    if (!context.mounted) {
      return null;
    }

    try {
      final inherited = context.dependOnInheritedWidgetOfExactType<AetherTheme>();
      return inherited?.data;
    } catch (_) {
      return null;
    }
  }
}
