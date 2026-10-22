import 'package:flutter/material.dart';

/// Platform-native font fallbacks for cross-platform visual consistency
/// without external font asset dependencies.
const List<String> kAetherFontFallbackSans = [
  '-apple-system',
  'BlinkMacSystemFont',
  'Segoe UI',
  'Roboto',
  'Helvetica Neue',
  'Ubuntu',
  'Cantarell',
  'sans-serif',
];

const List<String> kAetherFontFallbackMono = [
  'ui-monospace',
  'SFMono-Regular',
  'Menlo',
  'Monaco',
  'Consolas',
  'Liberation Mono',
  'Courier New',
  'monospace',
];

/// Standardized typography scale for Aether UI.
@immutable
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

  /// Factory creating standard typography with default neutral text colors.
  factory AetherTypography.standard({
    Color textPrimary = const Color(0xFF0F172A),
    Color textSecondary = const Color(0xFF475569),
    Color textMuted = const Color(0xFF64748B),
    Color textDisabled = const Color(0xFF94A3B8),
    String? fontFamily,
    List<String>? fontFamilyFallback,
  }) {
    return AetherTypography.fromColors(
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      textMuted: textMuted,
      textDisabled: textDisabled,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );
  }

  /// Factory creating typography pre-bound to semantic text colors.
  factory AetherTypography.fromColors({
    required Color textPrimary,
    required Color textSecondary,
    required Color textMuted,
    required Color textDisabled,
    String? fontFamily,
    List<String>? fontFamilyFallback,
  }) {
    final fallbackSans = fontFamilyFallback ?? kAetherFontFallbackSans;

    TextStyle sans({
      required double size,
      required FontWeight weight,
      required double height,
      double? letterSpacing,
      required Color color,
    }) {
      return TextStyle(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
        fontFamily: fontFamily,
        fontFamilyFallback: fallbackSans,
      );
    }

    return AetherTypography(
      displayLarge: sans(
        size: 32.0,
        weight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.5,
        color: textPrimary,
      ),
      displayMedium: sans(
        size: 26.0,
        weight: FontWeight.w700,
        height: 1.30,
        letterSpacing: -0.25,
        color: textPrimary,
      ),
      titleLarge: sans(
        size: 20.0,
        weight: FontWeight.w600,
        height: 1.35,
        color: textPrimary,
      ),
      titleMedium: sans(
        size: 17.0,
        weight: FontWeight.w600,
        height: 1.40,
        color: textPrimary,
      ),
      titleSmall: sans(
        size: 15.0,
        weight: FontWeight.w600,
        height: 1.40,
        color: textPrimary,
      ),
      bodyLarge: sans(
        size: 16.0,
        weight: FontWeight.w400,
        height: 1.50,
        letterSpacing: 0.15,
        color: textPrimary,
      ),
      bodyMedium: sans(
        size: 14.0,
        weight: FontWeight.w400,
        height: 1.50,
        letterSpacing: 0.25,
        color: textPrimary,
      ),
      bodySmall: sans(
        size: 12.0,
        weight: FontWeight.w400,
        height: 1.40,
        letterSpacing: 0.4,
        color: textSecondary,
      ),
      labelLarge: sans(
        size: 14.0,
        weight: FontWeight.w600,
        height: 1.40,
        letterSpacing: 0.1,
        color: textPrimary,
      ),
      labelMedium: sans(
        size: 12.0,
        weight: FontWeight.w500,
        height: 1.40,
        letterSpacing: 0.2,
        color: textSecondary,
      ),
      labelSmall: sans(
        size: 10.0,
        weight: FontWeight.w600,
        height: 1.40,
        letterSpacing: 0.3,
        color: textMuted,
      ),
      code: TextStyle(
        fontSize: 13.0,
        fontWeight: FontWeight.w500,
        height: 1.40,
        color: textPrimary,
        fontFamily: 'monospace',
        fontFamilyFallback: kAetherFontFallbackMono,
      ),
    );
  }

  /// Returns a copy of this typography with the given [color] applied across all text styles.
  AetherTypography applyColor(Color color) {
    return AetherTypography(
      displayLarge: displayLarge.copyWith(color: color),
      displayMedium: displayMedium.copyWith(color: color),
      titleLarge: titleLarge.copyWith(color: color),
      titleMedium: titleMedium.copyWith(color: color),
      titleSmall: titleSmall.copyWith(color: color),
      bodyLarge: bodyLarge.copyWith(color: color),
      bodyMedium: bodyMedium.copyWith(color: color),
      bodySmall: bodySmall.copyWith(color: color),
      labelLarge: labelLarge.copyWith(color: color),
      labelMedium: labelMedium.copyWith(color: color),
      labelSmall: labelSmall.copyWith(color: color),
      code: code.copyWith(color: color),
    );
  }

  AetherTypography copyWith({
    TextStyle? displayLarge,
    TextStyle? displayMedium,
    TextStyle? titleLarge,
    TextStyle? titleMedium,
    TextStyle? titleSmall,
    TextStyle? bodyLarge,
    TextStyle? bodyMedium,
    TextStyle? bodySmall,
    TextStyle? labelLarge,
    TextStyle? labelMedium,
    TextStyle? labelSmall,
    TextStyle? code,
  }) {
    return AetherTypography(
      displayLarge: displayLarge ?? this.displayLarge,
      displayMedium: displayMedium ?? this.displayMedium,
      titleLarge: titleLarge ?? this.titleLarge,
      titleMedium: titleMedium ?? this.titleMedium,
      titleSmall: titleSmall ?? this.titleSmall,
      bodyLarge: bodyLarge ?? this.bodyLarge,
      bodyMedium: bodyMedium ?? this.bodyMedium,
      bodySmall: bodySmall ?? this.bodySmall,
      labelLarge: labelLarge ?? this.labelLarge,
      labelMedium: labelMedium ?? this.labelMedium,
      labelSmall: labelSmall ?? this.labelSmall,
      code: code ?? this.code,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AetherTypography &&
          runtimeType == other.runtimeType &&
          displayLarge == other.displayLarge &&
          displayMedium == other.displayMedium &&
          titleLarge == other.titleLarge &&
          titleMedium == other.titleMedium &&
          titleSmall == other.titleSmall &&
          bodyLarge == other.bodyLarge &&
          bodyMedium == other.bodyMedium &&
          bodySmall == other.bodySmall &&
          labelLarge == other.labelLarge &&
          labelMedium == other.labelMedium &&
          labelSmall == other.labelSmall &&
          code == other.code;

  @override
  int get hashCode => Object.hash(
        displayLarge,
        displayMedium,
        titleLarge,
        titleMedium,
        titleSmall,
        bodyLarge,
        bodyMedium,
        bodySmall,
        labelLarge,
        labelMedium,
        labelSmall,
        code,
      );
}
